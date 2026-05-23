#!/usr/bin/env sh
# Tether Unblock — test suite runner
# Usage: ./tests/run_all.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PASS=0
FAIL=0
SKIP=0

red()   { printf '\033[31m%s\033[0m' "$1"; }
green() { printf '\033[32m%s\033[0m' "$1"; }
yellow(){ printf '\033[33m%s\033[0m' "$1"; }
bold()  { printf '\033[1m%s\033[0m'  "$1"; }

# --- helpers ---
run_test() {
	# $1 = label, $2 = test expression, $3 = optional skip reason
	local label="$1"
	if [ -n "${3:-}" ]; then
		printf "  %-55s %s\n" "${label}" "$(yellow "SKIP (${3})")"
		SKIP=$((SKIP + 1))
		return
	fi
	if eval "$2"; then
		printf "  %-55s %s\n" "${label}" "$(green PASS)"
		PASS=$((PASS + 1))
	else
		printf "  %-55s %s\n" "${label}" "$(red "FAIL")"
		FAIL=$((FAIL + 1))
	fi
}

assert_eq() {
	# $1 = expected, $2 = actual, $3 = label
	if [ "$1" = "$2" ]; then
		printf "  %-55s %s\n" "$3" "$(green PASS)"
		PASS=$((PASS + 1))
	else
		printf "  %-55s %s\n" "$3" "$(red "FAIL")"
		printf "         expected: %s\n" "$1"
		printf "         actual:   %s\n" "$2"
		FAIL=$((FAIL + 1))
	fi
}

assert_contains() {
	# $1 = needle, $2 = haystack, $3 = label
	if echo "$2" | grep -qF "$1"; then
		printf "  %-55s %s\n" "$3" "$(green PASS)"
		PASS=$((PASS + 1))
	else
		printf "  %-55s %s\n" "$3" "$(red "FAIL")"
		printf "         expected to contain: %s\n" "$1"
		printf "         got: %s\n" "$2"
		FAIL=$((FAIL + 1))
	fi
}

banner() {
	printf '\n%s\n' "$(bold "$1")"
}

cd "${PROJECT_DIR}"

# ============================================================
banner "=== 1. Metadata consistency ==="

PROP_VER="$(grep '^version='       module.prop | cut -d= -f2)"
PROP_VC="$(grep  '^versionCode='   module.prop | cut -d= -f2)"
PROP_ID="$(grep  '^id='            module.prop | cut -d= -f2)"
PROP_MAGISK="$(grep '^minMagisk='  module.prop | cut -d= -f2)"

if command -v python3 >/dev/null 2>&1; then
	JSON_VER="$(python3 -c "import json,sys; print(json.load(sys.stdin)['version'])"     < update.json)"
	JSON_VC="$(python3  -c "import json,sys; print(json.load(sys.stdin)['versionCode'])" < update.json)"
	assert_eq "${PROP_VER}" "${JSON_VER}" "module.prop version == update.json version"
	assert_eq "${PROP_VC}" "${JSON_VC}" "module.prop versionCode == update.json versionCode"
else
	run_test "module.prop version == update.json version"     false "python3 not found"
	run_test "module.prop versionCode == update.json versionCode" false "python3 not found"
fi

assert_eq "#MAGISK" "$(cat META-INF/com/google/android/updater-script)" \
	"updater-script contains exactly '#MAGISK'"

assert_contains "v${PROP_VER#v}" "$(cat CHANGELOG.md)" \
	"CHANGELOG.md contains version ${PROP_VER}"

run_test "module.prop has non-empty id"          "[ -n '${PROP_ID}' ]"
run_test "module.prop has non-empty version"     "[ -n '${PROP_VER}' ]"
run_test "module.prop has numeric versionCode"   "echo '${PROP_VC}' | grep -qE '^[0-9]+$'"
run_test "module.prop has minMagisk >= 20400"    "[ ${PROP_MAGISK} -ge 20400 ]"
run_test "module.prop id matches update.json"    \
	"echo '${PROP_ID}' | grep -q tether_unblock"

# ============================================================
banner "=== 2. Property consistency (service.sh ↔ uninstall.sh) ==="

