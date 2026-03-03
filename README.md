# Tether Unblock

Some mobile network operators block tethering. This Magisk module
bypasses these restrictions by incrementing TTL/HL values on tethering
interfaces and disabling carrier tethering detection.

## How to install

Stable release:
1. Download the latest zip from the
   [releases page](https://github.com/evdenis/tether_unblock/releases)
2. Magisk -> Modules -> Install from storage -> Reboot

Master branch:
1. git clone https://github.com/evdenis/tether_unblock
2. cd tether_unblock
3. make install

## Compatibility

- Magisk v20.4+
- KernelSU (uses `resetprop` which KernelSU provides in recent versions)

## Support

- [Telegram](https://t.me/joinchat/GsJfBBaxozXvVkSJhm0IOQ)
