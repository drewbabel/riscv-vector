`default_nettype none

module fp_rec7
  import fp_pkg::FlagNv, fp_pkg::FlagDz, fp_pkg::FlagOf, fp_pkg::FlagNx;
  import fp_pkg::fp_lzc, fp_pkg::FpLzcW, fp_pkg::fp_ovf_max;
  import fp_pkg::FlagW, fp_pkg::RmW;
  import fp_pkg::fp_canon_nan, fp_pkg::fp_inf_mag, fp_pkg::fp_max_mag;
#(
    parameter  int ExpW  = fp_pkg::ExpW,
    parameter  int FracW = fp_pkg::FracW,
    localparam int FLEN  = 1 + ExpW + FracW
) (
    input  wire              sqrt,
    input  wire  [  RmW-1:0] rm,
    input  wire  [ FLEN-1:0] a,
    output logic [ FLEN-1:0] result,
    output logic [FlagW-1:0] fflags
);

  localparam int Bias = (1 << (ExpW - 1)) - 1;
  localparam int LzW = $clog2(FracW + 1);
  localparam logic [ExpW:0] RsqBase = (ExpW + 1)'(3 * Bias - 1);
  localparam logic [ExpW-1:0] RecBase = ExpW'(2 * Bias - 1);
  localparam logic [FLEN-1:0] CanonNan = FLEN'(fp_canon_nan(ExpW, FracW));
  localparam logic [FLEN-2:0] InfMag = (FLEN - 1)'(fp_inf_mag(ExpW, FracW));
  localparam logic [FLEN-2:0] MaxMag = (FLEN - 1)'(fp_max_mag(ExpW, FracW));

  if (!((FracW >= 10) && (FracW <= FpLzcW))) begin : g_width_error
    $error("ExpW and FracW outside the supported range");
  end

  logic             sign;
  logic [ ExpW-1:0] exp_in;
  logic [FracW-1:0] frac;
  logic             is_nan;
  logic             is_snan;
  logic             is_inf;
  logic             is_zero;
  logic             is_sub;
  logic [  LzW-1:0] lz;
  logic [      6:0] norm_top;
  logic             norm_exp_lsb;
  logic [      6:0] rsq_idx;
  logic [      6:0] rec_lut;
  logic [      6:0] rsq_lut;
  logic [ ExpW-1:0] rsq_exp;
  logic [ ExpW-1:0] rec_exp;
  logic             rec_ovf;
  logic             rec_den;
  logic [FracW-1:0] rec_den_sig;
  logic             rec_max;

  assign sign = a[FLEN-1];
  assign exp_in = a[FLEN-2:FracW];
  assign frac = a[FracW-1:0];

  assign is_nan = (exp_in == '1) && (frac != '0);
  assign is_snan = is_nan && !frac[FracW-1];
  assign is_inf = (exp_in == '1) && (frac == '0);
  assign is_zero = (exp_in == '0) && (frac == '0);
  assign is_sub = (exp_in == '0) && (frac != '0);

  assign lz = LzW'(fp_lzc(FpLzcW'(frac), FracW));

  // Normalize subnormal significand
  assign norm_top = is_sub ? 7'({frac, 7'b0} >> (LzW'(FracW - 1) - lz)) : frac[FracW-1:FracW-7];
  assign norm_exp_lsb = is_sub ? lz[0] : exp_in[0];
  assign rsq_idx = {norm_exp_lsb, norm_top[6:1]};

  assign rsq_exp = is_sub ? ExpW'((RsqBase + (ExpW + 1)'(lz)) >> 1) :
      ExpW'((RsqBase - (ExpW + 1)'(exp_in)) >> 1);

  assign rec_exp = is_sub ? (RecBase + ExpW'(lz)) : (RecBase - exp_in);
  assign rec_ovf = is_sub && (frac[FracW-1:FracW-2] == 2'b00);
  assign rec_den = !is_sub && (exp_in >= RecBase);
  assign rec_den_sig = (exp_in == ExpW'(2 * Bias)) ?
      {2'b01, rec_lut, {(FracW - 9) {1'b0}}} : {1'b1, rec_lut, {(FracW - 8) {1'b0}}};
  assign rec_max = fp_ovf_max(rm, sign);

  // Reciprocal table entry
  function automatic logic [6:0] rec_entry(input int i);
    int d;
    d = 257 + 2 * i;
    rec_entry = 7'(((1 << 17) + d) / (2 * d) - 128);
  endfunction

  // Root table entry
  function automatic logic [6:0] rsq_entry(input int idx);
    int q;
    int n;
    q = (129 + 2 * (idx % 64)) << ((idx < 64) ? 1 : 0);
    n = 255;
    for (int k = 254; k >= 128; k--) begin
      if ((2 * k + 1) * (2 * k + 1) * q > (1 << 25)) n = k;
    end
    rsq_entry = 7'(n - 128);
  endfunction

  logic [6:0] rec_tab[128];
  logic [6:0] rsq_tab[128];

  for (genvar i = 0; i < 128; i++) begin : g_tab
    assign rec_tab[i] = rec_entry(i);
    assign rsq_tab[i] = rsq_entry(i);
  end

  assign rec_lut = rec_tab[norm_top];
  assign rsq_lut = rsq_tab[rsq_idx];

  always_comb begin
    result = '0;
    fflags = '0;
    if (is_nan) begin
      result = CanonNan;
      fflags = is_snan ? FlagNv : '0;
    end else if (is_zero) begin
      result = {sign, InfMag};
      fflags = FlagDz;
    end else if (sqrt) begin
      if (sign) begin
        result = CanonNan;
        fflags = FlagNv;
      end else if (!is_inf) begin
        result = {1'b0, rsq_exp, rsq_lut, {(FracW - 7) {1'b0}}};
      end
    end else if (is_inf) begin
      result = {sign, {(FLEN - 1) {1'b0}}};
    end else if (rec_ovf) begin
      result = {sign, rec_max ? MaxMag : InfMag};
      fflags = FlagOf | FlagNx;
    end else if (rec_den) begin
      result = {sign, {ExpW{1'b0}}, rec_den_sig};
    end else begin
      result = {sign, rec_exp, rec_lut, {(FracW - 7) {1'b0}}};
    end
  end

endmodule

`default_nettype wire
