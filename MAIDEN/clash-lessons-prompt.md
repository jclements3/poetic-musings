Write the remaining lessons of a Clash tutorial series for a single engineer (Jim), one file per
lesson, in ~/projects/maiden/lessons/src/.

## Context

This is the Clash analogue of Blaine Readler's "Verilog by Example" — the book Jim describes as
"what I wish I knew when starting out on FPGA programming." Lessons 01 and 02 already exist and
are the style reference. Read them first; match them exactly.

Jim is an experienced engineer, new to Clash, working alone. He is building MAIDEN (a radar/camera
tracking testbed) and has already produced a measured Clash/ECP5 block library — CIC, FIR, 512-pt
streaming FFT, CORDIC, CA-CFAR — plus a full theremin port. Those real results are teaching
material; use them.

## Environment

- GHC 9.6.7, cabal 3.14, Clash 1.8.5, WSL Ubuntu.
- Project at ~/projects/maiden/lessons with lessons.cabal + cabal.project already working.
- Build/verify command: `cl <Module>` (~/.local/bin/cl). It runs `cabal build`, then
  `cabal exec -- clash -isrc <Module> --vhdl`, deletes stale output first, and prints exactly
  `PASS: <Module> -> ...` or `FAIL: <reason>` plus the compiler error. Flags: -v full output,
  -s show generated VHDL.
- EVERY lesson you write must be verified with `cl LessonNN` before you move to the next one.
  A lesson that does not PASS is not done. Do not hand back unverified code.
- Add each new module to `exposed-modules` in lessons.cabal as you go.
- No FPGA board is attached and none is needed. Lessons requiring real hardware are deferred to
  the end and clearly marked.

## Diagrams (added 27 Aug)

Every lesson carries at least one text diagram INSIDE the .hs comments — box-drawing
characters, within 96 columns, four-space indented after `--` like other verbatim material so
a fill pass cannot mangle it. Original diagrams for our own examples, never redraws of
Readler's. The annotation convention is the point and is what Readler cannot do: under the
figure, repeat the source line and label its subexpressions so each wire/box in the picture
is tied to the exact code that makes it. Format reference: the counter figure in Lesson02.

Kinds: block diagrams for datapath lessons; state-transition charts (boxes and arrows with
guard labels) for state machines; and a timing sketch in Lesson05 showing blockRam's
one-cycle read latency — the detail most likely to bite when restructuring around a BRAM.

## Readler example mapping (added 27 Aug)

The 21 samples (PDF page order) and the lesson each belongs to:
Bus Breakout 04 (Vec/BitVector also 13); Bus Signals 04; Clock Buffer 06; D-flop with
Enable and Clear 02 ex.3; D-flop with Reset 02; Full Dual Port Memory 05; Intermediate Wire
Signals 04; Modular Design #1 04; Modular Design #2 04; Sample Design for Simulation 08;
Simple D-flop 02; Simple Dual Port Memory 05; Single-Port Memory 05 EXCEPT its inout/tristate
bus, which is a vendor-primitive topic and belongs in 07; SR flop and counter 03; SR flop
one always block 03; Standard Mux 02 (FAILURE 2); State Machine 1 03; State Machine 2 03;
Testbench Explicit Vectors 08; Testbench Automatic Vectors 09.

Notes: 15/16 and 18/19 are deliberate pairs teaching Verilog assignment-scheduling hazards
with no Clash counterpart — one "chapter that evaporates" paragraph in 03, not a lesson.
20 -> 21 is the arc into property testing; Lesson09 says explicitly that $random with a fixed
seed is a hedgehog generator with worse ergonomics and no shrinking.

## Corrections (added 27 Aug, from verification)

- Lesson02's three quoted errors were all wrong when compiled; the file now carries the real
  ones. Notably a topEntity with a HiddenClockResetEnable constraint SYNTHESISES in 1.8.5
  (auto-exposed ports) — FAILURE 3 is rewritten as a corrected claim.
- Lesson14 hardware: the ULX3S order was canceled; the ordered board is an Alchitry Cu
  (iCE40HX8K-CB132) + Br. Write 14 against theremin/clash/bringup/BRINGUP.md.
- cl now passes `-i` so only src/ is compiled (stray root-level lesson files had shadowed it).

## Hard formatting rules

- 96 columns maximum, everything, including comments. (Lessons 01-02 are currently set at 94;
  bring them to 96 for consistency, prose refilled, no content change.)
