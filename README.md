# Tether Unblock

Some mobile network operators block tethering. This Magisk module
bypasses these restrictions by incrementing TTL/HL values on tethering
interfaces and disabling carrier tethering detection.

## How to install

Stable release:
1. Download the latest zip from the
   [releases page](https://github.com/jaywoo0830a/tether_unblock/releases)
2. Magisk -> Modules -> Install from storage -> Reboot

Master branch:
1. git clone https://github.com/jaywoo0830a/tether_unblock
2. cd tether_unblock
3. make install

## Compatibility

- Magisk v20.4+
- KernelSU (uses `resetprop` which KernelSU provides in recent versions)
- APatch
- **Google Pixel**: Pixel 6+ (Tensor) devices use hardware tethering offload
  (IPA) which bypasses iptables. This module automatically disables offload so
  TTL rules take effect. A reboot is required after installation.

### Supported devices
Tested on Google Pixel 2–8 series, Samsung Galaxy, Xiaomi, OnePlus, and most
AOSP-based ROMs. If your device has a different tethering interface name it
will be auto-detected via `/sys/class/net/`.

## Support

- [Technical Documentation](docs/README.md) — how tethering detection works, manufacturer/carrier guides
- [Telegram](https://t.me/joinchat/GsJfBBaxozXvVkSJhm0IOQ)
