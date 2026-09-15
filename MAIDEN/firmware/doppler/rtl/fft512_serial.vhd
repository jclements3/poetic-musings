-- fft512_serial: 512-point radix-2 DIT complex FFT, fully serial.
--
-- Port contract pinned by lesson 17 (doppler_core and the recorder both
-- assume it). Samples stream continuously at the decimated rate into a
-- circular buffer (sliding window -- overlap between 50 Hz epochs is a
-- feature, ~53% at R=4); `start` snapshots the newest 512 and launches a
-- transform; magnitudes stream out in natural bin order.
--
-- Fixed-point formats (written down):
--   input     : signed 16
--   work RAM  : signed W_WORK = 20 (input 2^15 * worst-case per-pass
--               growth 1.21^9 ~ 5.6x -> < 2^18; 4x margin, no wrap, so
--               bit-true against the unbounded-int golden model)
--   twiddles  : Q15, 256-entry half-spectrum ROM built at elaboration
--               (math_real). A quarter-wave folded ROM (lesson 07 trick)
--               would quarter the storage; shipped unfolded for clarity --
--               fold it if the hx8k budget squeezes.
--   butterfly : t = (b*W) >> 15 (truncating); a' = (a+t) >> 1,
--               b' = (a-t) >> 1 -- block scale 1/2 per pass, 1/512 net.
--   mag       : max(|I|,|Q|) + min(|I|,|Q|)/2 (no sqrt on iCE40; ~11%
--               worst case; golden model identical), clamped to u18
--               (unreachable for sane input).
-- Multiplies use `*` directly (LUT logic on iCE40): functionally identical
-- to the lesson's serialized shift-add; costed honestly at synthesis. The
-- shift-add rewrite is a budget optimization, not a behavior change.
-- Cycle budget: 512 load + 2304 butterflies x 5 + 512 mag ~ 12.6k cycles
-- per epoch -- 5% of the 240k-cycle 20 ms budget at 12 MHz.
--
-- Requirements: GS-002.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity fft512_serial is
  port (
    clk, rst           : in  std_logic;
    sample_i, sample_q : in  signed(15 downto 0);
    sample_stb         : in  std_logic;               -- decimated rate
    start              : in  std_logic;               -- 50 Hz epoch tick
    mag                : out unsigned(17 downto 0);   -- |X(k)| approx
    mag_bin            : out unsigned(8 downto 0);    -- streamed 0..511
    mag_stb            : out std_logic;
    done               : out std_logic
  );
end entity;

architecture rtl of fft512_serial is
  constant NFFT   : natural := 512;
  constant W_WORK : natural := 20;

  type buf_t is array (0 to NFFT-1) of signed(15 downto 0);
  type work_t is array (0 to NFFT-1) of signed(W_WORK-1 downto 0);
  type rom_t is array (0 to NFFT/2-1) of signed(15 downto 0);

  function tw_rom(cospart : boolean) return rom_t is
    variable r   : rom_t;
    variable ang : real;
  begin
    for k in 0 to NFFT/2-1 loop
      ang := 2.0 * MATH_PI * real(k) / real(NFFT);
      if cospart then
        r(k) := to_signed(integer(round(32767.0 * cos(ang))), 16);
      else
        r(k) := to_signed(integer(round(-32767.0 * sin(ang))), 16);
      end if;
    end loop;
    return r;
  end function;

  constant TW_R : rom_t := tw_rom(true);
  constant TW_I : rom_t := tw_rom(false);

  function brev9(x : unsigned(8 downto 0)) return unsigned is
    variable r : unsigned(8 downto 0);
  begin
    for k in 0 to 8 loop
      r(k) := x(8 - k);
    end loop;
    return r;
  end function;

  signal circ_i, circ_q : buf_t := (others => (others => '0'));
  signal wp             : unsigned(8 downto 0) := (others => '0');

  signal wre, wim : work_t := (others => (others => '0'));

  type state_t is (IDLE, LOAD, B_RDA, B_RDB, B_MUL, B_WRA, B_WRB, MAGOUT);
  signal state : state_t := IDLE;

  signal n_ld          : unsigned(8 downto 0);
  signal stg           : natural range 0 to 8;        -- half = 2**stg
  signal grp           : unsigned(9 downto 0);        -- 0..511 by 2*half
  signal j             : unsigned(8 downto 0);        -- 0..half-1
  signal addr_a        : natural range 0 to NFFT-1;
  signal addr_b        : natural range 0 to NFFT-1;
  signal ra_r, ra_i    : signed(W_WORK-1 downto 0);
  signal rb_r, rb_i    : signed(W_WORK-1 downto 0);
  signal t_r, t_i      : signed(W_WORK-1 downto 0);
  signal k_out         : unsigned(8 downto 0);
