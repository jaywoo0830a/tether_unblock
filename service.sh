#!/system/bin/sh
# Tether Unblock -- service script
# Runs at late_start service boot stage.
# Compatible with Magisk v20.4+, KernelSU, and APatch.

SCRIPT_DIR="$(dirname "$0")"
[ -n "${MODDIR:-}" ] && SCRIPT_DIR="${MODDIR}"
. "${SCRIPT_DIR}/common.sh"

rotate_log
log "INFO" "===== Tether Unblock service starting (pid=$$) ====="
log "INFO" "Log level: ${LOG_LEVEL}"

# ---- system info ----
dump_system_info

# ---- locate resetprop ----
find_resetprop

# ---- disable tethering-detection properties ----
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
# Pixel 6+ (Tensor) and many Qualcomm devices use hardware offload (IPA)
# which bypasses iptables entirely.  Disabling it forces traffic through
# the CPU where our TTL/HL rules can process it.
if command -v settings >/dev/null 2>&1; then
	settings put global tether_offload_disabled 1 2>/dev/null && \
		log "INFO" "Pixel: tether_offload_disabled = 1"
	settings put global tether_dun_required 0 2>/dev/null && \
		log "INFO" "Pixel: tether_dun_required = 0 (settings global)"
	settings put global tether_dun_apn "" 2>/dev/null
	settings put global tether_supported true 2>/dev/null
	settings put global tether_enable_legacy_dhcp_server 1 2>/dev/null
fi

set_prop sys.tethering.offload_disabled         1         2>/dev/null
set_prop persist.vendor.cne.feature             0         2>/dev/null

# ---- detect nftables (required on Android 12+) ----
detect_nftables
if ! ${HAS_NFTABLES}; then
	log "ERROR" "nftables not available — tethering bypass cannot apply rules"
	log "ERROR" "This module requires Android 12+ with nftables support."
	log "INFO" "===== Service aborted (no nftables) ====="
	exit 0
fi

# ---- detect tethering interfaces ----
INTERFACES=$(detect_interfaces)
if [ -z "${INTERFACES}" ]; then
	INTERFACES="${FALLBACK_INTERFACES}"
	log "WARN" "No interfaces detected -- using static fallback list"
fi
log "INFO" "Target interfaces: ${INTERFACES}"

# ---- apply TTL / HL rules via nftables ----
if ${HAS_NFTABLES}; then
log "INFO" "Applying nftables rules..."
nft_init
dump_nftables_state "BEFORE"

for IFACE in ${INTERFACES}; do
	nft_add_rule inet prerouting \
		iifname "${IFACE}" ip ttl set ip ttl + 1
	nft_add_rule inet postrouting \
		oifname "${IFACE}" ip ttl set ip ttl + 1

	nft_add_rule inet prerouting \
		iifname "${IFACE}" ip6 nexthdr != ipv6-icmp \
		ip6 hoplimit set ip6 hoplimit + 1
	nft_add_rule inet postrouting \
		oifname "${IFACE}" ip6 nexthdr != ipv6-icmp \
		ip6 hoplimit set ip6 hoplimit + 1
done

dump_nftables_state "AFTER"
fi

# ---- /proc fallback (safety net) ----
# nftables handles TTL natively, but set /proc defaults as safety net.
echo 64 > /proc/sys/net/ipv4/ip_default_ttl 2>/dev/null || true
for path in /proc/sys/net/ipv6/conf/all/hop_limit \
            /proc/sys/net/ipv6/conf/default/hop_limit; do
	[ -f "${path}" ] && echo 64 > "${path}" 2>/dev/null || true
done

# ---- optional: VPN passthrough (WireGuard) ----
# Auto-detects wg* interfaces and routes tethered traffic through
# the VPN tunnel, completely defeating DPI and TCP fingerprinting.
VPN_IFACE=""

if [ -f "${VPN_CFG}" ]; then
	VPN_IFACE="$(grep '^VPN_INTERFACE=' "${VPN_CFG}" | tail -n1 | cut -d= -f2)"
	log "INFO" "VPN config loaded from ${VPN_CFG}"
fi

if [ -z "${VPN_IFACE}" ]; then
	for v in /sys/class/net/wg*; do
		[ -d "${v}" ] && VPN_IFACE="$(basename "${v}")" && break
	done
fi

if [ -n "${VPN_IFACE}" ] && [ -d "/sys/class/net/${VPN_IFACE}" ]; then
	log "INFO" "VPN interface detected: ${VPN_IFACE} -- enabling passthrough"

	if ${HAS_NFTABLES}; then
		# ---- nftables VPN path ----
		for IFACE in ${INTERFACES}; do
			nft_add_rule inet forward \
				iifname "${IFACE}" oifname "${VPN_IFACE}" accept
			nft_add_rule inet forward \
				iifname "${VPN_IFACE}" oifname "${IFACE}" accept
		done
		nft_add_nat_rule ip \
			oifname "${VPN_IFACE}" masquerade

		# IPv6 NAT
		if [ -f "${VPN_CFG}" ] && grep -q '^VPN_NO_IPV6=1' "${VPN_CFG}"; then
			log "INFO" "IPv6 VPN forwarding disabled (VPN_NO_IPV6=1)"
		else
			nft_add_nat_rule ip6 \
				oifname "${VPN_IFACE}" masquerade
		fi
	fi

	log "INFO" "VPN passthrough configured"
else
	log "INFO" "No VPN interface found (optional)"
fi

log "INFO" "===== Service finished ====="
