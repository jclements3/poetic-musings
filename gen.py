W0, KW, KY, KH, BW, BH = 40, 42, 180, 130, 26, 78
NOTES = "CDEFGAB"
white = [NOTES[i%7] + str(2 + i//7) for i in range(29)]  # C2..C6
xs = [W0 + KW*i for i in range(29)]
svg = []
svg.append('<rect x="5" y="5" width="1290" height="320" rx="12" fill="#e9e4d6" stroke="#b9b3a3" stroke-width="1.5"/>')
# LCD
svg.append('<rect x="40" y="22" width="700" height="140" rx="4" fill="#3b3e44"/><rect x="50" y="40" width="680" height="112" rx="2" fill="#0d1117"/><g style="font:bold 9px ui-monospace,Menlo,monospace;fill:#9fff8a"><text x="58" y="56">ok</text><text x="58" y="70">90099914 patch!  ok</text><text x="58" y="84">: arp  begin key? until  ;  ok</text><text x="58" y="98">rec  100 notes  tempo 120  rock-1</text><text x="58" y="112">▶ C4  E4  G4  C5  _</text></g><polyline points="380,120 400,90 430,100 470,106 520,112 560,118 600,124 640,132 700,140" fill="none" stroke="#c9553a" stroke-width="1.5"/><text x="380" y="148" class="tw">ADSSR envelope, live</text>'
 ''
 '<text x="390" y="32" class="tw" text-anchor="middle">8.8" 1920×480 BAR TFT, HDMI — FORTH CONSOLE + ENVELOPE/SPECTRUM VIEW</text><text x="44" y="30" class="id">V0</text>')
# sliders
def slider(x,w,label2,lines,idt):
    s=[]
    for j,l in enumerate(lines):
        s.append(f'<text x="{x+w/2}" y="{16+7*j}" class="tt" text-anchor="middle">{l}</text>')
    s.append(f'<rect x="{x}" y="33" width="{w}" height="12" rx="2" fill="#3b3e44"/><rect x="{x+w*0.3}" y="29" width="20" height="20" rx="2" fill="#6a6d74"/><text x="{x}" y="56" class="id">{idt}</text>')
    return "".join(s)
svg.append(slider(790,80,None,["","MIN — VOLUME — MAX"],"S0"))
svg.append(slider(885,90,None,["","RHYTHM — BALANCE — MELODY"],"S1"))
svg.append(slider(990,60,None,["OCTAVE","LOW · MID · HIGH"],"S2"))
svg.append(slider(1065,110,None,["MODE","P · O · E · T · I · C"],"S3"))
svg.append(slider(1190,80,None,["OFF · CAL","PLAY · REC"],"S4"))
# buttons
btns=[("RESET","AC","#c9553a"),("DEL","C","#6a6d74"),("TEMPO ▲","√","#6a6d74"),("TEMPO ▼","%","#6a6d74"),("RHYTHM","","#6a6d74"),("ML-C","MC","#6a6d74"),("MUSIC","MR","#d9962a"),("AUTO PLAY","M−","#3b5a7a")]
for i,(t,sub,c) in enumerate(btns):
    x=800+i*46
    svg.append(f'<g transform="translate({x},125)"><text y="-3" class="tt" text-anchor="middle">{t}</text><rect x="-6" y="2" width="12" height="28" rx="2" fill="{c}"/><text y="40" class="tt" text-anchor="middle">{sub}</text><text x="-6" y="48" class="id">P{i}</text></g>')
svg.append('<text x="1220" y="118" class="tt" text-anchor="middle">ONE KEY PLAY</text>')
for i,x in enumerate([1195,1248]):
    svg.append(f'<g transform="translate({x},125)"><rect x="-15" y="0" width="30" height="42" rx="4" fill="#3b5a7a"/><circle cx="0" cy="21" r="6" fill="none" stroke="#e9e4d6" stroke-width="1.5"/>{"<text y=\"52\" class=\"tt\" text-anchor=\"middle\">M+</text>" if i==0 else ""}<text x="-15" y="60" class="id">P{8+i}</text></g>')
# white keys
svg.append('<g fill="#f4f0e6" stroke="#8d877a" stroke-width="1">'+"".join(f'<rect x="{x}" y="{KY}" width="{KW}" height="{KH}"/>' for x in xs)+'</g>')
svg.append('<g class="lbl" text-anchor="middle">'+"".join(f'<text x="{x+KW/2}" y="{KY+24}">{n}</text>' for x,n in zip(xs,white))+'</g>')
# black keys
blk=[i for i in range(28) if NOTES[i%7] in "CDFGA"]
svg.append('<g fill="#2a2c30">'+"".join(f'<rect x="{W0+KW*(i+1)-BW//2}" y="{KY}" width="{BW}" height="{BH}" rx="2"/>' for i in blk)+'</g>')
# VL-1 style: keys are flat button caps (Cherry MX2A Silent Red) set in the printed keyboard graphic
svg.append('<g fill="#ffffff" stroke="#8d877a" stroke-width="1.2">'+"".join(f'<rect x="{x+KW/2-13}" y="{KY+104}" width="26" height="26" rx="3"/>' for x in xs)+'</g>')
svg.append('<g fill="#0c0d0f" stroke="#55575c" stroke-width="1.2">'+"".join(f'<rect x="{W0+KW*(i+1)-9}" y="{KY+50}" width="18" height="24" rx="2"/>' for i in blk)+'</g>')
# ASCII layers. Base printed large at key bottom; SHIFT layer (hold One Key Play L = P8) printed above it.
wb = ["SPC"]+list("abcdefghijklmnopqrstuvwxyz")+[".","RET"]
ws = [""]+[c.upper() for c in "abcdefghijklmnopqrstuvwxyz"]+[",",""]
bb = list("0123456789")+list(":;!@'\"-=/*")
bs = list(")(#$%^&+<>")+list("?[]{}\\|_`~")
def esc(c): return c.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace('"',"&quot;")
svg.append('<g class="t" text-anchor="middle">'+"".join(f'<text x="{x+KW/2}" y="{KY+124}">{esc(c)}</text>' for x,c in zip(xs,wb))+'</g>')
svg.append('<g class="sh" text-anchor="middle">'+"".join(f'<text x="{x+KW/2}" y="{KY+101}">{esc(c)}</text>' for x,c in zip(xs,ws))+'</g>')
bx=[W0+KW*(i+1) for i in blk]
svg.append('<g class="bk" text-anchor="middle">'+"".join(f'<text x="{x}" y="{KY+70}">{esc(c)}</text>' for x,c in zip(bx,bb))+'</g>')
svg.append('<g class="bks" text-anchor="middle">'+"".join(f'<text x="{x}" y="{KY+36}">{esc(c)}</text>' for x,c in zip(bx,bs))+'</g>')

# Harp Erand49 string labels: 49 diatonic strings A0..G7 mapped left-to-right across all 49 keys
hn=["A","B","C","D","E","F","G"]
harp=[]
o=0
for i in range(49):
    n=hn[i%7]; 
    if n=="C" and i>0: o+=1
    harp.append(f"{n}{o}")
harp=[("A0","B0")[i] if i<2 else harp[i] for i in range(49)]
keys=[(x,'w') for x in xs]+[(W0+KW*(i+1)-BW//2,'b') for i in blk]
keys.sort()
for (x,kind),lab in zip(keys,harp):
    if kind=='w':
        svg.append(f'<text x="{x+KW/2}" y="{KY+12}" class="hp" text-anchor="middle">{lab}</text>')
    else:
        svg.append(f'<text x="{x+BW/2}" y="{KY+12}" class="hpb" text-anchor="middle">{lab}</text>')
rhy=["MARCH","WALTZ","4-BEAT","SWING","ROCK-1","ROCK-2","BOSSA","SAMBA","RHUMBA","BEGUINE"]
svg.append('<g class="lbl" text-anchor="middle">'+"".join(f'<text x="{xs[13+j]+KW/2}" y="{KY+92}">{r}</text>' for j,r in enumerate(rhy))+'</g>')
svg.append(f'<text x="{W0}" y="320" class="id">Keys A0..G7 — 29 white + 20 black, C2–C6; flat button caps (Cherry MX2A Silent Red) in a printed keyboard graphic, as on the original VL-1. Key ID = gold pedal-harp string label. ASCII base on cap, SHIFT above (SHIFT = One Key Play L / P8); DEL = backspace.</text>')
body="\n".join(svg)
html=f'''<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=0.5, maximum-scale=6, user-scalable=yes"><title>VL-1 49-key panel map</title>
<style>
html,body{{margin:0;background:#ffffff !important;color:#111 !important;font:16px/1.45 ui-monospace,Menlo,Consolas,monospace}}
main{{max-width:1300px;margin:0 auto;padding:16px}} h1{{font-size:16px;font-weight:600;margin:0 0 4px;letter-spacing:.04em}} p.sub{{margin:0 0 12px;color:#333}}
.wrap{{overflow:auto;-webkit-overflow-scrolling:touch;border:1px solid #ccc;touch-action:pinch-zoom pan-x pan-y}} svg{{width:1300px;max-width:none;height:auto;display:block}} @media (min-width:1340px){{svg{{width:100%}}}}
table{{border-collapse:collapse;width:100%;margin-top:14px;font-size:13px}} th,td{{text-align:left;padding:6px 8px;border-bottom:1px solid #999;vertical-align:top;color:#111}} th{{color:#111;font-weight:700;background:#eee}}
.t{{font-size:8px;font-weight:700;fill:#111;font-family:ui-monospace,Menlo,Consolas,monospace}} .tt{{font-size:6px;font-weight:700;fill:#111;font-family:ui-monospace,Menlo,Consolas,monospace}}
.tw{{font-size:7px;font-weight:700;fill:#ffffff;font-family:ui-monospace,Menlo,Consolas,monospace}} .lbl{{font-size:6px;font-weight:700;fill:#111;font-family:ui-monospace,Menlo,Consolas,monospace}}
.sh{{font-size:6px;fill:#555;font-family:ui-monospace,Menlo,Consolas,monospace}} .bk{{font-size:8px;font-weight:700;fill:#fff;font-family:ui-monospace,Menlo,Consolas,monospace}} .bks{{font-size:7px;font-weight:700;fill:#ffffff;font-family:ui-monospace,Menlo,Consolas,monospace}} .hp{{font-size:6px;font-weight:700;fill:#a8700f;font-family:ui-monospace,Menlo,Consolas,monospace}} .hpb{{font-size:6px;font-weight:700;fill:#f2c14e;font-family:ui-monospace,Menlo,Consolas,monospace}} .id{{font-size:6px;fill:#b3341c;font-family:ui-monospace,Menlo,Consolas,monospace;font-weight:700}}
</style></head><body><main>
<h1 style="color:#111">VL-1 DERIVATIVE — 49-KEY PANEL MAP</h1>
<p class="sub">Speaker removed from the top face; 55 mm display band with full-width bar TFT; sliders banked top-right over the buttons; keyboard extended to 4 octaves C–C. Keys are flat button caps (Cherry MX2A Silent Red) set in a printed keyboard graphic, as on the original VL-1. Key pitch 16 mm — MX housing limit; original VL-1 was ~13 mm. Not to scale.</p>
<div class="wrap"><svg viewBox="0 0 1300 330" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="49-key VL-1 derivative panel layout">
{body}
</svg></div><p class="sub">Diagram scrolls sideways on a phone.</p>
<table>
<tr><th>ID</th><th>Element</th><th>Count</th><th>Port input</th></tr>
<tr><td>A0–G7</td><td>Keys, 29 white + 20 black, C2–C6 — pushbuttons like the original VL-1's; ID = pedal-harp string label, one per key; full printable-ASCII legend: letters/./SPC/RET on whites, digits + Forth symbols on blacks, SHIFT layer for uppercase and remaining symbols</td><td>49</td><td>Key matrix, 7×7 scan</td></tr>
<tr><td>P0–P9</td><td>Reset, Del, Tempo ▲/▼, Rhythm, ML-C, Music, Auto Play, One Key Play ×2</td><td>10</td><td>Fold into matrix (8×8 total)</td></tr>
<tr><td>S0, S1</td><td>Volume, Balance</td><td>2</td><td>ADC, continuous</td></tr>
<tr><td>S2</td><td>Octave (low / middle / high)</td><td>3 zones</td><td>ADC, zone + hysteresis</td></tr>
<tr><td>S3</td><td>MODE selector — P·O·E·T·I·C (Piano, Oracle, Erand49, Theremin, IRIG clock, CW). Switches after 1 s dwell in a new zone, banner on V0. Voice select in P mode: MUSIC (P6) + black-key digit</td><td>6 zones</td><td>ADC, zone + hysteresis</td></tr>
<tr><td>S4</td><td>Off / cal / play / rec — within the current mode (CAL = retune/calibrate, REC = record)</td><td>4 zones</td><td>ADC, zone + hysteresis</td></tr>
<tr><td>V0</td><td>8.8" 1920×480 bar TFT (~220×55 mm), HDMI driver board</td><td>1</td><td>GPDI/DVI from ULX3S; H2 vga.vhd text mode retimed, plus overlay framebuffer</td></tr>
<tr><td>—</td><td>Speaker, underside, rear port; ⅛" jack</td><td>1 ch</td><td>PWM/ΣΔ + RC LP</td></tr>
</table>
<p class="sub">Body width: 29 × 16 mm + 40 mm margins ≈ 504 mm (original 300 mm; 13 mm pitch dropped for the 15.6 mm MX2A housing, 14×14 mm plate cutouts); display band 55 mm, verify active area against panel datasheet before cutting. Sounding range with octave switch: C1–C7, 6 octaves.</p>
</main></body></html>'''
import os
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'README.html'),'w').write(html)
