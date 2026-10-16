`default_nettype none

package fp_pkg;

  parameter int ExpW = 8;
  parameter int FracW = 23;
  parameter int FLEN = 1 + ExpW + FracW;
  parameter int SigW = FracW + 1;
  parameter int Bias = (1 << (ExpW - 1)) - 1;

  localparam logic [2:0] RmRne = 3'b000;
  localparam logic [2:0] RmRtz = 3'b001;
  localparam logic [2:0] RmRdn = 3'b010;
  localparam logic [2:0] RmRup = 3'b011;
  localparam logic [2:0] RmRmm = 3'b100;
  localparam logic [2:0] RmDyn = 3'b111;

  localparam logic [4:0] FlagNv = 5'b10000;
  localparam logic [4:0] FlagDz = 5'b01000;
  localparam logic [4:0] FlagOf = 5'b00100;
  localparam logic [4:0] FlagUf = 5'b00010;
  localparam logic [4:0] FlagNx = 5'b00001;

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
  localparam logic [4:0] Funct5FmvXW = 5'b11100;
  localparam logic [4:0] Funct5FmvWX = 5'b11110;

  localparam logic [2:0] Funct3Fsgnj = 3'b000;
  localparam logic [2:0] Funct3Fsgnjn = 3'b001;
  localparam logic [2:0] Funct3Fsgnjx = 3'b010;
  localparam logic [2:0] Funct3Fmin = 3'b000;
  localparam logic [2:0] Funct3Fmax = 3'b001;
  localparam logic [2:0] Funct3Fle = 3'b000;
  localparam logic [2:0] Funct3Flt = 3'b001;
  localparam logic [2:0] Funct3Feq = 3'b010;
  localparam logic [2:0] Funct3Fmv = 3'b000;
  localparam logic [2:0] Funct3Fclass = 3'b001;

  localparam logic [1:0] FmtS = 2'b00;

  localparam logic [4:0] Rs2Zero = 5'b00000;
  localparam logic [4:0] Rs2CvtW = 5'b00000;
  localparam logic [4:0] Rs2CvtWu = 5'b00001;

  function automatic logic fp_round_up(input logic [2:0] rm, input logic neg, input logic lsb,
                                       input logic guard, input logic sticky);
    case (rm)
      RmRne:   fp_round_up = guard && (sticky || lsb);
      RmRtz:   fp_round_up = 1'b0;
      RmRdn:   fp_round_up = neg && (guard || sticky);
      RmRup:   fp_round_up = !neg && (guard || sticky);
      RmRmm:   fp_round_up = guard;
      default: fp_round_up = 1'b0;
    endcase
  endfunction

  localparam int FpLzcW = 128;

  function automatic int fp_lzc(input logic [FpLzcW-1:0] x, input int width);
    fp_lzc = 0;
    for (int i = 0; i < FpLzcW; i++) begin
      if ((i < width) && x[i]) fp_lzc = width - 1 - i;
    end
  endfunction

endpackage

`default_nettype wire