- Section rules are exactly 96 dashes.
- Comment prose is filled to the column — no ragged short lines.
- Verbatim material inside comments (type signatures, error text, VHDL snippets, repl sessions,
  Verilog comparisons) is indented four spaces after the `--` so a fill pass cannot mangle it.
  This matters: a previous automated reflow joined commented-out code into prose and corrupted
  both files.
- One working `topEntity` per file, uncommented. All variants commented out, with a note saying
  exactly one may be active.

## Style rules

- One idea per lesson. Small. Jim reads on a laptop between other work.
- Every lesson has: the working code, at least one FAILURE section showing code that does not
  compile with the actual compiler error text, an explanation of *why the error is right*, the
  Verilog behaviour it replaces, and 2-3 exercises.
- The failure sections are the point of the whole series. Clash's value proposition is that
  classes of bug become compile errors; show the error, do not describe it.
- Prose is direct and technical, occasionally wry. No cheerleading. No "great job!"
- Never claim a measured number you have not measured. Numbers quoted from Jim's existing work
  must be attributed to that work.

## Source material

Readler's code samples are downloadable from https://www.readler.com/books2.html
(`web_files/verilog_code_examples.zip`, `web_files/codesamples.pdf`, `web_files/verilog_errata.pdf`).

Use them ONLY to see which worked example each chapter is built around, so the lesson ordering and
pacing track the book. Do NOT translate his files, port his code line-for-line, or reproduce his
text or examples. Write original examples that teach the same concept. A mechanical port would
also be bad pedagogy: several of his chapters exist to teach hazards Clash deletes outright, and
several Clash topics have no chapter in his book at all.

## Lesson plan

Already written:

    Lesson01  A wire is a function; widths are types.       (his ch. 1-3)
    Lesson02  Registers, Signal, why you cannot `if` a wire. (his ch. 4)

To write, in order:

    Lesson03  State machines. ADTs as state, `mealy`/`moore`. The type checker replaces
              one-hot-vs-binary encoding anxiety and makes an unhandled state impossible.
              FAILURE: a state ADT missing an NFDataX instance; a transition function whose
              output type does not match the declared one.

    Lesson04  Modular design. Composition is function application — no port maps, no instance
              names, no wiring errors of the "connected to the wrong signal" kind. Generics
              become type-level naturals. Worked example: a block parameterised on a ratio,
              mirroring how MAIDEN's CIC takes its decimation ratio R as a type parameter
              (see decimation-audit.md: R=4 at 24 GHz, R=8 at 10.5 GHz, identical RTL).
              FAILURE: instantiating with a ratio the arithmetic cannot satisfy.

    Lesson05  MEMORIES. The most valuable lesson in the series — do not rush it.
              `Vec` in Moore state vs `asyncRam` vs `blockRam` vs `asyncRom`.
              Jim's measured result: DelayDiffFilter holding two 512-deep buffers as Vecs in
              Moore state measured 27.7k LUT4 / 23.5k FF and would not route at 100 MHz;
              rewritten on blockRam, the complete theremin_top is 1,816 LUT4 / 452 FF / 2 BRAM.
              A 20x reduction from one idiom change. State the rule plainly: Vec in register
              state is for small banks only, memories go in asyncRam/blockRam.
              Also cover the one-cycle read latency blockRam imposes and why it changes the
              surrounding design.

    Lesson06  Managing clocks. Domains as types. `createDomain`, custom periods, reset
              polarity. Clock crossing, `unsafeSynchronizer`, and — important — the honest
              statement that the type system prevents accidentally *mixing* domains but does
              not make a two-FF synchroniser correct. Metastability is still physics.

    Lesson07  I/O flavors and the vendor-primitive boundary. Blackboxes, primitive annotations,
              DDR I/O. The central finding, from Jim's own port: Clash does not get you out of
              vendor primitives, it only changes what surrounds them. Upstream's theremin front
              end uses IDELAYCTRL and ISERDESE2, which have no ECP5 equivalent; the port takes
              the edge stream as input and everything downstream is portable. A hand-written
              VHDL port would hit the identical wall — it is a hardware design problem, not a
              translation problem.

    Lesson08  Simulation without a simulator. `sampleN`, `simulate`, pure step functions.
              Every *Step function is an ordinary Haskell function, so behaviour is checkable
              as properties over full counter periods with no simulator at all.

    Lesson09  Verification that actually gates. Property tests (hedgehog) against an
              independently written reference model; cycle-exact structural-vs-model
              equivalence; then `make sim` — elaborating the *generated VHDL* under GHDL, which
              catches code-generation faults a Haskell-only test cannot see. Three distinct
              checks, three distinct failure classes. Explain why all three are needed.

    Lesson10  Types as the sizing tool. Overflow becomes either a compile error or a deliberate
              scaling decision. Worked example: fixed-point growth through a multiply-accumulate
              chain, and why MAIDEN's FFT carries explicit per-stage 1/2 scaling with an overall
              divide-by-512 rather than hoping.

    Lesson11  Area is a measurement, not an opinion. Run yosys synth_ecp5 + nextpnr-ecp5 on a
              lesson block and read real LUT/FF/BRAM/DSP/Fmax numbers on the LFE5U-85F.
              The headline case from Jim's work: a behavioural 512-point FFT synthesised to
              ~139k LUT4 — 166% of the 83,640 available, i.e. it did not fit the largest part in
              the family. The same transform as a streaming radix-2 single-delay-feedback design
              measured 3,537 LUT4 (4.2%), 28 DSP, 10 BRAM, timing-clean at 123.6 MHz. Roughly
              30x, and the work moved into the DSP and BRAM columns the behavioural estimate had
              left at zero. Pipelining *reduced* LUT count while fixing timing. The lesson:
              sizing questions are answered by running the flow, not by arguing, and they do not
              require owning a board.

    Lesson12  Porting from Verilog. What stating every width explicitly surfaces. Use the two
              real defects the theremin port found: a volume-path converter parameterised with
              the pitch width (23 bits where the path is 21), and a pulse-position output of
              EDGE_POSITION_BITS+1 bits connected to a signal declared one bit narrower, so an
              overflowing sum silently wraps. Both were reproduced faithfully in the port with
              comments rather than silently fixed, so the ports stay equivalent to the hardware.
              Also cover: RESET as data rather than a reset network; two independent ifs vs
              if/else; state banks that survive reset.

    Lesson13  Reference card. Signed/Unsigned/BitVector/Index, the Fixed types, resize vs
              truncateB vs bitCoerce, the Vec API, and the lifted-operator table. Terse; this
              one is lookup material, not a lesson.

    Lesson14  ON HARDWARE. Marked clearly as blocked until the ULX3S 85F arrives (expected
              2 Sep 2026). Bitstream, pin constraints, fujprog/openFPGALoader, and the first
              thing that will be wrong. Write it, note the block at the top, do not pretend to
              have run it.

