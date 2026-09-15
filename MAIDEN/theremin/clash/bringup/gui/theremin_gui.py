#!/usr/bin/env python3
"""Lab GUI for the Alchitry Cu theremin (bringup/bin/theremin-gui.bin).

Talks to the board over its USB UART (FT2232 channel B, /dev/ttyUSB1,
115200 8N1).  The sliders stand in for the antennas until the oscillator
hardware arrives.  The PITCH slider is the hand's position, 0 = away,
1 = closest; the GUI turns that into an oscillator period with upstream's
hand-distance curve (SensorConvertor::linearToPeriod, k = 4.5) between the
calibrated far/near periods (84 and 80 ticks - the NoteMap defaults), and
sends the NCO increment for the synthetic pitch oscillator inside the FPGA.
The board then does what a real theremin core does: measures the period,
linearises it, maps it to a note (A0..G7), and plays it.  Because the GUI
applies the physics curve and the FPGA undoes it, a linear sweep of the
slider should plot as a straight line across the musical axis.

The VOLUME slider is the other hand's position over the loop, 0 = away
(full volume), 1 = on the loop (mute); same curve, and the FPGA's AmpMap
(upstream's (1 - linear)^2) sets the amplitude by a real multiply.

Wire protocol (see bringup/cu_gui_top.v):
  host -> board   A5 pinc(4) vinc(4)   every 20 ms
                  (NCO increments, big-endian; period = 2^32/inc ticks)
  board -> host   5A seq pinc(4) vinc(4) {max,min} zc(2) dsm(2) per(3) peak(2)
                  every 20 ms; peak = largest |16-bit sample| in the window
      zc  = audio zero crossings in the 20 ms window (coarse, 50 Hz steps)
      dsm = 1-bit DSM ones / 16 (max 62500)
      per = 50 MHz cycles of the last audio period (0 = silent) -> the
            precise pitch used for the note/cents readout and the chart

Usage:  python3 theremin_gui.py [/dev/ttyUSB1] [--sweep]
Needs pyserial and tkinter.
"""
import collections
import math
import sys
import threading
import time
import tkinter as tk
from tkinter import ttk

import serial

ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
PORT = ARGS[0] if ARGS else "/dev/ttyUSB1"
START_SWEEP = "--sweep" in sys.argv
BAUD = 115200
F_CLK = 50e6
FRAME = 20
HIST = 500                          # 10 s of 20 ms frames
# NoteMap calibration (src/Theremin/Audio/NoteMap.hs defaultNoteMapParams):
PERIOD_FAR, PERIOD_NEAR = 84.0, 80.0    # pitch oscillator period in ticks, hand away / closest
VPERIOD_FAR, VPERIOD_NEAR = 92.0, 88.0  # volume oscillator, hand away (loud) / on the loop (mute)
LIN_K = 4.5                             # upstream linearizationK
MIDI_LO, MIDI_HI = 21, 103              # A0 .. G7
F_AXIS_LO, F_AXIS_HI = 16.352, 8372.0   # C0 .. C9 on the chart
TARGET_LO, TARGET_HI = 27.5, 3135.96    # A0 .. G7: the range the map is built for

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

def hand_to_period(u, far=PERIOD_FAR, near=PERIOD_NEAR):
    """Upstream linearToPeriod: hand position 0..1 -> oscillator period (ticks)."""
    u = max(0.0, min(1.0, u))
    frac = (math.exp(u * LIN_K) - 1) / (math.exp(LIN_K) - 1)     # 0..1, compressed
    return far + (near - far) * frac

def hand_to_inc(u, far=PERIOD_FAR, near=PERIOD_NEAR):
    return int(round(2 ** 32 / hand_to_period(u, far, near)))

def hand_to_expected_amp(v):
    """Upstream setVolumeRange: (1 - linear)^2 with linear = the hand position."""
    v = max(0.0, min(1.0, v))
    return (1 - v) ** 2

def db(x):
    return 20 * math.log10(x) if x > 0 else float("-inf")

def hand_to_expected_hz(u):
    """What the NoteMap should play: a straight line in u from A0 to G7."""
    midi = MIDI_LO + (MIDI_HI - MIDI_LO) * max(0.0, min(1.0, u))
    return 440 * 2 ** ((midi - 69) / 12)

def note_of(f):
    """(name, cents) of the nearest equal-tempered note, A4 = 440."""
    if f <= 0:
        return "-", 0.0
    m = 69 + 12 * math.log2(f / 440.0)
    n = int(round(m))
    return f"{NOTE_NAMES[n % 12]}{n // 12 - 1}", (m - n) * 100

