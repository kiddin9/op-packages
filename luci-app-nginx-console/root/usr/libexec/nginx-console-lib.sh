#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# nginx-console - backend for luci-app-nginx-console.
#
# Stage 1 is deliberately read-only: it only reports state.  Nothing here
# writes to /etc/config/nginx or /etc/nginx, so the page cannot break a running
# server yet.  Mutating commands will be added one at a time, and each of them
# has to snapshot, validate with `nginx -t` and roll back on failure.
#
# Every command prints exactly one JSON object on stdout and exits 0, so the
# caller never has to interpret exit codes.

CONF_DIR=/etc/nginx/conf.d
UCI_FILE=/etc/config/nginx
UCI_CONF=/etc/nginx/uci.conf
FALLBACK_CONF=/etc/nginx/nginx.conf
NGINX_BIN=/usr/sbin/nginx
NGINX_INIT=/etc/init.d/nginx
NGINX_UTIL=/usr/bin/nginx-util
PENDING=/tmp/nginx-console.pending
# The page stages each command into its own file so two tabs cannot overwrite
# each other's input, and passes that path as the command's last argument.  Only
# names matching this pattern are accepted: the path is used for reading and
# deleting, so it must not be able to point outside the staging area.
PENDING_PATH_PATTERN='^/tmp/nginx-console[.]pending[.][A-Za-z0-9_-]+$'
PENDING_PATH=''
SNAPSHOT=/tmp/nginx-console.snapshot
UPLOAD_DIR=/etc/luci-uploads
MAX_UPLOAD_BYTES=262144
# What may be uploaded, and under which name.  The name may not carry a path
# separator, so the file can only land inside the upload directory.
UPLOAD_NAME_PATTERN='^[A-Za-z0-9][A-Za-z0-9._-]*[.](crt|cer|pem|key|csr)$'
BACKUP_DIR=/root/backup/nginx-console
BACKUP_KEEP=10
FRAG_BACKUP_DIR=/root/backup/nginx-console-fragments
FRAG_BACKUP_KEEP=10
MAX_FRAG_BYTES=131072
FRAG_NAME_PATTERN='^[A-Za-z0-9][A-Za-z0-9._-]*[.]locations$'

# Fields the page may rewrite.  Everything else in a section (uci_manage_ssl,
# the ssl_session_* tuning, ...) is preserved untouched by every save.
# add_header is a list: one header per value.
EDITABLE_FIELDS='listen server_name include ssl_certificate ssl_certificate_key access_log error_log add_header server_tokens limit_req limit_conn'
SINGLE_FIELDS='server_name ssl_certificate ssl_certificate_key access_log error_log server_tokens limit_req limit_conn'
TAB="$(printf '\t')"

. /usr/share/libubox/jshn.sh

# ---------------------------------------------------------------- utilities

# Adopts the staged file named by the command's staging argument.  A command
# that reads staged input takes that path as its last argument; the pattern
# check keeps the value from naming anything outside the staging area, because
# this path is read and then deleted.
#   set_pending <path>  - returns 1 when the argument is not an allowed path
set_pending() {
	PENDING_PATH=''

	[ -n "${1:-}" ] || return 1

	printf '%s' "$1" | grep -qE "$PENDING_PATH_PATTERN" || return 1

	PENDING_PATH="$1"
	PENDING="$PENDING_PATH"

	return 0
}

nginx_running() {
	local pid
	pid="$(cat /var/run/nginx.pid 2>/dev/null)"
	[ -n "$pid" ] && [ -d "/proc/$pid" ]
}

detect_conf() {
	# nginx_init picks uci.conf when it exists, so does this check.
	if [ -f "$UCI_CONF" ]; then
		printf '%s' "$UCI_CONF"
	else
		printf '%s' "$FALLBACK_CONF"
	fi
}

config_test() {
	"$NGINX_BIN" -t -c "$(detect_conf)" -g "daemon off;" 2>&1
}

json_fail() {
	# json_fail <error> [output] [rollback]
	json_init
	json_add_boolean ok 0
	json_add_string error "$1"
	[ -n "${2:-}" ] && json_add_string output "$2"
	[ -n "${3:-}" ] && json_add_string rollback "$3"
	json_dump
	printf '\n'
}

json_ok() {
	# json_ok [key value]...
	json_init
	json_add_boolean ok 1
	while [ "$#" -ge 2 ]; do
		json_add_string "$1" "$2"
		shift 2
	done
	json_dump
	printf '\n'
}

valid_section() {
	# Section names are interpolated into uci commands as nginx.<name>, and uci
	# only accepts letters, digits and underscore there: a dash or a dot is read
	# as option/argument syntax, the command fails, and nothing is written.
	printf '%s' "$1" | grep -qE '^[A-Za-z0-9_]+$'
}

is_single() {
	case " $SINGLE_FIELDS " in
		*" $1 "*) return 0 ;;
	esac
	return 1
}