# Collect set_prop keys from service.sh
SET_PROPS="$(grep -E '^\s*set_prop\s+' service.sh | \
	sed 's/.*set_prop //' | awk '{print $1}' | sort -u)"

# Collect del_prop keys from uninstall.sh
DEL_PROPS="$(grep -E '^\s*del_prop\s+' uninstall.sh | \
	sed 's/.*del_prop //' | sort -u)"

# Every set_prop key must have a matching del_prop
for prop in ${SET_PROPS}; do
	assert_contains "${prop}" "${DEL_PROPS}" \
		"uninstall.sh deletes property: ${prop}"
done

# ============================================================
banner "=== 3. ShellCheck syntax validation ==="

SH_FILES="common.sh service.sh uninstall.sh"
SHELLCHECK_SKIP=""
for f in ${SH_FILES}; do
	if command -v shellcheck >/dev/null 2>&1; then
		if shellcheck -s sh "${f}" >/dev/null 2>&1; then
			printf "  %-55s %s\n" "shellcheck ${f}" "$(green PASS)"
			PASS=$((PASS + 1))
		else
			printf "  %-55s %s\n" "shellcheck ${f}" "$(red "FAIL")"
			shellcheck -s sh "${f}"
			FAIL=$((FAIL + 1))
		fi
	else
		SHELLCHECK_SKIP="${SHELLCHECK_SKIP} ${f}"
	fi
done
[ -n "${SHELLCHECK_SKIP}" ] && \
	printf "  %-55s %s\n" "shellcheck" "$(yellow "SKIP (shellcheck not installed)")" && \
	SKIP=$((SKIP + 1))

# ============================================================
banner "=== 4. File presence & structure ==="

REQUIRED_FILES="module.prop common.sh service.sh uninstall.sh update.json CHANGELOG.md README.md LICENSE"
REQUIRED_FILES="${REQUIRED_FILES} META-INF/com/google/android/update-binary"
REQUIRED_FILES="${REQUIRED_FILES} META-INF/com/google/android/updater-script"

for f in ${REQUIRED_FILES}; do
	run_test "file exists: ${f}" "[ -f '${f}' ]"
done

run_test "common.sh exists" "[ -f 'common.sh' ]"

run_test "service.sh sources common.sh" \
	"grep -q 'common.sh' service.sh"

run_test "uninstall.sh sources common.sh" \
	"grep -q 'common.sh' uninstall.sh"

run_test "service.sh starts with #!/system/bin/sh" \
	"head -n1 service.sh | grep -q '^#!/system/bin/sh'"

run_test "uninstall.sh starts with #!/system/bin/sh" \
	"head -n1 uninstall.sh | grep -q '^#!/system/bin/sh'"

run_test "update-binary starts with #!/sbin/sh" \
	"head -n1 META-INF/com/google/android/update-binary | grep -q '^#!/sbin/sh'"

# ============================================================
banner "=== 5. Interface list sanity ==="

# The static fallback list should contain the essential interfaces
FALLBACK="$(grep 'FALLBACK_INTERFACES=' common.sh | head -n1)"
for iface in rndis0 wlan0 ap0 bt-pan; do
	assert_contains "${iface}" "${FALLBACK}" \
		"static fallback includes interface: ${iface}"
done

# Should handle ICMPv6 exclusion (preserve neighbor discovery)
run_test "nftables excludes ICMPv6 (nexthdr != ipv6-icmp)" "grep -q 'ipv6-icmp' service.sh"
run_test "nftables uses ip ttl set" "grep -q 'ip ttl set ip ttl' service.sh"
run_test "nftables uses ip6 hoplimit set" "grep -q 'ip6 hoplimit set ip6 hoplimit' service.sh"

# ============================================================
banner "=== 6. Pixel / hardware offload support ==="

run_test "service.sh disables tether_offload_disabled" \
	"grep -q 'tether_offload_disabled.*1' service.sh"

run_test "service.sh uses settings put global" \
	"grep -q 'settings put global' service.sh"

# ============================================================
banner "=== 7. VPN passthrough (WireGuard) ==="

run_test "service.sh has VPN passthrough section" \
	"grep -q 'VPN passthrough' service.sh"

