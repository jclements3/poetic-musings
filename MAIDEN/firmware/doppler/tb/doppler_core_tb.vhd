-- doppler_core_tb: integration TB (maiden35). Golden I/Q ramp file in,
-- UART records decoded out, reported v_r tracks the commanded velocity.
--
-- Stimulus: build/vectors/top_stim.txt -- 1.0 s of 24.125 GHz I/Q for a
-- 12 -> 18 m/s ramp (fixed seed), injected at 48 kS/s (one pair per 250
-- clocks at 12 MHz). Expected: build/vectors/top_cmd_cm.txt -- commanded
-- velocity per 20 ms epoch, evaluated at the FFT window centre.
-- Check: record r corresponds to epoch r (first start tick at 20 ms);
-- once the 512-sample window is full (r >= 3), every record must be a
-- valid detection within TOL_CM of command. Tolerance covers bin
-- quantization (14.6 cm/s), noise, and residual window-centre error.
--
-- Asserts are requirement-tagged: GS-002.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity doppler_core_tb is
end entity;

architecture sim of doppler_core_tb is
  constant CLK_PERIOD : time := 83.333 ns;
  constant BIT_CLKS   : natural := 104;        -- uart_tx DIV at 12M/115200
  constant TOL_CM     : integer := 100;
  constant WARMUP     : integer := 3;          -- records before window full

  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal adc_i   : signed(15 downto 0) := (others => '0');
  signal adc_q   : signed(15 downto 0) := (others => '0');
  signal adc_stb : std_logic := '0';
  signal txd     : std_logic;
  signal raw_i   : signed(15 downto 0);
  signal raw_q   : signed(15 downto 0);
  signal raw_stb : std_logic;
  signal halt    : boolean := false;
begin

  dut : entity work.doppler_core
    port map (clk => clk, rst => rst,
              adc_i => adc_i, adc_q => adc_q, adc_stb => adc_stb,
              txd => txd, raw_i => raw_i, raw_q => raw_q,
              raw_stb => raw_stb);

  clk <= not clk after CLK_PERIOD / 2 when not halt else '0';

  stim : process
    file f : text open read_mode is "build/vectors/top_stim.txt";
    variable l      : line;
    variable vi, vq : integer;
  begin
    wait for 5 * CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';
    while not endfile(f) loop
      readline(f, l);
      read(l, vi);
      read(l, vq);
      adc_i   <= to_signed(vi, 16);
      adc_q   <= to_signed(vq, 16);
      adc_stb <= '1';
      wait until rising_edge(clk);
      adc_stb <= '0';
      for w in 1 to 249 loop
        wait until rising_edge(clk);
      end loop;
    end loop;
    wait for 30 ms;   -- drain the last epoch's record
    halt <= true;
    wait;
  end process;

  rx : process
    file fexp : text open read_mode is "build/vectors/top_cmd_cm.txt";
    variable l       : line;
    variable cmd     : integer;
    variable byte_v  : unsigned(7 downto 0);
    variable fr      : integer;
    type ibuf_t is array (0 to 12) of integer;
    variable buf     : ibuf_t;
    variable nbyte   : integer := 0;
    variable nrec    : integer := 0;
    variable nchk    : integer := 0;
    variable sum     : integer;
    variable v_cm    : integer;
    variable worst   : integer := 0;
    variable d       : integer;
  begin
    while not halt loop
      -- 8N1 receive: start edge, sample mid-bit
      wait until txd = '0' or halt;
      exit when halt;
      wait for CLK_PERIOD * BIT_CLKS * 1.5;
      byte_v := (others => '0');
      for b in 0 to 7 loop
        byte_v(b) := txd;
        wait for CLK_PERIOD * BIT_CLKS;
      end loop;
      fr := to_integer(byte_v);
      -- frame assembly with resync-on-A5
      if nbyte = 0 and fr /= 16#A5# then
        next;
      end if;
      buf(nbyte) := fr;
      nbyte := nbyte + 1;
      if nbyte = 13 then
        nbyte := 0;
        sum := 0;
        for b in 0 to 12 loop
          sum := sum + buf(b);
        end loop;
        assert (sum mod 256) = 0
          report "GS-002 FAIL: record " & integer'image(nrec) &
                 " checksum (sum mod 256 = " &
                 integer'image(sum mod 256) & ")"
          severity failure;
        assert buf(1) = 1
          report "GS-002 FAIL: unexpected record type " &
                 integer'image(buf(1))
          severity failure;
        v_cm := buf(4) + 256 * buf(5);
        if v_cm >= 32768 then
          v_cm := v_cm - 65536;
        end if;
        if nrec >= WARMUP and not endfile(fexp) then
          -- consume command lines so cmd = line index nrec
          while nchk <= nrec and not endfile(fexp) loop
            readline(fexp, l);
            read(l, cmd);
            nchk := nchk + 1;
          end loop;
          assert buf(3) = 1
            report "GS-002 FAIL: record " & integer'image(nrec) &
                   " no detection (cmd " & integer'image(cmd) & " cm/s)"
            severity failure;
          d := abs(v_cm - cmd);
          if d > worst then
            worst := d;
          end if;
          assert d <= TOL_CM
            report "GS-002 FAIL: record " & integer'image(nrec) &
                   " v_cm " & integer'image(v_cm) & " vs cmd " &
                   integer'image(cmd) & " (delta " & integer'image(d) &
                   " cm/s)"
            severity failure;
        end if;
        nrec := nrec + 1;
      end if;
    end loop;
    assert nrec - WARMUP >= 15
      report "GS-002 FAIL: only " & integer'image(nrec) &
             " records received"
      severity failure;
    report "GS-002 pass: doppler_core tracked the 12->18 m/s ramp: " &
           integer'image(nrec) & " records, " &
           integer'image(nrec - WARMUP) & " checked, worst |v-cmd| " &
           integer'image(worst) & " cm/s (tol " & integer'image(TOL_CM) &
           ")";
    wait;
  end process;

end architecture;