field_values() {
	# All staged values of one field, in the order the form sent them.
	# Parsed with plain shell on purpose: busybox awk does not understand \t
	# inside a regex, so a split on the tab keeps tripping over field names.
	local want="$1" line

	while IFS= read -r line; do
		case "$line" in
			"$want$TAB"*)
				printf '%s\n' "${line#"$want$TAB"}"
				;;
		esac
	done < "$PENDING"
}

field_present() {
	# Whether the staged file carries this field at all.  A field that is not
	# staged is left alone: an empty value and a missing value are different
	# things, and reading them the same way silently clears the option.
	local want="$1" line

	while IFS= read -r line; do
		case "$line" in
			"$want$TAB"*) return 0 ;;
		esac
	done < "$PENDING"

	return 1
}

uci_current_values() {
	# All current values of one option, one per line.
	#
	# This used to be `eval "set -- $(uci -q get ...)"`, which split the list
	# with the shell.  That is a command injection: `uci get` only quotes a
	# value when it needs quoting, so a value like `$(cmd)` printed bare and the
	# eval ran it as root.  The ubus uci interface returns the list as JSON
	# instead, and jsonfilter decodes it without invoking a shell, so the value
	# stays a literal string no matter what it contains.
	local name="$1" config section option

	config="${name%%.*}"
	section="${name#*.}"
	section="${section%%.*}"
	option="${name##*.}"

	[ -n "$config" ] && [ -n "$section" ] && [ -n "$option" ] || return 0

	ubus call uci get "{\"config\":\"$config\",\"section\":\"$section\",\"option\":\"$option\"}" 2>/dev/null \
		| jsonfilter -e '@.value[*]' 2>/dev/null

	return 0
}

# Path values the form may write.  `nginx -t` alone is not a guard here: it
# accepts any readable file for include and any path for access_log, so a write
# grant could point nginx at a file outside its configuration.  Both are
# restricted to the shapes this router actually uses.
valid_include() {
	printf '%s' "$1" | grep -qE '^[A-Za-z0-9_./*-]+$' || return 1
	printf '%s' "$1" | grep -qE '(^|/)[.][.]/' && return 1
	return 0
}

valid_log_target() {
	case "$1" in
		''|off|off\;*|logd*|syslog*) return 0 ;;
		/var/log/nginx/*) return 0 ;;
	esac

	return 1
}

# Validates one staged value for the field it belongs to.  Fields without a
# rule here are free-form nginx arguments.
valid_field_value() {
	local field="$1" value="$2"

	case "$field" in
		include)    valid_include "$value" || return 1 ;;
		access_log|error_log) valid_log_target "$value" || return 1 ;;
	esac

	return 0
}

apply_editable() {
	# Rewrites only the fields whose value actually changed.  Touching just
	# those keeps the other options of the section in place instead of forcing
	# every managed field to the end of the file on each save.
	local name="$1" field want current value

	for field in $EDITABLE_FIELDS; do
		# Only the fields the caller staged are touched.  A field that is not
		# in the staged file keeps the value it has.
		field_present "$field" || continue

		want="$(field_values "$field")"
		current="$(uci_current_values "nginx.$name.$field")"

		[ "$want" = "$current" ] && continue

		uci -q delete "nginx.$name.$field" 2>/dev/null

		# A here-doc rather than a pipe: the loop has to run in this shell so a
		# failing uci call aborts the whole save instead of being ignored.
		while IFS= read -r value; do
			[ -n "$value" ] || continue

			valid_field_value "$field" "$value" || return 2

			if is_single "$field"; then
				uci -q set "nginx.$name.$field=$value" || return 1
			else
				uci -q add_list "nginx.$name.$field=$value" || return 1
			fi
		done <<EOF
$want
EOF
	done

	return 0
}

render_uci_conf() {
	# The same steps nginx_init performs before testing the file: drop the
	# rendered uci.conf and let nginx-util rebuild it from /etc/config/nginx.
	[ -d /var/log/nginx ] || mkdir -p /var/log/nginx
	[ -d /var/lib/nginx ] || mkdir -p /var/lib/nginx
	rm -f "$(readlink "$UCI_CONF" 2>/dev/null)"
	"$NGINX_UTIL" init_lan >/dev/null 2>&1
}

# Backup file stamp.  One-second resolution is not enough: two saves in the same
# second wrote the same name and the earlier snapshot was overwritten, so the
# pid is appended to keep them apart.  The date part stays first because
# backup_entry() reads the creation time out of the name.
backup_stamp() {
	printf '%s-%s' "$(date '+%Y%m%d-%H%M%S')" "$$"
}


snapshot_uci() {
	cp -p "$UCI_FILE" "$SNAPSHOT" || return 1

	mkdir -p "$BACKUP_DIR" 2>/dev/null
	cp -p "$UCI_FILE" "$BACKUP_DIR/$(backup_stamp).nginx" 2>/dev/null
	ls -1t "$BACKUP_DIR" 2>/dev/null \
		| awk -v keep="$BACKUP_KEEP" 'NR > keep' \
		| while read -r f; do
			rm -f "$BACKUP_DIR/$f"
		done

	return 0
}

restore_uci() {
	[ -f "$SNAPSHOT" ] || return 1

	cp -p "$SNAPSHOT" "$UCI_FILE" || return 1
	uci -q revert nginx 2>/dev/null
	render_uci_conf
	return 0
}

valid_frag_name() {
	# Fragment names end up in a path, so no slashes and no surprises.
	case "$1" in
		''|*/*) return 1 ;;
	esac

	printf '%s' "$1" | grep -qE "$FRAG_NAME_PATTERN"
}

