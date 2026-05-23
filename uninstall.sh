#!/system/bin/sh
# Tether Unblock uninstall script
# Clean up all properties set by the module

# Locate resetprop (same logic as service.sh)
RESETPROP=""
if [ -x /data/adb/magisk/resetprop ]; then
	RESETPROP=/data/adb/magisk/resetprop
elif [ -x /data/adb/ksu/bin/resetprop ]; then
	RESETPROP=/data/adb/ksu/bin/resetprop
elif [ -x /data/adb/ap/bin/resetprop ]; then
	RESETPROP=/data/adb/ap/bin/resetprop
elif command -v resetprop >/dev/null 2>&1; then
	RESETPROP=resetprop
fi

del_prop() {
	[ -n "${RESETPROP}" ] && "${RESETPROP}" --delete "$1" 2>/dev/null
}

# Core tethering properties
del_prop tether_dun_required
del_prop net.tethering.noprovisioning
del_prop tether_entitlement_check_state

# Carrier / OEM bypass properties
del_prop ro.tether.denied
del_prop persist.sys.tether_data
del_prop sys.usb.tethering
del_prop tethering.entitlement_check
del_prop sys.tethering.simslot
del_prop persist.vendor.cne.feature
del_prop sys.tethering.offload_disabled

# Restore default TTL / HL (reset to kernel defaults)
echo 64 > /proc/sys/net/ipv4/ip_default_ttl 2>/dev/null
for path in /proc/sys/net/ipv6/conf/all/hop_limit \
            /proc/sys/net/ipv6/conf/default/hop_limit; do
	[ -f "${path}" ] && echo 64 > "${path}" 2>/dev/null
done
