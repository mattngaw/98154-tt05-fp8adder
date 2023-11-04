`default_nettype none

module clz
    #(parameter WIDTH_IN        = 32,
      parameter WIDTH_OUT       = $clog2(WIDTH_IN)+1)
    (input logic [WIDTH_IN-1:0]     word,
     output logic [WIDTH_OUT-1:0]   zeroes);

    localparam WIDTH = (64 >= WIDTH_IN && WIDTH_IN > 32) ? 64 
                     : (32 >= WIDTH_IN && WIDTH_IN > 16) ? 32
                     : (16 >= WIDTH_IN && WIDTH_IN > 8)  ? 16
                     : (8 >= WIDTH_IN && WIDTH_IN > 4)   ? 8
                     : (4 >= WIDTH_IN && WIDTH_IN > 2)   ? 4
                     : 2;
    localparam DIFF  = WIDTH - WIDTH_IN;
    localparam MAX_ZEROES = 1 << (WIDTH_OUT-2);

    logic [WIDTH-1:0] word_extended;
    logic [WIDTH/2-1:0] left_word, right_word;
    logic [WIDTH_OUT-2:0] left_zeroes, right_zeroes;

    assign word_extended = {word, {DIFF{1'b1}}};

    assign left_word = word_extended[WIDTH-1:WIDTH/2];
    assign right_word = word_extended[WIDTH/2-1:0];

    if (WIDTH == 2) begin
        always_comb begin
            case (word_extended)
                2'b00:   zeroes = 2'd2;
                2'b01:   zeroes = 2'd1;
                default: zeroes = 2'd0;
            endcase
        end
    end
    else begin
        clz #(.WIDTH_IN(WIDTH/2)) left  (left_word, left_zeroes),
                                  right (right_word, right_zeroes);
        assign zeroes = (left_zeroes == MAX_ZEROES) 
                      ? left_zeroes + right_zeroes
                      : left_zeroes;
    end

endmodule: clz
