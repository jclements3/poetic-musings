# Network — Phase 8 design (N · RMII/MAC/UDP + Ch.10 transport)

PLAN.md Phase 8: RMII PHY, MAC, UDP; stream ADC samples to a laptop, **zero drops
over 10 min**; Ch.10 transport framing on top. Hardware: RMII PHY PMOD (~$25,
fpga-development-plan #8). Prereq O; the bench capture tooling from Oracle bring-up
is assumed (the old "L letter" skills — Ethernet without capture is a bad afternoon).

## What MAIDEN gives us — and what it doesn't

MAIDEN has **no Ethernet anywhere**: its Ch.10 transport is one 115 200-baud 8N1
UART per FPGA into a Raspberry Pi 5 recorder (`MAIDEN/firmware/recorder/`), which
demultiplexes tagged records into IF-1 channels and writes the .ch10 file. So the
RMII/MAC/UDP fabric is *new work* for this letter — but the record layer, payloads,
recorder software, and the hard-won reliability discipline are all harvested.

### The framing we reuse (MAIDEN/firmware/recorder/PROTOCOL.md — single owner, do not fork)

Every message is a fixed-length tagged record:

```
byte 0   SYNC  0xA5
byte 1   TYPE
byte 2   SEQ    per-type modulo-256 counter
bytes 3+ PAYLOAD (fixed length per type, little-endian)
last     CKSUM  two's-complement of the byte-sum (whole frame sums to 0 mod 256)
```

Resync = scan for 0xA5 + checksum validate; SEQ gaps are logged, never fatal.
Existing types: 0x01 DOPPLER_V (50 Hz, 9 B: flags/v_cm/bin/peak/noise — ships even
with no detection so the channel stays gap-free), 0x10 PPS_STATUS (1 Hz, 4 B:
offset s20 + lock flags), 0x11 TIME_MARK (per PPS, 10 B: pps_rtc u48 + packed
TOD — the RTC↔UTC mapping), 0x12 STROBE_STAMP (per frame, 9 B: rtc/seq/sticky
overflow), 0x04 STATION_STATUS (1 Hz, 12 B, byte-identical to the Ch 6 payload).
Reliability rules inherited verbatim: never-drop-silently (drops are counted and
reported), records before first TIME_MARK counted+dropped, nondecreasing-RTC at the
writer, torn-tail salvage on ingest.

## Architecture

```
producers (ADC/Doppler/timebase/Imaging) ──record mux──► elastic FIFO (BRAM,
   │ tagged records, one SEQ per type            then SDRAM ring when Imaging lands)
   └── TIME_MARK from G (RTC↔UTC contract)              │
                                              UDP TX engine ─► IP/UDP checksums,
                                                       │        fixed headers from regs
                                        RMII MAC TX/RX ─┴─► PHY PMOD (100BASE-TX,
                                        50 MHz RMII ref domain, async-FIFO CDC)
```

- **MAC:** minimal 100 Mb RMII — preamble/SFD, CRC32, IFG enforcement; RX filtered
  to our MAC + broadcast ARP. No flow control, no VLAN.
- **IP stack, fabric-side, deliberately tiny:** ARP reply + one-deep ARP request,
  ICMP echo (bring-up sanity), UDP TX with precomputed pseudo-header partial
  checksum. Everything else (DHCP: no — static, config regs) is out.
- **Transport = tagged records inside UDP datagrams:** N records packed per
  datagram (MTU-limited, flush on timeout ≤10 ms or on TIME_MARK), preserving the
  PROTOCOL.md byte format so `recorder/sources.py`'s parser works unchanged — the
  laptop end is MAIDEN's recorder pointed at a UDP socket instead of a serial port.
  A 16-bit datagram sequence number rides in a thin prefix; per-type SEQ still
  detects producer-side loss. Ch.10 file writing stays on the laptop (writer.py);
  a native Ch.10-UDP streaming header (RCC 106 Ch.10 UDP transfer) is a later
  compatibility mode, not the gate.
- **Clock domains:** 50 MHz RMII ref (PHY-provided or fabric PLL) vs clk_sys —
  async FIFO CDC library blocks per fpga-resource-swag ("load-bearing, not
  optional"). SWAG budget: ~3k LUT, 16 KB BRAM, 0 DSP + SDRAM elasticity.

## Register block (eforth-pm.md conventions, provisional 0x4050 group)

| addr | write | read |
|---|---|---|
| 0x4050 | oNetCtrl — tx enable, source-select bitmask, flush | iNetStat — link up, tx busy, rx activity |
| 0x4052 | oNetMacLo/Hi (two writes, autoinc) | iNetDrops — elastic-FIFO drop count (sticky, loud) |
| 0x4054 | oNetIp / oNetDstIp (autoinc pair) | iNetSeq — current datagram seq |
| 0x4056 | oNetPort — src/dst UDP ports | iNetArp — dst MAC resolved flag |

Forth: `net-cfg` `net-go` `net-halt` `drops?` — configuration and start/stop are
control-plane (Forth); every per-packet action is gateware.

## Verification (the gate)

1. **Sim:** GHDL/Clash TB with a golden UDP-frame byte model (CRC32 + checksums vs
   Python scapy vectors); record-mux property: no interleaving corruption, SEQ
   monotone per type.
2. **Bring-up ladder:** link LEDs → ARP visible in Wireshark → ping → UDP counter
   pattern.
3. **Gate: zero-drop 10-minute stream** — ADC samples (theremin sensor or
   DOPPLER_V-style records at full rate) to the laptop; pass = laptop-side parser
   reports zero SEQ gaps, zero checksum failures, and iNetDrops == 0 for 10 min.
   Evidence logged under `Network/results/`.

## Out of scope

TCP, DHCP/DNS, receive-side data plane beyond ARP/ICMP (commands stay on the O
console), gigabit, PTP (time comes from G's TIME_MARK contract, not the network).
