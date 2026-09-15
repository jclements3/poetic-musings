-- doppler_top: SPI ADC front end + doppler_core. Board-facing top level.
--
-- First-light ADC path: MCP3202-class 12-bit dual-channel SPI ADC,
-- channels 0/1 = I/Q, read alternately, results left-shifted to 16 bits.
-- HONESTY NOTE: an MCP3202 tops out ~50 kS/s aggregate at 5 V -- fine for
-- fan/walk first light, NOT the production 48 kS/s/pair 16-bit chain D6
-- specifies. The production ADC swaps in behind the same pair-strobe
-- interface; this SPI master is verified on the bench in maiden36 (its
-- logic is exercised here only through synthesis + the core TB's direct
-- injection path).
--
-- Async inputs: none in sim; adc_miso is board-async -> 2-FF synchronized.
--
-- Requirements: GS-002.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity doppler_top is
  generic (
    CLK_HZ  : positive := 12_000_000;
    SCK_DIV : positive := 6           -- 12 MHz / 6 = 2 MHz SPI clock
  );
  port (
    clk, rst : in  std_logic;
    -- SPI to the ADC
    adc_cs_n : out std_logic;
    adc_sck  : out std_logic;
    adc_mosi : out std_logic;
    adc_miso : in  std_logic;
    -- telemetry + raw pass-through to the recorder
    txd      : out std_logic;
    raw_i    : out signed(15 downto 0);
    raw_q    : out signed(15 downto 0);
    raw_stb  : out std_logic
  );
end entity;

architecture rtl of doppler_top is
  signal miso_m, miso_s : std_logic := '0';   -- 2-FF synchronizer

  signal smp_i, smp_q : signed(15 downto 0) := (others => '0');
  signal pair_stb     : std_logic := '0';

  type spi_state_t is (START, XFER, GAP);
  signal sstate  : spi_state_t := START;
  signal chan    : std_logic := '0';          -- 0 = I, 1 = Q
  signal sck_c   : natural range 0 to SCK_DIV-1 := 0;
  signal sck_r   : std_logic := '0';
  signal bit_n   : natural range 0 to 17 := 0;
  signal sh_out  : std_logic_vector(17 downto 0);
  signal sh_in   : std_logic_vector(11 downto 0) := (others => '0');
begin

  sync : process (clk)
  begin
    if rising_edge(clk) then
      miso_m <= adc_miso;
      miso_s <= miso_m;
    end if;
  end process;

  -- MCP3202 frame: start(1) sgl/diff(1) odd/sign(chan) msbf(1) then
  -- null bit + 12 data bits on miso. 18 sck periods covers it.
  spi : process (clk)
  begin
    if rising_edge(clk) then
      pair_stb <= '0';
      if rst = '1' then
        sstate   <= START;
        chan     <= '0';
        adc_cs_n <= '1';
        sck_r    <= '0';
        sck_c    <= 0;
      else
        case sstate is
          when START =>
            adc_cs_n <= '0';
            sh_out   <= "1" & "1" & chan & "1" & (13 downto 0 => '0');
            bit_n    <= 0;
            sck_c    <= 0;
            sck_r    <= '0';
            sstate   <= XFER;
          when XFER =>
            if sck_c = SCK_DIV - 1 then
              sck_c <= 0;
              sck_r <= not sck_r;
              if sck_r = '1' then               -- falling edge: shift out
                sh_out <= sh_out(16 downto 0) & '0';
                if bit_n = 17 then
                  sstate <= GAP;
                else
                  bit_n <= bit_n + 1;
                end if;
              else                              -- rising edge: sample in
                sh_in <= sh_in(10 downto 0) & miso_s;
              end if;
            else
              sck_c <= sck_c + 1;
            end if;
          when GAP =>
            adc_cs_n <= '1';
            if chan = '0' then
              smp_i <= signed(sh_in & "0000");
            else
              smp_q <= signed(sh_in & "0000");
              pair_stb <= '1';
            end if;
            chan   <= not chan;
            sstate <= START;
        end case;
      end if;
    end if;
  end process;

  adc_sck  <= sck_r;
  adc_mosi <= sh_out(17);

  core : entity work.doppler_core
    generic map (CLK_HZ => CLK_HZ)
    port map (clk => clk, rst => rst,
              adc_i => smp_i, adc_q => smp_q, adc_stb => pair_stb,
              txd => txd, raw_i => raw_i, raw_q => raw_q,
              raw_stb => raw_stb);

end architecture;
