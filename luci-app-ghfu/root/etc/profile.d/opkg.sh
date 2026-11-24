# POSIX-compliant opkg helper functions (active only on opkg-based systems)
command -v opkg >/dev/null 2>&1 || return 0 2>/dev/null || exit 0

opkg() {
	local OPKG_CMD="${1}"
	local OPKG_UCI
	OPKG_UCI="$(uci -q get opkg.defaults."${OPKG_CMD}")"
	case "${OPKG_CMD}" in
		init|uci|import|save|restore|rollback|upgr|export|newconf|proc|reinstall)
			shift
			"opkg_${OPKG_CMD}" "${@}"
			;;
		*)
			command opkg "${@}"
			;;
	esac
}

opkg_init() {
	uci import opkg </dev/null
	uci -q batch <<-'EOI'
		set opkg.defaults='opkg'
		set opkg.defaults.save='auto'
		set opkg.defaults.restore='auto'
		set opkg.defaults.rollback='auto'
		set opkg.defaults.upgr='ai'
		set opkg.defaults.export='ai'
		set opkg.defaults.proc='--force-overwrite --force-checksum --force-depends'
		set opkg.defaults.reinstall='--force-reinstall --force-overwrite --force-checksum --force-depends'
		set opkg.defaults.newconf='/etc'
	EOI
	printf '%s\n' "kmod ipkg" "busybox ipkg" "base-files ipkg" | opkg uci ignore
}

opkg_uci() {
	local OPKG_OPT="${1:-${OPKG_UCI}}"
	OPKG_OPT="${OPKG_OPT:-auto}"
	uci -q get opkg.defaults >/dev/null || opkg init
	{
		printf "delete opkg.'%s'\nset opkg.'%s'='opkg'\n" "${OPKG_OPT}" "${OPKG_OPT}"
		sed -r -e "s/^(.*)[[:space:]]+([^[:space:]]+)$/del_list opkg.'${OPKG_OPT}'.'\2'='\1'\nadd_list opkg.'${OPKG_OPT}'.'\2'='\1'/"
		printf "commit opkg\n"
	} | uci -q batch
}

opkg_import() {
	local OPKG_OPT="${1:-${OPKG_UCI}}"
	[ -e "${OPKG_OPT}" ] || return 0
	sed -n -r -e "s/[[:space:]]+(overlay|unknown)$/\tipkg/p" "${OPKG_OPT}" | opkg uci auto
}

opkg_save() {
	local OPKG_OPT="${1:-${OPKG_UCI}}"
	local OPKG_WR OPKG_WI OPKG_UR OPKG_CM OPKG_UI
	OPKG_WR="$(opkg export wr)"
	OPKG_WI="$(opkg export wi)"
	OPKG_UR="$(opkg export ur)"
	OPKG_CM="$(opkg export cm)"
	OPKG_UI="$(opkg export ui)"
	if uci -q get fstab.rwm >/dev/null && grep -qE '[[:space:]]/rwm[[:space:]]' /etc/mtab; then
		{
			sed -e "s/$/\trpkg/" "${OPKG_WR}"
			sed -e "s/$/\tipkg/" "${OPKG_WI}"
		} | opkg uci init
	fi
	{
		sed -e "s/$/\trpkg/" "${OPKG_UR}"
		sed -n -e "s/^-\(.*\)$/\1\trpkg/p" "${OPKG_CM}"
		sed -e "s/$/\tipkg/" "${OPKG_UI}"
		sed -n -e "/^[^-]/s/$/\tipkg/p" "${OPKG_CM}"
	} | opkg uci "${OPKG_OPT}"
	rm -f "${OPKG_WR}" "${OPKG_WI}" "${OPKG_UR}" "${OPKG_CM}" "${OPKG_UI}"
}

opkg_restore() {
	local OPKG_OPT="${1:-${OPKG_UCI}}"
	local OPKG_CONF="${OPKG_OPT}"
	local OPKG_AI OPKG_PR OPKG_PI
	OPKG_AI="$(opkg export ai)"
	OPKG_PR="$(opkg export pr)"
	OPKG_PI="$(opkg export pi)"
	uci -q get opkg >/dev/null || opkg init
	[ -s "${OPKG_PR}" ] && grep -xF -f "${OPKG_AI}" "${OPKG_PR}" | opkg proc remove
	[ -s "${OPKG_PI}" ] && grep -vxF -f "${OPKG_AI}" "${OPKG_PI}" | opkg proc install
	rm -f "${OPKG_AI}" "${OPKG_PR}" "${OPKG_PI}"
}

opkg_rollback() {
	local OPKG_OPT="${1:-${OPKG_UCI}}"
	local OPKG_CONF="${OPKG_OPT}"
	local OPKG_UR OPKG_UI OPKG_PR OPKG_PI
	OPKG_UR="$(opkg export ur)"
	OPKG_UI="$(opkg export ui)"
	OPKG_PR="$(opkg export pr)"
	OPKG_PI="$(opkg export pi)"
	if uci -q get opkg."${OPKG_CONF}" >/dev/null; then
		opkg restore "${OPKG_CONF}"
		[ -s "${OPKG_UI}" ] && grep -vxF -f "${OPKG_PI}" "${OPKG_UI}" | opkg proc remove
		[ -s "${OPKG_UR}" ] && grep -vxF -f "${OPKG_PR}" "${OPKG_UR}" | opkg proc install
	fi
	rm -f "${OPKG_UR}" "${OPKG_UI}" "${OPKG_PR}" "${OPKG_PI}"
}

