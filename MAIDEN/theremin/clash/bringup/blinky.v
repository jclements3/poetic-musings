// Arrival-day step 2: proves yosys->nextpnr->icepack->openFPGALoader->silicon.
module blinky (input clk100, output [7:0] led);
  reg [26:0] c; always @(posedge clk100) c <= c + 1;
  assign led = 8'h01 << c[26:24];
endmodule
