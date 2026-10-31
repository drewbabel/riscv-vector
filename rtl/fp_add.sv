`default_nettype none

module fp_add
  import fp_pkg::RmRdn, fp_pkg::RmW;
  import fp_pkg::FlagNv, fp_pkg::FlagOf, fp_pkg::FlagUf, fp_pkg::FlagNx, fp_pkg::FlagW;
  import fp_pkg::fp_round_up, fp_pkg::fp_lzc, fp_pkg::FpLzcW, fp_pkg::fp_ovf_max;
  import fp_pkg::fp_canon_nan, fp_pkg::fp_inf_mag, fp_pkg::fp_max_mag;
#(
    parameter int ExpW = fp_pkg::ExpW,
    parameter int FracW = fp_pkg::FracW,
    localparam int FLEN = 1 + ExpW + FracW,
    localparam int Latency = fp_pkg::FpAddLatency
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              core_en,
    input  wire              sub,
    input  wire  [  RmW-1:0] rm,
    input  wire  [ FLEN-1:0] a,
    input  wire  [ FLEN-1:0] b,
    output logic [ FLEN-1:0] result,
    output logic [FlagW-1:0] fflags
);

  localparam int SigW = FracW + 1;
  localparam int GrsW = 3;
  localparam int AlignW = SigW + GrsW;
  localparam int SumW = AlignW + 1;
  localparam int WideW = 2 * AlignW;
  localparam int ShW = $clog2(AlignW + 1);
  localparam int LzW = $clog2(AlignW);
  localparam int ExpSumW = ExpW + 1;

  localparam int Stages = 2;
  localparam logic [FLEN-1:0] CanonNan = FLEN'(fp_canon_nan(ExpW, FracW));
  localparam logic [FLEN-2:0] InfMag = (FLEN - 1)'(fp_inf_mag(ExpW, FracW));
  localparam logic [FLEN-2:0] MaxMag = (FLEN - 1)'(fp_max_mag(ExpW, FracW));
  localparam logic [ExpSumW-1:0] ExpOvf = {1'b0, {ExpW{1'b1}}};
  localparam logic [AlignW-1:0] LimitTop = {1'b1, {(AlignW - 1) {1'b0}}};

  if (!((ExpW >= 2) && (FracW >= 2) && (AlignW <= FpLzcW))) begin : g_width_error
    $error("ExpW and FracW outside the supported range");
  end

  if (Stages != Latency) begin : g_latency_error
    $error("FpAddLatency must equal the two fp_add stages");
  end

  logic                  sa;
  logic                  sb;
  logic [      ExpW-1:0] ea;
  logic [      ExpW-1:0] eb;
  logic [     FracW-1:0] fa;
  logic [     FracW-1:0] fb;
  logic                  a_nan;
  logic                  b_nan;
  logic                  a_inf;
  logic                  b_inf;
  logic                  inf_clash;
  logic                  nv;

  logic                  swap;
  logic                  sx;
  logic                  eff_sub;
  logic [      ExpW-1:0] ex;
  logic [      ExpW-1:0] ey;
  logic [      SigW-1:0] mx;
  logic [      SigW-1:0] my;
  logic [      ExpW-1:0] d;
  logic [       ShW-1:0] sh;

  logic [     WideW-1:0] y_wide;
  logic [    AlignW-1:0] y_al;
  logic [      SumW-1:0] sum;
  logic [    AlignW-1:0] limit;
  logic [      SumW-1:0] sum_q1;
  logic [      ExpW-1:0] ex_q1;
  logic                  sx_q1;
  logic                  eff_sub_q1;
  logic [    AlignW-1:0] limit_q1;
  logic [       RmW-1:0] rm_q1;
  logic                  a_nan_q1;
  logic                  b_nan_q1;
  logic                  a_inf_q1;
  logic                  b_inf_q1;
  logic                  inf_clash_q1;
  logic                  nv_q1;
  logic                  sa_q1;
  logic                  sb_q1;

  logic [    AlignW-1:0] lz_in;
  logic [       LzW-1:0] lz;

  logic [    AlignW-1:0] n;
  logic [   ExpSumW-1:0] e;
  logic [   ExpSumW-1:0] e_field;
  logic                  lsb;
  logic                  g;
  logic                  st;
  logic                  inexact;
  logic                  inc;
  logic                  r_top;
  logic [ExpW+FracW-1:0] r_mag;
  logic                  ovf;
  logic                  to_max;
  logic                  uf;
  logic [      FLEN-1:0] result_next;
  logic [     FlagW-1:0] fflags_next;

  assign sa = a[FLEN-1];
  assign sb = b[FLEN-1] ^ sub;
  assign ea = a[FLEN-2:FracW];
  assign eb = b[FLEN-2:FracW];
  assign fa = a[FracW-1:0];
  assign fb = b[FracW-1:0];

  assign a_nan = (&ea) && (fa != '0);
  assign b_nan = (&eb) && (fb != '0);
  assign a_inf = (&ea) && (fa == '0);
  assign b_inf = (&eb) && (fb == '0);
  assign inf_clash = a_inf && b_inf && (sa != sb);
  assign nv = (a_nan && !fa[FracW-1]) || (b_nan && !fb[FracW-1]) || inf_clash;

  assign swap = b[FLEN-2:0] > a[FLEN-2:0];
  assign sx = swap ? sb : sa;
  assign eff_sub = sa != sb;
  assign ex = swap ? (eb | ExpW'(eb == '0)) : (ea | ExpW'(ea == '0));
  assign ey = swap ? (ea | ExpW'(ea == '0)) : (eb | ExpW'(eb == '0));
  assign mx = swap ? {eb != '0, fb} : {ea != '0, fa};
  assign my = swap ? {ea != '0, fa} : {eb != '0, fb};
  assign d = ex - ey;
  assign sh = (d > ExpW'(AlignW)) ? ShW'(AlignW) : ShW'(d);

  // Align with sticky
  assign y_wide = {my, {(WideW - SigW) {1'b0}}} >> sh;
  assign y_al = {
    y_wide[WideW-1-:AlignW-1], y_wide[WideW-AlignW] | (y_wide[WideW-AlignW-1:0] != '0)
  };
  assign sum = eff_sub ?
      {1'b0, mx, {GrsW{1'b0}}} - {1'b0, y_al} : {1'b0, mx, {GrsW{1'b0}}} + {1'b0, y_al};

  assign limit = LimitTop >> (ex - ExpW'(1));
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      sum_q1       <= '0;
      ex_q1        <= '0;
      sx_q1        <= 1'b0;
      eff_sub_q1   <= 1'b0;
      limit_q1     <= '0;
      rm_q1        <= '0;
      a_nan_q1     <= 1'b0;
      b_nan_q1     <= 1'b0;
      a_inf_q1     <= 1'b0;
      b_inf_q1     <= 1'b0;
      inf_clash_q1 <= 1'b0;
      nv_q1        <= 1'b0;
      sa_q1        <= 1'b0;
      sb_q1        <= 1'b0;
    end else if (core_en) begin
      sum_q1       <= sum;
      ex_q1        <= ex;
      sx_q1        <= sx;
      eff_sub_q1   <= eff_sub;
      limit_q1     <= limit;
      rm_q1        <= rm;
      a_nan_q1     <= a_nan;
      b_nan_q1     <= b_nan;
      a_inf_q1     <= a_inf;
      b_inf_q1     <= b_inf;
      inf_clash_q1 <= inf_clash;
      nv_q1        <= nv;
      sa_q1        <= sa;
      sb_q1        <= sb;
    end
  end

  // Normalize leading one
  assign lz_in = sum_q1[AlignW-1:0] | limit_q1;
  assign lz = LzW'(fp_lzc(FpLzcW'(lz_in), AlignW));

  assign n = sum_q1[AlignW] ? {sum_q1[AlignW:2], sum_q1[1] | sum_q1[0]} : sum_q1[AlignW-1:0] << lz;
  assign e = sum_q1[AlignW] ? {1'b0, ex_q1} + ExpSumW'(1) : {1'b0, ex_q1} - ExpSumW'(lz);
  assign e_field = n[AlignW-1] ? e : '0;

  assign lsb = n[GrsW];
  assign g = n[GrsW-1];
  assign st = |n[GrsW-2:0];
  assign inexact = g | st;

  assign inc = fp_round_up(rm_q1, sx_q1, lsb, g, st);

  assign {r_top, r_mag} = {e_field, n[AlignW-2:GrsW]} + FLEN'(inc);
  assign ovf = {r_top, r_mag[FLEN-2:FracW]} >= ExpOvf;
  assign to_max = fp_ovf_max(rm_q1, sx_q1);
  assign uf = inexact && ({r_top, r_mag[FLEN-2:FracW]} == '0);

  always_comb begin
    if (a_nan_q1 || b_nan_q1 || inf_clash_q1) begin
      result_next = CanonNan;
      fflags_next = nv_q1 ? FlagNv : '0;
    end else if (a_inf_q1 || b_inf_q1) begin
      result_next = {a_inf_q1 ? sa_q1 : sb_q1, InfMag};
      fflags_next = '0;
    end else if (sum_q1 == '0) begin
      result_next = {eff_sub_q1 ? (rm_q1 == RmRdn) : sx_q1, {(FLEN - 1) {1'b0}}};
      fflags_next = '0;
    end else if (ovf) begin
      result_next = {sx_q1, to_max ? MaxMag : InfMag};
      fflags_next = FlagOf | FlagNx;
    end else begin
      result_next = {sx_q1, r_mag};
      fflags_next = '0;
      if (uf) fflags_next = fflags_next | FlagUf;
      if (inexact) fflags_next = fflags_next | FlagNx;
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
