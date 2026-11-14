#!/bin/sh
# Auxiliary functions specially used for reading and writing YAML
#
# config_editor KEY VALUE FILE [RO]
#   RO empty:     set KEY (dotted path, e.g. dns.port) to VALUE in FILE.
#   RO non-empty: print the current value of KEY.
#
# Security: this runs as root on a file that lives in a directory owned by the
# unprivileged AdGuardHome user, so nothing taken from the file or from VALUE is
# ever handed to a shell. VALUE reaches awk through the environment (no -v escape
# processing) and the rewrite is done by awk itself, not by system("sed ...").
config_editor() {
	local key="$1" value="$2" file="$3" ro="$4" tmp new nl
	nl='
'
	[ -f "$file" ] && [ ! -L "$file" ] || return 1

	if [ -n "$ro" ]; then
		AGH_VALUE="" awk -v yaml="$key" -v ro="$ro" "$AGH_YAML_AWK" "$file"
		return
	fi

	# A newline or CR in the value would inject extra YAML lines.
	case "$value" in
	*"$nl"*|*"$(printf '\r')"*) return 1 ;;
	esac

	tmp="$(mktemp /tmp/agh_yaml.XXXXXX)" || return 1
	if AGH_VALUE="$value" awk -v yaml="$key" -v ro="" "$AGH_YAML_AWK" "$file" > "$tmp" && [ -s "$tmp" ]; then
		# Replace the file atomically: AdGuardHome may be (re)starting right now,
		# and truncating it in place lets it read an empty file and overwrite the
		# whole config with defaults. mktemp (O_EXCL) in the same directory gives
		# a rename on the same filesystem and cannot be redirected by a symlink.
		new="$(mktemp "$file.XXXXXX")" || { rm -f "$tmp"; return 1; }
		if cat "$tmp" > "$new" \
			&& chown "$(ls -ln "$file" | awk '{print $3":"$4}')" "$new" \
			&& chmod "$(ls -l "$file" | awk '{m=0; s=substr($1,2,9); for(i=1;i<=9;i++) if(substr(s,i,1)!="-") m+=2^(9-i); printf "%o", m}')" "$new" \
			&& mv -f "$new" "$file"; then
			:
		else
			rm -f "$new"
		fi
	fi
	rm -f "$tmp"
}

# Same key-matching logic as before (first "a:" then nested "[- ]{2}b:" ...),
# but the matching line is rewritten in awk instead of via system().
AGH_YAML_AWK='
BEGIN {
	n = split(yaml, part, ".")
	s = ""; i = 1; done = 0
	value = ENVIRON["AGH_VALUE"]
}
{
	if (!done && match($0, s part[i] ":")) {
		if (i == n) {
			done = 1
			idx = index($0, ": ")
			if (idx > 0) {
				key = substr($0, 1, idx - 1)
				cur = substr($0, idx + 2)
			} else {
				key = $0
				sub(/:[ \t]*$/, "", key)
				cur = ""
			}
			if (ro != "") { print cur; exit }
			print key ": " value
			next
		}
		s = s "[- ]{2}"
		i++
	}
	if (ro == "") print
}'
