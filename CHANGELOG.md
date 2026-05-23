# Changelog

## v2.2
- **Optional WireGuard VPN passthrough**: auto-detects `wg*` interfaces and
  routes tethered traffic through the VPN tunnel — completely defeats DPI,
  TCP fingerprinting, and User-Agent inspection at the carrier level
- `add_rule` now supports `-t <table>` override for non-mangle iptables tables
  (used by VPN FORWARD + MASQUERADE rules)
- Sample VPN config file (`tether_unblock_vpn.conf.sample`) with documentation
- **Google Pixel 6+ support**: disable hardware tethering offload (IPA) so iptables TTL/HL rules actually process tethered packets
- Pixel-specific `settings put global` commands for `tether_dun_required`, `tether_offload_disabled`, and entitlement bypass
- Dynamic tethering interface detection (auto-discovers rndis, wlan, bt-pan, usb, eth, ncm, swlan interfaces)
- Auto-load kernel modules (xt_ttl, xt_HL) when missing
- Multi-root-solution support: Magisk, KernelSU, and APatch resetprop detection
- Additional carrier bypass properties (ro.tether.denied, persist.sys.tether_data, Samsung-specific, etc.)
- Duplicate iptables rule prevention via -C check before -A
- xtables lock waiting (-w flag) to avoid "Resource temporarily unavailable"
- Structured logging to /data/local/tmp/tether_unblock.log and logcat
- Comprehensive uninstall cleanup of all properties and proc fallbacks
- Expanded static interface fallback list (swlan0, usb0, eth0, ncm0)
- Add comprehensive test suite (`make test`): metadata consistency, property symmetry,
  interface detection unit tests, kernel module loading tests, iptables format checks,
  and Pixel/hardware-offload validation
- Add `docs/` technical documentation: detection methods (TTL/HL, DUN, DPI, TCP
  fingerprinting, provisioning, hardware offload) and manufacturer/carrier-specific guide
  (Pixel, Samsung, Xiaomi, OnePlus, ASUS, Sony, Motorola, Huawei, and carriers worldwide)

## v2.1
- Add CHANGELOG.md for Magisk Manager update notes
- Add pre-commit hook for ShellCheck and version consistency checks
- Add dedicated ShellCheck CI workflow
- Overhaul release workflow with full validation, zip verification, and changelog-based release notes
- Fix zip packaging to exclude README.md, CHECKLIST.md, and hooks/
- Fix Makisk busybox path in Makefile install target
- Add Makefile setup target for pre-commit hook installation

## v2.0
- Add IPv6 hop limit manipulation (ip6tables)
- Exclude ICMPv6 from HL rules to preserve neighbor discovery
- Add fallback TTL/HL defaults via /proc when iptables targets are unavailable
- Add Magisk Manager auto-update support (updateJson)
- Add iptables/ip6tables availability checks
- Wait for boot completion before applying iptables rules
- Add USB (rndis0), Wi-Fi (wlan0/wlan1/ap0), and Bluetooth (bt-pan) tethering support

## v1.0
- Initial release
