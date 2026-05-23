#!/usr/bin/env sh
# Tether Unblock — unit tests with mocked system commands
# Run from project root: ./tests/test_functions.sh

set -u

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=""
PASS=0
FAIL=0

red()   { printf '\033[31m%s\033[0m' "$1"; }
green() { printf '\033[32m%s\033[0m' "$1"; }
yellow(){ printf '\033[33m%s\033[0m' "$1"; }
bold()  { printf '\033[1m%s\033[0m'  "$1"; }

cleanup() {
	[ -n "${TMPDIR}" ] && [ -d "${TMPDIR}" ] && rm -rf "${TMPDIR}"
}
trap cleanup EXIT

TMPDIR="$(mktemp -d)"

# ----------------------------------------------------------
# Mock infrastructure
# ----------------------------------------------------------
MOCK_DIR="${TMPDIR}/mock_bin"
mkdir -p "${MOCK_DIR}"
export PATH="${MOCK_DIR}:${PATH}"

# Shared state files that mocked commands read / write
MOCK_RESETPROP_CALLS="${TMPDIR}/resetprop_calls"
MOCK_IPTABLES_CALLS="${TMPDIR}/iptables_calls"
MOCK_IP6TABLES_CALLS="${TMPDIR}/ip6tables_calls"
MOCK_INSMOD_CALLS="${TMPDIR}/insmod_calls"
MOCK_MODPROBE_CALLS="${TMPDIR}/modprobe_calls"
MOCK_SETTINGS_CALLS="${TMPDIR}/settings_calls"
MOCK_LOG="${TMPDIR}/service.log"
MOCK_PROC="${TMPDIR}/proc"
MOCK_SYS_CLASS_NET="${TMPDIR}/sys_class_net"

> "${MOCK_RESETPROP_CALLS}"
> "${MOCK_IPTABLES_CALLS}"
> "${MOCK_IP6TABLES_CALLS}"
> "${MOCK_INSMOD_CALLS}"
> "${MOCK_MODPROBE_CALLS}"
> "${MOCK_SETTINGS_CALLS}"
> "${MOCK_LOG}"

# --- mocked resetprop ---
cat > "${MOCK_DIR}/resetprop" << 'MOCK_EOF'
#!/bin/sh
echo "$@" >> "${MOCK_RESETPROP_CALLS:?}"
exit 0
MOCK_EOF

# --- mocked setprop ---
cat > "${MOCK_DIR}/setprop" << 'MOCK_EOF'
#!/bin/sh
echo "setprop $*" >> "${MOCK_RESETPROP_CALLS:?}"
exit 0
MOCK_EOF

# --- mocked getprop ---
cat > "${MOCK_DIR}/getprop" << 'MOCK_EOF'
#!/bin/sh
case "$1" in
	sys.boot_completed) echo "1" ;;
	ro.product.brand)   echo "google" ;;
	*)                  echo "" ;;
esac
exit 0
MOCK_EOF

# --- mocked iptables ---
cat > "${MOCK_DIR}/iptables" << 'MOCK_EOF'
#!/bin/sh
echo "iptables $*" >> "${MOCK_IPTABLES_CALLS:?}"
# -C (check) should fail by default so -A is always tried
case "$*" in
	*-C*) exit 1 ;;  # rule doesn't exist yet
	*)    exit 0 ;;
esac
MOCK_EOF

# --- mocked ip6tables ---
cat > "${MOCK_DIR}/ip6tables" << 'MOCK_EOF'
#!/bin/sh
echo "ip6tables $*" >> "${MOCK_IP6TABLES_CALLS:?}"
case "$*" in
	*-C*) exit 1 ;;
	*)    exit 0 ;;
esac
MOCK_EOF

# --- mocked insmod ---
cat > "${MOCK_DIR}/insmod" << 'MOCK_EOF'
#!/bin/sh
echo "$1" >> "${MOCK_INSMOD_CALLS:?}"
exit 0
MOCK_EOF

# --- mocked modprobe ---
cat > "${MOCK_DIR}/modprobe" << 'MOCK_EOF'
#!/bin/sh
echo "modprobe $1" >> "${MOCK_MODPROBE_CALLS:?}"
exit 0
MOCK_EOF

