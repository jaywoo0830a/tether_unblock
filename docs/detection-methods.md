# Tethering Detection Methods

Mobile carriers use multiple techniques to detect whether you're tethering.
Understanding these is essential for effective bypass.

---

## 1. TTL / Hop Limit Analysis (Primary Method)

### How It Works

Every IP packet carries a **Time-To-Live (TTL)** field (IPv4) or **Hop Limit** (IPv6).
Each router along the path decrements this value by 1.

```
Normal phone traffic:
  Phone ──────────────────────→ Carrier
  TTL=64                        Sees TTL=64 ✓

Tethered traffic:
  Laptop ────→ Phone ────→ Carrier
  TTL=64       TTL=63      Sees TTL=63 ✗  ← "63" reveals one extra hop
```

The carrier's **PGW (PDN Gateway)** or **GGSN** inspects the TTL of incoming
packets. If the TTL is one less than the expected device TTL (typically 64),
they know there's a router (your phone) between the device and the carrier.

### Default TTL Values by OS

| OS | Default TTL | Carrier Sees |
|---|---|---|
| Android / Linux | 64 | 64 (normal) |
| iOS / macOS | 64 | 64 (normal) |
| Windows | 128 | 127 (detectable) |
| tethered → decremented | -1 | 63 or 127 (detectable) |

### IPv6 Hop Limit

The same principle applies to IPv6. The `Hop Limit` field is decremented
identically. Some carriers specifically check IPv6 because it's harder to
manipulate (fewer tools support `ip6tables` compared to `iptables`).

### Bypass Strategy

Increment TTL/HL by 1 on all tethering interfaces:

```sh
# IPv4
iptables -t mangle -A PREROUTING  -i $IFACE -j TTL --ttl-inc 1
iptables -t mangle -A POSTROUTING -o $IFACE -j TTL --ttl-inc 1

# IPv6 (exclude ICMPv6 — preserves Neighbor Discovery)
ip6tables -t mangle -A PREROUTING  ! -p icmpv6 -i $IFACE -j HL --hl-inc 1
ip6tables -t mangle -A POSTROUTING ! -p icmpv6 -o $IFACE -j HL --hl-inc 1
```

**Important**: ICMPv6 is excluded because Neighbor Discovery Protocol (NDP)
uses hop-limit=255 and must not be modified — otherwise IPv6 connectivity
breaks entirely.

---

## 2. DUN (Dial-Up Networking) APN

### How It Works

Mobile carriers define two APNs (Access Point Names):
- **Default APN**: Regular smartphone data (`internet`, `fast.t-mobile.com`, etc.)
- **DUN APN**: Tethering-only data (`dun`, `pcweb.t-mobile.com`, etc.)

Android checks the `tether_dun_required` property. If set to `1`, the phone
routes tethered traffic through the DUN APN, which either:
- Requires a separate tethering plan (most US carriers)
- Is throttled to very low speeds
- Is blocked entirely

### Bypass Strategy

Force all traffic through the default APN:

```sh
resetprop tether_dun_required 0
settings put global tether_dun_required 0
```

---

## 3. Tethering Provisioning / Entitlement Check

### How It Works

Android's `TetheringProvisioning` service (part of `NetworkStack`) sends an
HTTP request to the carrier's provisioning server:

```
GET /tetheringCheck?msisdn=1234567890 HTTP/1.1
Host: provisioning.carrier.com
```

The carrier responds with `200 OK` (allowed) or `403 Forbidden` (blocked).
On Android 12+, this uses the `ConnectivityService` entitlement API.

When blocked, the system immediately disables the hotspot and shows a
"Account not set up for tethering" notification.

### Bypass Strategy

```sh
# Disable the provisioning check entirely
resetprop net.tethering.noprovisioning true

# Fake the entitlement check result
resetprop tether_entitlement_check_state 0
```

On some carrier ROMs, these properties are read-only (`ro.*`). `resetprop`
(Magisk/KernelSU) can override even read-only properties at runtime.

---

## 4. HTTP User-Agent Inspection (DPI)

### How It Works

Some carriers (notably T-Mobile US, Vodafone, NTT Docomo) perform **Deep
Packet Inspection (DPI)** on unencrypted HTTP traffic. They look for browser
`User-Agent` headers that indicate desktop OS:

