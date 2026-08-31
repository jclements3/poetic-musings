import numpy as np, cairosvg, math
W,H=1200,1000
RX,RY=360,225
ell = {  # name: (cx, cy, rot deg)
 "T":(450,530,-40), "M":(600,630,-40), "P":(600,630,40), "H":(750,530,40)}
cols={"T":"#3b7dd8","M":"#d8443b","P":"#3ba85a","H":"#c58a1f"}
def inside(n,x,y):
    cx,cy,r=ell[n]; th=math.radians(r)
    dx,dy=x-cx,y-cy
    u= dx*math.cos(th)+dy*math.sin(th); v=-dx*math.sin(th)+dy*math.cos(th)
    return (u/RX)**2+(v/RY)**2<=1
ys,xs=np.mgrid[0:H:2,0:W:2]
masks={n:np.vectorize(lambda x,y,n=n:inside(n,x,y))(xs,ys) for n in ell}
regions={
 "T":["✓ LC oscillator front end","✓ Antenna capacitance","✓ Frequency counter","✓ Pitch→note quantizer"],
 "M":["○ IRIG-B decoder","○ Ch.10/TMATS packetizer","○ Dual-ch I/Q front end","○ Camera/gate trigger"],
 "P":["○ 8×8 key matrix + ASCII","○ Pulse-pattern osc (10)","○ ADSSR envelope","○ Rhythm ROM + percussion","○ 100-note sequencer","○ GPDI TMDS + overlay"],
 "H":["○ 49× KS waveguides","○ Allpass fractional delay","○ X/Y magnitude + angle","○ Velocity log map","○ 98-ch sensor mux","○ Dispersion reg B_q16"],
 "TM":["✓ FIR filter","✓ Phase/freq estimator"],
 "TP":["✓ NCO phase-inc table","✓ Vibrato LFO","✓ ΣΔ/PWM DAC"],
 "MP":["○ Video timing + text","○ 512-pt FFT tap"],
 "MH":["✓ CA-CFAR detector","○ DC-removal HPF"],
 "PH":["○ I²S/TDM link","○ Event frame UART","○ Note↔string map"],
 "TMH":["✓ CIC decimator","✓ CORDIC"],
 "MPH":["✓ 512-pt FFT","✓ BRAM tables","○ Timestamped events","○ Timer tick"],
 "TPH":["✓ Envelope gating"],
 "TMPH":["H2 FORTH SoC (control plane)","✓ PLL + reset","✓ UART + FIFO","✓ Register bus","✓ Fixed-point mult","✓ SPI ADC reader"],
}
def centroid(key):
    m=np.ones_like(masks["T"])
    for n in ell: m &= masks[n] if n in key else ~masks[n]
    if m.sum()==0: return None
    return xs[m].mean(), ys[m].mean()
s=[f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" font-family="ui-monospace,Menlo,Consolas,monospace"><rect width="{W}" height="{H}" fill="#fff"/>']
for n,(cx,cy,r) in ell.items():
    s.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{RX}" ry="{RY}" transform="rotate({r} {cx} {cy})" fill="{cols[n]}" fill-opacity="0.16" stroke="{cols[n]}" stroke-width="3"/>')
labels={"T":("THEREMIN",60,240),"M":("MAIDEN",120,940),"P":("PIANO (VL-49)",720,960),"H":("HARP (Erand49)",880,240)}
for n,(t,x,y) in labels.items():
    s.append(f'<text x="{x}" y="{y}" font-size="30" font-weight="700" fill="{cols[n]}">{t}</text>')
s.append('<text x="30" y="40" font-size="16" fill="#111">FPGA component overlap — four projects, one Clash library.  ✓ built   ○ planned   Centre = shared by all, H2 Forth SoC is the control plane for each.</text>')
for key,items in regions.items():
    c=centroid(key)
    if c is None: print("empty",key); continue
    x,y=c
    fs=15 if len(key)==4 else (13 if len(key)>=2 else 14)
    fw="700" if len(key)==4 else "400"
    y0=y-(len(items)-1)*fs*0.65
    for i,t in enumerate(items):
        s.append(f'<text x="{x:.0f}" y="{y0+i*fs*1.3:.0f}" font-size="{fs}" font-weight="{fw}" fill="#111" text-anchor="middle">{t}</text>')
s.append('</svg>')
svg="\n".join(s)
open('/mnt/user-data/outputs/fpga-venn4.svg','w').write(svg)
cairosvg.svg2png(bytestring=svg.encode(),write_to='/mnt/user-data/outputs/fpga-venn4.png',output_width=2400)
