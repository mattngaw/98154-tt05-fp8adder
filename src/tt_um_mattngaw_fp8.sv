`include "defines.svh"

`default_nettype none

module tt_um_mattngaw_fp8 (
    input  logic [7:0] ui_in,    // Dedicated inputs - connected to the input switches
    output logic [7:0] uo_out,   // Dedicated outputs - connected to the 7 segment display
    input  logic [7:0] uio_in,   // IOs: Bidirectional Input path
    output logic [7:0] uio_out,  // IOs: Bidirectional Output path
    output logic [7:0] uio_oe,   // IOs: Bidirectional Enable path (active high: 0=input, 1=output)
    input  logic       ena,      // will go high when the design is enabled
    input  logic       clk,      // clock
    input  logic       rst_n     // reset_n - low to reset
);

    // Use bidirectionals as inputs 
    assign uio_oe = 8'b00000000;

    fp_add #(.ROUNDING(ROUND_NEAREST), .WIDTH(8), .EXP_WIDTH(5), .MAN_WIDTH(2)) adder (ui_in, uio_in, 1'b0, uo_out);

endmodule
