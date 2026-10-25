`default_nettype none

module fp_cvt
  import fp_pkg::FlagNv, fp_pkg::FlagNx, fp_pkg::fp_round_up, fp_pkg::fp_lzc, fp_pkg::FpLzcW;
  import fp_pkg::FlagW, fp_pkg::RmW;
#(
    parameter  int XLEN  = arch_pkg::XLEN,
    parameter  int ExpW  = fp_pkg::ExpW,
    parameter  int FracW = fp_pkg::FracW,
    localparam int FLEN  = 1 + ExpW + FracW,
    localparam int OpW   = (FLEN > XLEN) ? FLEN : XLEN
) (
    input  wire              to_int,
    input  wire              is_unsigned,
    input  wire              half,
    input  wire  [  RmW-1:0] rm,
    input  wire  [  OpW-1:0] a,
    output logic [  OpW-1:0] result,
    output logic [FlagW-1:0] fflags
);

  localparam int SigW = FracW + 1;
  localparam int Bias = (1 << (ExpW - 1)) - 1;
  localparam int HalfW = XLEN / 2;
  localparam int FixW = SigW + XLEN;
  localparam int ShW = $clog2(XLEN + 1);
  localparam int LzW = $clog2(XLEN);
  localparam int WideW = XLEN + SigW + 1;

  localparam logic [ExpW-1:0] ExpBig = ExpW'(Bias + XLEN);
  localparam logic [ExpW-1:0] ExpTiny = ExpW'(Bias - 1);
  localparam logic [ExpW-1:0] ExpTop = ExpW'(Bias + XLEN - 1);

  localparam logic [XLEN-1:0] UMax = {XLEN{1'b1}};
  localparam logic [XLEN-1:0] SMax = {1'b0, {(XLEN - 1) {1'b1}}};
  localparam logic [XLEN-1:0] SMin = {1'b1, {(XLEN - 1) {1'b0}}};
  localparam logic [XLEN-1:0] UMaxHalf = {{(XLEN - HalfW) {1'b0}}, {HalfW{1'b1}}};
  localparam logic [XLEN-1:0] SMaxHalf = {{(XLEN - HalfW + 1) {1'b0}}, {(HalfW - 1) {1'b1}}};
  localparam logic [XLEN-1:0] SMinHalf = {{(XLEN - HalfW) {1'b0}}, 1'b1, {(HalfW - 1) {1'b0}}};

  if (!(((Bias + XLEN) <= ((1 << ExpW) - 2)) && (XLEN <= FpLzcW))) begin : g_width_error
    $error("ExpW and FracW outside the supported range");
  end

  // Float to integer
  logic             f_sign;
  logic [ ExpW-1:0] f_exp;
  logic [FracW-1:0] f_frac;
  logic [ SigW-1:0] f_sig;
  logic             f_nan;
  logic             f_big;
  logic             f_tiny;
  logic [ FixW-1:0] f_fix;
  logic [ XLEN-1:0] f_int;
  logic             f_guard;
  logic             f_sticky;
  logic             f_inc;
  logic [   XLEN:0] f_mag;
  logic [ XLEN-1:0] f_pos_max;
  logic [ XLEN-1:0] f_neg_max;
  logic             f_nv;
  logic [ XLEN-1:0] f_full;
  logic [ XLEN-1:0] f_res;
  logic [FlagW-1:0] f_flags;

  assign f_sign = a[FLEN-1];
  assign f_exp = a[FLEN-2:FracW];
  assign f_frac = a[FracW-1:0];
  assign f_sig = {f_exp != '0, f_frac};
  assign f_nan = (f_exp == '1) && (f_frac != '0);

  assign f_big = f_exp >= ExpBig;
  assign f_tiny = f_exp < ExpTiny;

  assign f_fix = f_tiny ? '0 : (FixW'(f_sig) << ShW'(f_exp - ExpTiny));
  assign f_int = f_fix[FixW-1:SigW];
  assign f_guard = f_fix[SigW-1];
  assign f_sticky = (f_fix[SigW-2:0] != '0) || (f_tiny && (a[FLEN-2:0] != '0));

  assign f_inc = fp_round_up(rm, f_sign, f_int[0], f_guard, f_sticky);
  assign f_mag = {1'b0, f_int} + (XLEN + 1)'(f_inc);

  // Destination bounds
  always_comb begin
    if (is_unsigned) begin
      f_pos_max = half ? UMaxHalf : UMax;
      f_neg_max = '0;
    end else begin
      f_pos_max = half ? SMaxHalf : SMax;
      f_neg_max = half ? SMinHalf : SMin;
    end
  end

  assign f_nv = f_nan || f_big || (f_mag > {1'b0, f_sign ? f_neg_max : f_pos_max});

  always_comb begin
    if (f_nv) begin
      f_full  = (f_nan || !f_sign) ? f_pos_max : f_neg_max;
      f_flags = FlagNv;
    end else begin
      f_full  = f_sign ? -f_mag[XLEN-1:0] : f_mag[XLEN-1:0];
      f_flags = (f_guard || f_sticky) ? FlagNx : '0;
    end
  end

  assign f_res = half ? {{(XLEN - HalfW) {1'b0}}, f_full[HalfW-1:0]} : f_full;

  // Integer to float
  logic [      XLEN-1:0] i_val;
  logic                  i_sign;
  logic [      XLEN-1:0] i_mag;
  logic [      XLEN-1:0] i_norm;
  logic [       LzW-1:0] i_lz;
  logic [     WideW-1:0] i_wide;
  logic                  i_guard;
  logic                  i_sticky;
  logic                  i_inc;
  logic [ExpW+FracW-1:0] i_body;
  logic [      FLEN-1:0] i_res;
  logic [     FlagW-1:0] i_flags;

  assign i_val = half ? {{(XLEN - HalfW) {a[HalfW-1] && !is_unsigned}}, a[HalfW-1:0]} : a[XLEN-1:0];
  assign i_sign = !is_unsigned && i_val[XLEN-1];
  assign i_mag = i_sign ? -i_val : i_val;

  // Normalize leading one
  assign i_lz = LzW'(fp_lzc(FpLzcW'(i_mag), XLEN));
  assign i_norm = i_mag << i_lz;

  assign i_wide = {i_norm, {(SigW + 1) {1'b0}}};
  assign i_guard = i_wide[XLEN];
  assign i_sticky = i_wide[XLEN-1:0] != '0;

  // Pack and round
  assign i_inc = fp_round_up(rm, i_sign, i_wide[XLEN+1], i_guard, i_sticky);
  assign i_body = {ExpTop - ExpW'(i_lz), i_wide[WideW-2-:FracW]} + (FLEN - 1)'(i_inc);

  assign i_res = (i_mag == '0) ? '0 : {i_sign, i_body};
  assign i_flags = (i_guard || i_sticky) ? FlagNx : '0;

  assign result = to_int ? OpW'(f_res) : OpW'(i_res);
  assign fflags = to_int ? f_flags : i_flags;

endmodule

`default_nettype wire
