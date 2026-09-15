-- pps_discipline: free-running 48-bit RTC + PPS interval measurement.
--
-- MAIDEN takes lesson 18's option 2: the RTC is NEVER steered. This block
-- measures and reports (offset counts vs nominal, lock state); the RTC->UTC
-- truth lives in the Ch 1 time packets that pair pps_rtc with the absolute
-- second (decoded by maiden.timebase on ingest). Drift is a slope there,
-- not an error here.
--
-- Clocking on hardware: 12 MHz osc -> PLL x5 = 60 MHz -> /6 = 10 MHz; this
-- clk IS the RTC domain (1 clk = 1 RTC count). Simulation drives clk at
-- RTC_HZ directly.
--
-- Requirements: SYS-006 (station timebase); feeds IF-1 Ch 1/Ch 6 and VT-02.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pps_discipline is
  generic (
    RTC_HZ   : positive := 10_000_000;  -- RTC counts per second
    LOCK_TOL : positive := 500          -- +/- counts (= 50 ppm) to call lock
  );
  port (
    clk     : in  std_logic;            -- 10 MHz RTC domain
    rst     : in  std_logic;            -- synchronous, active high
    pps_in  : in  std_logic;            -- async from u-blox
    rtc     : out unsigned(47 downto 0);  -- free-running, Ch. 10 width
    pps_rtc : out unsigned(47 downto 0);  -- RTC latched at last PPS edge
    pps_stb : out std_logic;            -- 1-clk pulse per accepted PPS edge
    offset  : out signed(19 downto 0);  -- last interval minus RTC_HZ, clamped
    locked  : out std_logic             -- last 3 intervals within +/-LOCK_TOL
  );
end entity;

architecture rtl of pps_discipline is
  -- watchdog: no PPS edge for > 1.5 s drops lock (holdover)
  constant WDOG_LIMIT : natural := RTC_HZ + RTC_HZ / 2;
  -- deviations beyond this are "wild" (e.g. first edge after holdover):
  -- classified bad and clamped so `offset` stays honest at its width
  constant OFF_MAX : integer := 2**19 - 1;

  signal rtc_q      : unsigned(47 downto 0) := (others => '0');
  signal pps_rtc_q  : unsigned(47 downto 0) := (others => '0');
  signal offset_q   : signed(19 downto 0)   := (others => '0');
  signal locked_q   : std_logic := '0';
  signal stb_q      : std_logic := '0';

  -- 2-FF synchronizer + edge detect (every async input, house rule)
  signal pps_s0, pps_s1, pps_s2 : std_logic := '0';

  signal have_prev  : std_logic := '0';
  signal good_cnt   : unsigned(1 downto 0) := (others => '0');
  signal wdog       : unsigned(31 downto 0) := (others => '0');
begin
  rtc     <= rtc_q;
  pps_rtc <= pps_rtc_q;
  pps_stb <= stb_q;
  offset  <= offset_q;
  locked  <= locked_q;

  process (clk)
    variable interval : signed(48 downto 0);
    variable dev      : signed(48 downto 0);
    variable good     : boolean;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        rtc_q     <= (others => '0');
        pps_rtc_q <= (others => '0');
        offset_q  <= (others => '0');
        locked_q  <= '0';
        stb_q     <= '0';
        pps_s0    <= '0';
        pps_s1    <= '0';
        pps_s2    <= '0';
        have_prev <= '0';
        good_cnt  <= (others => '0');
        wdog      <= (others => '0');
      else
        -- the RTC is sacred: it increments, nothing else touches it
        rtc_q  <= rtc_q + 1;
        stb_q  <= '0';

        pps_s0 <= pps_in;
        pps_s1 <= pps_s0;
        pps_s2 <= pps_s1;

        if wdog < to_unsigned(WDOG_LIMIT, wdog'length) then
          wdog <= wdog + 1;
        else
          -- holdover: PPS gone; drop lock, RTC and outputs carry on
          locked_q <= '0';
          good_cnt <= (others => '0');
        end if;

        if pps_s1 = '1' and pps_s2 = '0' then  -- rising edge, synchronized
          stb_q     <= '1';
          pps_rtc_q <= rtc_q;
          wdog      <= (others => '0');
          if have_prev = '1' then
            interval := signed(resize(rtc_q, 49)) -
                        signed(resize(pps_rtc_q, 49));
            dev      := interval - to_signed(RTC_HZ, 49);
            good     := abs dev <= to_signed(LOCK_TOL, 49);
            if dev > to_signed(OFF_MAX, 49) then
              offset_q <= to_signed(OFF_MAX, 20);
            elsif dev < to_signed(-OFF_MAX, 49) then
              offset_q <= to_signed(-OFF_MAX, 20);
            else
              offset_q <= resize(dev, 20);
            end if;
            if good then
              if good_cnt = "11" then
                locked_q <= '1';
              else
                good_cnt <= good_cnt + 1;
                if good_cnt = "10" then
                  locked_q <= '1';   -- third consecutive good interval
                end if;
              end if;
            else
              good_cnt <= (others => '0');
              locked_q <= '0';
            end if;
          end if;
          have_prev <= '1';
        end if;
      end if;
    end if;
  end process;
end architecture;
