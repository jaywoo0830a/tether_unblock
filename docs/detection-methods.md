# Tethering Detection & Bypass — OSI 7-Layer Model

Mobile carriers detect tethering by inspecting traffic at multiple layers of the
OSI stack.  This document maps every known detection method to its OSI layer and
explains how this module counters each one.

```
┌─────────────────────────────────────────────────────────────┐
│  LAYER 7  Application   HTTP User-Agent DPI, SNI inspection  │
│                          DNS pattern analysis                │
│                          → VPN (WireGuard) defeats this      │
├─────────────────────────────────────────────────────────────┤
│  LAYER 4  Transport     TCP stack fingerprinting (p0f)      │
│                          TCP window / options / TTL          │
│                          → TTL normalization + VPN defeats   │
├─────────────────────────────────────────────────────────────┤
│  LAYER 3  Network       TTL / Hop Limit analysis ← PRIMARY  │
│                          DUN APN routing                     │
│                          → nftables TTL/HL +1 bypasses both  │
├─────────────────────────────────────────────────────────────┤
│  LAYER 2  Data Link     MAC address                         │
│                          → Not used by carriers              │
├─────────────────────────────────────────────────────────────┤
│  ANDROID  Framework     TetheringProvisioning / entitlement  │
│                          Hardware offload (IPA / Tensor)     │
│                          → resetprop + settings bypass       │
└─────────────────────────────────────────────────────────────┘
```

---

## Layer 3 — Network Layer

This is where **90% of carrier tethering detection happens**.

### TTL / Hop Limit Analysis (Primary Detection Method)

Every IP packet carries a **Time-To-Live (TTL)** field (IPv4) or **Hop Limit**
(IPv6).  Each router along the path decrements this value by 1.  The carrier's
**PGW (PDN Gateway)** inspects the incoming TTL.

```
Phone-only traffic:
  Phone ──────────────────────→ Carrier PGW
  TTL=64                        Sees TTL=64 ✓

Tethered traffic:
  Laptop ────→ Phone(router) ────→ Carrier PGW
  TTL=64       TTL=63             Sees TTL=63 ✗  ← "63" = one extra hop
```

**Default TTL values by OS:**

| OS | Default TTL | After phone decrement |
|---|---|---|
| Android / Linux | 64 | 63 (flagged) |
| iOS / macOS | 64 | 63 (flagged) |
| Windows | 128 | 127 (flagged, also reveals Windows) |

#### Countermeasure (nftables)

Increment TTL by 1 on all tethering interfaces so the carrier sees the same TTL
as if the packet originated on the phone itself:

```sh
# IPv4 — nftables inet family
nft add rule inet tether_unblock prerouting  iifname rndis0 ip ttl set ip ttl + 1
nft add rule inet tether_unblock postrouting oifname rndis0 ip ttl set ip ttl + 1

# IPv6 — same, with ICMPv6 exclusion (Neighbor Discovery requires hop-limit=255)
nft add rule inet tether_unblock prerouting  iifname rndis0 \
    ip6 nexthdr != ipv6-icmp ip6 hoplimit set ip6 hoplimit + 1
```

> ⚠️ **ICMPv6 is excluded** because Neighbor Discovery Protocol uses
> hop-limit=255 and must not be modified — otherwise IPv6 breaks entirely.

#### Fallback: /proc values

If nftables is not available, the module sets the default TTL/HL via `/proc`:

```sh
echo 64 > /proc/sys/net/ipv4/ip_default_ttl
echo 64 > /proc/sys/net/ipv6/conf/all/hop_limit
```

This only affects packets originating from the phone itself, not tethered
packets.  It is a partial mitigation.

---

### DUN APN (Dial-Up Networking)

| Aspect | Detail |
|---|---|
| **OSI layer** | Layer 3 (routing decision via APN) |
| **How it works** | Carriers define a separate APN for tethering (`dun`). Android routes tethered traffic through this DUN APN instead of the default data APN. The DUN APN is throttled, blocked, or requires a separate paid plan. |
| **Module bypass** | `resetprop tether_dun_required 0` forces all traffic through the default APN |
| **Settings bypass** | `settings put global tether_dun_required 0` (Pixel / AOSP) |

```
With DUN enforced:
  Phone traffic → default APN (fast)        ✓
  Tethered      → DUN APN (throttled/blocked) ✗

After bypass:
  All traffic   → default APN (fast)        ✓
```

---

## Layer 4 — Transport Layer

### TCP Stack Fingerprinting (Passive OS Detection)

| Aspect | Detail |
|---|---|
| **OSI layer** | Layer 4 (TCP headers) |
| **Tools used** | p0f, proprietary carrier DPI appliances |
| **How it works** | The carrier passively inspects TCP SYN packets to identify the originating OS by its TCP stack signature — initial TTL, TCP window size, option ordering, and flags. |
| **Module bypass** | TTL normalization (Layer 3) corrects the initial TTL. For complete TCP fingerprint hiding, combine with WireGuard VPN. |

**TCP fingerprint signatures by OS:**

| Signature | Windows | Linux (Android) | macOS / iOS |
|---|---|---|---|
| Initial TTL | 128 | 64 | 64 |
| TCP window | 65535 | varies | 65535 |
| Options order | M,N,W,N,N,T | M,N,N,T,N,W | M,N,W,N,N,T |
| Don't Fragment | sometimes | usually | always |

> M=MSS, N=NOP, W=WindowScale, T=Timestamp

A TCP SYN from a Windows laptop saying TTL=127 and window=65535 is trivially
distinguishable from an Android phone saying TTL=64 and window=29200.  When
TTL normalization sets TTL=64, the carrier sees TTL=64 even from tethered
Windows devices — this removes one key signal.  Combined with WireGuard, all
TCP headers are encrypted and invisible to the carrier.

