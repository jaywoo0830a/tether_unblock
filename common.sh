#!/system/bin/sh
# Tether Unblock -- shared library
# Source this from service.sh, uninstall.sh, or any module script.
#
# Provides: logging, resetprop detection, property helpers,
#           iptables rule helpers, interface detection, module loading.
#
# Requires: LOG_TAG, LOG_FILE, LOG_LEVEL are set before or after sourcing.

# ---- resolve script directory (Magisk $MODDIR or dirname fallback) ----
COMMON_DIR="$(dirname "$0")"
[ -n "${MODDIR:-}" ] && COMMON_DIR="${MODDIR}"

# ---- defaults (caller may override before sourcing) ----
LOG_TAG="${LOG_TAG:-tether_unblock}"
LOG_FILE="${LOG_FILE:-/data/local/tmp/${LOG_TAG}.log}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
VPN_CFG="${VPN_CFG:-/data/local/tmp/tether_unblock_vpn.conf}"

# ---- load optional config (LOG_LEVEL) ----
if [ -f "${VPN_CFG}" ]; then
	cfg_level="$(grep '^LOG_LEVEL=' "${VPN_CFG}" | tail -n1 | cut -d= -f2)"
	[ "${cfg_level}" = "DEBUG" ] && LOG_LEVEL="DEBUG"
fi

# ---- logging (timestamped, leveled) ----
# Usage: log LEVEL message...
# Levels: INFO, WARN, ERROR, DEBUG (DEBUG suppressed unless LOG_LEVEL=DEBUG)
log() {
	local level="$1"; shift
	local ts
	ts="$(date '+%m-%d %H:%M:%S')"

	[ "${level}" = "DEBUG" ] && [ "${LOG_LEVEL}" != "DEBUG" ] && return

	printf '[%s] [%s] %s\n' "${ts}" "${level}" "$*" >> "${LOG_FILE}"
	log -p i -t "${LOG_TAG}" "[${level}] $*" 2>/dev/null
}

# Rotate log to last ~200 lines to prevent unbounded growth.
rotate_log() {
	if [ -f "${LOG_FILE}" ]; then
		tail -n 200 "${LOG_FILE}" > "${LOG_FILE}.tmp" 2>/dev/null && \
			mv "${LOG_FILE}.tmp" "${LOG_FILE}" 2>/dev/null
	fi
}

# ---- locate resetprop (Magisk / KernelSU / APatch) ----
# Exports RESETPROP with the path to the best available resetprop.
find_resetprop() {
	RESETPROP=""
	if [ -x /data/adb/magisk/resetprop ]; then
		RESETPROP=/data/adb/magisk/resetprop
	elif [ -x /data/adb/ksu/bin/resetprop ]; then
		RESETPROP=/data/adb/ksu/bin/resetprop
	elif [ -x /data/adb/ap/bin/resetprop ]; then
		RESETPROP=/data/adb/ap/bin/resetprop
	elif command -v resetprop >/dev/null 2>&1; then
		RESETPROP=resetprop
	else
		log "WARN" "resetprop not found -- falling back to setprop"
		RESETPROP=setprop
	fi
	log "INFO" "Using resetprop: ${RESETPROP}"
}

# ---- property helpers ----
# Usage: set_prop NAME VALUE
set_prop() {
	if "${RESETPROP}" "$1" "$2" 2>/dev/null; then
		log "INFO" "  prop: $1 = $2"
	else
		log "ERROR" "  prop: FAILED to set $1"
	fi
}

# Usage: del_prop NAME
del_prop() {
	if [ -n "${RESETPROP}" ] && "${RESETPROP}" --delete "$1" 2>/dev/null; then
		log "INFO" "  prop: deleted $1"
	else
		log "DEBUG" "  prop: $1 already absent (or resetprop unavailable)"
	fi
}

# ---- system info dump (for troubleshooting) ----
dump_system_info() {
	log "INFO" "Device: $(getprop ro.product.brand) $(getprop ro.product.model)"
	log "INFO" "Android: $(getprop ro.build.version.release) (SDK $(getprop ro.build.version.sdk))"
	log "INFO" "Kernel: $(uname -r)"
	log "DEBUG" "All network interfaces:"
	for iface in /sys/class/net/*; do
		[ -d "${iface}" ] && log "DEBUG" "  $(basename "${iface}")"
	done
}

# ---- kernel module loader ----
# Usage: load_mod NAME  (NAME without .ko, e.g. "xt_ttl")
load_mod() {
	for base in /system/lib/modules /vendor/lib/modules /lib/modules; do
		if [ -f "${base}/${1}.ko" ]; then
			insmod "${base}/${1}.ko" 2>/dev/null && \
				log "INFO" "Loaded kernel module: ${1}" && return 0
		fi
	done
	modprobe "$1" 2>/dev/null && \
		log "INFO" "Loaded kernel module via modprobe: ${1}" && return 0
	return 1
}

# ---- iptables tool detection ----
detect_iptables() {
	HAS_IPTABLES=false
	HAS_IP6TABLES=false
	command -v iptables  >/dev/null 2>&1 && HAS_IPTABLES=true
	command -v ip6tables >/dev/null 2>&1 && HAS_IP6TABLES=true
	log "INFO" "iptables: ${HAS_IPTABLES}  ip6tables: ${HAS_IP6TABLES}"
}

# ---- dynamic interface detection ----
# Usage: INTERFACES=$(detect_interfaces)
detect_interfaces() {
	local found=""
	for prefix in rndis usb ap wlan bt-pan swlan eth ncm; do
		for iface in /sys/class/net/${prefix}*; do
			[ -d "${iface}" ] && found="${found} $(basename "${iface}")"
		done 2>/dev/null
	done
	echo "${found# }"
}

# Static fallback covering many devices.
FALLBACK_INTERFACES="rndis0 wlan0 wlan1 ap0 bt-pan swlan0 usb0 eth0 ncm0"

# ---- iptables rule helper ----
# Usage: add_rule <bin> <chain> [-t <table>] <rule args...>
# Default table: mangle.  Uses -C to check before adding (dedup-safe)
# and -w to wait for xtables lock.
add_rule() {
	local bin="$1"; shift
	local chain="$1"; shift
	local table="mangle"

	if [ "$1" = "-t" ]; then
		table="$2"; shift 2
	fi

	if "${bin}" -w -t "${table}" -C "${chain}" "$@" 2>/dev/null; then
		return 0  # rule already exists
	fi
	"${bin}" -w -t "${table}" -A "${chain}" "$@" 2>/dev/null && \
		log "INFO" "  ${bin} -t ${table} -A ${chain} $*" || \
		log "ERROR" "  ${bin} -t ${table} -A ${chain} $*  -- FAILED"
}

# ---- iptables state dump (DEBUG level) ----
dump_iptables_state() {
	local label="$1"  # "BEFORE" or "AFTER"
	log "DEBUG" "--- iptables mangle (${label}) ---"
	iptables -t mangle -L -n 2>/dev/null | while IFS= read -r line; do
		log "DEBUG" "  ${line}"
	done
	log "DEBUG" "--- iptables nat (${label}) ---"
	iptables -t nat -L -n 2>/dev/null | while IFS= read -r line; do
		log "DEBUG" "  ${line}"
	done
}