run_test "service.sh detects wg* interfaces" \
	"grep -q 'wg\*' service.sh"

run_test "VPN config file referenced in scripts" \
	"grep -q 'tether_unblock_vpn.conf' common.sh"

run_test "service.sh has FORWARD rules for VPN" \
	"grep -q 'nft_add_rule inet forward' service.sh"

run_test "service.sh has masquerade for VPN" \
	"grep -q 'masquerade' service.sh"

run_test "service.sh has VPN_NO_IPV6 support" \
	"grep -q 'VPN_NO_IPV6' service.sh"

run_test "sample VPN config exists" \
	"[ -f 'tether_unblock_vpn.conf.sample' ]"

run_test "sample config documents options" \
	"grep -q 'VPN_INTERFACE\|VPN_NO_IPV6' tether_unblock_vpn.conf.sample"

run_test "common.sh has nft_init table creation" \
	"grep -q 'nft add table inet' common.sh"

# ============================================================
banner "=== 8. Enhanced logging ==="

run_test "log function has timestamp support" \
	"grep -q 'date.*%H:%M:%S' common.sh"

run_test "log function supports DEBUG level" \
	"grep -q 'LOG_LEVEL.*DEBUG\|level.*DEBUG' common.sh"

run_test "common.sh has system info dump" \
	"grep -q 'ro.product.brand' common.sh"

run_test "common.sh logs kernel version" \
	"grep -q 'uname -r' common.sh"

run_test "service.sh captures nftables BEFORE state" \
	"grep -q 'dump_nftables_state.*BEFORE' service.sh"

run_test "service.sh captures nftables AFTER state" \
	"grep -q 'dump_nftables_state.*AFTER' service.sh"

run_test "common.sh has nftables state dump function" \
	"grep -q 'dump_nftables_state' common.sh"

run_test "config supports LOG_LEVEL option" \
	"grep -q 'LOG_LEVEL' common.sh"

run_test "common.sh has log rotation (tail -n 200)" \
	"grep -q 'tail.*-n 200' common.sh"

# ============================================================
banner "=== 8. nftables support ==="

run_test "common.sh has detect_nftables function" \
	"grep -q 'detect_nftables()' common.sh"

run_test "common.sh has nft_init function" \
	"grep -q 'nft_init()' common.sh"

run_test "service.sh prefers nftables over iptables" \
	"grep -q 'HAS_NFTABLES' service.sh"

run_test "nftables TTL uses ip ttl set" \
	"grep -q 'ip ttl set ip ttl' service.sh"

run_test "nftables HL uses ip6 hoplimit" \
	"grep -q 'ip6 hoplimit set ip6 hoplimit' service.sh"

run_test "nftables excludes ICMPv6 (nexthdr != ipv6-icmp)" \
	"grep -q 'ipv6-icmp' service.sh"

run_test "uninstall.sh cleans nftables tables" \
	"grep -q 'nft delete table' uninstall.sh"

# ============================================================
banner "=== 9. Unit tests (mocked environment) ==="

if [ -x "${SCRIPT_DIR}/test_functions.sh" ]; then
	"${SCRIPT_DIR}/test_functions.sh"
	UNIT_EXIT=$?
	if [ "${UNIT_EXIT}" -eq 0 ]; then
		printf "  %-55s %s\n" "unit tests (all)" "$(green PASS)"
		PASS=$((PASS + 1))
	else
		printf "  %-55s %s\n" "unit tests (some failed)" "$(red "FAIL")"
		FAIL=$((FAIL + 1))
	fi
else
	printf "  %-55s %s\n" "unit tests" "$(yellow "SKIP (test_functions.sh not executable)")"
	SKIP=$((SKIP + 1))
fi

# ============================================================
TOTAL=$((PASS + FAIL + SKIP))
printf '\n%s\n' "$(bold "=== Results ===")"
printf "  Total:  %d\n" "${TOTAL}"
printf "  Passed: %s\n" "$(green "${PASS}")"
printf "  Failed: %s\n" "$(red "${FAIL}")"
printf "  Skipped: %s\n" "$(yellow "${SKIP}")"

[ "${FAIL}" -eq 0 ] && exit 0 || exit 1
