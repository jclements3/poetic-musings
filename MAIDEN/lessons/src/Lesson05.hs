-- Lesson 05: memories -- the most expensive idiom decision you will make, and the one-cycle
-- latency that comes with getting it right.
--
--     Build:  cabal exec -- clash -isrc Lesson05 --vhdl
--     Output: vhdl/Lesson05.topEntity/topEntity.vhdl
--
-- Add `Lesson05` to exposed-modules in lessons.cabal first.
--
-- Exactly one topEntity may be uncommented at a time.

module Lesson05 where

import Clash.Prelude

------------------------------------------------------------------------------------------------
-- The idea
------------------------------------------------------------------------------------------------
--
-- An FPGA has three physically different places to keep a table of values, and they differ in
-- cost by orders of magnitude:
--
--     fabric flip-flops   one FF per bit, plus a mux tree to read and a decoder to write
--     distributed RAM     the LUTs themselves used as tiny RAMs (ECP5: TRELLIS_DPR16X4,
--                         16 x 4 bits each); read is combinational
--     block RAM           dedicated 18 kbit hard macros (ECP5: DP16KD, 208 of them on the
--                         85F); read is synchronous -- one cycle of latency, no exceptions
--
-- In Verilog you steer between these with coding-style folklore: inference templates,
-- vendor-specific attributes, and rumours about what your synthesis version recognises this
-- year. In Clash the choice is explicit -- it is which function you call:
--
--     Vec in register state    fabric flip-flops
--     asyncRam                 distributed RAM
--     blockRam                 block RAM
--     asyncRom / rom           constant table, combinational / synchronous read
--
-- Same program meaning, wildly different hardware. This lesson is about choosing, and about
-- the one place the choice is NOT free: blockRam's read latency.

------------------------------------------------------------------------------------------------
-- What the wrong choice costs, measured
------------------------------------------------------------------------------------------------
--
-- These numbers are from the theremin port in this repo (theremin/clash/README.md), real
-- place-and-route on the ECP5 LFE5U-85F, not estimates.
--
-- The theremin's delay_diff_filter needs two 512-deep buffers. The first Clash version held
-- them the way Lessons 03-04 hold state: as `Vec`s inside Moore state. It compiled without a
-- murmur, it simulated correctly, and the sensor top measured
--
--     27,700 LUT4 / 23,500 FF -- and would not route at 100 MHz.
--
-- Every one of those 2 x 512 x ~24 buffer bits had become a fabric flip-flop, wrapped in mux
-- forests to read and decoders to write. Rewritten on `blockRam` -- pinned to the old
-- behaviour by a cycle-exact equivalence test -- the COMPLETE instrument, oscillator pins to
-- audio, is
--
--     1,816 LUT4 / 452 FF / 2 BRAM, closing at 75 MHz.
--
-- A 20x reduction from one idiom change, confirmed twice: the IIR filter's 8-entry state bank
-- told the same story in miniature (naive Vec-in-state: 519 LUT4 / 307 FF; on `asyncRam`:
-- 175 LUT4 / 67 FF -- exactly matching the hand-written SystemVerilog, primitive for
-- primitive).
--
-- The rule, plainly: `Vec` in register state is for small banks only -- a handful of entries
-- you genuinely need simultaneous access to. Anything that is morally a memory goes in
-- `asyncRam` or `blockRam`. Nothing in the compiler enforces this; the 27.7k-LUT version is a
-- perfectly well-typed program. This is the one failure mode in this series that shows up in
-- the place-and-route report instead of the compiler output, which is why Lesson 11 exists.

------------------------------------------------------------------------------------------------
-- The working example: a 512-cycle delay line on blockRam
------------------------------------------------------------------------------------------------
--
-- The simplest circuit that is morally a memory: output equals input, 512 cycles ago. One
-- write pointer, circular addressing, and the read address one slot ahead of the write.

delayLine ::
  forall dom.
  HiddenClockResetEnable dom =>
  Signal dom (Unsigned 8) ->
  Signal dom (Unsigned 8)