frag_backup() {
	# frag_backup <path>; prints the backup path, nothing when there was no file
	local src="$1" dst

	[ -f "$src" ] || return 1
	mkdir -p "$FRAG_BACKUP_DIR" || return 1
	dst="$FRAG_BACKUP_DIR/$(backup_stamp).${src##*/}"
	cp -p "$src" "$dst" || return 1

	ls -1t "$FRAG_BACKUP_DIR" 2>/dev/null \
		| awk -v keep="$FRAG_BACKUP_KEEP" 'NR > keep' \
		| while read -r f; do
			rm -f "$FRAG_BACKUP_DIR/$f"
		done

	printf '%s' "$dst"
}

frag_rollback() {
	# frag_rollback <name> <backup>
	local dst="$CONF_DIR/$1"

	if [ -n "${2:-}" ] && [ -f "$2" ]; then
		cp -p "$2" "$dst"
	else
		rm -f "$dst"
	fi
}

master_pid() {
	cat /var/run/nginx.pid 2>/dev/null
}

worker_pids() {
	pgrep -f 'nginx: worker process' 2>/dev/null | sort | tr '\n' ' '
}

reload_nginx_wait() {
	# A HUP is handled asynchronously, so return only once the new workers are
	# really up.  Prints the reload output when it fails.
	local before_master before_workers after_master after_workers out rc i

	before_master="$(master_pid)"
	before_workers="$(worker_pids)"

	out="$("$NGINX_INIT" reload 2>&1)"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		printf '%s' "$out"
		return 1
	fi

	i=0
	while [ "$i" -lt 10 ]; do
		after_master="$(master_pid)"
		after_workers="$(worker_pids)"

		if [ -n "$after_master" ] && [ "$after_master" != "$before_master" ]; then
			return 0
		fi
		if [ -n "$after_workers" ] && [ "$after_workers" != "$before_workers" ]; then
			return 0
		fi

		sleep 1
		i=$((i + 1))
	done

	[ -n "$after_master" ] || { printf 'nginx is not running after reload'; return 1; }
	return 0
}

server_listens() {
	uci -q get "nginx.$1.listen" 2>/dev/null
}

# Refuse an edit that would leave nginx serving nothing useful.  The page checks
# the same things before saving; this is the backstop.
validate_after_edit() {
	local sec listens crt key

	if ! server_listens _lan | grep -qE '(^|[^0-9])443([^0-9]|$)'; then
		printf '_lan 段必须保留一条包含 443 的 listen，否则 LuCI 面板会失联'
		return 1
	fi

	for sec in $(uci -q show nginx 2>/dev/null | sed -n 's/^nginx\.\([^.=]*\)=server$/\1/p'); do
		listens="$(server_listens "$sec")"

		if ! printf '%s' "$listens" | grep -qE '(^|[^0-9])443([^0-9]|$)|(^|\s)ssl(\s|$)'; then
			continue
		fi
		if [ "$(uci -q get "nginx.$sec.uci_manage_ssl" 2>/dev/null)" = "self-signed" ]; then
			continue
		fi

		crt="$(uci -q get "nginx.$sec.ssl_certificate" 2>/dev/null)"
		key="$(uci -q get "nginx.$sec.ssl_certificate_key" 2>/dev/null)"
		if [ -z "$crt" ] || [ -z "$key" ]; then
			printf 'nginx.%s 监听 443/ssl，但 ssl_certificate / ssl_certificate_key 不完整' "$sec"
			return 1
		fi
	done

	return 0
}

count_servers() {
	uci -q show nginx 2>/dev/null | grep -c '=server$'
}

count_fragments() {
	ls -1 "$CONF_DIR"/*.locations 2>/dev/null | wc -l | tr -d ' '
}

count_workers() {
	pgrep -f 'nginx: worker process' 2>/dev/null | wc -l | tr -d ' '
}

# ----------------------------------------------------------------- commands

cmd_status() {
	local version

	version="$("$NGINX_BIN" -v 2>&1 | sed -e 's/^nginx version: //' -e 's/^nginx\///' -e 's/ (.*//')"

	json_init
	json_add_boolean ok 1
	json_add_boolean running "$(nginx_running && echo 1 || echo 0)"
	json_add_string version "$version"
	json_add_string conf "$UCI_CONF"
	json_add_int servers "$(count_servers)"
	json_add_int fragments "$(count_fragments)"
	json_add_int workers "$(count_workers)"
	json_dump
	printf '\n'
}

