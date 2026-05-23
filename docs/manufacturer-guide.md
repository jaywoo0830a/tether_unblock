# Manufacturer & Carrier Guide

Device-specific behaviors, interface names, and carrier-specific bypass
strategies for tethering.

---

## Manufacturers

### Google Pixel

| Aspect | Detail |
|---|---|
| **Interfaces** | USB: `rndis0`, Wi-Fi: `ap0` (Pixel 6+), `wlan0`/`wlan1` (older) |
| **Key issue** | **Hardware tethering offload (IPA)** — iptables bypassed entirely |
| **Chipset** | Tensor (Pixel 6+) / Qualcomm Snapdragon (Pixel 5 and older) |
| **Provisioning** | Standard AOSP `TetheringProvisioning` via `NetworkStack` |
| **Android version** | Stock Android, fastest updates |

#### Pixel-specific properties
```sh
settings put global tether_offload_disabled 1    # CRITICAL for Pixel 6+
settings put global tether_dun_required 0
settings put global tether_dun_apn ""
settings put global tether_supported true
settings put global tether_enable_legacy_dhcp_server 1
```

#### Pixel 6+ (Tensor) — Why most modules fail
Tensor's IPA hardware offload routes packets from modem to Wi-Fi directly.
The Linux kernel never sees the packets — iptables rules are **silently
ineffective**. This is why users report "module installed but tethering
still blocked". Without `tether_offload_disabled=1`, the TTL manipulation
cannot work.

#### Pixel 2–5 (Snapdragon)
These use Qualcomm's IPA but may not have the aggressive offload policy.
The older `wlan0`/`wlan1` interface names apply. Generally work with
standard TTL rules.

---

### Samsung

| Aspect | Detail |
|---|---|
| **Interfaces** | USB: `rndis0`, Wi-Fi: **`swlan0`** (Samsung-specific!) |
| **Key issue** | Samsung uses `swlan0` instead of `ap0`/`wlan1` for hotspot |
| **Chipset** | Exynos (international) / Snapdragon (US) |
| **One UI** | Adds Knox security, CSC-based tethering restrictions |

#### Samsung-specific properties
```sh
resetprop sys.usb.tethering true    # Force USB tethering enabled
```

#### CSC Tethering Restrictions
Samsung devices sold through carriers (T-Mobile, AT&T, Verizon) have CSC
(Consumer Software Customization) files that enforce tethering restrictions
at the framework level. These include:
- `cscfeature.xml` — `CscFeature_Setting_EnableDefaultApnProvisioning`
- `others.xml` — tethering entitlement configurations

This module does NOT modify CSC files (requires root file system access and
can trigger Knox warranty bit). Instead, the runtime property bypass
(`net.tethering.noprovisioning`) overrides the CSC policy in most cases.

#### Exynos vs Snapdragon
- **Exynos**: Generally less restrictive, `swlan0` is the critical interface
- **Snapdragon (US)**: May have additional modem-level tethering checks.
  If TTL bypass doesn't work, try also setting DUN APN to match default APN.

---

### Xiaomi (MIUI / HyperOS)

| Aspect | Detail |
|---|---|
| **Interfaces** | USB: `rndis0`, Wi-Fi: `wlan0`/`wlan1` (MIUI may rename) |
| **Key issue** | MIUI's modified networking stack may ignore standard properties |
| **Chipset** | Qualcomm Snapdragon / MediaTek Dimensity |
| **MIUI version** | MIUI 12–14, HyperOS 1.0 |

#### MIUI-specific behavior
MIUI uses a heavily modified Android framework. Some versions ignore
`net.tethering.noprovisioning` because MIUI's `WifiService` and
`ConnectivityService` are custom implementations.

#### Additional bypass for MIUI
```sh
# MIUI sometimes checks these additional properties
resetprop persist.sys.tether_data -1
resetprop ro.tether.denied false

# Some MIUI versions need the settings DB approach
settings put global tether_dun_required 0
```

#### MIUI Dual SIM
If using dual SIM, specify which SIM slot for tethering:
```sh
resetprop sys.tethering.simslot -1   # Auto (use data SIM)
```

#### MediaTek (Dimensity) devices
MediaTek chipsets may use different interface names:
- `ccmni0`, `ccmni1` — some Redmi/POCO devices
- Module's dynamic detection covers these via `/sys/class/net/`

---

### OnePlus (OxygenOS / ColorOS)

