-- cfar: cell-averaging CFAR over one 512-bin magnitude spectrum.
--
-- Threshold theory (three lines from the exponential CDF): for noise
-- power exponentially distributed, a cell exceeds alpha times the mean of
-- N_t training cells with probability
--     P_fa = (1 + alpha/N_t)^(-N_t)
-- (each training sum is Erlang; integrating the exceedance gives the
-- compound-interest form, -> exp(-alpha) as N_t -> inf). Solved for alpha:
-- alpha = N_t * (P_fa^(-1/N_t) - 1). Tabulated at N_t = 16:
--
--     P_fa      alpha     ALPHA_Q8
--     1e-3      8.642       2212
--     1e-4     12.451       3187
--
-- Integer compare (no division): detect iff
--     mag[k] * N_t * 256  >  training_sum * ALPHA_Q8
-- Training window: TRAIN cells per side, skipping GUARD cells adjacent to
-- the cell under test, circular over the 512 bins. Bins 0, 1 and 511 (DC
-- clutter +/- 1) never detect. Report = largest detected cell: peak bin,
-- peak mag, noise estimate (training sum >> log2(N_t)) -> SNR downstream.
-- Magnitude input is the FFT's max+min/2 approximation -- a square root
-- on iCE40 is a self-inflicted wound.
--
-- Requirements: GS-002.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity cfar is
  generic (
    TRAIN    : positive := 8;   -- per side; N_t = 2*TRAIN
    GUARD    : positive := 2;   -- per side
    ALPHA_Q8 : positive := 2212
  );
  port (
    clk, rst   : in  std_logic;
    mag        : in  unsigned(17 downto 0);
    mag_bin    : in  unsigned(8 downto 0);
    mag_stb    : in  std_logic;
    frame_done : in  std_logic;           -- fft512_serial's done
    peak_bin   : out unsigned(8 downto 0);
    peak_mag   : out unsigned(17 downto 0);
    noise_est  : out unsigned(17 downto 0);
    det_valid  : out std_logic;
    out_stb    : out std_logic
  );
end entity;

architecture rtl of cfar is
  constant NFFT    : natural := 512;
  constant N_T     : natural := 2 * TRAIN;
  constant LOG2_NT : natural := integer(ceil(log2(real(N_T))));
  type spec_t is array (0 to NFFT-1) of unsigned(17 downto 0);
  signal spec : spec_t := (others => (others => '0'));

  type state_t is (FILL, SCAN_SUM, SCAN_DECIDE, EMIT);
  signal state : state_t := FILL;

  signal k     : unsigned(8 downto 0);
  signal d     : natural range 0 to TRAIN + GUARD;
  signal tsum  : unsigned(22 downto 0);          -- 32 * 2^18 fits 23 bits
  signal bbin  : unsigned(8 downto 0);
  signal bmag  : unsigned(17 downto 0);
  signal bne   : unsigned(17 downto 0);
  signal found : std_logic;
begin

  main : process (clk)
    variable lo, hi : unsigned(8 downto 0);
    variable lhs    : unsigned(35 downto 0);
    variable rhs    : unsigned(35 downto 0);
    variable is_dc  : boolean;
  begin
    if rising_edge(clk) then
      out_stb <= '0';
      if rst = '1' then
        state <= FILL;
        found <= '0';
      else
        case state is

          when FILL =>
            if mag_stb = '1' then
              spec(to_integer(mag_bin)) <= mag;
            end if;
            if frame_done = '1' then
              k     <= (others => '0');
              d     <= GUARD + 1;
              tsum  <= (others => '0');
              found <= '0';
              bbin  <= (others => '0');
              bmag  <= (others => '0');
              bne   <= (others => '0');
              state <= SCAN_SUM;
            end if;

          when SCAN_SUM =>
            lo := k - to_unsigned(d, 9);   -- mod-512 wrap for free
            hi := k + to_unsigned(d, 9);
            tsum <= tsum + resize(spec(to_integer(lo)), 23)
                         + resize(spec(to_integer(hi)), 23);
            if d = GUARD + TRAIN then
              state <= SCAN_DECIDE;
            else
              d <= d + 1;
            end if;

          when SCAN_DECIDE =>
            is_dc := (to_integer(k) = 0) or (to_integer(k) = 1)
                     or (to_integer(k) = NFFT - 1);
            lhs := resize(spec(to_integer(k)) * to_unsigned(N_T * 256, 18), 36);
            rhs := resize(tsum * to_unsigned(ALPHA_Q8, 13), 36);
            if (not is_dc) and lhs > rhs
               and spec(to_integer(k)) > bmag then
              found <= '1';
              bbin  <= k;
              bmag  <= spec(to_integer(k));
              bne   <= resize(shift_right(tsum, LOG2_NT), 18);  -- /N_t
            end if;
            if k = NFFT - 1 then
              state <= EMIT;
            else
              k    <= k + 1;
              d    <= GUARD + 1;
              tsum <= (others => '0');
              state <= SCAN_SUM;
            end if;

          when EMIT =>
            peak_bin  <= bbin;
            peak_mag  <= bmag;
            noise_est <= bne;
            det_valid <= found;
            out_stb   <= '1';
            state     <= FILL;

        end case;
      end if;
    end if;
  end process;

end architecture;