## Process

Work one lesson at a time. Write it, run `cl LessonNN`, fix until PASS, then move on. If a lesson
turns out to need two ideas, split it rather than making it longer.

### Every failure case must be compiled, not imagined

This is not optional and it is the easiest step to skip. A FAILURE section quotes compiler output,
and quoted compiler output that was written from memory is worse than no lesson at all — Jim will
hit the real message later and have to work out which of us was wrong.

For each FAILURE variant in each lesson:

1. Comment out the working topEntity and uncomment the failing one, so it is the only active
   definition.
2. Run `cl LessonNN`. It must report FAIL.
3. Copy the error text `cl` prints — verbatim, exact wording, exact GHC error code — into the
   comment block. Trim only for width, and if you trim, make it obvious you trimmed.
4. Restore the working topEntity and re-run `cl LessonNN` to confirm PASS before moving on.

If a case you expected to fail instead compiles, that is a finding, not an inconvenience. Do not
quietly reword the lesson around it. Say so explicitly in the file and in your summary: what you
expected, what actually happened, and what it means. It usually means the real boundary sits
somewhere other than where the lesson claimed, which is worth more than the lesson you planned.

### Errors already in the existing files

Lesson01's quoted error (`Couldn't match type '8' with '4'`, GHC-83865) came from Jim's own
terminal and is confirmed real.

Lesson02's three quoted errors are NOT confirmed. Verify all three by the procedure above and
correct the text to whatever the compiler actually emits. Treat FAILURE 3 (a topEntity that still
carries a `HiddenClockResetEnable` constraint) with particular suspicion — the claim is that it
type-checks as Haskell but fails inside Clash, and both the failure mode and the message need
checking rather than assuming.

### Summary

At the end, print a table: lesson number, filename, one-line topic, PASS/FAIL for the working
build, and the count of failure cases actually compiled and confirmed. Flag any lesson where a
predicted failure did not occur.