| Aspect | Detail |
|---|---|
| **Interfaces** | USB: `rndis0`, Wi-Fi: `wlan0`/`wlan1`/`ap0` (varies by model) |
| **Key issue** | OxygenOS 12+ merged with ColorOS — Oppo's restrictions apply |
| **Chipset** | Qualcomm Snapdragon |
| **OS versions** | OxygenOS 11 (near-stock) → OxygenOS 12+ (ColorOS base) |

OnePlus devices on OxygenOS 11 and earlier behave like standard AOSP. From
OxygenOS 12 onwards, the ColorOS merge introduced Chinese-market restrictions
that may interfere with tethering bypass:

```sh
# Additional Oppo/ColorOS properties
resetprop persist.sys.tether_data -1
resetprop sys.tethering.supported 1
```

---

### ASUS (ZenUI)

| Aspect | Detail |
|---|---|
| **Interfaces** | USB: `rndis0`, Wi-Fi: `wlan0`/`wlan1` |
| **Key issue** | ZenUI may have vendor-specific tethering overlay |
| **Chipset** | Qualcomm Snapdragon / MediaTek |

ASUS devices are generally close to AOSP. Standard properties and TTL
rules work in most cases. No special handling needed beyond the defaults.

---

### Sony (Xperia)

| Aspect | Detail |
|---|---|
| **Interfaces** | USB: `rndis0`, Wi-Fi: `wlan0`/`wlan1` |
| **Key issue** | Very close to AOSP — few customizations |
| **Chipset** | Qualcomm Snapdragon |

Sony Xperia devices run near-stock Android with minimal modifications.
Standard TTL bypass works reliably.

---

### Motorola / Lenovo

| Aspect | Detail |
|---|---|
| **Interfaces** | USB: `rndis0`, Wi-Fi: `wlan0`/`ap0` |
| **Key issue** | Near-AOSP, but carrier-locked models may have extra restrictions |
| **Chipset** | Qualcomm Snapdragon / MediaTek |

Motorola's Android is close to AOSP. Carrier-locked models (Verizon, AT&T)
may have additional provisioning checks that the standard property bypass
handles.

---

### Huawei / Honor (Pre-sanctions)

| Aspect | Detail |
|---|---|
| **Interfaces** | USB: `rndis0`, Wi-Fi: `wlan0`/`wlan1` |
| **Key issue** | EMUI's aggressive power management may kill tethering |
| **Chipset** | Kirin (HiSilicon) |

Pre-sanctions Huawei devices running EMUI may have aggressive battery
optimization that interferes with long-running tethering sessions.
No specific tethering detection differences — TTL bypass works if
iptables is available.

---

## Carriers

### United States

#### T-Mobile
| Aspect | Detail |
|---|---|
| **Detection method** | TTL analysis + HTTP DPI (declining) |
| **DUN APN** | `pcweb.t-mobile.com` (may be auto-detected) |
| **Enforcement** | Moderate — mostly TTL-based, some plans include tethering |

T-Mobile primarily uses TTL inspection. The TTL increment rules are
highly effective. On older plans, DUN APN separation may apply.

#### AT&T
| Aspect | Detail |
|---|---|
| **Detection method** | DUN APN + provisioning check |
| **DUN APN** | `phone` / `nxtgenphone` (DUN separated) |
| **Enforcement** | Aggressive on older plans |

AT&T uses DUN APN separation more strictly than other US carriers.
Setting `tether_dun_required=0` is essential.

#### Verizon
| Aspect | Detail |
|---|---|
| **Detection method** | Entitlement check + DUN |
| **Enforcement** | Plan-dependent |

Verizon's newer unlimited plans include tethering. Older plans require
the entitlement bypass. Standard properties handle this.

---

### South Korea

Korean carriers use some of the most aggressive tethering detection globally,
including deep packet inspection at the carrier level.

#### SK Telecom (SKT)
| Aspect | Detail |
|---|---|
| **Detection method** | TTL + DPI (HTTP User-Agent, TCP fingerprinting) |
| **Enforcement** | Very aggressive — may throttle or charge extra |

SKT is known for HTTP User-Agent inspection on unencrypted traffic.
TTL bypass alone may not be sufficient. Recommendations:
- Always use HTTPS
- Consider using a VPN (obscures all traffic patterns)
- TTL increment + DUN bypass handles the OS-level check

#### KT (Korea Telecom)
| Aspect | Detail |
|---|---|
| **Detection method** | TTL + provisioning + DPI |
| **Enforcement** | Aggressive — data caps on tethering |

Similar to SKT. TTL bypass is effective for the network-level detection.