cmd_test() {
	# Runs `nginx -t` on the configuration nginx is actually started with and
	# hands the raw output back, so a syntax error arrives with its file and
	# line number instead of a summary.
	local out rc

	out="$(config_test)"
	rc=$?

	json_init
	json_add_boolean ok "$([ "$rc" -eq 0 ] && echo 1 || echo 0)"
	[ "$rc" -eq 0 ] || json_add_string error test_failed
	json_add_string conf "$(detect_conf)"
	json_add_string output "$out"
	json_dump
	printf '\n'
}

cmd_server_save() {
	# Applies the edit form of one server section.  The values arrive in
	# $PENDING as "field<TAB>value" lines and only EDITABLE_FIELDS are touched,
	# so a save can never blank out certificates or log settings that the page
	# does not understand yet.  $2 is the staged file this call wrote.
	local name="$1" field value out rc

	valid_section "$name" || { json_fail invalid_section; return 0; }
	set_pending "$2" || { json_fail pending_missing; return 0; }
	uci -q get "nginx.$name" >/dev/null 2>&1 || { json_fail no_such_section; return 0; }
	[ -f "$PENDING" ] || { json_fail pending_missing; return 0; }

	# Start from a clean uci state in case an earlier run left changes behind.
	uci -q revert nginx 2>/dev/null

	snapshot_uci || { json_fail snapshot_failed; return 0; }

	apply_editable "$name"
	rc=$?

	if [ "$rc" -eq 2 ]; then
		uci -q revert nginx 2>/dev/null
		rm -f "$PENDING"
		json_fail invalid_value
		return 0
	fi

	if [ "$rc" -ne 0 ]; then
		uci -q revert nginx 2>/dev/null
		rm -f "$PENDING"
		json_fail write_failed
		return 0
	fi

	if ! out="$(validate_after_edit)"; then
		uci -q revert nginx 2>/dev/null
		rm -f "$PENDING"
		json_fail guard_failed "$out"
		return 0
	fi

	if ! uci -q commit nginx; then
		restore_uci
		rm -f "$PENDING"
		json_fail commit_failed
		return 0
	fi

	rm -f "$PENDING"

	render_uci_conf
	out="$(config_test)"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		restore_uci
		json_fail test_failed "$out" restored
		return 0
	fi

	if ! out="$(reload_nginx_wait)"; then
		restore_uci
		reload_nginx_wait >/dev/null 2>&1
		json_fail reload_failed "$out" restored
		return 0
	fi

	json_ok message applied section "$name"
}

cmd_frag_save() {
	# Installs a fragment.  The whole staged file is the fragment content, so
	# nothing has to be parsed here.  Same transaction as a server edit:
	# back up, install, `nginx -t`, roll back when the test fails.
	local name="$1" src dst backup out rc size

	valid_frag_name "$name" || { json_fail invalid_name; return 0; }
	set_pending "$2" || { json_fail pending_missing; return 0; }

	src="$PENDING"
	[ -f "$src" ] || { json_fail pending_missing; return 0; }

	size="$(wc -c < "$src" | tr -d ' ')"
	[ "$size" -gt 0 ] || { json_fail empty; return 0; }
	[ "$size" -le "$MAX_FRAG_BYTES" ] || { json_fail too_large; return 0; }

	dst="$CONF_DIR/$name"
	backup="$(frag_backup "$dst")"

	cp "$src" "$dst" || { json_fail write_failed; return 0; }
	chmod 0644 "$dst"
	rm -f "$PENDING"

	out="$(config_test)"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		frag_rollback "$name" "$backup"
		json_fail test_failed "$out" "$([ -n "$backup" ] && echo restored || echo removed)"
		return 0
	fi

	if ! out="$(reload_nginx_wait)"; then
		frag_rollback "$name" "$backup"
		reload_nginx_wait >/dev/null 2>&1
		json_fail reload_failed "$out" "$([ -n "$backup" ] && echo restored || echo removed)"
		return 0
	fi

	json_ok message applied fragment "$name"
}

cmd_frag_delete() {
	local name="$1" dst backup out rc

	valid_frag_name "$name" || { json_fail invalid_name; return 0; }

	dst="$CONF_DIR/$name"
	[ -f "$dst" ] || { json_fail not_found; return 0; }

	backup="$(frag_backup "$dst")"
	rm -f "$dst"

	out="$(config_test)"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		frag_rollback "$name" "$backup"
		json_fail test_failed "$out" restored
		return 0
	fi

	if ! out="$(reload_nginx_wait)"; then
		frag_rollback "$name" "$backup"
		reload_nginx_wait >/dev/null 2>&1
		json_fail reload_failed "$out" restored
		return 0
	fi

	json_ok message deleted fragment "$name"
}

