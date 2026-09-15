// ULX3S 85F arrival-day blinky: proves board, cable, openFPGALoader, and
// the ECP5 bitstream flow end to end before any theremin logic goes on.
// One LED walks along the 8-LED bank, full sweep ~1.3 s at the 25 MHz
// board clock. Port names match ulx3s_v20.lpf.
module blinky (
    input  wire       clk_25mhz,
    output wire [7:0] led
);
    reg [24:0] ctr = 0;
    always @(posedge clk_25mhz)
        ctr <= ctr + 1'b1;

    assign led = 8'b1 << ctr[24:22];
endmodule