opkg_upgr() {
	local OPKG_OPT="${1:-${OPKG_UCI}}"
	uci -q get opkg >/dev/null || opkg init
	case "${OPKG_OPT}" in
		ai|oi) opkg_upgr_type ;;
	esac | opkg proc upgrade
}

opkg_upgr_type() {
	local OPKG_AU OPKG_SRC
	OPKG_AU="$(opkg export au)"
	case "${OPKG_OPT}" in
		a*) OPKG_SRC="$(opkg export ai)" ;;
		o*) OPKG_SRC="$(opkg export oi)" ;;
	esac
	if [ -n "${OPKG_SRC}" ] && [ -s "${OPKG_AU}" ] && [ -s "${OPKG_SRC}" ]; then
		grep -xF -f "${OPKG_SRC}" "${OPKG_AU}"
	fi
	rm -f "${OPKG_SRC}" "${OPKG_AU}"
}

opkg_export() {
	local OPKG_OPT="${1:-${OPKG_UCI}}"
	local OPKG_TEMP
	OPKG_TEMP="$(mktemp -t opkg.XXXXXX)"
	case "${OPKG_OPT}" in
		ai|au)          opkg_export_cmd ;;
		ri|wr|wi|or|oi) opkg_export_type ;;
		ur|ui)          opkg_export_run ;;
		pr|pi|ig|cm)    opkg_export_uci ;;
	esac > "${OPKG_TEMP}"
	printf '%s\n' "${OPKG_TEMP}"
}

opkg_export_cmd() {
	case "${OPKG_OPT}" in
		?i)
			command opkg list-installed | sed -e 's/[[:space:]].*$//'
			;;
		?u)
			local OPKG_IG
			OPKG_IG="$(opkg export ig)"
			if [ -s "${OPKG_IG}" ]; then
				command opkg list-upgradable | sed -e 's/[[:space:]].*$//' | grep -v -f "${OPKG_IG}"
			else
				command opkg list-upgradable | sed -e 's/[[:space:]].*$//'
			fi
			rm -f "${OPKG_IG}"
			;;
	esac
}

opkg_export_type() {
	local OPKG_INFO="/usr/lib/opkg/info"
	local OPKG_TYPE
	case "${OPKG_OPT}" in
		r*) OPKG_INFO="/rom${OPKG_INFO}" ;;
		w*) OPKG_INFO="/rwm/upper${OPKG_INFO}" ;;
		o*) OPKG_INFO="/overlay/upper${OPKG_INFO}" ;;
	esac
	case "${OPKG_OPT}" in
		?r) OPKG_TYPE="c" ;;
		?i) OPKG_TYPE="f" ;;
	esac
	[ -d "${OPKG_INFO}" ] || return 0
	find "${OPKG_INFO}" -name "*.control" -type "${OPKG_TYPE}" 2>/dev/null \
		| sed -e 's|^.*/||;s|\.control$||'
}

opkg_export_run() {
	local OPKG_AI OPKG_RI
	OPKG_AI="$(opkg export ai)"
	OPKG_RI="$(opkg export ri)"
	case "${OPKG_OPT}" in
		?r) grep -vxF -f "${OPKG_AI}" "${OPKG_RI}" ;;
		?i) grep -vxF -f "${OPKG_RI}" "${OPKG_AI}" ;;
	esac
	rm -f "${OPKG_AI}" "${OPKG_RI}"
}

opkg_export_uci() {
	local OPKG_TYPE
	case "${OPKG_OPT}" in
		?r) OPKG_TYPE="rpkg"; OPKG_CONF="auto" ;;
		?i) OPKG_TYPE="ipkg"; OPKG_CONF="auto" ;;
		?g) OPKG_TYPE="ipkg"; OPKG_CONF="ignore" ;;
		?m) OPKG_TYPE="ipkg"; OPKG_CONF="custom" ;;
	esac
	uci -q get opkg."${OPKG_CONF}"."${OPKG_TYPE}" | tr ' ' '\n' | sed '/^$/d'
}

opkg_proc() {
	local OPKG_OPT="${OPKG_UCI}"
	local OPKG_ACT="${1:?}"
	local OPKG_PKG
	while read -r OPKG_PKG; do
		[ -n "${OPKG_PKG}" ] || continue
		command opkg "${OPKG_ACT}" "${OPKG_PKG}" ${OPKG_OPT}
	done
}

opkg_reinstall() {
	command opkg install "${@}" ${OPKG_UCI}
}

opkg_newconf() {
	local OPKG_OPT="${1:-${OPKG_UCI}}"
	find "${OPKG_OPT}" -name "*-opkg" 2>/dev/null
}