cmd_server_add() {
	# Creates a section from the same staged "field<TAB>value" input the editor
	# uses, so a new section already carries its listen directive and can never
	# be committed as an empty one that would collide on the default port.
	local name="$1" out rc

	valid_section "$name" || { json_fail invalid_section; return 0; }
	set_pending "$2" || { json_fail pending_missing; return 0; }
	[ -f "$PENDING" ] || { json_fail pending_missing; return 0; }

	if uci -q get "nginx.$name" >/dev/null 2>&1; then
		json_fail already_exists
		return 0
	fi

	uci -q revert nginx 2>/dev/null
	snapshot_uci || { json_fail snapshot_failed; return 0; }

	uci -q set "nginx.$name=server" || {
		uci -q revert nginx 2>/dev/null
		rm -f "$PENDING"
		json_fail write_failed
		return 0
	}

	apply_editable "$name"
	rc=$?

	if [ "$rc" -eq 2 ]; then
		uci -q revert nginx 2>/dev/null
		rm -f "$PENDING"
		json_fail invalid_value
		return 0
	fi

	if [ "$rc" -ne 0 ]; then
		uci -q revert nginx 2>/dev/null
		rm -f "$PENDING"
		json_fail write_failed
		return 0
	fi

	if ! out="$(validate_after_edit)"; then
		uci -q revert nginx 2>/dev/null
		rm -f "$PENDING"
		json_fail guard_failed "$out"
		return 0
	fi

	if ! uci -q commit nginx; then
		restore_uci
		rm -f "$PENDING"
		json_fail commit_failed
		return 0
	fi

	rm -f "$PENDING"
	render_uci_conf

	out="$(config_test)"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		restore_uci
		json_fail test_failed "$out" restored
		return 0
	fi

	if ! out="$(reload_nginx_wait)"; then
		restore_uci
		reload_nginx_wait >/dev/null 2>&1
		json_fail reload_failed "$out" restored
		return 0
	fi

	json_ok message created section "$name"
}

cmd_server_delete() {
	local name="$1" out rc

	valid_section "$name" || { json_fail invalid_section; return 0; }
	uci -q get "nginx.$name" >/dev/null 2>&1 || { json_fail no_such_section; return 0; }

	# _lan is what serves the LuCI panel; deleting it locks the door from the
	# inside.  The page hides the button for it, this is the backstop.
	if [ "$name" = "_lan" ]; then
		json_fail protected_section
		return 0
	fi

	uci -q revert nginx 2>/dev/null
	snapshot_uci || { json_fail snapshot_failed; return 0; }

	uci -q delete "nginx.$name"

	if ! out="$(validate_after_edit)"; then
		uci -q revert nginx 2>/dev/null
		json_fail guard_failed "$out"
		return 0
	fi

	if ! uci -q commit nginx; then
		restore_uci
		json_fail commit_failed
		return 0
	fi

	render_uci_conf

	out="$(config_test)"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		restore_uci
		json_fail test_failed "$out" restored
		return 0
	fi

	if ! out="$(reload_nginx_wait)"; then
		restore_uci
		reload_nginx_wait >/dev/null 2>&1
		json_fail reload_failed "$out" restored
		return 0
	fi

	json_ok message deleted section "$name"
}

# ------------------------------------------------------------------- 只读报告

cmd_logs() {
	local which="${1:-error}" lines="${2:-200}" out

	case "$which" in
		error|access) ;;
		*) json_fail bad_source; return 0 ;;
	esac

	case "$lines" in
		''|*[!0-9]*) lines=200 ;;
	esac
	[ "$lines" -lt 1 ] && lines=1
	[ "$lines" -gt 500 ] && lines=500

	# nginx logs to syslog here (access_log off / logd ...), so there is no
	# file to tail: it all comes back through logread.
	if [ "$which" = 'error' ]; then
		out="$(logread 2>/dev/null | grep -E 'nginx(\[|_init)' | tail -n "$lines")"
	else
		out="$(logread 2>/dev/null | grep -E '=> [0-9][0-9][0-9] ' | tail -n "$lines")"
	fi

	json_init
	json_add_boolean ok 1
	json_add_string source "$which"
	json_add_int limit "$lines"
	json_add_string content "$out"
	json_dump
	printf '\n'
}

cert_days_left() {
	# OpenWrt has no date parser for "Sep 12 17:54:00 2027 GMT", so the exact
	# remaining days are found by bisecting openssl's own expiry check.
	local f="$1" lo=0 hi=1460 mid

	openssl x509 -in "$f" -noout -checkend 0 >/dev/null 2>&1 || { echo 0; return; }

	while [ $((hi - lo)) -gt 1 ]; do
		mid=$(( (lo + hi) / 2 ))

		if openssl x509 -in "$f" -noout -checkend $((mid * 86400)) >/dev/null 2>&1; then
			lo=$mid
		else
			hi=$mid
		fi
	done

	echo "$lo"
}

