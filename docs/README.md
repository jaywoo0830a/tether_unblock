# Tether Unblock — Technical Documentation

## Contents

| Document | Description |
|---|---|
| [Detection Methods](detection-methods.md) | OSI 7-layer breakdown: how carriers detect tethering at each layer (Layer 3 TTL/HL, Layer 4 TCP fingerprinting, Layer 7 DPI/DNS/SNI) and how the module counters each — with recommended defense-in-depth strategy |
| [Manufacturer & Carrier Guide](manufacturer-guide.md) | Device-specific behaviors (Pixel, Samsung, Xiaomi, OnePlus, etc.) and carrier-specific bypass strategies (T-Mobile, AT&T, Verizon, Korean/European/Japanese carriers) |

## Quick Reference

```
┌──────────────────────────────────────────────────────────────┐
│                    HOW TETHERING DETECTION WORKS              │
│                                                               │
│  Your Laptop ──→ Phone ──→ Carrier ──→ Internet              │
│  TTL=64          TTL=63    (sees TTL=63, knows it's tethered) │
│                                                               │
│  → Module increments TTL by 1, so carrier sees TTL=64 ✓       │
│                                                               │
│  Pixel 6+ EXTRA ISSUE: Hardware offload bypasses iptables     │
│  → Module disables tether_offload_disabled to fix this        │
│                                                               │
│  OPTIONAL VPN: If WireGuard is active, tethered traffic       │
│  goes through the tunnel → carrier only sees encrypted packets│
└──────────────────────────────────────────────────────────────┘
```

## How This Module Works (4 Layers)

### Layer 1 — Property Bypass
Sets Android system properties that disable the OS-level tethering check:
- `tether_dun_required=0` — no separate DUN APN needed
- `net.tethering.noprovisioning=true` — skip carrier provisioning check
- `tether_entitlement_check_state=0` — pretend entitlement check passed

### Layer 2 — TTL/HL Manipulation (iptables)
Increments the TTL (IPv4) and Hop Limit (IPv6) of all packets passing through
tethering interfaces by 1, compensating for the router decrement. The carrier
sees the same TTL as if the packet originated on the phone itself.

```
PREROUTING  -i rndis0/wlan0/ap0  -j TTL --ttl-inc 1   (incoming from device)
POSTROUTING -o rndis0/wlan0/ap0  -j TTL --ttl-inc 1   (outgoing to carrier)
```

### Layer 3 — Hardware Offload Disable (Pixel 6+)
On Tensor-powered Pixels, tethering traffic goes through IPA hardware offload
which bypasses the Linux netfilter stack entirely. The module disables this
so iptables rules can actually process the packets.

### Layer 4 — VPN Passthrough (Optional, WireGuard auto-detect)
If a WireGuard (`wg*`) interface is detected, the module adds FORWARD and
MASQUERADE rules that force tethered traffic through the VPN tunnel. The
carrier only sees encrypted WireGuard packets — DPI, TCP fingerprinting,
and User-Agent inspection are completely defeated. Combined with TTL
increment, this is the strongest possible bypass.

## Supported Root Solutions

| Solution | `resetprop` Path | Notes |
|---|---|---|
| **Magisk** | `/data/adb/magisk/resetprop` | v20.4+ required |
| **KernelSU** | `/data/adb/ksu/bin/resetprop` | Built-in in recent versions |
| **APatch** | `/data/adb/ap/bin/resetprop` | |
| **Fallback** | `resetprop` from PATH, then `setprop` | Last resort |

## Testing

```bash
make test          # Run all 44 tests
./tests/run_all.sh # Direct invocation
```
