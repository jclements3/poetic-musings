// Jumper-test theremin: one wire from FAKE_OSC_OUT to PITCH_IN gives a
// steady tone; move the jumper away and the tone stops. Volume synthetic.
module cu_jumper_top (input clk100, input pitch_in,
                      output [7:0] led, output audio, output fake_osc);
  reg clk50 = 0; always @(posedge clk100) clk50 <= ~clk50;
  reg [7:0] rstc = 0; wire rst = (rstc != 8'hFF);
  always @(posedge clk50) if (rst) rstc <= rstc + 1;

  // ~1.4 MHz square (half = 18 ticks @50 MHz) for the loopback jumper
  reg [4:0] fc = 0; reg fo = 0;
  always @(posedge clk50)
    if (fc >= 5'd17) begin fc <= 0; fo <= ~fo; end else fc <= fc + 1;
  assign fake_osc = fo;

  reg [4:0] vc = 0; reg vosc = 0;
  always @(posedge clk50)
    if (vc >= 5'd19) begin vc <= 0; vosc <= ~vosc; end else vc <= vc + 1;

  wire a1; wire [3:0] pcm4;
  theremin_top u (.CLK(clk50), .RESET(rst),
                  .PITCH_OSC_IN(pitch_in), .VOLUME_OSC_IN(vosc),
                  .AUDIO_1BIT(a1), .AUDIO_PCM4(pcm4));
  assign led = {a1, 3'b000, pcm4};
  assign audio = a1;
endmodule
