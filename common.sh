#!/system/bin/sh
# Tether Unblock -- shared library
# Source this from service.sh, uninstall.sh, or any module script.
#
# Provides: logging, resetprop detection, property helpers,
#           nftables rule helpers, interface detection, module loading.
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

# ---- nftables detection ----
detect_nftables() {
	HAS_NFTABLES=false
	command -v nft >/dev/null 2>&1 && HAS_NFTABLES=true
	log "INFO" "nftables: ${HAS_NFTABLES}"
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

# ---- nftables support ----
# Modern Android (12+) ships nftables as the primary firewall framework.
# nftables replaces legacy {iptables,ip6tables} with a single unified tool.

detect_nftables() {
	HAS_NFTABLES=false
	command -v nft >/dev/null 2>&1 && HAS_NFTABLES=true
	log "INFO" "nftables: ${HAS_NFTABLES}"
}

# Initialise the tether_unblock nftables table (idempotent).
# Called once before adding any rules.
nft_init() {
	# Delete our table if it already exists (fresh start each boot).
	nft delete table inet tether_unblock 2>/dev/null || true
	nft delete table ip tether_unblock_nat 2>/dev/null || true

	# Main table (inet = IPv4 + IPv6 combined, for mangle & filter)
	nft add table inet tether_unblock
	nft add chain inet tether_unblock prerouting \
		'{ type filter hook prerouting priority mangle; }'
	nft add chain inet tether_unblock postrouting \
		'{ type filter hook postrouting priority mangle; }'
	nft add chain inet tether_unblock forward \
		'{ type filter hook forward priority filter; }'

	# NAT tables (must be ip/ip6 families, not inet)
	nft add table ip tether_unblock_nat
	nft add chain ip tether_unblock_nat postrouting \
		'{ type nat hook postrouting priority srcnat; }'

	log "INFO" "nftables: initialised"
}

# Add an nftables rule to a chain.
# Usage: nft_add_rule <family> <chain> <rule...>
#   family: inet | ip | ip6
#   chain:  prerouting | postrouting | forward
nft_add_rule() {
	local family="$1"; shift
	local chain="$1"; shift

	if nft add rule "${family}" tether_unblock "${chain}" "$@" 2>/dev/null; then
		log "INFO" "  nft ${family} ${chain} $*"
	else
		log "ERROR" "  nft ${family} ${chain} $*  -- FAILED"
	fi
}

# Add a NAT rule (uses the separate nat table).
nft_add_nat_rule() {
	local family="$1"; shift

	if nft add rule "${family}" tether_unblock_nat postrouting "$@" 2>/dev/null; then
		log "INFO" "  nft ${family} nat postrouting $*"
	else
		log "ERROR" "  nft ${family} nat postrouting $*  -- FAILED"
	fi
}

# Dump nftables ruleset for DEBUG logging.
dump_nftables_state() {
	local label="$1"
	log "DEBUG" "--- nftables ruleset (${label}) ---"
	nft list ruleset 2>/dev/null | while IFS= read -r line; do
		log "DEBUG" "  ${line}"
	done
}

# Clean up nftables rules on uninstall.
nft_teardown() {
	nft delete table inet tether_unblock 2>/dev/null || true
	nft delete table ip tether_unblock_nat 2>/dev/null || true
	log "INFO" "nftables: cleaned up"
}
