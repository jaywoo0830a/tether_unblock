#!/system/bin/sh
# Tether Unblock service script
# Compatible with Magisk v20.4+, KernelSU, and APatch

LOG_TAG="tether_unblock"
LOG_FILE="/data/local/tmp/${LOG_TAG}.log"
LOG_LEVEL="INFO"  # INFO or DEBUG

# ---- load optional config (for LOG_LEVEL) ----
VPN_CFG="/data/local/tmp/tether_unblock_vpn.conf"
if [ -f "${VPN_CFG}" ]; then
	cfg_level="$(grep '^LOG_LEVEL=' "${VPN_CFG}" | tail -n1 | cut -d= -f2)"
	[ "${cfg_level}" = "DEBUG" ] && LOG_LEVEL="DEBUG"
fi

# ---- logging (timestamped, leveled) ----
# Usage: log LEVEL message...
# Levels: INFO, WARN, ERROR, DEBUG (DEBUG only when LOG_LEVEL=DEBUG)
log() {
	local level="$1"; shift
	local ts
	ts="$(date '+%m-%d %H:%M:%S')"

	# DEBUG messages are suppressed unless LOG_LEVEL=DEBUG
	[ "${level}" = "DEBUG" ] && [ "${LOG_LEVEL}" != "DEBUG" ] && return

	printf '[%s] [%s] %s\n' "${ts}" "${level}" "$*" >> "${LOG_FILE}"
	log -p i -t "${LOG_TAG}" "[${level}] $*" 2>/dev/null
}

# Truncate log to last ~200 lines on each boot so it doesn't grow
# unbounded over months of uptime.
if [ -f "${LOG_FILE}" ]; then
	tail -n 200 "${LOG_FILE}" > "${LOG_FILE}.tmp" 2>/dev/null && \
		mv "${LOG_FILE}.tmp" "${LOG_FILE}" 2>/dev/null
fi

log "INFO" "===== Tether Unblock service starting (pid=$$) ====="
log "INFO" "Log level: ${LOG_LEVEL}"