```
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) ...  ← Desktop → BLOCKED
User-Agent: Mozilla/5.0 (Linux; Android 13) ...             ← Mobile  → ALLOWED
```

### Bypass Strategy

This method is increasingly irrelevant because:
1. Most web traffic is now HTTPS (DPI can't see headers)
2. HTTP/2 and HTTP/3 multiplex streams, making header inspection harder
3. This module does NOT attempt User-Agent spoofing (iptables TTL bypass is
   sufficient for 95%+ of carriers)

If you specifically encounter User-Agent-based blocking, use a browser
extension to spoof the mobile User-Agent string.

---

## 5. TCP/IP Stack Fingerprinting

### How It Works

Advanced carriers (e.g., China Mobile, some European operators) use passive
OS fingerprinting tools (like **p0f**) to identify the TCP stack of the
originating device:

| Signature | Windows | Linux (Android) | macOS/iOS |
|---|---|---|---|
| Initial TTL | 128 | 64 | 64 |
| TCP window size | 65535 | varies | 65535 |
| TCP options order | MSS,NOP,WScale,NOP,NOP,TS | MSS,NOP,NOP,TS,NOP,WScale | MSS,NOP,WScale,NOP,NOP,TS |
| Don't Fragment | sometimes | usually | always |

If the TCP fingerprint says "Windows" but the subscriber's device is Android,
the carrier flags it as tethering.

### Bypass Strategy

This is the hardest detection to bypass. TTL normalization (Layer 2) helps
because the carrier sees TTL=64 instead of 127. The TCP window size is harder
to fake, but it's rarely the sole detection method. Most carriers combine
multiple signals, and TTL + DUN bypass is sufficient for the majority.

---

## 6. Hardware Tethering Offload (Pixel 6+ / QCOM IPA)

### How It Works

Modern chipsets (Google Tensor, Qualcomm Snapdragon 8 Gen 1+) use **IPA
(IP Accelerator)** hardware to offload tethering traffic. Packets go:

```
Modem → IPA hardware → Wi-Fi chip
         ↑
    (bypasses Linux netfilter completely!)
```

When offload is active, **iptables rules have zero effect** because packets
never traverse the Linux network stack. This is why many tethering bypass
modules mysteriously "don't work" on Pixel 6/7/8.

### Bypass Strategy

```sh
settings put global tether_offload_disabled 1
```

This forces all tethered traffic through the CPU's netfilter stack, where
iptables TTL/HL rules can process it. Trade-off: ~5-10% higher CPU usage
while tethering (usually imperceptible).

---

## 7. Data Volume / Traffic Pattern Analysis

### How It Works

Some carriers analyze traffic patterns at the network level:
- **Volume**: Sudden spike to 50 GB/month → likely tethering
- **Destination diversity**: Connections to CDNs, desktop update servers, etc.
- **Protocol mix**: Desktop-only protocols (e.g., Steam, Battle.net)
- **DNS queries**: Desktop application DNS patterns

### Bypass Strategy

This is outside the scope of a device-side module. Mitigations:
- Use a VPN (obscures destination diversity)
- Use DNS-over-HTTPS (obscures DNS patterns)
- Spread usage across time (avoid sudden spikes)

---

## Summary: Detection Methods and Countermeasures

| Method | Prevalence | This Module Handles? |
|---|---|---|
| TTL / Hop Limit | ★★★★★ Very common | ✅ iptables TTL --ttl-inc 1 |
| DUN APN | ★★★★☆ Common | ✅ tether_dun_required=0 |
| Provisioning check | ★★★★☆ Common | ✅ noprovisioning=true, entitlement=0 |
| HTTP User-Agent DPI | ★★★☆☆ Declining | ❌ (HTTPS makes this obsolete) |
| TCP fingerprinting | ★★☆☆☆ Rare | ⚠️ Partial (TTL normalization helps) |
| Hardware offload | ★★★★☆ Pixel 6+, QCOM | ✅ tether_offload_disabled=1 |
| Traffic patterns | ★★☆☆☆ Rare | ❌ (needs VPN) |
