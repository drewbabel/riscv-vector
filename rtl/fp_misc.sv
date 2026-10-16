`default_nettype none

module fp_misc (
    input  wire  [ 4:0] funct5,
    input  wire  [ 2:0] funct3,
    input  wire  [31:0] a,
    input  wire  [31:0] b,
    output logic [31:0] result,
    output logic [ 4:0] fflags
);

  localparam logic [7:0] OpFsgnj = 8'b00100_000;
  localparam logic [7:0] OpFsgnjn = 8'b00100_001;
  localparam logic [7:0] OpFsgnjx = 8'b00100_010;
  localparam logic [7:0] OpFmin = 8'b00101_000;
  localparam logic [7:0] OpFmax = 8'b00101_001;
  localparam logic [7:0] OpFeq = 8'b10100_010;
  localparam logic [7:0] OpFlt = 8'b10100_001;
  localparam logic [7:0] OpFle = 8'b10100_000;
  localparam logic [7:0] OpFclass = 8'b11100_001;

  localparam logic [31:0] CanonicalNan = 32'h7FC0_0000;

  logic a_sign, b_sign;
  logic [30:0] a_mag, b_mag;
  logic a_exp_max, b_exp_max;
  logic a_exp_zero;
  logic a_man_zero, b_man_zero;

  assign a_sign     = a[31];
  assign b_sign     = b[31];
  assign a_mag      = a[30:0];
  assign b_mag      = b[30:0];
  assign a_exp_max  = &a[30:23];
  assign b_exp_max  = &b[30:23];
  assign a_exp_zero = ~|a[30:23];
  assign a_man_zero = ~|a[22:0];
  assign b_man_zero = ~|b[22:0];

  // Bit 22 quiet
  logic a_nan, b_nan, a_snan, b_snan, any_nan, any_snan;

  assign a_nan    = a_exp_max & ~a_man_zero;
  assign b_nan    = b_exp_max & ~b_man_zero;
  assign a_snan   = a_nan & ~a[22];
  assign b_snan   = b_nan & ~b[22];
  assign any_nan  = a_nan | b_nan;
  assign any_snan = a_snan | b_snan;

  logic mag_lt, mag_gt, both_zero, ord_lt, ord_eq;

  assign mag_lt    = a_mag < b_mag;
  assign mag_gt    = a_mag > b_mag;
  assign both_zero = ~|a_mag & ~|b_mag;

  // Negative zero first
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

  logic [31:0] fmin, fmax;

  always_comb begin
    if (a_nan & b_nan) begin
      fmin = CanonicalNan;
      fmax = CanonicalNan;
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

  logic a_inf, a_zero, a_sub, a_norm;
  logic [9:0] fclass;

  assign a_inf = a_exp_max & a_man_zero;
  assign a_zero = a_exp_zero & a_man_zero;
  assign a_sub = a_exp_zero & ~a_man_zero;
  assign a_norm = ~a_exp_zero & ~a_exp_max;

  assign fclass = {
    a_nan & a[22],
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
    result = 32'b0;
    fflags = 5'b0;
    case ({
      funct5, funct3
    })
      OpFsgnj:  result = {b_sign, a_mag};
      OpFsgnjn: result = {~b_sign, a_mag};
      OpFsgnjx: result = {a_sign ^ b_sign, a_mag};
      OpFmin: begin
        result    = fmin;
        fflags[4] = any_snan;
      end
      OpFmax: begin
        result    = fmax;
        fflags[4] = any_snan;
      end
      OpFeq: begin
        result    = {31'b0, feq};
        fflags[4] = any_snan;
      end
      OpFlt: begin
        result    = {31'b0, flt};
        fflags[4] = any_nan;
      end
      OpFle: begin
        result    = {31'b0, fle};
        fflags[4] = any_nan;
      end
      OpFclass: result = {22'b0, fclass};
      default:  ;
    endcase
  end

endmodule

`default_nettype wire
