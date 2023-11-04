`include "defines.svh"

`timescale 1ns/1ps
`default_nettype none

typedef enum {
    ROUND_UPWARD,
    ROUND_DOWNWARD,
    ROUND_ZERO,
    ROUND_NEAREST
} rounding_mode_t;

/**
 * Unpack and subtract exponents
 **/
module fp_add_stage_1
    #(parameter WIDTH       = FP8_E5M2_WIDTH,
      parameter EXP_WIDTH   = FP8_E5M2_EXP_WIDTH, 
      parameter MAN_WIDTH   = FP8_E5M2_MAN_WIDTH)
    (input logic [WIDTH-1:0]        a_in, b_in,
     input logic                    subtract_in,
     output logic                   sign_a_out, sign_b_out, 
                                    subtract_out,
                                    b_larger_out,
     output logic [EXP_WIDTH-1:0]   exp_larger_out,
                                    pre_shamt_out,
     output logic [MAN_WIDTH:0]     man_larger_out, man_smaller_out);

    logic [MAN_WIDTH-1:0] man_a_detached, man_b_detached;
    logic [MAN_WIDTH:0] man_a, man_b;
    logic [EXP_WIDTH-1:0] exp_a, exp_b;
    logic [EXP_WIDTH:0] exp_a_extended, exp_b_extended, exp_diff;

    // Forward subtract
    assign subtract_out = subtract_in;

    // Unpack inputs
    assign {sign_a_out, exp_a, man_a_detached} = a_in;
    assign {sign_b_out, exp_b, man_b_detached} = b_in;

    // Reattach implied 1, or flush to zero if subnormal
    assign man_a = (exp_a == 'b0) ? 'b0 : {1'b1, man_a_detached};
    assign man_b = (exp_b == 'b0) ? 'b0 : {1'b1, man_b_detached};
    
    // Extend exponents to detect negative difference
    assign exp_a_extended = {1'b0, exp_a};
    assign exp_b_extended = {1'b0, exp_b};

    // Determine preshift amount from exponent difference
    assign exp_diff = exp_a - exp_b;

    // 1) Signal which input is larger
    // 2) Complement the preshift amount if it is negative
    // 3) Use the lower value exponent
    always_comb begin
        if (exp_diff[EXP_WIDTH]) begin
            b_larger_out = 1'b1;
            pre_shamt_out = -exp_diff[EXP_WIDTH-1:0];
            exp_larger_out = exp_b[EXP_WIDTH-1:0];
            man_larger_out = man_b;
            man_smaller_out = man_a;
        end
        else begin
            b_larger_out = 1'b0;
            pre_shamt_out = exp_diff[EXP_WIDTH-1:0];
            exp_larger_out = exp_a[EXP_WIDTH-1:0];
            man_larger_out = man_a;
            man_smaller_out = man_b;
        end
    end

endmodule: fp_add_stage_1

/**
 * Possible swap, selective complement, and mantissa alignment
 */
module fp_add_stage_2
    #(parameter WIDTH       = FP8_E5M2_WIDTH,
      parameter EXP_WIDTH   = FP8_E5M2_EXP_WIDTH, 
      parameter MAN_WIDTH   = FP8_E5M2_MAN_WIDTH)
    (input logic [MAN_WIDTH:0]      man_larger_in, man_smaller_in,
     input logic [EXP_WIDTH-1:0]    pre_shamt_in, exp_larger_in,
     input logic                    sign_a_in, sign_b_in,
                                    subtract_in,
                                    b_larger_in,
     output logic [MAN_WIDTH+5:0]   man_top_out, man_btm_aligned_out,
     output logic [EXP_WIDTH-1:0]   exp_larger_out,
     output logic                   sign_out, sign_diff_out);

    logic [MAN_WIDTH+5:0] man_larger_extended, man_smaller_extended,
                          man_twos_complemented, man_shifted;


    // Sign logic
    assign sign_out = (b_larger_in) ? sign_b_in : sign_a_in;
    always_comb begin
        if (subtract_in) begin
            sign_diff_out = !(sign_a_in ^ sign_b_in);
        end
        else begin
            sign_diff_out = sign_a_in ^ sign_b_in;
        end
    end

    // Extend to catch Guard, Round, and Sticky bits
    assign man_larger_extended = {2'b0, man_larger_in, 3'b0};
    assign man_smaller_extended = {2'b0, man_smaller_in, 3'b0};

    // Selective complement
    assign man_twos_complemented = -man_larger_extended;

    // Variable shift
    assign man_shifted = (pre_shamt_in >= (MAN_WIDTH+4)) ? 
                         'b0 : man_smaller_extended >> pre_shamt_in;

    // Assign possibly swapped values to output
    assign man_top_out = sign_diff_out ? man_twos_complemented
                                         : man_larger_extended;
    assign man_btm_aligned_out = man_shifted;

    // Forward larger exponent
    assign exp_larger_out = exp_larger_in;

endmodule: fp_add_stage_2


/**
 * Mantissa addition and normalize 1
 */
module fp_add_stage_3
    #(parameter WIDTH       = FP8_E5M2_WIDTH,
      parameter EXP_WIDTH   = FP8_E5M2_EXP_WIDTH, 
      parameter MAN_WIDTH   = FP8_E5M2_MAN_WIDTH)
    (input logic [MAN_WIDTH+5:0]    man_top_in, man_btm_aligned_in,
     input logic [EXP_WIDTH-1:0]    exp_larger_in,
     input logic                    sign_in, sign_diff_in,
     output logic [MAN_WIDTH+4:0]   man_sum_out,
     output logic [EXP_WIDTH-1:0]   exp_norm1_out,
     output logic                   sign_out);
    
    localparam SHAMT_WIDTH = $clog2(MAN_WIDTH+5) + 1; // +1 needed??

    logic carry; // needed??
    logic negate; // needed??
    logic [MAN_WIDTH+5:0] man_sum_unnorm, man_sum_unnorm_abs, man_sum_norm;
    logic [SHAMT_WIDTH-1:0] zeroes;

    localparam MAX_ZEROES = MAN_WIDTH+5;

    // Add aligned mantissas to get unnormalized mantissa sum
    assign {carry, man_sum_unnorm} = man_top_in + man_btm_aligned_in;

    assign negate = man_sum_unnorm[MAN_WIDTH+5];

    assign man_sum_unnorm_abs = (sign_diff_in ? -man_sum_unnorm : man_sum_unnorm);

    // Count the leading zeroes of the sum to get shift amount
    clz #(.WIDTH_IN(MAN_WIDTH+5)) postshift_counter (
        man_sum_unnorm_abs[MAN_WIDTH+4:0],
        zeroes
    );

    always_comb begin
        case (zeroes)
            // Mantissa sum is within [2, 4)
            0:          man_sum_norm = man_sum_unnorm_abs >> 1;
            // Mantissa sum is within [1, 2)
            1:          man_sum_norm = man_sum_unnorm_abs;
            // Mantissa sum is within [0, 1)
            default:    man_sum_norm = man_sum_unnorm_abs << (zeroes - 1);
        endcase
    end

    // Remove the unnecessary leading zero now that the result is normalized
    assign man_sum_out = man_sum_norm[MAN_WIDTH+4:0];

    // Recalculate exponent based on postshift amount
    assign exp_norm1_out = (zeroes == MAX_ZEROES) 
                         ? 'd0
                         : exp_larger_in - $signed(zeroes - 1);

    // Forward the sign
    assign sign_out = sign_in;

endmodule: fp_add_stage_3

/**
 * Round and normalize 2
 */
module fp_add_stage_4
    #(parameter ROUNDING    = ROUND_NEAREST,
      parameter WIDTH       = FP8_E5M2_WIDTH,
      parameter EXP_WIDTH   = FP8_E5M2_EXP_WIDTH, 
      parameter MAN_WIDTH   = FP8_E5M2_MAN_WIDTH)
    (input logic [MAN_WIDTH+4:0]    man_sum_in,
     input logic [EXP_WIDTH-1:0]    exp_norm1_in,
     input logic                    sign_in,
     output logic [MAN_WIDTH:0]     man_rounded_out,
     output logic [EXP_WIDTH-1:0]   exp_norm2_out,
     output logic                   sign_out);

    logic [MAN_WIDTH+1:0] man_rounded, man_normalized;
    logic [MAN_WIDTH:0] man_sum;
    logic ulp, g, r, s;
    logic carry;

    // The sum without GRS
    assign man_sum = man_sum_in[MAN_WIDTH+3:3];
    
    // Extra bits
    assign ulp = man_sum_in[3];
    assign g = man_sum_in[2];
    assign r = man_sum_in[1];
    assign s = man_sum_in[0];

    // Rounding logic
    if (ROUNDING == ROUND_NEAREST) begin
        logic under_half, to_even;

        assign under_half = !g;
        assign to_even = !ulp && !r && !s;

        always_comb begin
            if (under_half || to_even) man_rounded = man_sum;
            else man_rounded = man_sum + 'd1;
        end
    end
    else if (ROUNDING == ROUND_UPWARD) begin
        assign man_rounded = ((g || r || s) ^ sign_in) ? man_sum +'d1 : man_sum;
    end
    else if (ROUNDING == ROUND_DOWNWARD) begin
        assign man_rounded = ((g || r || s) ^ sign_in) ? man_sum : man_sum + 'd1;
    end
    else if (ROUNDING == ROUND_ZERO) begin
        assign man_rounded = man_sum;
    end

    assign carry = man_rounded[MAN_WIDTH+1];

    // Postshift 2 if rounding up put man_out within [2, 4)
    assign man_normalized = carry ? man_rounded >> 1 : man_rounded;
    assign man_rounded_out = man_normalized[MAN_WIDTH:0];

    // Recalculate exponent again based on rounding postshift
    assign exp_norm2_out = exp_norm1_in + carry;

    // Forward sign
    assign sign_out = sign_in;

endmodule: fp_add_stage_4


/**
 * Pack bits together
 **/
module fp_add_stage_5
    #(parameter WIDTH       = FP8_E5M2_WIDTH,
      parameter EXP_WIDTH   = FP8_E5M2_EXP_WIDTH, 
      parameter MAN_WIDTH   = FP8_E5M2_MAN_WIDTH)
    (input logic                    sign_in,
     input logic [EXP_WIDTH-1:0]    exp_in,
     input logic [MAN_WIDTH:0]      man_attached_in,
     output logic [WIDTH-1:0]       result_out);

    logic [MAN_WIDTH-1:0] man;

    // Remove implied 1/0
    assign man = man_attached_in[MAN_WIDTH-1:0];

    // Concatenate
    assign result_out = {sign_in, exp_in, man};

endmodule: fp_add_stage_5

module fp_add
    #(parameter ROUNDING    = ROUND_NEAREST,
      parameter WIDTH       = FP8_E5M2_WIDTH,
      parameter EXP_WIDTH   = FP8_E5M2_EXP_WIDTH, 
      parameter MAN_WIDTH   = FP8_E5M2_MAN_WIDTH)
    (input logic [WIDTH-1:0]        a, b,
     input logic                    subtract,
     output logic [WIDTH-1:0]       result);

    // Stage 1 wires
    logic sign_a_1, sign_b_1;
    logic subtract_1;
    logic b_larger_1;
    logic [EXP_WIDTH-1:0] exp_larger_1, pre_shamt_1;
    logic [MAN_WIDTH:0] man_larger_1, man_smaller_1;

    // Stage 2 wires
    logic [MAN_WIDTH+5:0] man_top_2, man_btm_aligned_2;
    logic [EXP_WIDTH-1:0] exp_larger_2;
    logic sign_2, sign_diff_2;

    // Stage 3 wires
    logic [MAN_WIDTH+4:0] man_sum_3;
    logic [EXP_WIDTH-1:0] exp_norm1_3;
    logic sign_3;

    // Stage 4 wires
    logic [MAN_WIDTH:0] man_rounded_4;
    logic [EXP_WIDTH-1:0] exp_norm2_4;
    logic sign_4;

    fp_add_stage_1 #(WIDTH, EXP_WIDTH, MAN_WIDTH) stage1 (
        .a_in(a), .b_in(b),
        .subtract_in(subtract),
        .sign_a_out(sign_a_1), .sign_b_out(sign_b_1),
        .subtract_out(subtract_1),
        .b_larger_out(b_larger_1),
        .exp_larger_out(exp_larger_1), .pre_shamt_out(pre_shamt_1),
        .man_larger_out(man_larger_1), .man_smaller_out(man_smaller_1)
    );

    /*
    always_comb begin
        $display("Stage 1");
        $display("%b", sign_a_1);
        $display("%b", sign_b_1);
        $display("%b", subtract_1);
        $display("%b", b_larger_1);
        $display("%b", exp_larger_1);
        $display("%b", pre_shamt_1);
        $display("%b", man_larger_1);
        $display("%b", man_smaller_1);
        $display("");
    end
    */

        
    fp_add_stage_2 #(WIDTH, EXP_WIDTH, MAN_WIDTH) stage2 (
        .man_larger_in(man_larger_1), .man_smaller_in(man_smaller_1),
        .pre_shamt_in(pre_shamt_1), .exp_larger_in(exp_larger_1),
        .sign_a_in(sign_a_1), .sign_b_in(sign_b_1),
        .subtract_in(subtract_1),
        .b_larger_in(b_larger_1),
        .man_top_out(man_top_2), .man_btm_aligned_out(man_btm_aligned_2),
        .exp_larger_out(exp_larger_2),
        .sign_out(sign_2), .sign_diff_out(sign_diff_2)
    );

    /*
    always_comb begin
        $display("Stage 2");
        $display("%b", man_top_2);
        $display("%b", man_btm_aligned_2);
        $display("%b", exp_larger_2);
        $display("%b", sign_2);
        $display("");
    end
    */

    fp_add_stage_3 #(WIDTH, EXP_WIDTH, MAN_WIDTH) stage3 (
        .man_top_in(man_top_2), .man_btm_aligned_in(man_btm_aligned_2),
        .exp_larger_in(exp_larger_2),
        .sign_in(sign_2), .sign_diff_in(sign_diff_2),
        .man_sum_out(man_sum_3),
        .exp_norm1_out(exp_norm1_3),
        .sign_out(sign_3)
    );

    /*
    always_comb begin
        $display("Stage 3");
        $display("%b", man_sum_3);
        $display("%b", exp_norm1_3);
        $display("%b", sign_3);
        $display("%b", stage3.zeroes);
        $display("");
    end
    */

    fp_add_stage_4 #(ROUNDING, WIDTH, EXP_WIDTH, MAN_WIDTH) stage4 (
        .man_sum_in(man_sum_3),
        .exp_norm1_in(exp_norm1_3),
        .sign_in(sign_3),
        .man_rounded_out(man_rounded_4),
        .exp_norm2_out(exp_norm2_4),
        .sign_out(sign_4)
    );

    /*
    always_comb begin
        $display("Stage 4");
        $display("%b", man_rounded_4);
        $display("%b", exp_norm2_4);
        $display("%b", sign_4);
        $display("");
    end
    */

    fp_add_stage_5 #(WIDTH, EXP_WIDTH, MAN_WIDTH) stage5 (
        .sign_in(sign_4),
        .exp_in(exp_norm2_4),
        .man_attached_in(man_rounded_4),
        .result_out(result)
    );

endmodule: fp_add
