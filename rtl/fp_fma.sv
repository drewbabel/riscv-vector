`default_nettype none

module fp_fma
  import fp_pkg::RmRne, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNv, fp_pkg::FlagOf, fp_pkg::FlagUf, fp_pkg::FlagNx;
#(
    parameter  int ExpW  = fp_pkg::ExpW,
    parameter  int FracW = fp_pkg::FracW,
    localparam int FLEN  = 1 + ExpW + FracW
) (
    input  wire             neg_prod,
    input  wire             neg_add,
    input  wire  [     2:0] rm,
    input  wire  [FLEN-1:0] a,
    input  wire  [FLEN-1:0] b,
    input  wire  [FLEN-1:0] c,
    output logic [FLEN-1:0] result,
    output logic [     4:0] fflags
);

  localparam int SigW = FracW + 1;
  localparam int ProdW = 2 * SigW;
  localparam int GrdW = 3;
  localparam int SlotW = SigW + 2;
  localparam int DpW = SlotW + ProdW + GrdW;
  localparam int SumW = DpW + 1;
  localparam int AlnW = DpW + SigW;
  localparam int ExpSW = ExpW + 2;
  localparam int ShW = $clog2(SumW);

  localparam logic [ExpSW-1:0] Bias = ExpSW'((1 << (ExpW - 1)) - 1);
  localparam logic [ExpSW-1:0] ExpMax = ExpSW'((1 << ExpW) - 1);
  localparam logic [ExpSW-1:0] AddSlot = ExpSW'(DpW - GrdW - SigW - FracW);
  localparam logic [ExpSW-1:0] TopSlot = ExpSW'(DpW - GrdW - 2 * FracW);
  localparam logic [ExpSW-1:0] MaxShift = ExpSW'(DpW);

  localparam logic [FLEN-1:0] CanonicalNan = {1'b0, {ExpW{1'b1}}, 1'b1, {(FracW - 1) {1'b0}}};
  localparam logic [FLEN-2:0] InfMag = {{ExpW{1'b1}}, {FracW{1'b0}}};
  localparam logic [FLEN-2:0] MaxFiniteMag = {{(ExpW - 1) {1'b1}}, 1'b0, {FracW{1'b1}}};

  logic [ExpW-1:0] ea, eb, ec;
  logic [FracW-1:0] fa, fb, fc;
  logic a_zero, b_zero, c_zero;
  logic a_inf, b_inf, c_inf;
  logic a_nan, b_nan, c_nan;
  logic any_snan;
  logic inf_zero;
  logic sp, sc, sub;

  logic [SigW-1:0] ma, mb, mc;
  logic [ExpSW-1:0] xa, xb, xc;
  logic [ProdW-1:0] prod_sig;
  logic [ExpSW-1:0] ep;
  logic [ExpSW-1:0] s_raw;
  logic s_le0, s_big, use_c;
  logic [  ShW-1:0] shamt;
  logic [ExpSW-1:0] e_top;

  logic [ AlnW-1:0] aln;
  logic [DpW-1:0] addend, prod;
  logic [SumW:0] sum;
  logic neg;
  logic [SumW-1:0] mag;
  logic res_sign, zero_sign;

  logic deep;
  logic [ExpSW-1:0] lim;
  logic [SumW-1:0] norm;
  logic [ShW-1:0] nsh;
  logic [SumW-1:0] rsrc;
  logic [ExpSW-1:0] e_norm;
  logic is_norm;
  logic [FracW-1:0] frac;
  logic g, st, inc, inc_wide;
  logic [FLEN-2:0] rnd;
  logic ovf, tiny, inexact, to_inf;

  function automatic logic round_inc(input logic [2:0] mode, input logic sign, input logic lsb,
                                     input logic guard, input logic sticky);
    case (mode)
      RmRne:   round_inc = guard & (sticky | lsb);
      RmRdn:   round_inc = sign & (guard | sticky);
      RmRup:   round_inc = !sign & (guard | sticky);
      RmRmm:   round_inc = guard;
      default: round_inc = 1'b0;
    endcase
  endfunction

  assign ea = a[FLEN-2-:ExpW];
  assign eb = b[FLEN-2-:ExpW];
  assign ec = c[FLEN-2-:ExpW];
  assign fa = a[FracW-1:0];
  assign fb = b[FracW-1:0];
  assign fc = c[FracW-1:0];

  assign a_zero = (ea == '0) && (fa == '0);
  assign b_zero = (eb == '0) && (fb == '0);
  assign c_zero = (ec == '0) && (fc == '0);
  assign a_inf = (ea == '1) && (fa == '0);
  assign b_inf = (eb == '1) && (fb == '0);
  assign c_inf = (ec == '1) && (fc == '0);
  assign a_nan = (ea == '1) && (fa != '0);
  assign b_nan = (eb == '1) && (fb != '0);
  assign c_nan = (ec == '1) && (fc != '0);
  assign any_snan = (a_nan && !fa[FracW-1]) || (b_nan && !fb[FracW-1]) || (c_nan && !fc[FracW-1]);
  assign inf_zero = (a_inf && b_zero) || (a_zero && b_inf);

  assign sp = a[FLEN-1] ^ b[FLEN-1] ^ neg_prod;
  assign sc = c[FLEN-1] ^ neg_add;
  assign sub = sp ^ sc;

  assign ma = {ea != '0, fa};
  assign mb = {eb != '0, fb};
  assign mc = {ec != '0, fc};
  assign xa = (ea == '0) ? ExpSW'(1) : ExpSW'(ea);
  assign xb = (eb == '0) ? ExpSW'(1) : ExpSW'(eb);
  assign xc = (ec == '0) ? ExpSW'(1) : ExpSW'(ec);

  assign prod_sig = ProdW'(ma) * ProdW'(mb);

  assign ep = xa + xb - Bias;
  assign s_raw = ep + AddSlot - xc;
  assign s_le0 = s_raw[ExpSW-1] || (s_raw == '0);
  assign s_big = !s_raw[ExpSW-1] && (s_raw >= MaxShift);
  assign use_c = a_zero || b_zero || (s_le0 && !c_zero);
  assign shamt = (use_c || s_le0) ? ShW'(0) : (s_big ? ShW'(MaxShift) : s_raw[ShW-1:0]);

  assign e_top = use_c ? xc + ExpSW'(1) : ep + TopSlot;

  assign aln = {mc, (AlnW - SigW)'(0)} >> shamt;
  assign addend = aln[AlnW-1-:DpW] | DpW'(aln[AlnW-DpW-1:0] != '0);
  assign prod = {SlotW'(0), prod_sig, GrdW'(0)};

  assign sum = (SumW + 1)'(prod) + ((SumW + 1)'(addend) ^ {(SumW + 1) {sub}}) + (SumW + 1)'(sub);
  assign neg = sum[SumW];
  assign mag = neg ? (~sum[SumW-1:0] + SumW'(1)) : sum[SumW-1:0];

  assign res_sign = neg ? sc : sp;
  assign zero_sign = (sp == sc) ? sp : (rm == RmRdn);

  assign deep = e_top[ExpSW-1] || (e_top == '0);
  assign lim = deep ? '0 : e_top - ExpSW'(1);

  always_comb begin
    logic [SumW-1:0] v;
    logic [ ShW-1:0] n;
    v = mag;
    n = '0;
    for (int i = ShW - 1; i >= 0; i--) begin
      if (((v >> (SumW - (1 << i))) == '0) && ((ExpSW'(n) + ExpSW'(1 << i)) <= lim)) begin
        v = v << (1 << i);
        n = n | ShW'(1 << i);
      end
    end
    norm = v;
    nsh  = n;
  end

  assign rsrc = deep ? '0 : norm;
  assign e_norm = e_top - ExpSW'(nsh);
  assign is_norm = rsrc[SumW-1];

  assign frac = rsrc[SumW-2-:FracW];
  assign g = rsrc[SumW-2-FracW];
  assign st = deep ? (mag != '0) : (rsrc[SumW-3-FracW:0] != '0);
  assign inc = round_inc(rm, res_sign, frac[0], g, st);

  assign rnd = {(is_norm ? e_norm[ExpW-1:0] : ExpW'(0)), frac} + (FLEN - 1)'(inc);

  assign ovf = is_norm && ((e_norm >= ExpMax) || (rnd[FLEN-2-:ExpW] == '1));

  assign inc_wide = round_inc(
      rm, res_sign, rsrc[SumW-2-FracW], rsrc[SumW-3-FracW], rsrc[SumW-4-FracW:0] != '0
  );
  assign tiny = !is_norm && !((rsrc[SumW-2-:SigW] == '1) && inc_wide);
  assign inexact = g || st;

  assign to_inf = (rm == RmRne) || (rm == RmRmm) || ((rm == RmRdn) && res_sign) ||
      ((rm == RmRup) && !res_sign);

  always_comb begin
    fflags = '0;
    if (a_nan || b_nan || c_nan || inf_zero) begin
      result = CanonicalNan;
      fflags = (any_snan || inf_zero) ? FlagNv : '0;
    end else if (a_inf || b_inf) begin
      if (c_inf && sub) begin
        result = CanonicalNan;
        fflags = FlagNv;
      end else begin
        result = {sp, InfMag};
      end
    end else if (c_inf) begin
      result = {sc, InfMag};
    end else if (mag == '0) begin
      result = {zero_sign, (FLEN - 1)'(0)};
    end else if (ovf) begin
      result = {res_sign, to_inf ? InfMag : MaxFiniteMag};
      fflags = FlagOf | FlagNx;
    end else begin
      result = {res_sign, rnd};
      fflags = (tiny && inexact ? FlagUf : '0) | (inexact ? FlagNx : '0);
    end
  end

endmodule

`default_nettype wire