#### LG U+
| Aspect | Detail |
|---|---|
| **Detection method** | TTL + provisioning |
| **Enforcement** | Moderate |

Standard TTL bypass works in most cases.

---

### Europe

#### Vodafone (Pan-European)
| Aspect | Detail |
|---|---|
| **Detection method** | TTL + HTTP DPI (varies by country) |
| **Enforcement** | Moderate — country-dependent |

Vodafone operates across multiple European countries with varying policies.
TTL bypass is generally sufficient. In Germany and UK, DPI may be used.

#### Deutsche Telekom (Germany)
| Aspect | Detail |
|---|---|
| **Detection method** | TTL + DUN APN |
| **Enforcement** | Moderate |

Standard property + TTL bypass works.

#### Orange (France / Pan-European)
| Aspect | Detail |
|---|---|
| **Detection method** | TTL + provisioning |
| **Enforcement** | Plan-dependent |

#### EE / BT (UK)
| Aspect | Detail |
|---|---|
| **Detection method** | TTL + DUN |
| **Enforcement** | Moderate |

---

### Japan

#### NTT Docomo
| Aspect | Detail |
|---|---|
| **Detection method** | TTL + DPI (HTTP User-Agent known to be used) |
| **Enforcement** | Aggressive — tethering is a separate paid option |

NTT Docomo uses HTTP User-Agent inspection on unencrypted traffic.
TTL bypass + HTTPS is recommended.

#### KDDI (au)
| Aspect | Detail |
|---|---|
| **Detection method** | TTL + provisioning |
| **Enforcement** | Moderate |

#### SoftBank
| Aspect | Detail |
|---|---|
| **Detection method** | TTL + DUN APN |
| **Enforcement** | Plan-dependent |

---

### Other Notable Carriers

#### China Mobile / China Unicom / China Telecom
Chinese carriers use deep packet inspection extensively, including TCP
fingerprinting. TTL bypass + VPN is recommended for reliable tethering.
Note: VPN usage itself may be restricted on some plans.

#### Jio (India)
Jio uses TTL inspection and has been known to block tethering on some
plans. TTL increment rules are effective. IPv6 is heavily used — ensure
ip6tables HL rules are applied.

#### Airtel (India)
Standard TTL-based detection. Standard bypass works.

#### Telstra / Optus / Vodafone (Australia)
Standard TTL + provisioning detection. Standard bypass works.

---

## Interface Name Reference

This module auto-detects interfaces but has a comprehensive static fallback:

| Interface | Device / Scenario |
|---|---|
| `rndis0` | USB tethering (universal standard) |
| `wlan0` | Primary Wi-Fi (most devices) |
| `wlan1` | Secondary Wi-Fi / hotspot (older devices) |
| `ap0` | Wi-Fi hotspot (Pixel 6+, modern Android) |
| `swlan0` | Samsung Wi-Fi hotspot |
| `bt-pan` | Bluetooth tethering |
| `usb0` | USB tethering (alternate naming, Linux-style) |
| `eth0` | Ethernet tethering (rare, some tablets) |
| `ncm0` | USB CDC-NCM (newer USB tethering standard) |
| `ccmni0/1` | MediaTek cellular interface (some Xiaomi/POCO) |

Dynamic detection covers all of these. If your device uses a different
name, it will be picked up automatically from `/sys/class/net/`.

---

## Optional: WireGuard VPN Passthrough

For carriers that use **Deep Packet Inspection** (DPI), TCP fingerprinting,
or HTTP User-Agent analysis, TTL bypass alone may not be enough. The module
can **optionally** route tethered traffic through an active WireGuard tunnel
so the carrier sees only encrypted WireGuard packets.

### How It Works

```
Without VPN:
  Laptop → Phone(rndis0) → TTL+1 → Carrier(sees TTL=64, but can DPI HTTP)
                                  ↑
                          DPI can still see unencrypted HTTP headers!

With VPN Passthrough:
  Laptop → Phone(rndis0) → TTL+1 → WireGuard(wg0) → Carrier(only sees 🔒)
                                                    ↑
                                   All traffic is encrypted WireGuard.
                                   DPI, User-Agent, TCP fingerprinting
                                   are completely defeated.
```

### Setup

1. **Install WireGuard** from Google Play or F-Droid
2. **Configure a tunnel** to any WireGuard server (self-hosted VPS, 3rd party, etc.)
3. **Activate the tunnel** in the WireGuard app
4. **That's it** — the module auto-detects `wg0` and adds forwarding rules

### Configuration (Optional)

Most users don't need any configuration. The module auto-detects any `wg*`
interface. If you need to override:

