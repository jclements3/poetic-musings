// cu_top.v — Alchitry Cu board wrapper for santa_glide (Clash-generated).
//
// Two adaptations live here, because a PCF cannot express either:
//
// 1. Clock: the Cu's oscillator is 100 MHz (ball P7), but the santa_glide
//    logic (32-bit dwell counters/comparators) closes timing around 60 MHz
//    on the HX8K fabric, so an SB_PLL40_CORE divides it to a 50 MHz logic
//    clock (icepll -i 100 -o 50: DIVR=0 DIVF=7 DIVQ=4). msTicks in
//    SantaGlide.hs is set to 50000 to match — 1 ms is still 1 ms.
//
// 2. Reset/enable: the Clash `System` domain expects an active-HIGH
//    synchronous reset and active-high enable. The Cu's reset button
//    (ball P8) is active LOW, so it is inverted and synchronized (the
//    design is also held in reset until the PLL locks), and en is tied 1.
`default_nettype none

module cu_top (
    input  wire       clk,     // 100 MHz on-board oscillator (ball P7)
    input  wire       rst_n,   // Cu reset button (ball P8), LOW while pressed
    input  wire       show_on, // show switch, Br bank A pin A14 (ball C1)
    output wire [7:0] gates    // MOSFET gate drives, Br bank A pins A2..A12
);

    // 100 MHz -> 50 MHz PLL (F_VCO = 800 MHz).
    wire clk50;
    wire pll_locked;
    SB_PLL40_CORE #(
        .FEEDBACK_PATH ("SIMPLE"),
        .DIVR          (4'b0000),
        .DIVF          (7'b0000111),
        .DIVQ          (3'b100),
        .FILTER_RANGE  (3'b101)
    ) pll (
        .REFERENCECLK  (clk),
        .PLLOUTGLOBAL  (clk50),
        .LOCK          (pll_locked),
        .RESETB        (1'b1),
        .BYPASS        (1'b0)
    );

    // Two-flop synchronizer: active-high reset from the active-low button,
    // held asserted until the PLL locks. Powers up in reset (2'b11).
    reg [1:0] rst_sync = 2'b11;
    always @(posedge clk50) rst_sync <= {rst_sync[0], ~rst_n | ~pll_locked};

    santa_glide sg (
        .clk     (clk50),
        .rst     (rst_sync[1]),
        .en      (1'b1),
        .show_on (show_on),
        .gates   (gates)
    );

endmodule
