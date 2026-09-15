-- strobe_latch: camera-strobe timestamp capture.
--
-- Async strobe -> 2-FF synchronizer -> rising-edge detect -> push
-- (rtc, seq) into a DEPTH-deep FIFO drained by the recorder link.
-- Worst-case synchronizer latency is 2 clks (200 ns at 10 MHz), five
-- orders below the SYS-006 5 ms budget.
--
-- Overflow is LOUD: a push against a full FIFO drops the stamp, but sets
-- a sticky `overflow` flag surfaced on the recorder's Ch 6 status channel.
-- seq still increments on every strobe, so the drop is countable offline.
--
-- Requirements: SYS-006 (frame stamping half); IF-1 Ch 2/Ch 5 metadata.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity strobe_latch is
  generic (
    DEPTH : positive := 16              -- power of two
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;          -- synchronous, active high
    strobe_in : in  std_logic;          -- async from camera
    rtc       : in  unsigned(47 downto 0);
    rd_en     : in  std_logic;          -- pop one entry when valid
    rd_valid  : out std_logic;          -- FIFO non-empty
    rd_rtc    : out unsigned(47 downto 0);
    rd_seq    : out unsigned(15 downto 0);
    count     : out unsigned(4 downto 0);   -- entries held (0..DEPTH)
    overflow  : out std_logic           -- sticky; clears only on rst
  );
end entity;

architecture rtl of strobe_latch is
  type rtc_mem_t is array (0 to DEPTH - 1) of unsigned(47 downto 0);
  type seq_mem_t is array (0 to DEPTH - 1) of unsigned(15 downto 0);
  signal rtc_mem : rtc_mem_t := (others => (others => '0'));
  signal seq_mem : seq_mem_t := (others => (others => '0'));

  signal s0, s1, s2 : std_logic := '0';
  signal wr_ptr, rd_ptr : natural range 0 to DEPTH - 1 := 0;
  signal fill  : natural range 0 to DEPTH := 0;
  signal seq_q : unsigned(15 downto 0) := (others => '0');
  signal ovf_q : std_logic := '0';
begin
  rd_valid <= '1' when fill > 0 else '0';
  rd_rtc   <= rtc_mem(rd_ptr);
  rd_seq   <= seq_mem(rd_ptr);
  count    <= to_unsigned(fill, 5);
  overflow <= ovf_q;

  process (clk)
    variable push, pop : boolean;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        s0 <= '0'; s1 <= '0'; s2 <= '0';
        wr_ptr <= 0; rd_ptr <= 0; fill <= 0;
        seq_q <= (others => '0');
        ovf_q <= '0';
      else
        s0 <= strobe_in;
        s1 <= s0;
        s2 <= s1;

        push := (s1 = '1' and s2 = '0');
        pop  := (rd_en = '1' and fill > 0);

        if push then
          seq_q <= seq_q + 1;             -- counts every strobe, drops too
          if fill < DEPTH or pop then
            rtc_mem(wr_ptr) <= rtc;
            seq_mem(wr_ptr) <= seq_q;
            wr_ptr <= (wr_ptr + 1) mod DEPTH;
          else
            ovf_q <= '1';                 -- loud, sticky
          end if;
        end if;

        if pop then
          rd_ptr <= (rd_ptr + 1) mod DEPTH;
        end if;

        if push and pop then
          null;                            -- fill unchanged
        elsif push and fill < DEPTH then
          fill <= fill + 1;
        elsif pop and not push then
          fill <= fill - 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
