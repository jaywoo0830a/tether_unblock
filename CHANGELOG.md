# Changelog

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
