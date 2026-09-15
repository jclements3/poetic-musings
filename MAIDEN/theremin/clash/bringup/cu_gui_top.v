// GUI-driven theremin for the Alchitry Cu: the self-test wrapper with the
// synthetic oscillators steered over the board's USB UART (FT2232 channel B,
// /dev/ttyUSB1 on the lab machine, 115200 8N1).  Zero external wiring.
//
// Host -> board (9 bytes):  A5, pinc[31:0] (big-endian), vinc[31:0]
//   pinc/vinc: 32-bit NCO increments of the synthetic PITCH and VOLUME
//   oscillators, square waves of frequency inc * 50 MHz / 2^32 (period
//   2^32/inc ticks) - so the host can place either period anywhere with
//   sub-tick resolution, which the musical NoteMap (pitch: far 84 -> near
//   80 ticks) and AmpMap (volume: far 92 -> near 88 ticks) need. If no
//   frame arrives for 250 ms the board falls back to a triangle sweep of
//   the pitch period across its calibrated range at full volume, so this
//   bitstream doubles as the BRINGUP.md step-3 self-test.
//   led[4] = link alive.
//
// Board -> host (20 bytes every 20 ms, a 1M-cycle window):
//   5A, seq, pinc[31:0], vinc[31:0], {pcm_max, pcm_min},
//   zc_hi, zc_lo   (rising crossings of AUDIO_PCM4 through mid, with
//                   hysteresis 6/9 -> audio frequency = zc * 50 Hz)
//   dsm_hi, dsm_lo (AUDIO_1BIT ones counted every 16th cycle, max 62500)
//   per2, per1, per0 (50 MHz cycles of the last full audio period, rising
//                   crossing to rising crossing; 0 = none in the last 335 ms)
//   peak_hi, peak_lo (largest |AUDIO_S16| in the window: the real amplitude)
//
// led[7] = AUDIO_1BIT, led[3:0] = AUDIO_PCM4 (as in the self-test),
// audio pin = AUDIO_1BIT.
module cu_gui_top #(parameter WIN = 1000000) (input clk100, input usb_rx, output usb_tx,
                   output [7:0] led, output audio);
  reg clk50 = 0; always @(posedge clk100) clk50 <= ~clk50;

  reg [7:0] rstc = 0; wire rst = (rstc != 8'hFF);
  always @(posedge clk50) if (rst) rstc <= rstc + 1;

  localparam BAUD_DIV = 434;            // 50e6 / 115200 = 434.03

  // ---------------------------------------------------------------- UART RX
  reg [1:0] rxs = 2'b11; always @(posedge clk50) rxs <= {rxs[0], usb_rx};
  wire rxl = rxs[1];
  reg [9:0] rcnt = 0; reg [3:0] rbit = 0; reg rbusy = 0; reg [7:0] rsh = 0;
  reg [7:0] rdata = 0; reg rvalid = 0;
  always @(posedge clk50) begin
    rvalid <= 0;
    if (!rbusy) begin
      if (!rxl) begin                   // start edge: wait 1.5 bits to bit-0 centre
        rbusy <= 1; rcnt <= BAUD_DIV + BAUD_DIV/2 - 1; rbit <= 0;
      end
    end else if (rcnt != 0) rcnt <= rcnt - 1;
    else begin
      rcnt <= BAUD_DIV - 1;
      if (rbit < 8) begin rsh <= {rxl, rsh[7:1]}; rbit <= rbit + 1; end
      else begin rbusy <= 0; if (rxl) begin rdata <= rsh; rvalid <= 1; end end
    end
  end

  // frame parser + link watchdog
  localparam INC_FAR  = 32'd51_130_563;   // 2^32 / 84 ticks (pitch, hand away)
  localparam INC_NEAR = 32'd53_687_091;   // 2^32 / 80 ticks (pitch, closest)
  localparam VINC_FAR = 32'd46_684_427;   // 2^32 / 92 ticks (volume, hand away = loud)
  reg [3:0] fst = 0; reg [31:0] tmpp = 0, tmpv = 0;
  reg [31:0] ginc = INC_FAR, gvinc = VINC_FAR; reg gframe = 0;
  always @(posedge clk50) begin
    gframe <= 0;
    if (rvalid) case (fst)
      4'd0: if (rdata == 8'hA5) fst <= 4'd1;
      4'd1, 4'd2, 4'd3, 4'd4: begin tmpp <= {tmpp[23:0], rdata}; fst <= fst + 1; end
      4'd5, 4'd6, 4'd7:       begin tmpv <= {tmpv[23:0], rdata}; fst <= fst + 1; end
      4'd8: begin ginc <= tmpp; gvinc <= {tmpv[23:0], rdata}; gframe <= 1; fst <= 4'd0; end
      default: fst <= 4'd0;
    endcase
  end
  reg [23:0] wdt = 0; wire link = (wdt != 0);           // 250 ms
  always @(posedge clk50)
    if (gframe) wdt <= 24'd12_500_000; else if (wdt != 0) wdt <= wdt - 1;

  // ------------------------------------------------- synthetic oscillators
  // self-test sweep: ~1.3 s triangle of the increment over ~82 % of the
  // calibrated range (INC_FAR + t*2048, t = 0..1023)
  reg [26:0] sw = 0; always @(posedge clk50) sw <= sw + 1;
  wire [10:0] t = sw[26:16];
  wire [9:0] trg = t[10] ? ~t[9:0] : t[9:0];
  wire [31:0] swinc = INC_FAR + {11'd0, trg, 11'd0};
  wire [31:0] pinc = link ? ginc : swinc;
  wire [31:0] vinc = link ? gvinc : VINC_FAR;

  reg [31:0] pacc = 0; always @(posedge clk50) pacc <= pacc + pinc;
  wire posc = pacc[31];
  reg [31:0] vacc = 0; always @(posedge clk50) vacc <= vacc + vinc;
  wire vosc = vacc[31];

  // ------------------------------------------------------- the instrument
  wire a1; wire [3:0] pcm4; wire signed [15:0] s16;
  theremin_top u (.CLK(clk50), .RESET(rst),
                  .PITCH_OSC_IN(posc), .VOLUME_OSC_IN(vosc),
                  .AUDIO_1BIT(a1), .AUDIO_PCM4(pcm4), .AUDIO_S16(s16));
  // led[5]: raw usb_rx activity (stretched ~40 ms per low), led[6]: a byte parsed
  reg [20:0] act = 0; always @(posedge clk50) if (!rxl) act <= 21'h1FFFFF; else if (act != 0) act <= act - 1;
  reg [20:0] bact = 0; always @(posedge clk50) if (rvalid) bact <= 21'h1FFFFF; else if (bact != 0) bact <= bact - 1;
  assign led = {a1, bact != 0, act != 0, link, pcm4};
  assign audio = a1;

  // ------------------------------------------------ 20 ms telemetry window
  reg [19:0] win = 0; wire wend = (win == WIN - 1);
  always @(posedge clk50) win <= wend ? 20'd0 : win + 1;
  reg [3:0] pcm_q = 0; reg a1_q = 0;
  always @(posedge clk50) begin pcm_q <= pcm4; a1_q <= a1; end
  reg [3:0] pmax = 0, pmin = 4'hF; reg [15:0] zc = 0, dsm = 0; reg above = 0;
  reg [3:0] lmax = 0, lmin = 0; reg [15:0] lzc = 0, ldsm = 0;
  reg [23:0] pcyc = 0, lper = 0, fper = 0;   // audio period: running, last, latched
  reg [31:0] lpinc = 0, lvinc = 0;
  reg signed [15:0] s16_q = 0; always @(posedge clk50) s16_q <= s16;
  wire [15:0] s16abs = s16_q[15] ? -s16_q : s16_q;
  reg [15:0] peak = 0, lpeak = 0;
  always @(posedge clk50) begin
    if (wend) begin
      lmax <= pmax; lmin <= pmin; lzc <= zc; ldsm <= dsm; lpinc <= pinc; lvinc <= vinc;
      fper <= lper; lpeak <= peak;
      pmax <= 0; pmin <= 4'hF; zc <= 0; dsm <= 0; peak <= 0;
    end else begin
      if (s16abs > peak) peak <= s16abs;
      if (pcm_q > pmax) pmax <= pcm_q;
      if (pcm_q < pmin) pmin <= pcm_q;
      if (a1_q && win[3:0] == 4'd0) dsm <= dsm + 1;
      if (!above && pcm_q >= 4'd9) begin above <= 1; zc <= zc + 1; end
      else if (above && pcm_q <= 4'd6) above <= 0;
    end
    // period between rising crossings, independent of the window
    if (!above && pcm_q >= 4'd9) begin lper <= pcyc + 1; pcyc <= 0; end
    else if (pcyc != 24'hFFFFFF) pcyc <= pcyc + 1;
    else lper <= 0;                       // >335 ms without a crossing: silent
  end

  // ---------------------------------------------------------------- UART TX
  reg [4:0] tidx = 5'd20;               // 20 = idle, 0..19 = next byte to send
  reg [7:0] seq = 0;
  reg [7:0] tbyte;
  always @(*) case (tidx)
    5'd0: tbyte = 8'h5A;         5'd1: tbyte = seq;
    5'd2: tbyte = lpinc[31:24];  5'd3: tbyte = lpinc[23:16];
    5'd4: tbyte = lpinc[15:8];   5'd5: tbyte = lpinc[7:0];
    5'd6: tbyte = lvinc[31:24];  5'd7: tbyte = lvinc[23:16];
    5'd8: tbyte = lvinc[15:8];   5'd9: tbyte = lvinc[7:0];
    5'd10: tbyte = {lmax, lmin};
    5'd11: tbyte = lzc[15:8];    5'd12: tbyte = lzc[7:0];
    5'd13: tbyte = ldsm[15:8];   5'd14: tbyte = ldsm[7:0];
    5'd15: tbyte = fper[23:16];  5'd16: tbyte = fper[15:8]; 5'd17: tbyte = fper[7:0];
    5'd18: tbyte = lpeak[15:8];  5'd19: tbyte = lpeak[7:0];
    default: tbyte = 8'h00;
  endcase
  reg txr = 1; assign usb_tx = txr;
  reg tbusy = 0; reg [9:0] tcnt = 0; reg [3:0] tbit = 0; reg [8:0] tsh = 0;
  always @(posedge clk50) begin
    if (!tbusy) begin
      if (tidx != 5'd20) begin          // load: start bit now, data+stop follow
        tsh <= {1'b1, tbyte}; txr <= 0; tbusy <= 1; tbit <= 0; tcnt <= BAUD_DIV - 1;
        tidx <= tidx + 1;
      end
    end else if (tcnt != 0) tcnt <= tcnt - 1;
    else begin
      tcnt <= BAUD_DIV - 1;
      if (tbit < 4'd9) begin txr <= tsh[0]; tsh <= {1'b1, tsh[8:1]}; tbit <= tbit + 1; end
      else tbusy <= 0;                  // stop bit has had its full period
    end
    if (wend && tidx == 5'd20 && !tbusy) begin tidx <= 5'd0; seq <= seq + 1; end
    // (frame is 1.7 ms << 20 ms; a window ending mid-frame is skipped, never torn)
  end
endmodule