# ---- system info dump (troubleshooting) ----
log "INFO" "Device: $(getprop ro.product.brand) $(getprop ro.product.model)"
log "INFO" "Android: $(getprop ro.build.version.release) (SDK $(getprop ro.build.version.sdk))"
log "INFO" "Kernel: $(uname -r)"
log "DEBUG" "All network interfaces:"
for iface in /sys/class/net/*; do
	[ -d "${iface}" ] && log "DEBUG" "  $(basename "${iface}")"
done

# ---- locate resetprop (Magisk / KernelSU / APatch) ----
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
	log "WARN" "resetprop not found — falling back to setprop"
	RESETPROP=setprop
fi
log "INFO" "Using resetprop: ${RESETPROP}"

# ---- disable tethering-detection properties ----
set_prop() {
	if "${RESETPROP}" "$1" "$2" 2>/dev/null; then
		log "INFO" "  prop: $1 = $2"
	else
		log "ERROR" "  prop: FAILED to set $1"
	fi
}

set_prop tether_dun_required           0
set_prop net.tethering.noprovisioning  true
set_prop tether_entitlement_check_state 0

# Carrier / OEM specific bypasses
set_prop ro.tether.denied              false
set_prop persist.sys.tether_data       -1
set_prop sys.usb.tethering             true      2>/dev/null  # Samsung

# Additional provisioning props used by some carriers
set_prop tethering.entitlement_check   0         2>/dev/null
set_prop sys.tethering.simslot         -1        2>/dev/null

# ---- wait for boot completion ----
log "INFO" "Waiting for boot to complete..."
until [ "$(getprop sys.boot_completed)" = 1 ]; do
	sleep 1
done
log "INFO" "Boot completed"

# ---- Google Pixel & hardware tethering offload ----
# Pixel 6+ (Tensor) and many modern Qualcomm devices use hardware-
# accelerated tethering offload (IPA/IPA-WAN) which bypasses iptables
# netfilter entirely — packets go directly from modem to Wi-Fi/USB
# without touching the CPU.  Without disabling offload, the TTL/HL
# iptables rules below have zero effect on tethered traffic.
# Trade-off: software tethering uses slightly more CPU / battery.
if command -v settings >/dev/null 2>&1; then
	# Disable hardware tethering offload (Pixel 6+, QCOM IPA)
	settings put global tether_offload_disabled 1 2>/dev/null && \
		log "INFO" "Pixel: tether_offload_disabled = 1"

	# Settings-level DUN bypass (Pixel / AOSP provisioning)
	settings put global tether_dun_required 0 2>/dev/null && \
		log "INFO" "Pixel: tether_dun_required = 0 (settings global)"

	# Additional provisioning flags used by Pixel TetheringProvisioning
	settings put global tether_dun_apn "" 2>/dev/null
	settings put global tether_supported true 2>/dev/null

	# On Android 13+ disable the new entitlement check flow
	settings put global tether_enable_legacy_dhcp_server 1 2>/dev/null
fi

# Pixel / Tensor / QCOM supplementary properties
set_prop sys.tethering.offload_disabled         1         2>/dev/null
set_prop persist.vendor.cne.feature             0         2>/dev/null

# ---- try to load kernel modules for TTL / HL targets ----
load_mod() {
	# $1 = module name (without .ko)
	for base in /system/lib/modules /vendor/lib/modules /lib/modules; do
		if [ -f "${base}/${1}.ko" ]; then
			insmod "${base}/${1}.ko" 2>/dev/null && log "INFO" "Loaded kernel module: ${1}" && return 0
		fi
	done
	# modprobe (available on newer devices)
	modprobe "$1" 2>/dev/null && log "INFO" "Loaded kernel module via modprobe: ${1}" && return 0
	return 1
}

log "INFO" "Checking kernel modules..."
load_mod xt_ttl || log "WARN" "xt_ttl module not found"
load_mod xt_HL  || log "WARN" "xt_HL module not found"

# ---- detect available iptables tools ----
HAS_IPTABLES=false
HAS_IP6TABLES=false
command -v iptables  >/dev/null 2>&1 && HAS_IPTABLES=true
command -v ip6tables >/dev/null 2>&1 && HAS_IP6TABLES=true
log "INFO" "iptables: ${HAS_IPTABLES}  ip6tables: ${HAS_IP6TABLES}"

# ---- detect tethering interfaces dynamically ----
detect_interfaces() {
	local found=""

	# Common interface name patterns for tethering
	for prefix in rndis usb ap wlan bt-pan swlan eth ncm; do
		for iface in /sys/class/net/${prefix}*; do
			[ -d "${iface}" ] && found="${found} $(basename "${iface}")"
		done 2>/dev/null
	done

	# Trim leading space
	echo "${found# }"
}

INTERFACES=$(detect_interfaces)
if [ -z "${INTERFACES}" ]; then
	# Comprehensive static fallback covering many devices
	INTERFACES="rndis0 wlan0 wlan1 ap0 bt-pan swlan0 usb0 eth0 ncm0"
	log "WARN" "No interfaces detected — using static fallback list"
fi
log "INFO" "Target interfaces: ${INTERFACES}"

# ---- apply iptables rules ----
# -w = wait for xtables lock (prevents "Resource temporarily unavailable")
# -C = check if rule exists before adding (dedup-safe)
# Usage: add_rule <bin> <chain> [-t <table>] <rule args...>
# Default table is "mangle".
add_rule() {
	local bin="$1"; shift
	local chain="$1"; shift
	local table="mangle"

	# Optional -t <table> override (e.g. "nat", "filter")
	if [ "$1" = "-t" ]; then
		table="$2"; shift 2
	fi

	# Check first to avoid duplicates
	if "${bin}" -w -t "${table}" -C "${chain}" "$@" 2>/dev/null; then
		return 0  # rule already exists
	fi
	"${bin}" -w -t "${table}" -A "${chain}" "$@" 2>/dev/null && \
		log "INFO" "  ${bin} -t ${table} -A ${chain} $*" || \
		log "ERROR" "  ${bin} -t ${table} -A ${chain} $*  -- FAILED"
}

log "INFO" "Applying iptables rules..."

# Capture pre-rule iptables state for troubleshooting
log "DEBUG" "--- iptables mangle (BEFORE) ---"
if ${HAS_IPTABLES}; then
	iptables -t mangle -L -n 2>/dev/null | while IFS= read -r line; do
		log "DEBUG" "  ${line}"
	done
fi

for IFACE in ${INTERFACES}; do
	if ${HAS_IPTABLES}; then
		add_rule iptables  PREROUTING  -i "${IFACE}" -j TTL --ttl-inc 1
		add_rule iptables  POSTROUTING -o "${IFACE}" -j TTL --ttl-inc 1
	fi

	if ${HAS_IP6TABLES}; then
		add_rule ip6tables PREROUTING  ! -p icmpv6 -i "${IFACE}" -j HL --hl-inc 1
		add_rule ip6tables POSTROUTING ! -p icmpv6 -o "${IFACE}" -j HL --hl-inc 1
	fi
done

# Capture post-rule iptables state for diff comparison
log "DEBUG" "--- iptables mangle (AFTER) ---"
if ${HAS_IPTABLES}; then
	iptables -t mangle -L -n 2>/dev/null | while IFS= read -r line; do
		log "DEBUG" "  ${line}"
	done
fi
log "DEBUG" "--- iptables nat (AFTER) ---"
iptables -t nat -L -n 2>/dev/null | while IFS= read -r line; do
	log "DEBUG" "  ${line}"
done

# ---- fallback: set default TTL / HL via proc ----
TTL_READY=false
HL_READY=false
${HAS_IPTABLES}  && grep -q TTL /proc/net/ip_tables_targets  2>/dev/null && TTL_READY=true
${HAS_IP6TABLES} && grep -q HL  /proc/net/ip6_tables_targets 2>/dev/null && HL_READY=true

if ! ${TTL_READY}; then
	echo 64 > /proc/sys/net/ipv4/ip_default_ttl 2>/dev/null && \
		log "WARN" "Fallback: IPv4 default TTL = 64"
fi

if ! ${HL_READY}; then
	# Some kernels have conf/default, others conf/all
	for path in /proc/sys/net/ipv6/conf/all/hop_limit \
	            /proc/sys/net/ipv6/conf/default/hop_limit; do
		[ -f "${path}" ] && echo 64 > "${path}" 2>/dev/null && \
			log "WARN" "Fallback: IPv6 hop_limit = 64 (${path})"
	done
fi

# ---- optional: VPN passthrough (WireGuard / any wg* interface) ----
# If a WireGuard interface is active, allow tethered traffic to pass
# through the VPN tunnel.  The carrier then only sees encrypted WireGuard
# packets — DPI, TCP fingerprinting, and User-Agent inspection are all
# defeated.  Combined with TTL increment above, this is the strongest
# possible bypass.
#
# Config (optional): /data/local/tmp/tether_unblock_vpn.conf
#   VPN_INTERFACE=wg0     Force a specific VPN interface
#   VPN_NO_IPV6=1         Skip IPv6 forwarding (use when your VPN is
#                          IPv4-only, e.g. a VPS without IPv6 support)
VPN_IFACE=""
VPN_CFG="/data/local/tmp/tether_unblock_vpn.conf"

if [ -f "${VPN_CFG}" ]; then
	VPN_IFACE="$(grep '^VPN_INTERFACE=' "${VPN_CFG}" | tail -n1 | cut -d= -f2)"
	log "INFO" "VPN config loaded from ${VPN_CFG}"
fi

# Auto-detect any wg* (WireGuard) interface if not explicitly configured
if [ -z "${VPN_IFACE}" ]; then
	for v in /sys/class/net/wg*; do
		[ -d "${v}" ] && VPN_IFACE="$(basename "${v}")" && break
	done
fi

if [ -n "${VPN_IFACE}" ] && [ -d "/sys/class/net/${VPN_IFACE}" ]; then
	log "INFO" "VPN interface detected: ${VPN_IFACE} — enabling passthrough"

	if ${HAS_IPTABLES}; then
		for IFACE in ${INTERFACES}; do
			# Forward tethered ↔ VPN (filter table)
			add_rule iptables FORWARD -t filter \
				-i "${IFACE}" -o "${VPN_IFACE}" -j ACCEPT
			add_rule iptables FORWARD -t filter \
				-i "${VPN_IFACE}" -o "${IFACE}" -j ACCEPT

			# NAT: masquerade tethered traffic as coming from
			# the VPN interface.  This is the critical rule that
			# forces tethered traffic *into* the tunnel instead
			# of going directly to the carrier.
			add_rule iptables POSTROUTING -t nat \
				-o "${VPN_IFACE}" -j MASQUERADE
		done
	fi

	# IPv6 forwarding (skip if VPN_NO_IPV6=1 in config)
	if ${HAS_IP6TABLES}; then
		if [ -f "${VPN_CFG}" ] && grep -q '^VPN_NO_IPV6=1' "${VPN_CFG}"; then
			log "INFO" "IPv6 VPN forwarding disabled (VPN_NO_IPV6=1)"
		else
			for IFACE in ${INTERFACES}; do
				add_rule ip6tables FORWARD -t filter \
					-i "${IFACE}" -o "${VPN_IFACE}" -j ACCEPT
				add_rule ip6tables FORWARD -t filter \
					-i "${VPN_IFACE}" -o "${IFACE}" -j ACCEPT
			done
		fi
	fi

	log "INFO" "VPN passthrough configured"
else
	log "INFO" "No VPN interface found (optional — see docs for WireGuard setup)"
fi

log "INFO" "===== Service finished ====="