cmd_certs() {
	local dir f end subject sans days

	json_init
	json_add_boolean ok 1
	json_add_array certificates

	# The upload directory is included as well: a certificate the console
	# uploaded from the picker has to show up in the list too.
	for dir in /etc/ssl/acme /etc/nginx/certs /etc/luci-uploads; do
		[ -d "$dir" ] || continue

		for f in "$dir"/*.crt "$dir"/*.cer; do
			[ -f "$f" ] || continue
			openssl x509 -in "$f" -noout -subject >/dev/null 2>&1 || continue

			# Issuer/chain certificates are not what a server presents, so a
			# CA:TRUE file (acme's chain.crt) is skipped.
			openssl x509 -in "$f" -noout -ext basicConstraints 2>/dev/null \
				| grep -q 'CA:TRUE' && continue

			end="$(openssl x509 -in "$f" -noout -enddate 2>/dev/null | sed 's/^notAfter=//')"
			subject="$(openssl x509 -in "$f" -noout -subject 2>/dev/null | sed -e 's/^subject=//' -e 's/^ *//')"
			sans="$(openssl x509 -in "$f" -noout -ext subjectAltName 2>/dev/null \
				| tail -n +2 | tr -d ' \n' | sed 's/DNS://g')"
			days="$(cert_days_left "$f")"

			json_add_object
			json_add_string path "$f"
			json_add_string subject "$subject"
			json_add_string not_after "$end"
			json_add_int days_left "$days"
			json_add_string sans "$sans"
			json_close_object
		done
	done

	json_close_array
	json_dump
	printf '\n'
}

# Installs a file the page uploaded.  The content comes in through the staged
# file, the name is checked here: the browser is not trusted with the path the
# file ends up at, and the mode follows the content.
cmd_upload() {
	local name="$1" src dst tmp mode size

	[ -n "$name" ] || { json_fail invalid_name; return 0; }
	set_pending "$2" || { json_fail pending_missing; return 0; }
	printf '%s' "$name" | grep -qE "$UPLOAD_NAME_PATTERN" || {
		json_fail invalid_name
		return 0
	}

	[ -f "$PENDING" ] || { json_fail pending_missing; return 0; }

	size="$(wc -c < "$PENDING" | tr -d ' ')"
	[ "${size:-0}" -le "$MAX_UPLOAD_BYTES" ] || { json_fail too_large; return 0; }

	mkdir -p "$UPLOAD_DIR" || { json_fail write_failed; return 0; }

	# A private key is readable for root only, a certificate like the ones
	# acme writes.
	if grep -q -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' "$PENDING"; then
		mode=0600
	else
		mode=0644
	fi

	src="$PENDING"
	dst="$UPLOAD_DIR/$name"

	# Write a temporary file and move it into place: a copy would follow a
	# symlink and could write over a file outside the upload directory.
	tmp="$UPLOAD_DIR/.upload.$$"

	cp "$src" "$tmp" || { rm -f "$tmp"; json_fail write_failed; return 0; }
	chmod "$mode" "$tmp" || { rm -f "$tmp"; json_fail write_failed; return 0; }
	mv -f "$tmp" "$dst" || { rm -f "$tmp"; json_fail write_failed; return 0; }

	rm -f "$PENDING"

	json_ok path "$dst"
}

backup_entry() {
	local f="$1" kind="$2" size stamp name

	name="${f##*/}"
	size="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"

	# The creation time is in the file name: cp -p keeps the source mtime, so
	# the file's own timestamp says when the config was edited, not when the
	# backup was taken.
	stamp="$(printf '%s' "$name" | sed -n \
		's/^\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\).*/\1-\2-\3 \4:\5:\6/p')"

	json_add_object
	json_add_string kind "$kind"
	json_add_string path "$f"
	json_add_string name "$name"
	json_add_int size "${size:-0}"
	json_add_string time "$stamp"
	json_close_object
}

