`default_nettype none

module fp_add
  import fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup;
  import fp_pkg::FlagNv, fp_pkg::FlagOf, fp_pkg::FlagUf, fp_pkg::FlagNx;
  import fp_pkg::fp_round_up, fp_pkg::fp_lzc, fp_pkg::FpLzcW;
#(
    parameter  int ExpW  = fp_pkg::ExpW,
    parameter  int FracW = fp_pkg::FracW,
    localparam int FLEN  = 1 + ExpW + FracW
) (
    input  wire             sub,
    input  wire  [     2:0] rm,
    input  wire  [FLEN-1:0] a,
    input  wire  [FLEN-1:0] b,
    output logic [FLEN-1:0] result,
    output logic [     4:0] fflags
);

  localparam int SigW = FracW + 1;
  localparam int GrsW = 3;
  localparam int AlignW = SigW + GrsW;
  localparam int SumW = AlignW + 1;
  localparam int WideW = 2 * AlignW;
  localparam int ShW = $clog2(AlignW + 1);
  localparam int LzW = $clog2(AlignW);
  localparam int ExpSumW = ExpW + 1;

  localparam logic [FLEN-1:0] CanonNan = {1'b0, {ExpW{1'b1}}, 1'b1, {(FracW - 1) {1'b0}}};
  localparam logic [FLEN-2:0] InfMag = {{ExpW{1'b1}}, {FracW{1'b0}}};
  localparam logic [FLEN-2:0] MaxMag = {{(ExpW - 1) {1'b1}}, 1'b0, {FracW{1'b1}}};
  localparam logic [ExpSumW-1:0] ExpOvf = {1'b0, {ExpW{1'b1}}};
  localparam logic [AlignW-1:0] LimitTop = {1'b1, {(AlignW - 1) {1'b0}}};

  if (!((ExpW >= 2) && (FracW >= 2) && (AlignW <= FpLzcW))) begin : g_width_error
    $error("ExpW and FracW outside the supported range");
  end

  logic               sa;
  logic               sb;
  logic [   ExpW-1:0] ea;
  logic [   ExpW-1:0] eb;
  logic [  FracW-1:0] fa;
  logic [  FracW-1:0] fb;
  logic               a_nan;
  logic               b_nan;
  logic               a_inf;
  logic               b_inf;
  logic               inf_clash;
  logic               nv;

  logic               swap;
  logic               sx;
  logic               eff_sub;
  logic [   ExpW-1:0] ex;
  logic [   ExpW-1:0] ey;
  logic [   SigW-1:0] mx;
  logic [   SigW-1:0] my;
  logic [   ExpW-1:0] d;
  logic [    ShW-1:0] sh;

  logic [  WideW-1:0] y_wide;
  logic [ AlignW-1:0] y_al;
  logic [   SumW-1:0] sum;
  logic [ AlignW-1:0] limit;
  logic [ AlignW-1:0] lz_in;
  logic [    LzW-1:0] lz;

  logic [ AlignW-1:0] n;
  logic [ExpSumW-1:0] e;
  logic [ExpSumW-1:0] e_field;
  logic               lsb;
  logic               g;
  logic               st;
  logic               inexact;
  logic               inc;
  logic               r_top;
  logic [   FLEN-2:0] r_mag;
  logic               ovf;
  logic               to_max;
  logic               uf;

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

  // Normalize leading one
  assign limit = LimitTop >> (ex - ExpW'(1));
  assign lz_in = sum[AlignW-1:0] | limit;
  assign lz = LzW'(fp_lzc(FpLzcW'(lz_in), AlignW));

  assign n = sum[AlignW] ? {sum[AlignW:2], sum[1] | sum[0]} : sum[AlignW-1:0] << lz;
  assign e = sum[AlignW] ? {1'b0, ex} + ExpSumW'(1) : {1'b0, ex} - ExpSumW'(lz);
  assign e_field = n[AlignW-1] ? e : '0;

  assign lsb = n[GrsW];
  assign g = n[GrsW-1];
  assign st = |n[GrsW-2:0];
  assign inexact = g | st;

  assign inc = fp_round_up(rm, sx, lsb, g, st);

  assign {r_top, r_mag} = {e_field, n[AlignW-2:GrsW]} + FLEN'(inc);
  assign ovf = {r_top, r_mag[FLEN-2:FracW]} >= ExpOvf;
  assign to_max = (rm == RmRtz) || ((rm == RmRdn) && !sx) || ((rm == RmRup) && sx);
  assign uf = inexact && ({r_top, r_mag[FLEN-2:FracW]} == '0);

  always_comb begin
    if (a_nan || b_nan || inf_clash) begin
      result = CanonNan;
      fflags = nv ? FlagNv : '0;
    end else if (a_inf || b_inf) begin
      result = {a_inf ? sa : sb, InfMag};
      fflags = '0;
    end else if (sum == '0) begin
      result = {eff_sub ? (rm == RmRdn) : sx, {(FLEN - 1) {1'b0}}};
      fflags = '0;
    end else if (ovf) begin
      result = {sx, to_max ? MaxMag : InfMag};
      fflags = FlagOf | FlagNx;
    end else begin
      result = {sx, r_mag};
      fflags = '0;
      if (uf) fflags = fflags | FlagUf;
      if (inexact) fflags = fflags | FlagNx;
    end
  end

endmodule

`default_nettype wire
