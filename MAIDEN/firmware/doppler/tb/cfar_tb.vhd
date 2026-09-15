-- cfar_tb: golden-model comparison for CA-CFAR (maiden35).
--
-- Eight spectra from golden/model.py (fixed seed): exponential noise,
-- a strong peak injected at a random bin in every second spectrum.
-- Expected (peak_bin, peak_mag, noise_est, valid) per spectrum come from
-- the bit-true golden CFAR; comparison is exact.
--
-- Asserts are requirement-tagged: GS-002.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity cfar_tb is
end entity;

architecture sim of cfar_tb is
  constant CLK_PERIOD : time := 83.333 ns;

  signal clk        : std_logic := '0';
  signal rst        : std_logic := '1';
  signal mag        : unsigned(17 downto 0) := (others => '0');
  signal mag_bin    : unsigned(8 downto 0) := (others => '0');
  signal mag_stb    : std_logic := '0';
  signal frame_done : std_logic := '0';
  signal peak_bin   : unsigned(8 downto 0);
  signal peak_mag   : unsigned(17 downto 0);
  signal noise_est  : unsigned(17 downto 0);
  signal det_valid  : std_logic;
  signal out_stb    : std_logic;
  signal halt       : boolean := false;
begin

  dut : entity work.cfar
    generic map (TRAIN => 8, GUARD => 2, ALPHA_Q8 => 2212)
    port map (clk => clk, rst => rst,
              mag => mag, mag_bin => mag_bin, mag_stb => mag_stb,
              frame_done => frame_done,
              peak_bin => peak_bin, peak_mag => peak_mag,
              noise_est => noise_est, det_valid => det_valid,
              out_stb => out_stb);

  clk <= not clk after CLK_PERIOD / 2 when not halt else '0';

  main : process
    file fexp : text open read_mode is "build/vectors/cfar_exp.txt";
    file fs   : text;
    variable l : line;
    variable v : integer;
    variable e_bin, e_mag, e_ne, e_valid : integer;
  begin
    wait for 5 * CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';
    for trial in 0 to 7 loop
      file_open(fs, "build/vectors/cfar_spec_" &
                integer'image(trial) & ".txt", read_mode);
      for k in 0 to 511 loop
        readline(fs, l);
        read(l, v);
        mag     <= to_unsigned(v, 18);
        mag_bin <= to_unsigned(k, 9);
        mag_stb <= '1';
        wait until rising_edge(clk);
      end loop;
      mag_stb    <= '0';
      frame_done <= '1';
      wait until rising_edge(clk);
      frame_done <= '0';
      file_close(fs);
      loop
        wait until rising_edge(clk);
        exit when out_stb = '1';
      end loop;
      readline(fexp, l);
      read(l, e_bin);
      read(l, e_mag);
      read(l, e_ne);
      read(l, e_valid);
      if e_valid = 1 then
        assert det_valid = '1' and
               to_integer(peak_bin) = e_bin and
               to_integer(peak_mag) = e_mag and
               to_integer(noise_est) = e_ne
          report "GS-002 FAIL: spectrum " & integer'image(trial) &
                 ": got bin " & integer'image(to_integer(peak_bin)) &
                 " mag " & integer'image(to_integer(peak_mag)) &
                 " ne " & integer'image(to_integer(noise_est)) &
                 " valid " & std_logic'image(det_valid) &
                 "; want " & integer'image(e_bin) & "/" &
                 integer'image(e_mag) & "/" & integer'image(e_ne) & "/1"
          severity failure;
      else
        assert det_valid = '0'
          report "GS-002 FAIL: spectrum " & integer'image(trial) &
                 ": false alarm at bin " &
                 integer'image(to_integer(peak_bin))
          severity failure;
      end if;
    end loop;
    report "GS-002 pass: cfar matches golden model on 8 spectra " &
           "(detections and rejections, exact)";
    halt <= true;
    wait;
  end process;

end architecture;