cmd_backups() {
	local what="${1:-list}" f

	if [ "$what" = 'list' ]; then
		json_init
		json_add_boolean ok 1
		json_add_string uci_dir "$BACKUP_DIR"
		json_add_string frag_dir "$FRAG_BACKUP_DIR"
		json_add_array backups

		for f in "$BACKUP_DIR"/*.nginx; do
			[ -f "$f" ] || continue
			backup_entry "$f" uci
		done

		for f in "$FRAG_BACKUP_DIR"/*; do
			[ -f "$f" ] || continue
			backup_entry "$f" fragment
		done

		json_close_array
		json_dump
		printf '\n'
		return 0
	fi

	json_fail unknown_action
}

valid_backup_path() {
	case "$1" in
		"$BACKUP_DIR"/*.nginx|"$FRAG_BACKUP_DIR"/*) return 0 ;;
		*) return 1 ;;
	esac
}

cmd_backup_restore() {
	local target="$1" out base current current_backup

	valid_backup_path "$target" || { json_fail bad_backup_path; return 0; }
	[ -f "$target" ] || { json_fail no_such_backup; return 0; }

	case "$target" in
	"$BACKUP_DIR"/*.nginx)
		snapshot_uci || { json_fail snapshot_failed; return 0; }

		cp -p "$target" "$UCI_FILE" || { restore_uci; json_fail write_failed; return 0; }
		uci -q revert nginx 2>/dev/null
		render_uci_conf

		if ! out="$(config_test)"; then
			restore_uci
			json_fail test_failed "$out" restored
			return 0
		fi

		if ! out="$(reload_nginx_wait)"; then
			restore_uci
			reload_nginx_wait >/dev/null 2>&1
			json_fail reload_failed "$out" restored
			return 0
		fi

		json_ok message restored kind uci name "${target##*/}"
		return 0
		;;
	esac

	# Fragment backups are "<stamp>.<fragment name>".
	base="${target##*/}"
	base="${base#*.}"

	valid_frag_name "$base" || { json_fail bad_backup_name; return 0; }

	current="$CONF_DIR/$base"
	current_backup=""
	[ -f "$current" ] && current_backup="$(frag_backup "$current")"

	cp -p "$target" "$current" || { json_fail write_failed; return 0; }

	# A restore that fails the syntax test must not leave the broken file
	# behind: the next reload of any kind would fail with it.
	if ! out="$(config_test)"; then
		frag_rollback "$base" "$current_backup"
		json_fail test_failed "$out" restored
		return 0
	fi

	if ! out="$(reload_nginx_wait)"; then
		frag_rollback "$base" "$current_backup"
		reload_nginx_wait >/dev/null 2>&1
		json_fail reload_failed "$out" restored
		return 0
	fi

	json_ok message restored kind fragment name "$base"
}

# ------------------------------------------------------------------ htpasswd

HTPASSWD=/etc/nginx/htpasswd

valid_user() {
	printf '%s' "$1" | grep -qE '^[A-Za-z0-9_.-]+$'
}

htpasswd_has_user() {
	awk -F: -v u="$1" '$1 == u { found = 1 } END { exit !found }' "$HTPASSWD" 2>/dev/null
}

cmd_auth() {
	local action="${1:-list}" user="$2" pass hash tmp

	# The read-only entry point may list the users but never touch them.
	if [ "${AUTH_MODE:-rw}" = "ro" ] && [ "$action" != "list" ]; then
		json_fail permission_denied
		return 0
	fi

	# Only the writing actions read staged input ($3 is that file).
	if [ "$action" != "list" ]; then
		set_pending "$3" || { json_fail pending_missing; return 0; }
	fi

	case "$action" in
		list)
			json_init
			json_add_boolean ok 1
			json_add_string path "$HTPASSWD"
			json_add_array users

			if [ -f "$HTPASSWD" ]; then
				while IFS=: read -r u h; do
					[ -n "$u" ] || continue
					json_add_object
					json_add_string user "$u"
					json_close_object
				done < "$HTPASSWD"
			fi

			json_close_array
			json_dump
			printf '\n'
			;;

		set)
			valid_user "$user" || { json_fail invalid_user; return 0; }
			[ -f "$PENDING" ] || { json_fail pending_missing; return 0; }

			# The password comes from the staged file, never from argv: it
			# must not turn up in the process list.
			pass="$(head -n 1 "$PENDING")"
			[ -n "$pass" ] || { json_fail empty_password; return 0; }

			hash="$(printf '%s\n' "$pass" | openssl passwd -apr1 -stdin 2>/dev/null)"
			[ -n "$hash" ] || { json_fail hash_failed; return 0; }

			[ -f "$HTPASSWD" ] && cp -p "$HTPASSWD" "$HTPASSWD.bak"

			tmp="/tmp/nginx-console.htpasswd.$$"

			if [ -f "$HTPASSWD" ]; then
				awk -F: -v u="$user" '$1 != u' "$HTPASSWD" > "$tmp" || {
					rm -f "$tmp"
					json_fail write_failed
					return 0
				}
			else
				: > "$tmp"
			fi

			printf '%s:%s\n' "$user" "$hash" >> "$tmp"
			cp "$tmp" "$HTPASSWD" || { rm -f "$tmp"; json_fail write_failed; return 0; }
			rm -f "$tmp"
			# The file holds password hashes: keep it for root only.
			chmod 0600 "$HTPASSWD" 2>/dev/null

			json_ok message saved user "$user"
			;;

		delete)
			valid_user "$user" || { json_fail invalid_user; return 0; }
			[ -f "$HTPASSWD" ] || { json_fail no_such_user; return 0; }
			htpasswd_has_user "$user" || { json_fail no_such_user; return 0; }

			cp -p "$HTPASSWD" "$HTPASSWD.bak"
			tmp="/tmp/nginx-console.htpasswd.$$"

			if ! awk -F: -v u="$user" '$1 != u' "$HTPASSWD" > "$tmp"; then
				rm -f "$tmp"
				json_fail write_failed
				return 0
			fi

			if ! cp "$tmp" "$HTPASSWD"; then
				rm -f "$tmp"
				json_fail write_failed
				return 0
			fi

			rm -f "$tmp"
			chmod 0600 "$HTPASSWD" 2>/dev/null

			json_ok message deleted user "$user"
			;;

		*)
			json_fail unknown_action
			;;
	esac
}

