-- irigb_gen: IRIG-B DCLS frame generator, bit-for-bit.
--
-- 100 cells/second, 10 ms each (= RTC_HZ/100 counts, exact at 10 MHz).
-- Symbols by high-time within the cell: '0' = 2 ms, '1' = 5 ms, P = 8 ms.
-- On-time point is the leading edge of P_r, aligned to the PPS-derived top
-- of second when PPS is present; in holdover the frame free-runs at the
-- crystal cadence and TOD keeps counting.
--
-- Frame layout implemented (RCC IRIG-B, unused control cells emit '0'):
--   0        P_r
--   1-8      seconds  BCD units 1,2,4,8 | cell5 = 0 | tens 10,20,40
--   9        P1
--   10-17    minutes  BCD units | cell14 = 0 | tens          18 = 0
--   19       P2
--   20-28    hours    BCD units | cell24 = 0 | tens 10,20    27,28 = 0
--   29       P3
--   30-41    day-of-year BCD units | 34 = 0 | tens | [39 = P4] | hundreds
--   49,59,69,79  P5..P8 (cells 42-48, 50-58, 60-78 emit '0': legal)
--   80-88    SBS bits 0-8 (straight binary seconds-of-day, LSB first)
--   89       P9
--   90-97    SBS bits 9-16
--   98       0
--   99       P0   (P0 then next frame's P_r = the double-8 ms frame mark)
--
-- NOTE (lesson 18 erratum, found while implementing): the lesson sketches
-- SBS as contiguous cells 80-97 with P9 at 99, which contradicts its own
-- "position identifiers land on every 10th cell". The real standard puts
-- P9 at cell 89 and splits SBS 80-88 / 90-97 with P0 at 99; that is what
-- is built here and what the TB decoder checks.
--
-- tod_set loads seconds-of-day + day from the SBC (NMEA gives the second
-- LABEL, PPS gives the EDGE). The /3600 and /60 splits below are fine in
-- simulation and constant-divisor synthesizable, but a hardware revision
-- would load h/m/s directly - noted for maiden39.
--
-- Requirements: SYS-006. Sim-only verification this sprint (maiden38).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity irigb_gen is
  generic (
    RTC_HZ : positive := 10_000_000
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;                 -- synchronous, active high
    rtc       : in  unsigned(47 downto 0);
    pps_stb   : in  std_logic;
    tod_set   : in  std_logic;                 -- load TOD (from NMEA via SBC)
    tod_secs  : in  unsigned(16 downto 0);     -- seconds-of-day 0..86399
    tod_day   : in  unsigned(8 downto 0);      -- day-of-year 1..366
    irigb     : out std_logic;
    frame_stb : out std_logic                  -- 1 clk at each P_r edge
  );
end entity;

architecture rtl of irigb_gen is
  constant CELL_CNT : natural := RTC_HZ / 100;         -- counts per 10 ms cell
  constant HI_0     : natural := (2 * CELL_CNT) / 10;  -- 2 ms
  constant HI_1     : natural := (5 * CELL_CNT) / 10;  -- 5 ms
  constant HI_P     : natural := (8 * CELL_CNT) / 10;  -- 8 ms

  type sym_t is (S0, S1, SP);
  type frame_t is array (0 to 99) of sym_t;

  -- Build the 100-symbol frame from the TOD counters.
  function build_frame (ss, mm, hh : natural;
                        day        : natural;
                        sbs        : unsigned(16 downto 0)) return frame_t is
    variable f : frame_t := (others => S0);
    procedure bcd (start : natural; digit : natural; nbits : natural) is
    begin
      for b in 0 to nbits - 1 loop
        if ((digit / (2 ** b)) mod 2) = 1 then
          f(start + b) := S1;
        end if;
      end loop;
    end procedure;
  begin
    for p in 0 to 9 loop                       -- P1..P9 at 9,19..89; P0 at 99
      f(p * 10 + 9) := SP;
    end loop;
    f(0) := SP;                                -- P_r
    bcd(1,  ss mod 10, 4);  bcd(6,  ss / 10, 3);
    bcd(10, mm mod 10, 4);  bcd(15, mm / 10, 3);
    bcd(20, hh mod 10, 4);  bcd(25, hh / 10, 2);
    bcd(30, day mod 10, 4); bcd(35, (day / 10) mod 10, 4);
    bcd(40, day / 100, 2);
    for b in 0 to 8 loop                       -- SBS 0-8 at 80-88
      if sbs(b) = '1' then f(80 + b) := S1; end if;
    end loop;
    for b in 9 to 16 loop                      -- SBS 9-16 at 90-97
      if sbs(b) = '1' then f(90 + (b - 9)) := S1; end if;
    end loop;
    return f;
  end function;

  -- TOD counters (h/m/s + parallel seconds-of-day for SBS + day)
  signal ss_q  : natural range 0 to 59 := 0;
  signal mm_q  : natural range 0 to 59 := 0;
  signal hh_q  : natural range 0 to 23 := 0;
  signal day_q : natural range 0 to 366 := 1;
  signal sbs_q : unsigned(16 downto 0) := (others => '0');

  signal frame_q    : frame_t := (others => S0);
  signal cell_idx   : natural range 0 to 99 := 0;
  signal cell_tick  : natural range 0 to CELL_CNT - 1 := 0;
  signal irigb_q    : std_logic := '0';
  signal fstb_q     : std_logic := '0';
begin
  irigb     <= irigb_q;
  frame_stb <= fstb_q;

  process (clk)
    -- top of second: advance TOD, rebuild frame, restart cell sequencer
    procedure top_of_second is
      variable ss_v  : natural range 0 to 60;
      variable mm_v  : natural range 0 to 60;
      variable hh_v  : natural range 0 to 24;
      variable day_v : natural range 0 to 367;
      variable sbs_v : unsigned(16 downto 0);
    begin
      ss_v := ss_q + 1;  mm_v := mm_q;  hh_v := hh_q;  day_v := day_q;
      sbs_v := sbs_q + 1;
      if ss_v = 60 then
        ss_v := 0;  mm_v := mm_q + 1;
        if mm_v = 60 then
          mm_v := 0;  hh_v := hh_q + 1;
          if hh_v = 24 then
            hh_v := 0;  day_v := day_q + 1;  sbs_v := (others => '0');
          end if;
        end if;
      end if;
      ss_q <= ss_v;  mm_q <= mm_v;  hh_q <= hh_v;  day_q <= day_v;
      sbs_q <= sbs_v;
      frame_q   <= build_frame(ss_v, mm_v, hh_v, day_v, sbs_v);
      cell_idx  <= 0;
      cell_tick <= 0;
      fstb_q    <= '1';
    end procedure;

    variable hi : natural;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        ss_q <= 0; mm_q <= 0; hh_q <= 0; day_q <= 1;
        sbs_q <= (others => '0');
        frame_q <= (others => S0);
        cell_idx <= 0; cell_tick <= 0;
        irigb_q <= '0'; fstb_q <= '0';
      else
        fstb_q <= '0';

        if tod_set = '1' then
          -- constant-divisor splits; see header note
          ss_q  <= to_integer(tod_secs) mod 60;
          mm_q  <= (to_integer(tod_secs) / 60) mod 60;
          hh_q  <= to_integer(tod_secs) / 3600;
          sbs_q <= tod_secs;
          day_q <= to_integer(tod_day);
          frame_q <= build_frame(to_integer(tod_secs) mod 60,
                                 (to_integer(tod_secs) / 60) mod 60,
                                 to_integer(tod_secs) / 3600,
                                 to_integer(tod_day), tod_secs);
          cell_idx  <= 0;
          cell_tick <= 0;
          fstb_q    <= '1';
        elsif pps_stb = '1' then
          -- PPS realign. If the crystal ran fast, the natural wrap already
          -- incremented TOD just before this edge (cell_idx small): restart
          -- the sequencer without a second increment. Late in the frame
          -- (crystal slow): this edge IS the top of second.
          if cell_idx < 50 then
            cell_idx  <= 0;
            cell_tick <= 0;
            fstb_q    <= '1';
          else
            top_of_second;
          end if;
        elsif cell_tick = CELL_CNT - 1 then
          cell_tick <= 0;
          if cell_idx = 99 then
            top_of_second;      -- holdover cadence: crystal-derived
          else
            cell_idx <= cell_idx + 1;
          end if;
        else
          cell_tick <= cell_tick + 1;
        end if;

        -- pulse-width shaper off the RTC-domain tick
        case frame_q(cell_idx) is
          when S0 => hi := HI_0;
          when S1 => hi := HI_1;
          when SP => hi := HI_P;
        end case;
        if cell_tick < hi then
          irigb_q <= '1';
        else
          irigb_q <= '0';
        end if;
      end if;
    end if;
  end process;
end architecture;