```sh
# Push the sample config (edit first if needed):
adb push tether_unblock_vpn.conf.sample /data/local/tmp/tether_unblock_vpn.conf

# Options:
#   VPN_INTERFACE=wg0    Force specific interface (default: auto-detect)
#   VPN_NO_IPV6=1        Skip IPv6 forwarding if VPN is IPv4-only
```

### What The Module Does

When a `wg*` interface is detected, it adds these iptables rules:

```sh
# Allow forwarding between tethered and VPN interfaces
iptables -A FORWARD -i rndis0 -o wg0 -j ACCEPT
iptables -A FORWARD -i wg0 -o rndis0 -j ACCEPT

# Force tethered traffic through the VPN tunnel (critical!)
iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE
```

The `MASQUERADE` rule is the key — without it, Android's default routing
sends tethered traffic directly to the carrier instead of through the VPN.

### IPv6 Note

If your WireGuard server doesn't support IPv6 (common with cheap VPS),
set `VPN_NO_IPV6=1` in the config file. This prevents IPv6 forwarding
rules. Tethered IPv6 traffic will still go through the normal path
(bypassed by TTL increment), but won't go through the VPN.

### Limitations

- The VPN must be **already active** when tethering starts. The module
  runs once at boot (late_start service). If you start WireGuard later,
  reboot or restart the module.
- Only `wg*` interfaces are auto-detected. For OpenVPN (`tun0`) or
  other VPNs, specify the interface name in the config file.
- Combined TTL+VPN bypass may use slightly more CPU (negligible on
  modern devices).

---

## Troubleshooting Flow

### Getting the Log

The module writes a timestamped log to `/data/local/tmp/tether_unblock.log`.
**Always attach this log when reporting issues.**

```sh
# View the log
adb shell cat /data/local/tmp/tether_unblock.log

# Pull to your computer
adb pull /data/local/tmp/tether_unblock.log

# Enable verbose (DEBUG) logging for detailed diagnostics:
# 1. Push the sample config and enable LOG_LEVEL=DEBUG
adb push tether_unblock_vpn.conf.sample /data/local/tmp/tether_unblock_vpn.conf
adb shell "echo 'LOG_LEVEL=DEBUG' >> /data/local/tmp/tether_unblock_vpn.conf"
# 2. Reboot
# 3. Reproduce the issue
# 4. Pull the log
```

### What the Log Shows

| Log Level | Content |
|---|---|
| **INFO** (default) | Device model, Android version, kernel, resetprop location, every property set, every iptables rule added, VPN detection, errors |
| **DEBUG** | All INFO + network interface list, full iptables mangle/nat table before & after, internal state |

### Diagnostic Flow

```
Tethering still blocked after installing?
│
├→ 1. Reboot? (required after install)
│   └→ Yes → continue
│
├→ 2. Get the log (see above) — FIRST THING
│   └→ Look for [ERROR] lines
│   └→ Are iptables rules showing FAILED?
│       └→ Kernel may lack TTL/HL target. Fallback /proc values used.
│       └→ Check: grep 'Fallback' log → should show TTL=64, hop_limit=64
│
├→ 3. Pixel 6/7/8?
│   └→ Log should show: "Pixel: tether_offload_disabled = 1"
│   └→ Verify: adb shell settings get global tether_offload_disabled
│       └→ Must be "1". If "0" or null, offload is still active.
│
├→ 4. Samsung?
│   └→ Log should show "swlan0" in target interfaces
│
├→ 5. Using WireGuard?
│   └→ Log should show: "VPN interface detected: wg0"
│   └→ Log should show FORWARD and MASQUERADE rules without FAILED
│   └→ Is WireGuard connected *before* tethering?
│       └→ If not, reboot or reconnect WireGuard, restart module
│
├→ 6. Still blocked despite VPN?
│   └→ Carrier may be blocking WireGuard protocol itself
│       └→ Try: use a different WireGuard port (443, 53, 123)
│       └→ Try: use obfuscation proxies with WireGuard
│
├→ 7. Enable DEBUG logging and re-test
│   └→ Compare BEFORE/AFTER iptables state in the log
│   └→ Check that all target interfaces are listed
│   └→ Verify TTL/HL targets are in /proc/net/ip*_tables_targets
│
├→ 8. Still blocked?
│   └→ Carrier may use DPI (HTTP User-Agent, TCP fingerprinting)
│       └→ Try: use HTTPS everywhere + VPN
│
└→ 9. Open an issue with the DEBUG log attached
```