delayLine x = blockRam (replicate d512 0) rdAddr wrPort
 where
  wrAddr :: Signal dom (Index 512)
  wrAddr = register 0 (satSucc SatWrap <$> wrAddr)

  rdAddr :: Signal dom (Index 512)
  rdAddr = satSucc SatWrap <$> wrAddr

  wrPort :: Signal dom (Maybe (Index 512, Unsigned 8))
  wrPort = Just <$> bundle (wrAddr, x)

topEntity ::
  Clock System ->
  Reset System ->
  Enable System ->
  Signal System (Unsigned 8) ->
  Signal System (Unsigned 8)
topEntity = exposeClockResetEnable delayLine

-- The datapath, drawn:
--
--                                    ┌──────────────────────┐
--     x ────────────────────────────▶│ wrData               │
--                                    │                      │
--        ┌────────────┐              │   blockRam 512 x 8   │──────▶ x delayed 512 cycles
--        │  wrAddr    │──┬──────────▶│ wrAddr   (DP16KD)    │
--        │  counter   │  │  ┌────┐   │                      │
--        └────────────┘  └─▶│ +1 │──▶│ rdAddr               │
--                           └────┘   └──────────────────────┘
--
--     delayLine x = blockRam (replicate d512 0) rdAddr wrPort
--                   │         │                 │      │
--                   │         │                 │      └── wrAddr + wrData, fused with the
--                   │         │                 │          write enable in one Maybe
--                   │         │                 └───────── the +1 tap into the read port
--                   │         └─────────────────────────── shape (512 x 8) and power-up value
--                   └───────────────────────────────────── the RAM macro itself
--
--   * The initial-content vector is the memory's declaration: its length is the depth, its
--     element type is the width. There is no other place those are stated.
--   * The write port is `Signal dom (Maybe (addr, data))`. There is no separate write-enable
--     wire to forget or leave floating -- `Nothing` is "no write", `Just (a, d)` is a write,
--     and you cannot construct write data without having decided which. (FAILURE 1 tries.)
--   * `satSucc SatWrap` on an `Index 512` is the circular buffer: the counter IS mod-512
--     because its type is. No bit-width-matches-depth invariant to maintain by hand.
--   * Why does rdAddr lead by one? That is the latency, next section.

------------------------------------------------------------------------------------------------
-- The one-cycle read latency, and why the design bends around it
------------------------------------------------------------------------------------------------
--
-- A block RAM's read is registered inside the macro. The address you present on cycle t comes
-- back as data on cycle t+1 -- always. `asyncRam` (distributed RAM) answers in the same
-- cycle. Side by side:
--
--     cycle                 │  t   │  t+1  │  t+2  │  t+3  │
--     address presented     │  a   │  a+1  │  a+2  │  a+3  │
--     asyncRam output       │ m[a] │ m[a+1]│ m[a+2]│ m[a+3]│   combinational, same cycle
--     blockRam output       │  ?   │ m[a]  │ m[a+1]│ m[a+2]│   registered, one cycle later
--                              ▲
--                              └── whatever the macro registered before t (at power-up: the
--                                  initial-content value, here 0)
--
--     rdAddr = satSucc SatWrap <$> wrAddr
--     │                            │
--     │                            └── the "address presented" row: on cycle t it points one
--     │                                PAST the slot being written, i.e. the oldest sample
--     └─────────────────────────────── feeds the blockRam row: its value at t emerges at t+1
--
-- Follow the delay line through it. On cycle t the write pointer is at slot a: x(t) goes into
-- m[a], and slot a+1 -- written 511 cycles ago -- is presented for reading. Its value emerges
-- at t+1, which is 512 cycles after it went in. The off-by-one in `rdAddr` and the one-cycle
-- read latency cancel to give exactly 512. Do that arithmetic consciously every time; it is
-- the standard off-by-one of every synchronous FIFO and it does not forgive estimation.
--
-- This is why the latency changes the SURROUNDING design, not just the memory:
--
--   * Anything that travels alongside a RAM read (a valid flag, a tag, the address itself)
--     needs a `register` next to the RAM, or it arrives a cycle early.
--   * A read-modify-write loop (read, add, write back) takes two cycles per element, or gets
--     pipelined so the write of element k overlaps the read of k+1.
--   * If the consumer only samples occasionally, you can instead freeze the read address
--     between strobes so the output register simply holds -- the trick the theremin's
--     DelayDiffFilter uses (theremin/clash/src/Theremin/DelayDiffFilter.hs) to stay
--     cycle-exact with its behavioural model.
--
-- One more sharp edge: on a same-cycle read and write of the SAME address, Clash's `blockRam`
-- returns the newly written value (write-first). The delay line's read and write addresses
-- always differ by one, so it never exercises that case -- arranging never to collide is the
-- usual discipline, because vendors differ on collision behaviour and the tools take the
-- write-first demand seriously.