begin

  -- continuous circular capture, independent of the transform FSM
  capture : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        wp <= (others => '0');
      elsif sample_stb = '1' then
        circ_i(to_integer(wp)) <= sample_i;
        circ_q(to_integer(wp)) <= sample_q;
        wp <= wp + 1;
      end if;
    end if;
  end process;

  fsm : process (clk)
    variable half_u  : unsigned(9 downto 0);
    variable tw_idx  : natural range 0 to NFFT/2-1;
    variable pr, pi  : signed(W_WORK+16 downto 0);
    variable mi, mq  : unsigned(W_WORK-1 downto 0);
    variable mg      : unsigned(W_WORK-1 downto 0);
  begin
    if rising_edge(clk) then
      mag_stb <= '0';
      done    <= '0';
      if rst = '1' then
        state <= IDLE;
      else
        half_u := shift_left(to_unsigned(1, 10), stg);
        case state is

          when IDLE =>
            if start = '1' then
              n_ld  <= (others => '0');
              state <= LOAD;
            end if;

          when LOAD =>
            -- oldest-first: circ[wp + n] is the sample 512-n strobes ago
            wre(to_integer(brev9(n_ld))) <=
              resize(circ_i(to_integer(wp + n_ld)), W_WORK);
            wim(to_integer(brev9(n_ld))) <=
              resize(circ_q(to_integer(wp + n_ld)), W_WORK);
            if n_ld = NFFT - 1 then
              stg   <= 0;
              grp   <= (others => '0');
              j     <= (others => '0');
              state <= B_RDA;
            end if;
            n_ld <= n_ld + 1;

          when B_RDA =>
            addr_a <= to_integer(grp(8 downto 0) + j);
            state  <= B_RDB;

          when B_RDB =>
            ra_r   <= wre(addr_a);
            ra_i   <= wim(addr_a);
            addr_b <= to_integer(grp(8 downto 0) + j + half_u(8 downto 0));
            state  <= B_MUL;

          when B_MUL =>
            rb_r  <= wre(addr_b);
            rb_i  <= wim(addr_b);
            state <= B_WRA;

          when B_WRA =>
            -- twiddle index = j * (256/half) = j << (8 - stg)
            tw_idx := to_integer(shift_left(resize(j, 17), 8 - stg));
            pr := resize(rb_r * TW_R(tw_idx), W_WORK+17)
                - resize(rb_i * TW_I(tw_idx), W_WORK+17);
            pi := resize(rb_r * TW_I(tw_idx), W_WORK+17)
                + resize(rb_i * TW_R(tw_idx), W_WORK+17);
            t_r <= resize(shift_right(pr, 15), W_WORK);
            t_i <= resize(shift_right(pi, 15), W_WORK);
            state <= B_WRB;

          when B_WRB =>
            wre(addr_a) <= resize(shift_right(
              resize(ra_r, W_WORK+1) + resize(t_r, W_WORK+1), 1), W_WORK);
            wim(addr_a) <= resize(shift_right(
              resize(ra_i, W_WORK+1) + resize(t_i, W_WORK+1), 1), W_WORK);
            wre(addr_b) <= resize(shift_right(
              resize(ra_r, W_WORK+1) - resize(t_r, W_WORK+1), 1), W_WORK);
            wim(addr_b) <= resize(shift_right(
              resize(ra_i, W_WORK+1) - resize(t_i, W_WORK+1), 1), W_WORK);
            -- advance j -> group -> stage
            if j = half_u(8 downto 0) - 1 then
              j <= (others => '0');
              if to_integer(grp) + 2 * to_integer(half_u) >= NFFT then
                grp <= (others => '0');
                if stg = 8 then
                  k_out <= (others => '0');
                  state <= MAGOUT;
                else
                  stg   <= stg + 1;
                  state <= B_RDA;
                end if;
              else
                grp   <= grp + shift_left(half_u, 1);
                state <= B_RDA;
              end if;
            else
              j     <= j + 1;
              state <= B_RDA;
            end if;

          when MAGOUT =>
            mi := unsigned(abs(wre(to_integer(k_out))));
            mq := unsigned(abs(wim(to_integer(k_out))));
            if mi >= mq then
              mg := mi + shift_right(mq, 1);
            else
              mg := mq + shift_right(mi, 1);
            end if;
            if mg > to_unsigned(2**18 - 1, W_WORK) then
              mag <= (others => '1');   -- clamp; unreachable for sane input
            else
              mag <= resize(mg, 18);
            end if;
            mag_bin <= k_out;
            mag_stb <= '1';
            if k_out = NFFT - 1 then
              done  <= '1';
              state <= IDLE;
            end if;
            k_out <= k_out + 1;

        end case;
      end if;
    end if;
  end process;

end architecture;
