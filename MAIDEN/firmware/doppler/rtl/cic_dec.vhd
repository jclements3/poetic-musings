-- cic_dec: N-stage integrator-comb decimator for the Doppler I/Q chain.
--
-- Fixed-point formats (written down, per the theremin-roadmap habit):
--   input  : signed W_IN = 16 bits, 48 kS/s I/Q
--   growth : N * ceil(log2(R*M)) bits, M = 1
--            R = 4 -> 6 bits -> 22-bit internal registers
--            R = 8 -> 9 bits -> 25-bit internal registers
--   output : internal arithmetic-shifted right by the growth (unity DC
--            gain, truncating), resized to 16 bits. Truncation, not
--            rounding -- the golden model mirrors this exactly.
-- Passband droop at 512-pt Doppler resolution is negligible (signal sits
-- far below decimated Nyquist; CFAR is insensitive to sub-dB tilt) -- no
-- compensation FIR. See results/design-notes/decimation-audit.md for why
-- R is a generic (D6 rev): R = 4 at 24.125 GHz, 8 at 10.525 GHz.
--
-- Requirements: GS-002 (50 Hz v_r chain front end).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity cic_dec is
  generic (
    N    : positive := 3;
    R    : positive := 4;
    W_IN : positive := 16
  );
  port (
    clk, rst     : in  std_logic;
    in_i, in_q   : in  signed(W_IN-1 downto 0);
    in_stb       : in  std_logic;
    out_i, out_q : out signed(W_IN-1 downto 0);
    out_stb      : out std_logic
  );
end entity;

architecture rtl of cic_dec is
  constant G : natural := N * integer(ceil(log2(real(R))));
  constant W : natural := W_IN + G;
  type stage_t is array (0 to N-1) of signed(W-1 downto 0);
  signal acc_i, acc_q   : stage_t := (others => (others => '0'));
  signal prev_i, prev_q : stage_t := (others => (others => '0'));
  signal phase          : natural range 0 to R-1 := 0;
begin

  main : process (clk)
    variable si, sq : signed(W-1 downto 0);
    variable di, dq : signed(W-1 downto 0);
  begin
    if rising_edge(clk) then
      out_stb <= '0';
      if rst = '1' then
        acc_i  <= (others => (others => '0'));
        acc_q  <= (others => (others => '0'));
        prev_i <= (others => (others => '0'));
        prev_q <= (others => (others => '0'));
        phase  <= 0;
      elsif in_stb = '1' then
        -- integrators at the fast rate (wraparound is the CIC contract)
        si := resize(in_i, W);
        sq := resize(in_q, W);
        for k in 0 to N-1 loop
          si := acc_i(k) + si;
          sq := acc_q(k) + sq;
          acc_i(k) <= si;
          acc_q(k) <= sq;
        end loop;
        if phase = R-1 then
          phase <= 0;
          -- combs at the slow rate
          di := si;
          dq := sq;
          for k in 0 to N-1 loop
            si := di - prev_i(k);
            sq := dq - prev_q(k);
            prev_i(k) <= di;
            prev_q(k) <= dq;
            di := si;
            dq := sq;
          end loop;
          out_i   <= resize(shift_right(di, G), W_IN);
          out_q   <= resize(shift_right(dq, G), W_IN);
          out_stb <= '1';
        else
          phase <= phase + 1;
        end if;
      end if;
    end if;
  end process;

end architecture;
