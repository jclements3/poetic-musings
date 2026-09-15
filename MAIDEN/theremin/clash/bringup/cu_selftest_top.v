// Self-test theremin: synthetic oscillators inside, zero external wiring.
// Pitch half-period sweeps 14..29 ticks (the range the PitchMap constants
// are calibrated for) on a ~1.5 s triangle; volume is fixed. AUDIO_PCM4
// drives led[3:0] as a meter, AUDIO_1BIT drives led[7] and the audio pin.
module cu_selftest_top (input clk100, output [7:0] led, output audio);
  reg clk50 = 0; always @(posedge clk100) clk50 <= ~clk50;

  reg [7:0] rstc = 0; wire rst = (rstc != 8'hFF);
  always @(posedge clk50) if (rst) rstc <= rstc + 1;

  // sweep: triangle 0..15 -> half-period 14..29
  reg [25:0] sw; always @(posedge clk50) sw <= sw + 1;
  wire [4:0] t = sw[24:20];
  wire [4:0] half = 5'd14 + (t[4] ? (5'd31 - t) : t);

  reg [4:0] pc = 0; reg posc = 0;
  always @(posedge clk50)
    if (pc >= half - 1) begin pc <= 0; posc <= ~posc; end
    else pc <= pc + 1;

  reg [4:0] vc = 0; reg vosc = 0;
  always @(posedge clk50)
    if (vc >= 5'd19) begin vc <= 0; vosc <= ~vosc; end
    else vc <= vc + 1;

  wire a1; wire [3:0] pcm4;
  theremin_top u (.CLK(clk50), .RESET(rst),
                  .PITCH_OSC_IN(posc), .VOLUME_OSC_IN(vosc),
                  .AUDIO_1BIT(a1), .AUDIO_PCM4(pcm4));
  assign led = {a1, 3'b000, pcm4};
  assign audio = a1;
endmodule
