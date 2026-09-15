-- doppler_core: sample-in -> UART-record-out Doppler chain.
--
--   adc I/Q (16b, 48 kS/s) --> cic_dec (R) --> fft512_serial --> cfar
--        |                                                        |
--        +--> raw pass-through (recorder Ch 3)          DOPPLER_V record
--                                                       via uart_tx, 50 Hz
--
-- Epoch tick: CLK_HZ/RATE_HZ counter (240 000 at the defaults). Every
-- epoch the FFT snapshots its sliding window (~53% overlap at R=4 -- a
-- feature, per lesson 17). CFAR result -> one 13-byte DOPPLER_V record
-- per firmware/recorder/PROTOCOL.md: records ship at 50 Hz even with no
-- detection (flags.det_valid = 0, v/bin zeroed) so Ch 4 stays gap-free.
--
-- v_r scaling: v_cm = (k_signed * VCM_PER_BIN_Q8) >>> 8, truncating,
-- k_signed = bin - 512 for bins >= 256 (negative spectrum half = sign
-- from I/Q, lesson 16's Q channel earning its keep). Default 3728 =
-- (12 kS/s / 512) * (lambda/2) * 100 * 256 at 24.125 GHz, R = 4 -- see
-- results/design-notes/decimation-audit.md.
--
-- Separated from doppler_top (SPI ADC front end) so the integration TB
-- injects golden file samples here directly.
--
-- Requirements: GS-002.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity doppler_core is
  generic (
    CLK_HZ         : positive := 12_000_000;
    RATE_HZ        : positive := 50;
    R              : positive := 4;
    VCM_PER_BIN_Q8 : positive := 3728;
    BAUD           : positive := 115_200;
    TRAIN          : positive := 8;
    GUARD          : positive := 2;
    ALPHA_Q8       : positive := 2212
  );
  port (
    clk, rst       : in  std_logic;
    adc_i, adc_q   : in  signed(15 downto 0);
    adc_stb        : in  std_logic;
    txd            : out std_logic;
    -- raw I/Q pass-through for the recorder's Ch 3 (registered copy)
    raw_i, raw_q   : out signed(15 downto 0);
    raw_stb        : out std_logic
  );
end entity;

architecture rtl of doppler_core is
  constant DIV_EPOCH : positive := CLK_HZ / RATE_HZ;

  signal dec_i, dec_q : signed(15 downto 0);
  signal dec_stb      : std_logic;
  signal start        : std_logic := '0';
  signal mag          : unsigned(17 downto 0);
  signal mag_bin      : unsigned(8 downto 0);
  signal mag_stb      : std_logic;
  signal fft_done     : std_logic;
  signal peak_bin     : unsigned(8 downto 0);
  signal peak_mag     : unsigned(17 downto 0);
  signal noise_est    : unsigned(17 downto 0);
  signal det_valid    : std_logic;
  signal cfar_stb     : std_logic;

  signal u_data : std_logic_vector(7 downto 0);
  signal u_stb  : std_logic := '0';
  signal u_busy : std_logic;

  type frame_t is array (0 to 12) of std_logic_vector(7 downto 0);
  signal frame   : frame_t;
  signal f_idx   : natural range 0 to 13 := 13;   -- 13 = idle
  signal seq     : unsigned(7 downto 0) := (others => '0');
  signal epoch_c : natural range 0 to DIV_EPOCH-1 := 0;
begin

  u_cic : entity work.cic_dec
    generic map (N => 3, R => R, W_IN => 16)
    port map (clk => clk, rst => rst,
              in_i => adc_i, in_q => adc_q, in_stb => adc_stb,
              out_i => dec_i, out_q => dec_q, out_stb => dec_stb);

  u_fft : entity work.fft512_serial
    port map (clk => clk, rst => rst,
              sample_i => dec_i, sample_q => dec_q, sample_stb => dec_stb,
              start => start, mag => mag, mag_bin => mag_bin,
              mag_stb => mag_stb, done => fft_done);

  u_cfar : entity work.cfar
    generic map (TRAIN => TRAIN, GUARD => GUARD, ALPHA_Q8 => ALPHA_Q8)
    port map (clk => clk, rst => rst,
              mag => mag, mag_bin => mag_bin, mag_stb => mag_stb,
              frame_done => fft_done,
              peak_bin => peak_bin, peak_mag => peak_mag,
              noise_est => noise_est, det_valid => det_valid,
              out_stb => cfar_stb);

  u_uart : entity work.uart_tx
    generic map (CLK_HZ => CLK_HZ, BAUD => BAUD)
    port map (clk => clk, rst => rst,
              data => u_data, stb => u_stb, busy => u_busy, txd => txd);

  -- epoch tick + raw pass-through
  ticker : process (clk)
  begin
    if rising_edge(clk) then
      start   <= '0';
      raw_stb <= '0';
      if rst = '1' then
        epoch_c <= 0;
      else
        if adc_stb = '1' then
          raw_i   <= adc_i;
          raw_q   <= adc_q;
          raw_stb <= '1';
        end if;
        if epoch_c = DIV_EPOCH - 1 then
          epoch_c <= 0;
          start   <= '1';
        else
          epoch_c <= epoch_c + 1;
        end if;
      end if;
    end if;
  end process;

  -- record builder + byte pump (PROTOCOL.md type 0x01)
  pump : process (clk)
    variable k_s   : integer range -256 to 255;
    variable v_cm  : signed(15 downto 0);
    variable vprod : signed(23 downto 0);
    variable sum   : unsigned(7 downto 0);
    variable fr    : frame_t;
  begin
    if rising_edge(clk) then
      u_stb <= '0';
      if rst = '1' then
        f_idx <= 13;
        seq   <= (others => '0');
      elsif cfar_stb = '1' then
        if det_valid = '1' then
          if to_integer(peak_bin) >= 256 then
            k_s := to_integer(peak_bin) - 512;
          else
            k_s := to_integer(peak_bin);
          end if;
          vprod := to_signed(k_s * VCM_PER_BIN_Q8, 24);
          v_cm  := resize(shift_right(vprod, 8), 16);
        else
          v_cm := (others => '0');
        end if;
        fr(0) := x"A5";
        fr(1) := x"01";
        fr(2) := std_logic_vector(seq);
        fr(3) := "0000000" & det_valid;
        fr(4) := std_logic_vector(v_cm(7 downto 0));
        fr(5) := std_logic_vector(v_cm(15 downto 8));
        if det_valid = '1' then
          fr(6) := std_logic_vector(resize(peak_bin, 8));
          fr(7) := "0000000" & peak_bin(8);
        else
          fr(6) := x"00";
          fr(7) := x"00";
        end if;
        fr(8)  := std_logic_vector(peak_mag(9 downto 2));
        fr(9)  := std_logic_vector(peak_mag(17 downto 10));
        fr(10) := std_logic_vector(noise_est(9 downto 2));
        fr(11) := std_logic_vector(noise_est(17 downto 10));
        sum := (others => '0');
        for b in 0 to 11 loop
          sum := sum + unsigned(fr(b));
        end loop;
        fr(12) := std_logic_vector(unsigned'(x"00") - sum);
        frame  <= fr;
        seq    <= seq + 1;
        f_idx  <= 0;
      elsif f_idx /= 13 and u_busy = '0' and u_stb = '0' then
        u_data <= frame(f_idx);
        u_stb  <= '1';
        f_idx  <= f_idx + 1;
      end if;
    end if;
  end process;

end architecture;