------------------------------------------------------------------------------------------------
-- asyncRam and the ROMs, briefly
------------------------------------------------------------------------------------------------
--
-- `asyncRam` has the same read/write-port shape but no initial content -- distributed RAM
-- powers up undefined, so its type takes a depth instead of a contents vector, and reads
-- before the first write return X in simulation:
--
--     asyncRam :: ... => SNat n -> Signal dom addr -> Signal dom (Maybe (addr, a))
--                     -> Signal dom a
--
-- Use it where the SystemVerilog would have used a small unregistered array: shallow, narrow,
-- read-addressed combinationally. The theremin IIR's 8-entry state bank on `asyncRam` is the
-- proof it is the right tool at that size -- 175 LUT4 / 67 FF, identical to the hand-written
-- SV. At 512 deep you want the BRAM instead; depth is the deciding variable.
--
-- Constant tables split the same way:
--
--     asyncRom :: ... => Vec n a -> addr -> a                              -- combinational
--     rom      :: ... => Vec n a -> Signal dom (Unsigned m) -> Signal dom a  -- 1-cycle, BRAM
--
-- `asyncRom` is not even a circuit function -- it is an ordinary function you can apply under
-- `fmap`, and it becomes LUTs. `rom` has blockRam's registered read and lands in BRAM. A sine
-- table for an NCO goes in `rom`; a 16-entry gamma curve can be `asyncRom`.

------------------------------------------------------------------------------------------------
-- FAILURE 1: there is no write-enable wire to forget
------------------------------------------------------------------------------------------------
--
-- Verilog memory bugs cluster around the write enable: unconnected, mis-polarised, or gated
-- with the wrong qualifier. Try to hand `blockRam` bare address+data, no enable decision:
--
--     delayLine x = blockRam (replicate d512 0) rdAddr wrPort
--      where
--       ...
--       wrPort = bundle (wrAddr, x)                    -- forgot the Just
--
--     src/Lesson05.hs:92:19: error: [GHC-83865]
--         * Couldn't match type: (Signal dom (Index 512),
--                                 Signal dom (Unsigned 8))
--                          with: Signal dom (Maybe (Index 512, Unsigned 8))
--           Expected: Unbundled dom (Maybe (Index 512, Unsigned 8))
--             Actual: (Signal dom (Index 512), Signal dom (Unsigned 8))
--         * In the first argument of `bundle', namely `(wrAddr, x)'
--
-- Compiled and confirmed 27 Aug 2026. The gap is the missing `Maybe`, but note WHERE it
-- surfaces: at `bundle`, phrased through its `Unbundled` type family -- "what tuple-of-
-- Signals would bundle into the port type you promised?" Lesson 02's pattern again: the
-- mismatch is reported from the adjacent plumbing, and the `Relevant bindings` list (trimmed
-- here) is what orients you -- it shows `wrPort`'s declared type right next to the actual.
--
-- The write port's type is `Maybe (addr, a)`: "am I writing this cycle" is part of the value,
-- not a separate wire that can dangle. You are forced to say `Just` -- and the moment this
-- delay line grows a real reason not to write every cycle, that reason has an obvious place
-- to live: `mux we (Just <$> ...) (pure Nothing)`.

