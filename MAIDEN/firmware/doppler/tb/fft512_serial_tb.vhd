-- fft512_serial_tb: golden-model comparison for the serial FFT (maiden35).
--
-- Two frames from golden/model.py (fixed seed):
--   1. impulse  -> flat magnitude spectrum (the analytic sanity case)
--   2. tone     -> energy concentrated at bin +37
-- Each frame: stream 512 samples in, pulse start, compare all 512 streamed
-- magnitudes against the bit-true golden files. Tolerance +/-2 LSB, expected
-- to close at 0 (the model mirrors the RTL arithmetic exactly).
--
-- Asserts are requirement-tagged: GS-002.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity fft512_serial_tb is
end entity;

architecture sim of fft512_serial_tb is
  constant CLK_PERIOD : time := 83.333 ns;
  constant TOL        : integer := 2;

  signal clk        : std_logic := '0';
  signal rst        : std_logic := '1';
  signal sample_i   : signed(15 downto 0) := (others => '0');
  signal sample_q   : signed(15 downto 0) := (others => '0');
  signal sample_stb : std_logic := '0';
  signal start      : std_logic := '0';
  signal mag        : unsigned(17 downto 0);
  signal mag_bin    : unsigned(8 downto 0);
  signal mag_stb    : std_logic;
  signal fft_done   : std_logic;
  signal halt       : boolean := false;
begin

  dut : entity work.fft512_serial
    port map (clk => clk, rst => rst,
              sample_i => sample_i, sample_q => sample_q,
              sample_stb => sample_stb, start => start,
              mag => mag, mag_bin => mag_bin, mag_stb => mag_stb,
              done => fft_done);

  clk <= not clk after CLK_PERIOD / 2 when not halt else '0';

  main : process
    file fin  : text;
    file fexp : text;
    variable l      : line;
    variable vi, vq : integer;
    variable ex     : integer;
    variable d      : integer;
    variable worst  : integer;
    variable peak_b : integer;
    variable peak_m : integer;

    procedure run_frame(inpath, expath, name : string) is
    begin
      file_open(fin, inpath, read_mode);
      file_open(fexp, expath, read_mode);
      -- stream the frame into the circular buffer
      while not endfile(fin) loop
        readline(fin, l);
        read(l, vi);
        read(l, vq);
        sample_i   <= to_signed(vi, 16);
        sample_q   <= to_signed(vq, 16);
        sample_stb <= '1';
        wait until rising_edge(clk);
        sample_stb <= '0';
        wait until rising_edge(clk);
      end loop;
      file_close(fin);
      start <= '1';
      wait until rising_edge(clk);
      start <= '0';
      worst  := 0;
      peak_b := 0;
      peak_m := 0;
      for k in 0 to 511 loop
        loop
          wait until rising_edge(clk);
          exit when mag_stb = '1';
        end loop;
        assert to_integer(mag_bin) = k
          report "GS-002 FAIL: " & name & " bin order: got " &
                 integer'image(to_integer(mag_bin)) & " want " &
                 integer'image(k)
          severity failure;
        readline(fexp, l);
        read(l, ex);
        d := abs(to_integer(mag) - ex);
        if d > worst then
          worst := d;
        end if;
        if to_integer(mag) > peak_m then
          peak_m := to_integer(mag);
          peak_b := k;
        end if;
        assert d <= TOL
          report "GS-002 FAIL: " & name & " bin " & integer'image(k) &
                 " mag " & integer'image(to_integer(mag)) & " want " &
                 integer'image(ex) & " (delta " & integer'image(d) & ")"
          severity failure;
      end loop;
      file_close(fexp);
      report "GS-002 pass: fft512_serial " & name &
             " matches golden model, 512 bins, worst delta " &
             integer'image(worst) & " LSB, peak bin " &
             integer'image(peak_b);
    end procedure;
  begin
    wait for 5 * CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';
    run_frame("build/vectors/fft_impulse_in.txt",
              "build/vectors/fft_impulse_mag.txt", "impulse");
    run_frame("build/vectors/fft_tone_in.txt",
              "build/vectors/fft_tone_mag.txt", "tone(bin37)");
    halt <= true;
    wait;
  end process;

end architecture;