---

## Layer 7 — Application Layer

### HTTP User-Agent Deep Packet Inspection (DPI)

| Aspect | Detail |
|---|---|
| **OSI layer** | Layer 7 (HTTP headers) |
| **How it works** | Carriers (T-Mobile US, Vodafone, NTT Docomo) inspect unencrypted HTTP `User-Agent` headers. Desktop browser signatures are flagged as tethering. |
| **Why declining** | >90% of web traffic is now HTTPS. HTTP/2 and HTTP/3 multiplex streams, making header inspection harder. |
| **Module bypass** | Not needed for HTTPS. For unencrypted HTTP, use WireGuard VPN (encrypts everything). |

```
HTTP (visible to DPI):
  GET / HTTP/1.1
  User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)  ← flagged!

HTTPS (invisible):
  TLS 1.3 encrypted — carrier sees nothing.

WireGuard (invisible):
  All packets are encrypted UDP — carrier sees only tunnel.
```

### SNI (Server Name Indication) Inspection

| Aspect | Detail |
|---|---|
| **OSI layer** | Layer 7 (TLS handshake) |
| **How it works** | Even with HTTPS, the TLS `ClientHello` includes the destination domain in plaintext (SNI field). Carriers can flag connections to desktop-only services (Steam CDN, Windows Update, Battle.net). |
| **Mitigation** | ECH (Encrypted Client Hello) in TLS 1.3 + DoH. WireGuard VPN hides all destinations. |

### DNS Pattern Analysis

| Aspect | Detail |
|---|---|
| **OSI layer** | Layer 7 (DNS queries) |
| **How it works** | Carriers inspect DNS queries for desktop-application patterns (e.g., `client.steam.com`, `update.microsoft.com`). |
| **Mitigation** | DNS-over-HTTPS (DoH) or DNS-over-TLS (DoT). WireGuard VPN routes all DNS through the tunnel. |

---

## Android Framework Layer (Outside OSI)

Android adds its own tethering detection mechanisms that operate at the
framework level, independent of the network stack.

### Tethering Provisioning / Entitlement Check

| Aspect | Detail |
|---|---|
| **How it works** | Android's `TetheringProvisioning` service sends an HTTP request to the carrier's provisioning server. If the carrier responds `403 Forbidden`, Android immediately disables the hotspot and shows "Account not set up for tethering." |
| **Module bypass** | `resetprop net.tethering.noprovisioning true` — skips the check entirely |
| | `resetprop tether_entitlement_check_state 0` — fakes a successful check |

### Hardware Tethering Offload (Google Tensor / QCOM IPA)

| Aspect | Detail |
|---|---|
| **Affected devices** | Google Pixel 6+, some Snapdragon 8 Gen 1+ devices |
| **How it works** | The IPA (IP Accelerator) hardware routes tethered packets directly from modem to Wi-Fi, bypassing the Linux netfilter stack entirely. **nftables rules have zero effect** on offloaded traffic. |
| **Module bypass** | `settings put global tether_offload_disabled 1` — forces all traffic through the CPU where nftables can process it |
| **Trade-off** | ~5-10% higher CPU usage during tethering (imperceptible on modern devices) |

```
With offload ON:
  Modem → IPA hardware → Wi-Fi chip    (nftables is bypassed ✗)

With offload OFF:
  Modem → CPU (nftables) → Wi-Fi chip  (nftables processes TTL/HL ✓)
```

### Carrier / OEM Property Checks

Some carriers and OEMs add property-based tethering detection at the framework
level. The module sets these properties to bypass all known variants:

```sh
resetprop tether_dun_required 0            # No separate DUN APN
resetprop net.tethering.noprovisioning true # Skip provisioning
resetprop tether_entitlement_check_state 0  # Fake entitlement OK
resetprop ro.tether.denied false            # Carrier "denied" flag
resetprop persist.sys.tether_data -1        # Some firmware checks
resetprop sys.usb.tethering true            # Samsung USB tethering
```

---

## Summary: Detection Methods vs Module Coverage

| OSI Layer | Detection Method | Prevalence | Module Coverage |
|---|---|---|---|
| **Layer 3** | TTL / Hop Limit | ★★★★★ Primary | ✅ nftables `ip ttl set + 1` |
| **Layer 3** | DUN APN routing | ★★★★☆ Common | ✅ `tether_dun_required=0` |
| **Layer 4** | TCP fingerprinting | ★★☆☆☆ Rare | ⚠️ Partial (TTL norm + VPN) |
| **Layer 7** | HTTP User-Agent DPI | ★★★☆☆ Declining | ✅ VPN (WireGuard) |
| **Layer 7** | SNI inspection | ★★☆☆☆ Emerging | ✅ VPN (WireGuard) |
| **Layer 7** | DNS patterns | ★★☆☆☆ Rare | ✅ DoH/DoT + VPN |
| **Android** | Provisioning check | ★★★★☆ Common | ✅ `noprovisioning=true` |
| **Android** | Hardware offload | ★★★★☆ Pixel/QCOM | ✅ `tether_offload_disabled=1` |
| **Android** | OEM properties | ★★★☆☆ Varies | ✅ `resetprop` bypasses |

### Recommended Defense-in-Depth

```
Layer 1:  resetprop properties     → OS/framework bypass
Layer 2:  nftables TTL/HL +1       → network detection bypass
Layer 3:  WireGuard VPN            → DPI/fingerprint defeat
         (optional but strongest)

All 3 layers active = maximum protection.
```