# --------------------------------------------------------------- serial I/O
class Link:
    def __init__(self, port):
        self.ser = serial.Serial(port, BAUD, timeout=0.05)
        self.frames = collections.deque(maxlen=HIST)
        self.lock = threading.Lock()
        self.rx_count = 0
        self.seq_gaps = 0
        self.last_rx = 0.0
        self._last_seq = None
        self.hand = 0.5
        self.vhand = 0.0
        self.alive = True
        threading.Thread(target=self._reader, daemon=True).start()
        threading.Thread(target=self._sender, daemon=True).start()

    def _reader(self):
        buf = b""
        while self.alive:
            buf += self.ser.read(64)
            while True:
                i = buf.find(b"\x5a")
                if i < 0 or len(buf) - i < FRAME:
                    buf = buf[i:] if i >= 0 else b""
                    break
                f = buf[i:i + FRAME]
                buf = buf[i + FRAME:]
                seq = f[1]
                p = int.from_bytes(f[2:6], "big")     # echoed pitch increment
                v = int.from_bytes(f[6:10], "big")    # echoed volume increment
                mm = f[10]
                zc = (f[11] << 8) | f[12]
                dsm = (f[13] << 8) | f[14]
                per = (f[15] << 16) | (f[16] << 8) | f[17]
                peak = (f[18] << 8) | f[19]
                freq = F_CLK / per if per else 0.0
                with self.lock:
                    if self._last_seq is not None and (self._last_seq + 1) & 0xFF != seq:
                        self.seq_gaps += 1
                    self._last_seq = seq
                    self.rx_count += 1
                    self.last_rx = time.time()
                    self.frames.append((time.time(), p, v, mm >> 4, mm & 0xF, zc, dsm, freq, peak))

    def _sender(self):
        while self.alive:
            inc = hand_to_inc(self.hand)
            vinc = hand_to_inc(self.vhand, VPERIOD_FAR, VPERIOD_NEAR)
            try:
                self.ser.write(bytes([0xA5]) + inc.to_bytes(4, "big") + vinc.to_bytes(4, "big"))
            except serial.SerialException:
                pass
            time.sleep(0.02)

