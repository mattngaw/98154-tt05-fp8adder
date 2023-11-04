`ifndef _DEFINES_SVH_
`define _DEFINES_SVH_

/*-----------------------------------------------------------------------------
 * Rounding Modes
 *---------------------------------------------------------------------------*/

typedef enum logic [2:0] {
    ROUND_UPWARD,
    ROUND_DOWNWARD,
    ROUND_ZERO,
    ROUND_NEAREST
} rounding_mode_t;


/*-----------------------------------------------------------------------------
 * Floating Point Formats
 *---------------------------------------------------------------------------*/

/*--- FP8 E5M2 ---*/
parameter FP8_E5M2_WIDTH        = 8;
parameter FP8_E5M2_EXP_WIDTH    = 5;
parameter FP8_E5M2_MAN_WIDTH    = 2;

/*--- bfloat16 ---*/
parameter BFLOAT16_WIDTH        = 16;
parameter BFLOAT16_EXP_WIDTH    = 8;
parameter BFLOAT16_MAN_WIDTH    = 7;

/*--- IEEE 754 binary16 ---*/
parameter BINARY16_WIDTH        = 16;
parameter BINARY16_EXP_WIDTH    = 5;
parameter BINARY16_MAN_WIDTH    = 10;

/*--- IEEE 754 binary32 ---*/
parameter BINARY32_WIDTH        = 32;
parameter BINARY32_EXP_WIDTH    = 8;
parameter BINARY32_MAN_WIDTH    = 23;

/*--- IEEE 754 binary64 ---*/
parameter BINARY64_WIDTH        = 64;
parameter BINARY64_EXP_WIDTH    = 11;
parameter BINARY64_MAN_WIDTH    = 52;


`endif /* _DEFINES_SVH_ */
