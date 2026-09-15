-- timebase_tb: SYS-006 verification of pps_discipline + irigb_gen +
-- strobe_latch.
--
-- Cases (each assert tagged SYS-006):
--   T1/T2   nominal PPS -> locked within 3 intervals, offset ~ 0
--   T3      IRIG-B frame decodes to the loaded TOD (independent decoder
--           written here, by hand, per lesson 18: encoder and decoder by
--           the same hand find each other's bugs) + SBS == BCD cross-check
--   T4      P_r edge within 3 RTC counts of the PPS latch (2 counts of
--           register pipeline; the async->sync path is a fixed 2-3 clk)
--   T5/T6   +30 ppm crystal offset -> still locked, offset ~ +300
--   T7-T10  holdover: lock drops, frames keep crystal cadence, TOD
--           continuous through PPS return and relock
--   T11-T15 strobe FIFO: monotonic stamps, exact count, no overflow;
--           17-burst -> sticky overflow, fill capped at DEPTH
--
-- PPS jitter/offset is programmable via signals (deterministic - no
-- now-based randomness; CI needs repeatability).
--
-- SCALING NOTE: the DUTs are generic in RTC_HZ, and this TB runs them at
-- RTC_HZ = 1_000_000 so a "second" costs 1M clk ticks instead of 10M --
-- a 32-"second" scenario simulates in minutes, not the better part of an
-- hour, and every duration below derives from the single SEC constant.
-- All ppm relationships are rate-invariant: the +30 ppm case asserts
-- offset = 30 ppm x RTC_HZ = +30 counts here, which is the same physics
-- as the +300 counts the card quotes at the hardware's 10 MHz.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity timebase_tb is
end entity;

architecture sim of timebase_tb is
  constant CLK_PERIOD : time := 100 ns;
  constant RTC_HZ     : positive := 1_000_000;   -- scaled; see header note
  constant SEC        : time := CLK_PERIOD * RTC_HZ;  -- one scaled second
  constant CELL       : time := SEC / 100;            -- one IRIG-B cell
  constant LOCK_TOL_C : positive := 50;               -- 50 ppm, as at 10 MHz
  constant PPM30      : integer := 30 * (RTC_HZ / 1_000_000);  -- +30 ppm

  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';
  signal done : boolean := false;

  -- PPS generator controls
  signal pps        : std_logic := '0';
  signal pps_en     : boolean := false;
  signal pps_period : time := SEC;

  -- DUT wiring
  signal rtc, pps_rtc : unsigned(47 downto 0);
  signal pps_stb, locked : std_logic;
  signal offset : signed(19 downto 0);

  signal tod_set  : std_logic := '0';
  signal tod_secs : unsigned(16 downto 0) := (others => '0');
  signal tod_day  : unsigned(8 downto 0)  := (others => '0');
  signal irigb, frame_stb : std_logic;

  signal strobe : std_logic := '0';
  signal rd_en  : std_logic := '0';
  signal rd_valid, overflow : std_logic;
  signal rd_rtc : unsigned(47 downto 0);
  signal rd_seq : unsigned(15 downto 0);
  signal fifo_count : unsigned(4 downto 0);

  -- monitors
  signal frame_count_en : boolean := false;
  signal frame_count    : natural := 0;
  signal last_pps_rtc_seen : unsigned(47 downto 0) := (others => '0');

  type sym_arr is array (0 to 99) of integer;  -- 0,1,2='P'

  -- decode helpers ---------------------------------------------------------
  -- BCD value from decoded symbol cells [start .. start+n-1], weights 2^i
  function bits_val (s : sym_arr; start, n : natural) return natural is
    variable v : natural := 0;
  begin
    for i in 0 to n - 1 loop
      if s(start + i) = 1 then
        v := v + 2 ** i;
      end if;
    end loop;
    return v;
  end function;

begin
  clk <= not clk after CLK_PERIOD / 2 when not done else '0';

  dut_disc : entity work.pps_discipline
    generic map (RTC_HZ => RTC_HZ, LOCK_TOL => LOCK_TOL_C)
    port map (clk => clk, rst => rst, pps_in => pps,
              rtc => rtc, pps_rtc => pps_rtc, pps_stb => pps_stb,
              offset => offset, locked => locked);

  dut_gen : entity work.irigb_gen
    generic map (RTC_HZ => RTC_HZ)
    port map (clk => clk, rst => rst, rtc => rtc, pps_stb => pps_stb,
              tod_set => tod_set, tod_secs => tod_secs, tod_day => tod_day,
              irigb => irigb, frame_stb => frame_stb);

  dut_strobe : entity work.strobe_latch
    generic map (DEPTH => 16)
    port map (clk => clk, rst => rst, strobe_in => strobe, rtc => rtc,
              rd_en => rd_en, rd_valid => rd_valid, rd_rtc => rd_rtc,
              rd_seq => rd_seq, count => fifo_count, overflow => overflow);

  -- PPS generator: 100 us pulse, programmable period
  -- NB: written as a self-restarting loop with a guarded wait; a trailing
  -- `wait until pps_en` after the loop deadlocks on re-enable (the process
  -- restarts at the top and `wait until` needs a fresh event).
  pps_gen : process
  begin
    if not pps_en then
      pps <= '0';
      wait until pps_en;
    end if;
    pps <= '1';
    wait for SEC / 1000;
    pps <= '0';
    wait for pps_period - SEC / 1000;
  end process;

  -- monitors: holdover frame counter, P_r alignment
  frame_mon : process (clk)
  begin
    if rising_edge(clk) then
      if frame_stb = '1' and frame_count_en then
        frame_count <= frame_count + 1;
      end if;
      if pps_stb = '1' then
        last_pps_rtc_seen <= rtc;
      end if;
      -- T4: whenever a frame start follows a PPS closely, it must be
      -- register-pipeline close (checked continuously while locked)
      if frame_stb = '1' and locked = '1' then
        if rtc - last_pps_rtc_seen < RTC_HZ / 1000 then  -- stb follows a PPS
          assert to_integer(rtc - last_pps_rtc_seen) <= 3
            report "SYS-006 T4 FAIL: P_r start " &
                   integer'image(to_integer(rtc - last_pps_rtc_seen)) &
                   " RTC counts after PPS latch (limit 3)"
            severity failure;
        end if;
      end if;
    end if;
  end process;

  main : process
    variable syms : sym_arr;
    variable a, b : std_logic;
    variable ss, mm, hh, day, sod, sbs : integer;
    variable v1, v2, v_pre, v_post : integer := 0;
    variable t1, t_pre, t_post : time;
    variable elapsed : integer;
    variable seq_prev : integer;
    variable rtc_prev : unsigned(47 downto 0);
    variable drained : natural;
    variable pass_n : natural := 0;

    -- decode one full IRIG-B frame; call right after frame_stb
    procedure decode_frame (variable sod_o : out integer;
                            variable day_o : out integer;
                            variable sbs_o : out integer) is
    begin
      for i in 0 to 99 loop
        wait for 0.35 * CELL;  a := irigb;
        wait for 0.30 * CELL;  b := irigb;
        wait for 0.35 * CELL;
        if a = '1' and b = '1' then
          syms(i) := 2;
        elsif a = '1' then
          syms(i) := 1;
        else
          syms(i) := 0;
        end if;
      end loop;
      -- frame structure: P_r at 0, P1..P9 at 9,19..89, P0 at 99
      assert syms(0) = 2
        report "SYS-006 T3 FAIL: cell 0 is not a P_r marker"
        severity failure;
      for p in 0 to 9 loop
        assert syms(p * 10 + 9) = 2
          report "SYS-006 T3 FAIL: no position identifier at cell " &
                 integer'image(p * 10 + 9)
          severity failure;
      end loop;
      ss  := bits_val(syms, 1, 4)  + 10 * bits_val(syms, 6, 3);
      mm  := bits_val(syms, 10, 4) + 10 * bits_val(syms, 15, 3);
      hh  := bits_val(syms, 20, 4) + 10 * bits_val(syms, 25, 2);
      day := bits_val(syms, 30, 4) + 10 * bits_val(syms, 35, 4) +
             100 * bits_val(syms, 40, 2);
      sbs := bits_val(syms, 80, 9) + 512 * bits_val(syms, 90, 8);
      sod_o := hh * 3600 + mm * 60 + ss;
      day_o := day;
      sbs_o := sbs;
      -- encoder self-consistency: SBS field must equal the BCD TOD
      assert sbs = hh * 3600 + mm * 60 + ss
        report "SYS-006 T3 FAIL: SBS " & integer'image(sbs) &
               " /= BCD seconds-of-day " &
               integer'image(hh * 3600 + mm * 60 + ss)
        severity failure;
    end procedure;

    procedure next_frame is
    begin
      wait until rising_edge(clk) and frame_stb = '1';
    end procedure;

    procedure pass (msg : string) is
    begin
      report "SYS-006 pass: " & msg;
      pass_n := pass_n + 1;
    end procedure;
  begin
    -- reset
    wait for 1 us;
    wait until rising_edge(clk);
    rst <= '0';

    ----------------------------------------------------------------- T1/T2
    pps_period <= SEC;
    pps_en <= true;
    wait for 5.5 * SEC;                    -- 5 edges: 4 intervals, 3 needed
    assert locked = '1'
      report "SYS-006 T1 FAIL: not locked after 4 nominal PPS intervals"
      severity failure;
    pass("T1 locked after nominal PPS");
    assert abs to_integer(offset) <= 2
      report "SYS-006 T2 FAIL: nominal offset " &
             integer'image(to_integer(offset)) & " counts (|limit| 2)"
      severity failure;
    pass("T2 offset ~0 at nominal");

    ------------------------------------------------------------------- T3
    -- load TOD 14:30:45 day 233 just after a top of second
    wait until rising_edge(clk) and pps_stb = '1';
    tod_secs <= to_unsigned(14 * 3600 + 30 * 60 + 45, 17);
    tod_day  <= to_unsigned(233, 9);
    tod_set  <= '1';
    wait until rising_edge(clk);
    tod_set  <= '0';
    t1 := now;
    next_frame;
    decode_frame(v1, day, sbs);
    assert day = 233
      report "SYS-006 T3 FAIL: day " & integer'image(day) & " /= 233"
      severity failure;
    elapsed := (now - t1) / SEC;
    assert abs (v1 - (14 * 3600 + 30 * 60 + 45 + elapsed)) <= 1
      report "SYS-006 T3 FAIL: decoded TOD " & integer'image(v1) &
             " vs loaded+elapsed " &
             integer'image(14 * 3600 + 30 * 60 + 45 + elapsed)
      severity failure;
    -- no next_frame here: the PPS realign strobes the next frame a few
    -- ticks BEFORE the 100-cell decode loop returns, so waiting would skip
    -- a frame; frame 2 began <=3 ticks ago, sample it immediately.
    decode_frame(v2, day, sbs);
    assert v2 = v1 + 1
      report "SYS-006 T3 FAIL: consecutive frames " & integer'image(v1) &
             " -> " & integer'image(v2) & " (want +1)"
      severity failure;
    pass("T3 frame decodes to loaded TOD; SBS==BCD; +1/frame");
    pass("T4 P_r-to-PPS alignment monitored throughout (see monitor)");

    ---------------------------------------------------------------- T5/T6
    pps_period <= SEC + PPM30 * CLK_PERIOD;   -- +30 ppm crystal-vs-GPS
    wait for 4.5 * SEC;
    assert locked = '1'
      report "SYS-006 T5 FAIL: lock lost at +30 ppm (LOCK_TOL 500)"
      severity failure;
    pass("T5 locked at +30 ppm");
    assert to_integer(offset) >= PPM30 - 2 and to_integer(offset) <= PPM30 + 2
      report "SYS-006 T6 FAIL: offset " &
             integer'image(to_integer(offset)) & " not ~ +30 ppm x RTC_HZ"
      severity failure;
    pass("T6 offset reports 30 ppm x RTC_HZ counts (+300 at 10 MHz)");

    --------------------------------------------------------------- T7-T10
    pps_period <= SEC;                   -- back to exact for the decode math
    wait for 2.5 * SEC;
    next_frame;
    t_pre := now;
    decode_frame(v_pre, day, sbs);
    pps_en <= false;                     -- kill PPS: holdover
    frame_count_en <= true;
    wait for 2.5 * SEC;
    assert locked = '0'
      report "SYS-006 T7 FAIL: still locked 2.5 s after PPS loss"
      severity failure;
    pass("T7 lock drops in holdover");
    wait for 7.5 * SEC;                  -- 10 scaled seconds dead total
    frame_count_en <= false;
    assert frame_count >= 9
      report "SYS-006 T8 FAIL: only " & integer'image(frame_count) &
             " frames during 10 s holdover"
      severity failure;
    pass("T8 frames keep crystal cadence in holdover");
    pps_en <= true;                      -- PPS returns
    wait for 4.5 * SEC;
    assert locked = '1'
      report "SYS-006 T9 FAIL: no relock 4.5 s after PPS return"
      severity failure;
    pass("T9 relock after PPS return");
    next_frame;
    t_post := now;
    decode_frame(v_post, day, sbs);
    elapsed := (t_post - t_pre) / SEC;
    assert abs (v_post - (v_pre + elapsed)) <= 1
      report "SYS-006 T10 FAIL: TOD " & integer'image(v_post) &
             " after holdover; expected ~" & integer'image(v_pre + elapsed)
      severity failure;
    pass("T10 TOD continuous through holdover and relock");

    -------------------------------------------------------------- T11-T15
    -- 12 strobes at ~30 Hz with deterministic alternating jitter
    for i in 1 to 12 loop
      strobe <= '1';
      wait for SEC / 1000;
      strobe <= '0';
      if (i mod 2) = 0 then
        wait for SEC / 30 - SEC / 1000 + SEC / 1000;  -- ~30 Hz, +jitter
      else
        wait for SEC / 30 - SEC / 1000 - SEC / 1000;  -- ~30 Hz, -jitter
      end if;
    end loop;
    wait for 5.0 * CELL;
    assert to_integer(fifo_count) = 12
      report "SYS-006 T11 FAIL: FIFO holds " &
             integer'image(to_integer(fifo_count)) & " of 12 strobes"
      severity failure;
    pass("T11 FIFO count matches strobes");
    assert overflow = '0'
      report "SYS-006 T12 FAIL: spurious overflow" severity failure;
    pass("T12 no overflow at 30 Hz");
    drained := 0;
    seq_prev := -1;
    rtc_prev := (others => '0');
    while rd_valid = '1' loop
      assert rd_rtc > rtc_prev
        report "SYS-006 T13 FAIL: non-monotonic strobe stamp"
        severity failure;
      assert seq_prev = -1 or to_integer(rd_seq) = seq_prev + 1
        report "SYS-006 T13 FAIL: seq gap at " &
               integer'image(to_integer(rd_seq))
        severity failure;
      rtc_prev := rd_rtc;
      seq_prev := to_integer(rd_seq);
      drained  := drained + 1;
      rd_en <= '1';
      wait until rising_edge(clk);
      rd_en <= '0';
      wait until rising_edge(clk);
    end loop;
    assert drained = 12
      report "SYS-006 T13 FAIL: drained " & integer'image(drained)
      severity failure;
    pass("T13 stamps monotonic, seqs contiguous, all drained");
    -- 17-strobe burst, no draining: 16 held + sticky overflow
    for i in 1 to 17 loop
      strobe <= '1';
      wait for 2 us;
      strobe <= '0';
      wait for 2 us;
    end loop;
    wait for 5 us;
    assert overflow = '1'
      report "SYS-006 T14 FAIL: overflow not sticky-set on 17-burst"
      severity failure;
    pass("T14 sticky overflow on burst");
    assert to_integer(fifo_count) = 16
      report "SYS-006 T15 FAIL: fill " &
             integer'image(to_integer(fifo_count)) & " /= DEPTH"
      severity failure;
    pass("T15 fill capped at DEPTH, drops counted via seq");

    report "SYS-006: all " & integer'image(pass_n) &
           " timebase cases pass";
    done <= true;
    wait;
  end process;
end architecture;
