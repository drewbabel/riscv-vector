`default_nettype none

module fp_mul
  import fp_pkg::FlagNv, fp_pkg::FlagOf, fp_pkg::FlagUf, fp_pkg::FlagNx;
  import fp_pkg::fp_round_up, fp_pkg::fp_lzc, fp_pkg::FpLzcW, fp_pkg::fp_ovf_max;
  import fp_pkg::FlagW, fp_pkg::RmW;
  import fp_pkg::fp_canon_nan, fp_pkg::fp_inf_mag, fp_pkg::fp_max_mag;
#(
    parameter int ExpW = fp_pkg::ExpW,
    parameter int FracW = fp_pkg::FracW,
    localparam int FLEN = 1 + ExpW + FracW,
    localparam int Latency = fp_pkg::FpMulLatency
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              core_en,
    input  wire  [  RmW-1:0] rm,
    input  wire  [ FLEN-1:0] a,
    input  wire  [ FLEN-1:0] b,
    output logic [ FLEN-1:0] result,
    output logic [FlagW-1:0] fflags
);

  localparam int SigW = FracW + 1;
  localparam int Bias = (1 << (ExpW - 1)) - 1;
  localparam int ProdW = 2 * SigW;
  localparam int LzW = $clog2(ProdW);
  localparam int ExpSW = ExpW + 2;
  localparam int MaxRshift = SigW + 2;
  localparam int RshiftW = $clog2(MaxRshift + 1);
  localparam int AlignW = ProdW + MaxRshift;

  localparam int Stages = 3;
  localparam logic [FLEN-1:0] CanonNan = FLEN'(fp_canon_nan(ExpW, FracW));
  localparam logic [FLEN-2:0] InfMag = (FLEN - 1)'(fp_inf_mag(ExpW, FracW));
  localparam logic [FLEN-2:0] MaxMag = (FLEN - 1)'(fp_max_mag(ExpW, FracW));
  localparam logic [ExpW:0] ExpOverflow = {1'b0, {ExpW{1'b1}}};

  if (!(((2 * FracW) <= (3 * (1 << (ExpW - 1)) + 3)) && (ProdW <= FpLzcW))) begin : g_width_error
    $error("ExpW and FracW outside the supported range");
  end

  if (Stages != Latency) begin : g_latency_error
    $error("FpMulLatency must equal the three fp_mul stages");
  end

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

  // Signed biased exponents
  logic [ExpSW-1:0] exp_top;
  assign exp_top = ExpSW'(eff_exp_a) + ExpSW'(eff_exp_b) - ExpSW'(Bias - 1);

  logic [ProdW-1:0] prod_q1;
  logic [ExpSW-1:0] exp_top_q1;
  logic sign_q1;
  logic [RmW-1:0] rm_q1;
  logic nan_a_q1, nan_b_q1, invalid_q1, inf_a_q1, inf_b_q1, zero_a_q1, zero_b_q1;

  always_ff @(posedge clk) begin
    if (!rst_n) prod_q1 <= '0;
    else if (core_en) prod_q1 <= prod;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      exp_top_q1 <= '0;
      sign_q1    <= 1'b0;
      rm_q1      <= '0;
      nan_a_q1   <= 1'b0;
      nan_b_q1   <= 1'b0;
      invalid_q1 <= 1'b0;
      inf_a_q1   <= 1'b0;
      inf_b_q1   <= 1'b0;
      zero_a_q1  <= 1'b0;
      zero_b_q1  <= 1'b0;
    end else if (core_en) begin
      exp_top_q1 <= exp_top;
      sign_q1    <= sign;
      rm_q1      <= rm;
      nan_a_q1   <= nan_a;
      nan_b_q1   <= nan_b;
      invalid_q1 <= invalid;
      inf_a_q1   <= inf_a;
      inf_b_q1   <= inf_b;
      zero_a_q1  <= zero_a;
      zero_b_q1  <= zero_b;
    end
  end

  // Normalize leading one
  logic [LzW-1:0] lz;
  assign lz = LzW'(fp_lzc(FpLzcW'(prod_q1), ProdW));

  logic [ExpSW-1:0] exp_lz, rshift_full;
  assign exp_lz      = exp_top_q1 - ExpSW'(lz);
  assign rshift_full = ExpSW'(1) - exp_top_q1;

  logic normal, partial_left;
  assign normal       = !exp_lz[ExpSW-1] && (exp_lz != '0);
  assign partial_left = !exp_top_q1[ExpSW-1] && (exp_top_q1 != '0);

  logic [LzW-1:0] lshift;
  logic [RshiftW-1:0] rshift;
  logic [ExpW:0] exp_norm;
  always_comb begin
    lshift = '0;
    rshift = '0;
    if (normal) lshift = lz;
    else if (partial_left) lshift = exp_top_q1[LzW-1:0] - LzW'(1);
    else if (rshift_full > ExpSW'(MaxRshift)) rshift = RshiftW'(MaxRshift);
    else rshift = rshift_full[RshiftW-1:0];
  end
  assign exp_norm = normal ? exp_lz[ExpW:0] : (ExpW + 1)'(1);

  logic [ ProdW-1:0] norm;
  logic [AlignW-1:0] aligned;
  assign norm    = prod_q1 << lshift;
  assign aligned = {norm, {MaxRshift{1'b0}}} >> rshift;

  logic [SigW-1:0] mant;
  logic guard, round, sticky;
  assign mant   = aligned[AlignW-1-:SigW];
  assign guard  = aligned[ProdW+1];
  assign round  = aligned[ProdW];
  assign sticky = |aligned[ProdW-1:0];

  logic [SigW-1:0] mant_q2;
  logic guard_q2, round_q2, sticky_q2;
  logic [ExpW:0] exp_norm_q2;
  logic sign_q2;
  logic [RmW-1:0] rm_q2;
  logic nan_a_q2, nan_b_q2, invalid_q2, inf_a_q2, inf_b_q2, zero_a_q2, zero_b_q2;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mant_q2     <= '0;
      guard_q2    <= 1'b0;
      round_q2    <= 1'b0;
      sticky_q2   <= 1'b0;
      exp_norm_q2 <= '0;
      sign_q2     <= 1'b0;
      rm_q2       <= '0;
      nan_a_q2    <= 1'b0;
      nan_b_q2    <= 1'b0;
      invalid_q2  <= 1'b0;
      inf_a_q2    <= 1'b0;
      inf_b_q2    <= 1'b0;
      zero_a_q2   <= 1'b0;
      zero_b_q2   <= 1'b0;
    end else if (core_en) begin
      mant_q2     <= mant;
      guard_q2    <= guard;
      round_q2    <= round;
      sticky_q2   <= sticky;
      exp_norm_q2 <= exp_norm;
      sign_q2     <= sign_q1;
      rm_q2       <= rm_q1;
      nan_a_q2    <= nan_a_q1;
      nan_b_q2    <= nan_b_q1;
      invalid_q2  <= invalid_q1;
      inf_a_q2    <= inf_a_q1;
      inf_b_q2    <= inf_b_q1;
      zero_a_q2   <= zero_a_q1;
      zero_b_q2   <= zero_b_q1;
    end
  end

  logic inc, inc_unbounded;
  assign inc = fp_round_up(rm_q2, sign_q2, mant_q2[0], guard_q2, round_q2 || sticky_q2);
  // Tininess after rounding
  assign inc_unbounded = fp_round_up(rm_q2, sign_q2, guard_q2, round_q2, sticky_q2);

  logic [FLEN-1:0] rounded, finite;
  assign rounded = {exp_norm_q2 - (ExpW + 1)'(1), {FracW{1'b0}}} + {{ExpW{1'b0}}, mant_q2} +
      FLEN'(inc);
  assign finite = {sign_q2, rounded[FLEN-2:0]};

  logic inexact, overflow, tiny, overflow_to_max;
  assign inexact         = guard_q2 || round_q2 || sticky_q2;
  assign overflow        = rounded[FLEN-1:FracW] >= ExpOverflow;
  assign tiny            = !mant_q2[SigW-1] && !((&mant_q2[SigW-2:0]) && guard_q2 && inc_unbounded);

  assign overflow_to_max = fp_ovf_max(rm_q2, sign_q2);

  logic [ FLEN-1:0] result_next;
  logic [FlagW-1:0] fflags_next;

  always_comb begin
    result_next = finite;
    fflags_next = '0;
    if (tiny && inexact) fflags_next = fflags_next | FlagUf;
    if (inexact) fflags_next = fflags_next | FlagNx;
    if (nan_a_q2 || nan_b_q2 || invalid_q2) begin
      result_next = CanonNan;
      fflags_next = invalid_q2 ? FlagNv : '0;
    end else if (inf_a_q2 || inf_b_q2) begin
      result_next = {sign_q2, InfMag};
      fflags_next = '0;
    end else if (zero_a_q2 || zero_b_q2) begin
      result_next = {sign_q2, {(FLEN - 1) {1'b0}}};
      fflags_next = '0;
    end else if (overflow) begin
      result_next = {sign_q2, overflow_to_max ? MaxMag : InfMag};
      fflags_next = FlagOf | FlagNx;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      result <= '0;
      fflags <= '0;
    end else if (core_en) begin
      result <= result_next;
      fflags <= fflags_next;
    end
  end

endmodule

`default_nettype wire