# ---------------------------------------------------------------------- 自检

finding() {
	# finding <level> <title> <detail>
	json_add_object
	json_add_string level "$1"
	json_add_string title "$2"
	json_add_string detail "$3"
	json_close_object
}

port_listening() {
	netstat -ltn 2>/dev/null | awk '{ print $4 }' | grep -qE "[:.]$1\$"
}

cmd_audit() {
	local secs sec sn seen seen_keys dup f size inc val url host port days mode

	json_init
	json_add_boolean ok 1
	json_add_array findings

	secs="$(uci -q show nginx 2>/dev/null | sed -n 's/^nginx\.\([A-Za-z0-9_]*\)=server$/\1/p')"

	# 1. the same server_name claimed by two sections: nginx accepts it and
	#    silently sends everything to whichever comes first.
	seen=''
	for sec in $secs; do
		sn="$(uci -q get "nginx.$sec.server_name" 2>/dev/null)"
		[ -n "$sn" ] || continue

		case "$seen" in
			*"|$sn|"*) finding warn 'server_name 重复' "「$sn」被多个 server 段声明，只有第一个会生效" ;;
		esac

		seen="$seen|$sn|"
	done

	# 2. reverse proxy targets that nothing is listening on
	for f in "$CONF_DIR"/*.locations; do
		[ -f "$f" ] || continue

		while read -r url; do
			[ -n "$url" ] || continue
			case "$url" in
				*unix:*) continue ;;
			esac

			host="$(printf '%s' "$url" | sed -e 's|^https\?://||' -e 's|/.*$||' -e 's|:.*$||')"
			port="$(printf '%s' "$url" | sed -n 's|^https\?://[^:/]*:\([0-9]*\).*|\1|p')"
			[ -n "$port" ] || continue
			case "$host" in
				127.0.0.1|localhost|'[::1]') ;;
				*) continue ;;
			esac

			port_listening "$port" || finding warn '反代目标没有在监听' \
				"${f##*/}: proxy_pass $url（本机 $port 端口无监听）"
		done <<EOF
$(grep -ohE 'proxy_pass[ \t]+https?://[^;]+' "$f" 2>/dev/null | sed -e 's/^proxy_pass[ \t]*//')
EOF
	done

	# 3. certificates that are close to expiring
	for f in /etc/ssl/acme/*.crt /etc/nginx/certs/*.crt; do
		[ -f "$f" ] || continue
		openssl x509 -in "$f" -noout -subject >/dev/null 2>&1 || continue

		days="$(cert_days_left "$f")"
		[ "$days" -lt 30 ] && finding warn '证书即将到期' "$f 剩余 ${days} 天"
	done

	# 4. fragment files that are empty or nearly so
	for f in "$CONF_DIR"/*.locations; do
		[ -f "$f" ] || continue
		size="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"
		[ "${size:-0}" -lt 2 ] && finding info '空的片段文件' "${f##*/} 没有任何内容"
	done

	# 4b. private keys that other accounts on the router can read.  nginx only
	# needs root to read them, and a certificate directory that the console
	# lists is where a bundled key is easy to leave world-readable.
	seen_keys=''

	for f in "$CONF_DIR"/*.key /etc/nginx/certs/*.key /etc/ssl/acme/*.key /etc/luci-uploads/*.key; do
		[ -f "$f" ] || continue

		# The same key can be matched by more than one directory, and a
		# duplicate finding adds nothing.
		case "$seen_keys" in
			*"|$f|"*) continue ;;
		esac
		seen_keys="$seen_keys|$f|"

		mode="$(ls -l "$f" 2>/dev/null | awk '{print $1}')"

		case "$mode" in
			??????---*)		;;	# no group/other bits: fine
			*)			finding warn '私钥权限过宽' "${f##*/}（$mode）对 group/other 可读，建议 chmod 600" ;;
		esac
	done

	# 5. include directives pointing at nothing
	for sec in $secs; do
		# `uci get` quotes a list value, so the quotes are stripped and the
		# value is split on whitespace by the shell itself.  eval would do
		# the same job but would also expand `$(...)` inside a value.
		inc_raw="$(uci -q get "nginx.$sec.include" 2>/dev/null | tr -d "'")"

		for inc in $inc_raw; do
			case "$inc" in
				*'*'*)
					set -- /etc/nginx/$inc
					[ -e "$1" ] || finding warn 'include 没有匹配到文件' \
						"nginx.$sec: include $inc"
					;;
				'')
					;;
				*)
					[ -e "/etc/nginx/$inc" ] || finding warn 'include 目标不存在' \
						"nginx.$sec: include $inc"
					;;
			esac
		done
	done

	json_close_array
	json_dump
	printf '\n'
}
