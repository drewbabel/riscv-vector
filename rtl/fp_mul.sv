`default_nettype none

module fp_mul
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNv, fp_pkg::FlagOf, fp_pkg::FlagUf, fp_pkg::FlagNx;
#(
    parameter  int ExpW  = fp_pkg::ExpW,
    parameter  int FracW = fp_pkg::FracW,
    localparam int FLEN  = 1 + ExpW + FracW
) (
    input  wire  [     2:0] rm,
    input  wire  [FLEN-1:0] a,
    input  wire  [FLEN-1:0] b,
    output logic [FLEN-1:0] result,
    output logic [     4:0] fflags
);

  localparam int SigW = FracW + 1;
  localparam int Bias = (1 << (ExpW - 1)) - 1;
  localparam int ProdW = 2 * SigW;
  localparam int LzW = $clog2(ProdW);
  localparam int ExpSW = ExpW + 2;
  localparam int MaxRshift = SigW + 2;
  localparam int RshiftW = $clog2(MaxRshift + 1);
  localparam int AlignW = ProdW + MaxRshift;

  localparam logic [FLEN-1:0] CanonicalNan = {1'b0, {ExpW{1'b1}}, 1'b1, {(FracW - 1) {1'b0}}};
  localparam logic [FLEN-2:0] InfMag = {{ExpW{1'b1}}, {FracW{1'b0}}};
  localparam logic [FLEN-2:0] MaxFiniteMag = {{(ExpW - 1) {1'b1}}, 1'b0, {FracW{1'b1}}};
  localparam logic [ExpW:0] ExpOverflow = {1'b0, {ExpW{1'b1}}};

  function automatic logic round_up(input logic [2:0] mode, input logic neg, input logic lsb,
                                    input logic half, input logic rest);
    case (mode)
      RmRne:   round_up = half && (rest || lsb);
      RmRtz:   round_up = 1'b0;
      RmRdn:   round_up = neg && (half || rest);
      RmRup:   round_up = !neg && (half || rest);
      RmRmm:   round_up = half;
      default: round_up = 1'b0;
    endcase
  endfunction

  logic sign_a, sign_b, sign;
  logic [ExpW-1:0] exp_a, exp_b;
  logic [FracW-1:0] frac_a, frac_b;
  assign {sign_a, exp_a, frac_a} = a;
  assign {sign_b, exp_b, frac_b} = b;
  assign sign = sign_a ^ sign_b;

  logic zero_a, zero_b, inf_a, inf_b, nan_a, nan_b, snan_a, snan_b;
  assign zero_a = (exp_a == '0) && (frac_a == '0);
  assign zero_b = (exp_b == '0) && (frac_b == '0);
  assign inf_a  = (exp_a == '1) && (frac_a == '0);
  assign inf_b  = (exp_b == '1) && (frac_b == '0);
  assign nan_a  = (exp_a == '1) && (frac_a != '0);
  assign nan_b  = (exp_b == '1) && (frac_b != '0);
  assign snan_a = nan_a && !frac_a[FracW-1];
  assign snan_b = nan_b && !frac_b[FracW-1];

  logic invalid;
  assign invalid = snan_a || snan_b || (inf_a && zero_b) || (zero_a && inf_b);

  logic [ExpW-1:0] eff_exp_a, eff_exp_b;
  logic [SigW-1:0] sig_a, sig_b;
  assign eff_exp_a = (exp_a == '0) ? ExpW'(1) : exp_a;
  assign eff_exp_b = (exp_b == '0) ? ExpW'(1) : exp_b;
  assign sig_a = {exp_a != '0, frac_a};
  assign sig_b = {exp_b != '0, frac_b};

  logic [ProdW-1:0] prod;
  assign prod = {{SigW{1'b0}}, sig_a} * {{SigW{1'b0}}, sig_b};

  logic [LzW-1:0] lz;
  always_comb begin
    lz = '0;
    for (int i = 0; i < ProdW; i++) begin
      if (prod[i]) lz = LzW'(ProdW - 1 - i);
    end
  end

  logic [ExpSW-1:0] exp_top, exp_lz, rshift_full;
  assign exp_top     = ExpSW'(eff_exp_a) + ExpSW'(eff_exp_b) - ExpSW'(Bias - 1);
  assign exp_lz      = exp_top - ExpSW'(lz);
  assign rshift_full = ExpSW'(1) - exp_top;

  logic normal, partial_left;
  assign normal       = !exp_lz[ExpSW-1] && (exp_lz != '0);
  assign partial_left = !exp_top[ExpSW-1] && (exp_top != '0);

  logic [LzW-1:0] lshift;
  logic [RshiftW-1:0] rshift;
  logic [ExpW:0] exp_norm;
  assign lshift = normal ? lz : (partial_left ? exp_top[LzW-1:0] - LzW'(1) : '0);
  assign rshift = (normal || partial_left) ? '0
      : ((rshift_full > ExpSW'(MaxRshift)) ? RshiftW'(MaxRshift) : rshift_full[RshiftW-1:0]);
  assign exp_norm = normal ? exp_lz[ExpW:0] : (ExpW + 1)'(1);

  logic [ ProdW-1:0] norm;
  logic [AlignW-1:0] aligned;
  assign norm    = prod << lshift;
  assign aligned = {norm, {MaxRshift{1'b0}}} >> rshift;

  logic [SigW-1:0] mant;
  logic guard, round, sticky;
  assign mant   = aligned[AlignW-1-:SigW];
  assign guard  = aligned[ProdW+1];
  assign round  = aligned[ProdW];
  assign sticky = |aligned[ProdW-1:0];

  logic inc, inc_unbounded;
  assign inc = round_up(rm, sign, mant[0], guard, round || sticky);
  assign inc_unbounded = round_up(rm, sign, guard, round, sticky);

  logic [FLEN-1:0] rounded, finite;
  assign rounded = {exp_norm - (ExpW + 1)'(1), {FracW{1'b0}}} + {{ExpW{1'b0}}, mant} + FLEN'(inc);
  assign finite  = {sign, rounded[FLEN-2:0]};

  logic inexact, overflow, tiny, overflow_to_inf;
  assign inexact  = guard || round || sticky;
  assign overflow = rounded[FLEN-1:FracW] >= ExpOverflow;
  assign tiny     = !mant[SigW-1] && !((&mant[SigW-2:0]) && guard && inc_unbounded);

  always_comb begin
    case (rm)
      RmRtz:   overflow_to_inf = 1'b0;
      RmRdn:   overflow_to_inf = sign;
      RmRup:   overflow_to_inf = !sign;
      default: overflow_to_inf = 1'b1;
    endcase
  end

  always_comb begin
    result = finite;
    fflags = (tiny && inexact ? FlagUf : '0) | (inexact ? FlagNx : '0);
    if (nan_a || nan_b || invalid) begin
      result = CanonicalNan;
      fflags = invalid ? FlagNv : '0;
    end else if (inf_a || inf_b) begin
      result = {sign, InfMag};
      fflags = '0;
    end else if (zero_a || zero_b) begin
      result = {sign, {(FLEN - 1) {1'b0}}};
      fflags = '0;
    end else if (overflow) begin
      result = overflow_to_inf ? {sign, InfMag} : {sign, MaxFiniteMag};
      fflags = FlagOf | FlagNx;
    end
  end

endmodule

`default_nettype wire