# --- mocked settings ---
cat > "${MOCK_DIR}/settings" << 'MOCK_EOF'
#!/bin/sh
echo "settings $*" >> "${MOCK_SETTINGS_CALLS:?}"
exit 0
MOCK_EOF

# --- mocked log (logcat) ---
cat > "${MOCK_DIR}/log" << 'MOCK_EOF'
#!/bin/sh
exit 0
MOCK_EOF

chmod +x "${MOCK_DIR}"/*

# ----------------------------------------------------------
# Mock /proc and /sys filesystem
# ----------------------------------------------------------
mkdir -p "${MOCK_PROC}/net/ipv6/conf/all"
mkdir -p "${MOCK_PROC}/net/ipv6/conf/default"
mkdir -p "${MOCK_PROC}/sys/net/ipv4"

echo "TTL" > "${MOCK_PROC}/net/ip_tables_targets"
echo "HL"  > "${MOCK_PROC}/net/ip6_tables_targets"

# Virtual interfaces (simulate a Pixel 7: rndis0, wlan0, ap0)
mkdir -p "${MOCK_SYS_CLASS_NET}/rndis0"
mkdir -p "${MOCK_SYS_CLASS_NET}/wlan0"
mkdir -p "${MOCK_SYS_CLASS_NET}/ap0"
# No bt-pan — it should still appear in the static fallback

# ----------------------------------------------------------
# Helpers
# ----------------------------------------------------------
run_mock_test() {
	local label="$1"; shift
	if eval "$1"; then
		printf "  %-55s %s\n" "${label}" "$(green PASS)"
		PASS=$((PASS + 1))
	else
		printf "  %-55s %s\n" "${label}" "$(red "FAIL")"
		FAIL=$((FAIL + 1))
	fi
}

assert_file_contains()   { grep -qF "$1" "$2" 2>/dev/null; }
assert_file_not_contains(){ ! grep -qF "$1" "$2" 2>/dev/null; }
count_lines()            { wc -l < "$1" 2>/dev/null || echo 0; }

# ----------------------------------------------------------
# Source service.sh functions in a sandbox
# We can't directly source service.sh because it has side
# effects.  Extract key functions and test them in isolation.
# ----------------------------------------------------------

banner() { printf '\n%s\n' "$(bold "$1")"; }

banner "--- detect_interfaces (dynamic detection) ---"

# Re-create the detect_interfaces function from service.sh
detect_interfaces() {
	local found=""
	for prefix in rndis usb ap wlan bt-pan swlan eth ncm; do
		for iface in /sys/class/net/${prefix}*; do
			[ -d "${iface}" ] && found="${found} $(basename "${iface}")"
		done 2>/dev/null
	done
	echo "${found# }"
}

# Override /sys/class/net path for testing
detect_interfaces_at() {
	# $1 = path to fake /sys/class/net
	local found=""
	for prefix in rndis usb ap wlan bt-pan swlan eth ncm; do
		for iface in "${1}/${prefix}"*; do
			[ -d "${iface}" ] && found="${found} $(basename "${iface}")"
		done 2>/dev/null
	done
	echo "${found# }"
}

run_mock_test "detects rndis0, wlan0, ap0 in mock /sys/class/net" \
	"[ \"$(detect_interfaces_at "${MOCK_SYS_CLASS_NET}")\" = \"rndis0 ap0 wlan0\" ]"

# Empty dir
EMPTY_SYS="${TMPDIR}/empty_sys"
mkdir -p "${EMPTY_SYS}"
run_mock_test "returns empty string when no interfaces present" \
	"[ -z \"$(detect_interfaces_at "${EMPTY_SYS}")\" ]"

# Samsung swlan0 test
SAMSUNG_SYS="${TMPDIR}/samsung_sys"
mkdir -p "${SAMSUNG_SYS}/swlan0"
mkdir -p "${SAMSUNG_SYS}/rndis0"
run_mock_test "detects Samsung swlan0 interface" \
	"[ \"$(detect_interfaces_at "${SAMSUNG_SYS}")\" = \"rndis0 swlan0\" ]"

# USB ethernet test
USB_SYS="${TMPDIR}/usb_sys"
mkdir -p "${USB_SYS}/usb0"
mkdir -p "${USB_SYS}/eth0"
run_mock_test "detects usb0 and eth0 interfaces" \
	"[ \"$(detect_interfaces_at "${USB_SYS}")\" = \"usb0 eth0\" ]"

# NCM test
NCM_SYS="${TMPDIR}/ncm_sys"
mkdir -p "${NCM_SYS}/ncm0"
run_mock_test "detects ncm0 interface" \
	"[ \"$(detect_interfaces_at "${NCM_SYS}")\" = \"ncm0\" ]"

banner "--- load_mod (kernel module loading) ---"

# Re-create the function
load_mod() {
	for base in /system/lib/modules /vendor/lib/modules /lib/modules; do
		if [ -f "${base}/${1}.ko" ]; then
			insmod "${base}/${1}.ko" 2>/dev/null && return 0
		fi
	done
	modprobe "$1" 2>/dev/null && return 0
	return 1
}

# Test with module present
MOD_SYS="${TMPDIR}/mod_sys"
mkdir -p "${MOD_SYS}/system/lib/modules"
touch "${MOD_SYS}/system/lib/modules/xt_ttl.ko"

load_mod_at() {
	for base in "${1}/system/lib/modules" "${1}/vendor/lib/modules" "${1}/lib/modules"; do
		if [ -f "${base}/${2}.ko" ]; then
			return 0
		fi
	done
	return 1
}

run_mock_test "load_mod finds module in /system/lib/modules" \
	"load_mod_at '${MOD_SYS}' xt_ttl"

run_mock_test "load_mod returns 1 for missing module" \
	"! load_mod_at '${MOD_SYS}' nonexistent"

# Vendor path
MOD_VENDOR="${TMPDIR}/mod_vendor"
mkdir -p "${MOD_VENDOR}/vendor/lib/modules"
touch "${MOD_VENDOR}/vendor/lib/modules/xt_HL.ko"

run_mock_test "load_mod finds module in /vendor/lib/modules" \
	"load_mod_at '${MOD_VENDOR}' xt_HL"

banner "--- set_prop / del_prop consistency ---"

# Parse actual files into temp files (avoids multi-line-in-eval issues)
SET_PROPS_FILE="${TMPDIR}/set_props"
DEL_PROPS_FILE="${TMPDIR}/del_props"
grep -E '^\s*set_prop\s+' "${PROJECT_DIR}/service.sh" | \
	sed 's/.*set_prop //' | awk '{print $1}' | sort -u > "${SET_PROPS_FILE}"
grep -E '^\s*del_prop\s+' "${PROJECT_DIR}/uninstall.sh" | \
	sed 's/.*del_prop //' | sort -u > "${DEL_PROPS_FILE}"

# Check every set_prop has matching del_prop
check_prop_consistency() {
	while IFS= read -r prop; do
		[ -z "${prop}" ] && continue
		if ! grep -qxF "${prop}" "${DEL_PROPS_FILE}"; then
			return 1
		fi
	done < "${SET_PROPS_FILE}"
	return 0
}
run_mock_test "all set_prop keys have matching del_prop" "check_prop_consistency"

# Core properties must be present
for prop in tether_dun_required net.tethering.noprovisioning tether_entitlement_check_state; do
	run_mock_test "core property in set_props: ${prop}" \
		"grep -qxF '${prop}' '${SET_PROPS_FILE}'"
done
for prop in tether_dun_required net.tethering.noprovisioning tether_entitlement_check_state; do
	run_mock_test "core property in del_props: ${prop}" \
		"grep -qxF '${prop}' '${DEL_PROPS_FILE}'"
done

banner "--- Settings commands (Pixel) ---"

SETTINGS_LINES="$(grep -c 'settings put global' "${PROJECT_DIR}/service.sh" || echo 0)"

run_mock_test "service.sh has tether_offload_disabled setting" \
	"grep -q 'tether_offload_disabled.*1' '${PROJECT_DIR}/service.sh'"

run_mock_test "service.sh has tether_dun_required setting" \
	"grep -q 'tether_dun_required.*0' '${PROJECT_DIR}/service.sh'"

run_mock_test "service.sh has at least 3 settings commands" \
	"[ ${SETTINGS_LINES} -ge 3 ]"

banner "--- iptables rule format ---"

run_mock_test "iptables uses TTL target" \
	"grep -q 'iptables.*TTL' '${PROJECT_DIR}/service.sh'"

run_mock_test "ip6tables uses HL target" \
	"grep -q 'ip6tables.*HL' '${PROJECT_DIR}/service.sh'"

run_mock_test "TTL --ttl-inc value is 1" \
	"grep -q -- '--ttl-inc 1' '${PROJECT_DIR}/service.sh'"

run_mock_test "HL --hl-inc value is 1" \
	"grep -q -- '--hl-inc 1' '${PROJECT_DIR}/service.sh'"

run_mock_test "iptables rules use -w (xtables lock)" \
	"grep -q -- '-w.*-t' '${PROJECT_DIR}/service.sh'"

banner "--- Fallback /proc values ---"

run_mock_test "IPv4 default TTL fallback = 64" \
	"grep -q '64.*ip_default_ttl' '${PROJECT_DIR}/service.sh'"

run_mock_test "IPv6 hop_limit fallback = 64" \
	"grep -q 'hop_limit.*64' '${PROJECT_DIR}/service.sh'"

run_mock_test "IPv6 fallback tries conf/all path" \
	"grep -q 'conf/all/hop_limit' '${PROJECT_DIR}/service.sh'"

run_mock_test "IPv6 fallback tries conf/default path" \
	"grep -q 'conf/default/hop_limit' '${PROJECT_DIR}/service.sh'"

banner "--- Boot wait loop ---"

run_mock_test "service.sh waits for sys.boot_completed" \
	"grep -q 'sys.boot_completed' '${PROJECT_DIR}/service.sh'"

run_mock_test "boot wait has sleep to avoid busy-loop" \
	"grep -q 'sleep 1' '${PROJECT_DIR}/service.sh'"

banner "--- VPN passthrough (WireGuard) ---"

run_mock_test "service.sh detects wg* interfaces" \
	"grep -q '/sys/class/net/wg\*' '${PROJECT_DIR}/service.sh'"

run_mock_test "service.sh reads VPN config file" \
	"grep -q 'tether_unblock_vpn.conf' '${PROJECT_DIR}/service.sh'"

run_mock_test "VPN section has FORWARD rules" \
	"grep -q 'FORWARD.*-t filter' '${PROJECT_DIR}/service.sh'"

run_mock_test "VPN section has MASQUERADE rule" \
	"grep -q 'MASQUERADE' '${PROJECT_DIR}/service.sh'"

run_mock_test "VPN section handles IPv6" \
	"grep -q 'ip6tables.*FORWARD' '${PROJECT_DIR}/service.sh'"

run_mock_test "VPN section respects VPN_NO_IPV6" \
	"grep -q 'VPN_NO_IPV6=1' '${PROJECT_DIR}/service.sh'"

run_mock_test "add_rule function supports -t table" \
	"grep -q 'table=' '${PROJECT_DIR}/service.sh'"

banner "--- Enhanced logging ---"

run_mock_test "log function uses timestamp format" \
	"grep -q 'date.*%H:%M' '${PROJECT_DIR}/service.sh'"

run_mock_test "DEBUG messages are gated on LOG_LEVEL" \
	"grep -q 'LOG_LEVEL.*DEBUG' '${PROJECT_DIR}/service.sh'"

run_mock_test "system info dump includes device model" \
	"grep -q 'ro.product.model' '${PROJECT_DIR}/service.sh'"

run_mock_test "log file is rotated on each boot" \
	"grep -q 'tail.*-n 200.*LOG_FILE' '${PROJECT_DIR}/service.sh'"

run_mock_test "failed property set logs as ERROR" \
	"grep -q 'ERROR.*FAILED to set' '${PROJECT_DIR}/service.sh'"

run_mock_test "failed iptables rule logs as ERROR" \
	"grep -q 'ERROR.*FAILED' '${PROJECT_DIR}/service.sh'"

# ----------------------------------------------------------
printf '\n'
printf "  Unit tests: %s passed, %s failed\n" \
	"$(green "${PASS}")" "$(red "${FAIL}")"
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1
