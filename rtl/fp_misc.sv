`default_nettype none

module fp_misc
  import fp_pkg::Funct5Fsgnj, fp_pkg::Funct5Fminmax, fp_pkg::Funct5Fcmp, fp_pkg::Funct5FmvXW;
  import fp_pkg::Funct3Fsgnj, fp_pkg::Funct3Fsgnjn, fp_pkg::Funct3Fsgnjx;
  import fp_pkg::Funct3Fmin, fp_pkg::Funct3Fmax;
  import fp_pkg::Funct3Fle, fp_pkg::Funct3Flt, fp_pkg::Funct3Feq, fp_pkg::Funct3Fclass;
  import fp_pkg::FlagNv;
#(
    parameter  int ExpW  = fp_pkg::ExpW,
    parameter  int FracW = fp_pkg::FracW,
    localparam int FLEN  = 1 + ExpW + FracW
) (
    input  wire  [     4:0] funct5,
    input  wire  [     2:0] funct3,
    input  wire  [FLEN-1:0] a,
    input  wire  [FLEN-1:0] b,
    output logic [FLEN-1:0] result,
    output logic [     4:0] fflags
);

  localparam int OpW = $bits(Funct5Fsgnj) + $bits(Funct3Fsgnj);
  localparam int QuietBit = FracW - 1;

  localparam logic [OpW-1:0] OpFsgnj = {Funct5Fsgnj, Funct3Fsgnj};
  localparam logic [OpW-1:0] OpFsgnjn = {Funct5Fsgnj, Funct3Fsgnjn};
  localparam logic [OpW-1:0] OpFsgnjx = {Funct5Fsgnj, Funct3Fsgnjx};
  localparam logic [OpW-1:0] OpFmin = {Funct5Fminmax, Funct3Fmin};
  localparam logic [OpW-1:0] OpFmax = {Funct5Fminmax, Funct3Fmax};
  localparam logic [OpW-1:0] OpFeq = {Funct5Fcmp, Funct3Feq};
  localparam logic [OpW-1:0] OpFlt = {Funct5Fcmp, Funct3Flt};
  localparam logic [OpW-1:0] OpFle = {Funct5Fcmp, Funct3Fle};
  localparam logic [OpW-1:0] OpFclass = {Funct5FmvXW, Funct3Fclass};

  localparam logic [FLEN-1:0] CanonNan = {1'b0, {ExpW{1'b1}}, 1'b1, {(FracW - 1) {1'b0}}};

  if (!((FracW >= 2) && (FLEN >= 10))) begin : g_width_error
    $error("ExpW and FracW outside the supported range");
  end

  logic a_sign, b_sign;
  logic [ExpW-1:0] a_exp, b_exp;
  logic [FracW-1:0] a_frac, b_frac;
  logic [FLEN-2:0] a_mag, b_mag;
  logic a_exp_max, b_exp_max;
  logic a_exp_zero;
  logic a_man_zero, b_man_zero;

  assign {a_sign, a_exp, a_frac} = a;
  assign {b_sign, b_exp, b_frac} = b;

  assign a_mag = {a_exp, a_frac};
  assign b_mag = {b_exp, b_frac};
  assign a_exp_max = &a_exp;
  assign b_exp_max = &b_exp;
  assign a_exp_zero = ~|a_exp;
  assign a_man_zero = ~|a_frac;
  assign b_man_zero = ~|b_frac;

  logic a_nan, b_nan, a_snan, b_snan, any_nan, any_snan;

  assign a_nan    = a_exp_max & ~a_man_zero;
  assign b_nan    = b_exp_max & ~b_man_zero;
  assign a_snan   = a_nan & ~a_frac[QuietBit];
  assign b_snan   = b_nan & ~b_frac[QuietBit];
  assign any_nan  = a_nan | b_nan;
  assign any_snan = a_snan | b_snan;

  logic mag_lt, mag_gt, both_zero, ord_lt, ord_eq;

  assign mag_lt    = a_mag < b_mag;
  assign mag_gt    = a_mag > b_mag;
  assign both_zero = ~|a_mag & ~|b_mag;

  // Ordered less than
  always_comb begin
    if (a_sign != b_sign) ord_lt = a_sign;
    else if (a_sign) ord_lt = mag_gt;
    else ord_lt = mag_lt;
  end

  assign ord_eq = (a == b) | both_zero;

  logic feq, flt, fle;

  assign feq = ~any_nan & ord_eq;
  assign flt = ~any_nan & ord_lt & ~both_zero;
  assign fle = ~any_nan & (ord_lt | ord_eq);

  // Minimum and maximum
  logic [FLEN-1:0] fmin, fmax;

  always_comb begin
    if (a_nan & b_nan) begin
      fmin = CanonNan;
      fmax = CanonNan;
    end else if (a_nan) begin
      fmin = b;
      fmax = b;
    end else if (b_nan) begin
      fmin = a;
      fmax = a;
    end else begin
      fmin = ord_lt ? a : b;
      fmax = ord_lt ? b : a;
    end
  end

  // Class bits
  logic a_inf, a_zero, a_sub, a_norm;
  logic [9:0] fclass;

  assign a_inf = a_exp_max & a_man_zero;
  assign a_zero = a_exp_zero & a_man_zero;
  assign a_sub = a_exp_zero & ~a_man_zero;
  assign a_norm = ~a_exp_zero & ~a_exp_max;

  assign fclass = {
    a_nan & a_frac[QuietBit],
    a_snan,
    ~a_sign & a_inf,
    ~a_sign & a_norm,
    ~a_sign & a_sub,
    ~a_sign & a_zero,
    a_sign & a_zero,
    a_sign & a_sub,
    a_sign & a_norm,
    a_sign & a_inf
  };

  always_comb begin
    result = '0;
    fflags = '0;
    case ({
      funct5, funct3
    })
      OpFsgnj:  result = {b_sign, a_mag};
      OpFsgnjn: result = {~b_sign, a_mag};
      OpFsgnjx: result = {a_sign ^ b_sign, a_mag};
      OpFmin: begin
        result = fmin;
        fflags = any_snan ? FlagNv : '0;
      end
      OpFmax: begin
        result = fmax;
        fflags = any_snan ? FlagNv : '0;
      end
      OpFeq: begin
        result = FLEN'(feq);
        fflags = any_snan ? FlagNv : '0;
      end
      OpFlt: begin
        result = FLEN'(flt);
        fflags = any_nan ? FlagNv : '0;
      end
      OpFle: begin
        result = FLEN'(fle);
        fflags = any_nan ? FlagNv : '0;
      end
      OpFclass: result = FLEN'(fclass);
      default:  ;
    endcase
  end

endmodule

`default_nettype wire