------------------------------------------------------------------------------------------------
-- FAILURE 2: the buffer does not widen itself
------------------------------------------------------------------------------------------------
--
-- Lesson 04 widened a datapath by changing one type parameter. Suppose that happened here --
-- samples are now 9 bits -- but the buffer declaration kept its 8-bit contents:
--
--     delayLine :: ... Signal dom (Unsigned 9) -> Signal dom (Unsigned 9)
--     delayLine x = blockRam (replicate d512 (0 :: Unsigned 8)) rdAddr wrPort
--       ...
--
--     src/Lesson05.hs:83:66: error: [GHC-83865]
--         * Couldn't match type `8' with `9'
--           Expected: Signal dom (Maybe (Index 512, Unsigned 9))
--             Actual: Signal dom (Maybe (Index 512, Unsigned 8))
--         * In the third argument of `blockRam', namely `wrPort'
--
--     (...two more GHC-83865 errors follow, at wrPort's own annotation and at topEntity --
--      every line still assuming 8 bits, listed in one compile...)
--
-- Compiled and confirmed 27 Aug 2026. The initial-content vector declared the RAM 8 bits
-- wide, the write port offers 9, and the disagreement is caught at the RAM's declaration
-- site -- with the rest of the errors enumerating every other place the old width still
-- stands, Lesson 04's complete-list-of-stale-assumptions again. The Verilog equivalent -- a
-- `reg [7:0] mem [0:511]` fed from a widened bus -- lops the MSB off every sample per write,
-- which in a delay line means the corruption is also 512 cycles away from its cause when you
-- finally see it downstream.

------------------------------------------------------------------------------------------------
-- NOT A FAILURE, and worth knowing: the address side is barely checked
------------------------------------------------------------------------------------------------
--
-- After Lessons 01 and 04 you might expect the depth to be type-checked against the address
-- width. Look at the signature again: the address is any `Enum`. This compiles:
--
--     wrAddr :: Signal dom (Index 4)          -- 2-bit counter...
--     ...
--     delayLine x = blockRam (replicate d512 0) rdAddr wrPort   -- ...into a 512-deep RAM
--
-- Compiled and confirmed 27 Aug 2026: PASS, no complaint. The RAM converts addresses through
-- `fromEnum`, so depth-vs-address consistency is YOUR invariant, not the compiler's. Too-few
-- address bits strand most of the RAM (as above); an address type that can exceed the depth
-- fails in simulation with an out-of-bounds X, not at compile time. The discipline that keeps
-- this honest is the one `delayLine` uses: address with `Index depth`, never a free-floating
-- `Unsigned`, so your counters carry the depth in their type even though the RAM does not
-- demand it. Types stop where `Enum` starts; know where the guardrail ends.

------------------------------------------------------------------------------------------------
-- Exercises
------------------------------------------------------------------------------------------------
--
-- 1. Rebuild `delayLine` on `asyncRam d512` and diff the VHDL. Where did the output register
--    go, and what happened to the read-address off-by-one -- is it still `+1`, and why not?
--    (Work the timing table by hand before you look.)
--
-- 2. Make the depth a parameter: `delayBy :: SNat n -> ...` with `Index n` addressing, in the
--    Lesson 04 style. What constraint does the compiler ask for the moment you write
--    `satSucc SatWrap`? (It is telling you an empty delay line is not a thing.)
--
-- 3. Build a 256-entry sine ROM for an audio NCO: `rom $(listToVecTH ...)` is the industrial
--    route, but `rom (map f indicesI)` needs no Template Haskell -- generate a quarter wave
--    and exploit symmetry if you want the classic trick. Account for the ROM's read latency
--    in the phase accumulator: does a one-cycle-late sample ever matter to an NCO? Say why
--    not out loud.
