`default_nettype none

package fp_pkg;

  typedef enum logic [3:0] {
    FP_NONE,
    FP_ADD,
    FP_MUL,
    FP_FMA,
    FP_DIV_SQRT,
    FP_CVT,
    FP_MISC,
    FP_LOAD,
    FP_STORE,
    FP_MV_X_W,
    FP_MV_W_X
  } fp_unit_e;

  // OP-FP funct5
  localparam logic [4:0] Funct5Fadd = 5'b00000;
  localparam logic [4:0] Funct5Fsub = 5'b00001;
  localparam logic [4:0] Funct5Fmul = 5'b00010;
  localparam logic [4:0] Funct5Fdiv = 5'b00011;
  localparam logic [4:0] Funct5Fsgnj = 5'b00100;
  localparam logic [4:0] Funct5Fminmax = 5'b00101;
  localparam logic [4:0] Funct5Fsqrt = 5'b01011;
  localparam logic [4:0] Funct5Fcmp = 5'b10100;
  localparam logic [4:0] Funct5FcvtWS = 5'b11000;
  localparam logic [4:0] Funct5FcvtSW = 5'b11010;
  localparam logic [4:0] Funct5FmvXW = 5'b11100;  // Also FCLASS
  localparam logic [4:0] Funct5FmvWX = 5'b11110;

  localparam logic [1:0] FmtS = 2'b00;

endpackage

`default_nettype wire