# --------------------------------------------------------------------- GUI
class App:
    def __init__(self, root, link):
        self.root, self.link = root, link
        root.title(f"Cu theremin - {PORT}")
        root.geometry("1180x660")
        main = ttk.Frame(root, padding=10); main.pack(fill="both", expand=True)

        ctl = ttk.LabelFrame(main, text="Synthetic oscillators (stand-ins for the antennas)", padding=8)
        ctl.pack(fill="x")
        self.hand = tk.DoubleVar(value=0.5); self.vhand = tk.DoubleVar(value=0.0)
        self.sweep = tk.BooleanVar(value=START_SWEEP)
        self._hand_slider(ctl, 0)
        self._vhand_slider(ctl, 1)
        ttk.Checkbutton(ctl, text="Sweep the hand 0 -> 1 -> 0 over 6 s (should draw a straight line A0 -> G7)",
                        variable=self.sweep).grid(row=2, column=0, columnspan=3, sticky="w")
        ttk.Label(ctl, foreground="#888",
                  text=f"Pitch: far {PERIOD_FAR:.0f} ticks -> A0, near {PERIOD_NEAR:.0f} -> G7.  "
                       f"Volume: far {VPERIOD_FAR:.0f} -> full, near {VPERIOD_NEAR:.0f} -> mute, amp = (1-v)^2.  "
                       f"k = {LIN_K}; the GUI applies the hand curve, the FPGA undoes it."
                  ).grid(row=3, column=0, columnspan=3, sticky="w")
        ctl.columnconfigure(1, weight=1)

        st = ttk.LabelFrame(main, text="Link", padding=8); st.pack(fill="x", pady=(8, 0))
        self.status = tk.StringVar(value="waiting for frames...")
        ttk.Label(st, textvariable=self.status, font=("TkFixedFont", 10)).pack(anchor="w")

        out = ttk.LabelFrame(main, text="What the instrument core is producing", padding=8)
        out.pack(fill="both", expand=True, pady=(8, 0))
        self.note = tk.StringVar(); self.freq = tk.StringVar(); self.amp = tk.StringVar(); self.dsm = tk.StringVar()
        ttk.Label(out, textvariable=self.note, font=("TkDefaultFont", 22, "bold"), width=9).grid(row=0, column=0, rowspan=2, sticky="w")
        ttk.Label(out, textvariable=self.freq, font=("TkFixedFont", 11)).grid(row=0, column=1, sticky="w", padx=12)
        ttk.Label(out, textvariable=self.amp).grid(row=0, column=2, sticky="w", padx=12)
        ttk.Label(out, textvariable=self.dsm).grid(row=0, column=3, sticky="w")
        self.ampbar = ttk.Progressbar(out, maximum=15, length=180); self.ampbar.grid(row=1, column=2, sticky="w", padx=12)
        self.dsmbar = ttk.Progressbar(out, maximum=62500, length=180); self.dsmbar.grid(row=1, column=3, sticky="w")
        self.canvas = tk.Canvas(out, bg="#111", height=300, highlightthickness=0)
        self.canvas.grid(row=2, column=0, columnspan=4, sticky="nsew", pady=(8, 0))
        out.rowconfigure(2, weight=1); out.columnconfigure(3, weight=1)
        ttk.Label(out, text="green: audio pitch on a log (musical) axis, one gridline per octave, last 10 s   "
                            "shaded: A0-G7, the NoteMap range   amber: amplitude (16-bit peak, linear 0..1)"
                  ).grid(row=3, column=0, columnspan=4, sticky="w")

        self.t0 = time.time()
        self.tick()

    def _hand_slider(self, parent, row):
        ttk.Label(parent, text="Hand position (pitch)").grid(row=row, column=0, sticky="w")
        s = ttk.Scale(parent, from_=0.0, to=1.0, variable=self.hand, orient="horizontal")
        s.grid(row=row, column=1, sticky="ew", padx=8)
        lbl = ttk.Label(parent, width=52, font=("TkFixedFont", 9)); lbl.grid(row=row, column=2, sticky="w")
        def upd(*_):
            u = self.hand.get(); per = hand_to_period(u)
            name, _ = note_of(hand_to_expected_hz(u))
            lbl.config(text=f"u={u:4.2f}  period {per:6.3f} ticks = {50e3/per:7.2f} kHz  expect {name}")
        self.hand.trace_add("write", upd); upd()

    def _vhand_slider(self, parent, row):
        ttk.Label(parent, text="Hand position (volume loop)").grid(row=row, column=0, sticky="w")
        s = ttk.Scale(parent, from_=0.0, to=1.0, variable=self.vhand, orient="horizontal")
        s.grid(row=row, column=1, sticky="ew", padx=8)
        lbl = ttk.Label(parent, width=52, font=("TkFixedFont", 9)); lbl.grid(row=row, column=2, sticky="w")
        def upd(*_):
            v = self.vhand.get(); per = hand_to_period(v, VPERIOD_FAR, VPERIOD_NEAR)
            a = hand_to_expected_amp(v)
            lbl.config(text=f"v={v:4.2f}  period {per:6.3f} ticks  expect amp {a:5.3f} = {db(a):+6.1f} dB")
        self.vhand.trace_add("write", upd); upd()

    def _slider(self, parent, label, var, lo, hi, row, cal=None):
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w")
        s = ttk.Scale(parent, from_=lo, to=hi, variable=var, orient="horizontal",
                      command=lambda v, var=var: var.set(int(float(v))))
        s.grid(row=row, column=1, sticky="ew", padx=8)
        lbl = ttk.Label(parent, width=40, font=("TkFixedFont", 9)); lbl.grid(row=row, column=2, sticky="w")
        def upd(*_):
            h = var.get(); f = F_CLK / (2 * h)
            flag = "" if cal is None or cal[0] <= h <= cal[1] else "  (outside calibrated band)"
            lbl.config(text=f"{h:3d} ticks = {f/1e3:7.1f} kHz osc{flag}")
        var.trace_add("write", upd); upd()

    def tick(self):
        if self.sweep.get():
            ph = ((time.time() - self.t0) / 3.0) % 2.0        # 6 s triangle of the hand
            self.hand.set(ph if ph < 1 else 2 - ph)
        self.link.hand = self.hand.get(); self.link.vhand = self.vhand.get()

        with self.link.lock:
            frames = list(self.link.frames)
            n, gaps, last = self.link.rx_count, self.link.seq_gaps, self.link.last_rx
        age = time.time() - last
        if frames and age < 0.5:
            _, p, v, mx, mn, zc, dsm, freq, peak = frames[-1]
            rate = sum(1 for f in frames if f[0] > time.time() - 1.0)
            self.status.set(f"LINK UP   {rate:3d} frames/s   total {n}   seq gaps {gaps}   "
                            f"board echoes pitch period {2**32 / p if p else 0:7.3f}, volume period {2**32 / v if v else 0:7.3f} ticks")
            if freq > 0 and peak >= 64:
                name, cents = note_of(freq)
                exp_hz = hand_to_expected_hz(self.hand.get())
                err = 1200 * math.log2(freq / exp_hz)
                self.note.set(name)
                self.freq.set(f"{freq:8.1f} Hz  {cents:+5.0f} cents   vs expected {note_of(exp_hz)[0]} ({err:+.0f} c)\n"
                              f"(zero-crossing check {zc*50:6d} Hz)")
            else:
                self.note.set("silent"); self.freq.set(f"period 0 / peak {peak}\n(zero-crossing check {zc*50:6d} Hz)")
            a = peak / 32767
            exp_a = hand_to_expected_amp(self.vhand.get())
            self.amp.set(f"amplitude {a:5.3f} = {db(a):+6.1f} dB   expected {exp_a:5.3f} = {db(exp_a):+6.1f} dB\n"
                         f"(peak {peak}/32767, PCM4 {mn}..{mx})")
            self.dsm.set(f"DSM density {dsm / 62500:5.1%}")
            self.ampbar["value"] = a * 15; self.dsmbar["value"] = dsm
        else:
            self.status.set(f"NO LINK  ({n} frames so far; last {age:.1f} s ago)  "
                            "- is theremin-gui.bin flashed and the cable a data cable?")
        self.draw(frames)
        self.root.after(50, self.tick)

    def draw(self, frames):
        c = self.canvas; c.delete("all")
        w, h = c.winfo_width(), c.winfo_height()
        if w < 10:
            return
        L, R, T, B = 44, w - 8, 6, h - 6                        # plot box
        span = 10.0; now = time.time()
        lo, hi = math.log2(F_AXIS_LO), math.log2(F_AXIS_HI)
        def yf(f):
            return B - (math.log2(f) - lo) / (hi - lo) * (B - T)
        # target band
        c.create_rectangle(L, yf(TARGET_HI), R, yf(TARGET_LO), fill="#1c2a1c", outline="")
        # octave gridlines at every C, plus faint lines at G (the fifth)
        f = F_AXIS_LO; n = 0
        while f <= F_AXIS_HI * 1.001:
            y = yf(f)
            c.create_line(L, y, R, y, fill="#3a3a3a")
            c.create_text(L - 4, y, text=f"C{n}", fill="#9a9a9a", anchor="e", font=("TkFixedFont", 8))
            c.create_text(R - 2, y - 1, text=f"{f:.0f} Hz", fill="#555", anchor="se", font=("TkFixedFont", 7))
            g = f * 2 ** (7 / 12)
            if g < F_AXIS_HI:
                c.create_line(L, yf(g), R, yf(g), fill="#232323", dash=(2, 4))
            f *= 2; n += 1
        c.create_line(L, T, L, B, fill="#555")
        # amplitude (amber, right-hand 0..15 -> full height) and pitch (green)
        pts_a = []; segs = []; cur = []
        for t, p, v, mx, mn, zc, dsm, freq, peak in frames:
            x = R - (now - t) / span * (R - L)
            if x < L:
                continue
            pts_a += [x, B - peak / 32767 * (B - T)]
            if freq > 0 and peak >= 64 and F_AXIS_LO <= freq <= F_AXIS_HI:
                cur += [x, yf(freq)]
            else:
                if len(cur) >= 4: segs.append(cur)
                cur = []
        if len(cur) >= 4: segs.append(cur)
        if len(pts_a) >= 4:
            c.create_line(*pts_a, fill="#8a6a2a", width=1)
        for sgm in segs:
            c.create_line(*sgm, fill="#5fd35f", width=2)
        c.create_text(L + 6, T + 4, anchor="nw", fill="#5fd35f", font=("TkFixedFont", 8),
                      text="Upstream port: linearisation k=4.5, note table A0..G7, quarter-semitone phase table, (1-v)^2 volume")

def main():
    link = Link(PORT)
    root = tk.Tk()
    App(root, link)
    try:
        root.mainloop()
    finally:
        link.alive = False

if __name__ == "__main__":
    main()
