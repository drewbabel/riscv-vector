`default_nettype none

module fp_fma
  import fp_pkg::RmRne, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNv, fp_pkg::FlagOf, fp_pkg::FlagUf, fp_pkg::FlagNx;
  import fp_pkg::fp_round_up;
#(
    parameter int ExpW = fp_pkg::ExpW,
    parameter int FracW = fp_pkg::FracW,
    localparam int FLEN = 1 + ExpW + FracW,
    localparam int Latency = fp_pkg::FpFmaLatency
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             core_en,
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
  localparam int NormSplit = (ShW < 4) ? ShW : 4;

  localparam logic [ExpSW-1:0] Bias = ExpSW'((1 << (ExpW - 1)) - 1);
  localparam logic [ExpSW-1:0] ExpMax = ExpSW'((1 << ExpW) - 1);
  localparam logic [ExpSW-1:0] AddSlot = ExpSW'(DpW - GrdW - SigW - FracW);
  localparam logic [ExpSW-1:0] TopSlot = ExpSW'(DpW - GrdW - 2 * FracW);
  localparam logic [ExpSW-1:0] MaxShift = ExpSW'(DpW);

  localparam logic [FLEN-1:0] CanonNan = {1'b0, {ExpW{1'b1}}, 1'b1, {(FracW - 1) {1'b0}}};
  localparam logic [FLEN-2:0] InfMag = {{ExpW{1'b1}}, {FracW{1'b0}}};
  localparam logic [FLEN-2:0] MaxMag = {{(ExpW - 1) {1'b1}}, 1'b0, {FracW{1'b1}}};

  if (!((SigW + 3) < (1 << (ExpW - 1)))) begin : g_width_error
    $error("ExpW and FracW outside the supported range");
  end

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

  logic [ProdW-1:0] prod_sig_q1;
  logic [  DpW-1:0] addend_q1;
  logic [ExpSW-1:0] e_top_q1;
  logic sub_q1, sp_q1, sc_q1;
  logic [2:0] rm_q1;
  logic a_nan_q1, b_nan_q1, c_nan_q1, any_snan_q1, inf_zero_q1;
  logic a_inf_q1, b_inf_q1, c_inf_q1;

  logic [SumW:0] sum;
  logic neg;
  logic [SumW-1:0] mag;
  logic res_sign, zero_sign;

  logic deep;
  logic [ExpSW-1:0] lim;
  logic [SumW-1:0] v_part;
  logic [ShW-1:0] n_part;

  logic [SumW-1:0] v_part_q2;
  logic [ShW-1:0] n_part_q2;
  logic [ExpSW-1:0] lim_q2;
  logic deep_q2;
  logic [ExpSW-1:0] e_top_q2;
  logic res_sign_q2, zero_sign_q2, mag_nz_q2;
  logic sub_q2, sp_q2, sc_q2;
  logic [2:0] rm_q2;
  logic a_nan_q2, b_nan_q2, c_nan_q2, any_snan_q2, inf_zero_q2;
  logic a_inf_q2, b_inf_q2, c_inf_q2;

  logic [SumW-1:0] norm;
  logic [ShW-1:0] nsh;
  logic [SumW-1:0] rsrc;
  logic [ExpSW-1:0] e_norm;
  logic is_norm;
  logic [FracW-1:0] frac;
  logic g, st, inc, inc_wide;
  logic [FLEN-2:0] rnd;
  logic ovf, tiny, inexact, to_inf;
  logic [FLEN-1:0] result_next;
  logic [4:0] fflags_next;

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

  // Addend shift amount
  assign ep = xa + xb - Bias;
  assign s_raw = ep + AddSlot - xc;
  assign s_le0 = s_raw[ExpSW-1] || (s_raw == '0);
  assign s_big = !s_raw[ExpSW-1] && (s_raw >= MaxShift);
  assign use_c = a_zero || b_zero || (s_le0 && !c_zero);
  always_comb begin
    if (use_c || s_le0) shamt = '0;
    else if (s_big) shamt = ShW'(MaxShift);
    else shamt = s_raw[ShW-1:0];
  end

  // Top bit exponent
  assign e_top = use_c ? xc + ExpSW'(1) : ep + TopSlot;

  assign aln = {mc, (AlnW - SigW)'(0)} >> shamt;
  assign addend = aln[AlnW-1-:DpW] | DpW'(aln[AlnW-DpW-1:0] != '0);

  always_ff @(posedge clk) begin
    if (!rst_n) prod_sig_q1 <= '0;
    else if (core_en) prod_sig_q1 <= prod_sig;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      addend_q1   <= '0;
      e_top_q1    <= '0;
      sub_q1      <= 1'b0;
      sp_q1       <= 1'b0;
      sc_q1       <= 1'b0;
      rm_q1       <= '0;
      a_nan_q1    <= 1'b0;
      b_nan_q1    <= 1'b0;
      c_nan_q1    <= 1'b0;
      any_snan_q1 <= 1'b0;
      inf_zero_q1 <= 1'b0;
      a_inf_q1    <= 1'b0;
      b_inf_q1    <= 1'b0;
      c_inf_q1    <= 1'b0;
    end else if (core_en) begin
      addend_q1   <= addend;
      e_top_q1    <= e_top;
      sub_q1      <= sub;
      sp_q1       <= sp;
      sc_q1       <= sc;
      rm_q1       <= rm;
      a_nan_q1    <= a_nan;
      b_nan_q1    <= b_nan;
      c_nan_q1    <= c_nan;
      any_snan_q1 <= any_snan;
      inf_zero_q1 <= inf_zero;
      a_inf_q1    <= a_inf;
      b_inf_q1    <= b_inf;
      c_inf_q1    <= c_inf;
    end
  end

  assign prod = {SlotW'(0), prod_sig_q1, GrdW'(0)};

  assign sum = (SumW + 1)'(prod) + ((SumW + 1)'(addend_q1) ^ {(SumW + 1) {sub_q1}}) +
      (SumW + 1)'(sub_q1);
  assign neg = sum[SumW];
  assign mag = neg ? (~sum[SumW-1:0] + SumW'(1)) : sum[SumW-1:0];

  assign res_sign = neg ? sc_q1 : sp_q1;
  assign zero_sign = (sp_q1 == sc_q1) ? sp_q1 : (rm_q1 == RmRdn);

  assign deep = e_top_q1[ExpSW-1] || (e_top_q1 == '0);
  assign lim = deep ? '0 : e_top_q1 - ExpSW'(1);

  // Normalize within lim
  always_comb begin
    logic [SumW-1:0] v;
    logic [ ShW-1:0] n;
    v = mag;
    n = '0;
    for (int i = ShW - 1; i >= NormSplit; i--) begin
      if (((v >> (SumW - (1 << i))) == '0) && ((ExpSW'(n) + ExpSW'(1 << i)) <= lim)) begin
        v = v << (1 << i);
        n = n | ShW'(1 << i);
      end
    end
    v_part = v;
    n_part = n;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      v_part_q2    <= '0;
      n_part_q2    <= '0;
      lim_q2       <= '0;
      deep_q2      <= 1'b0;
      e_top_q2     <= '0;
      res_sign_q2  <= 1'b0;
      zero_sign_q2 <= 1'b0;
      mag_nz_q2    <= 1'b0;
      sub_q2       <= 1'b0;
      sp_q2        <= 1'b0;
      sc_q2        <= 1'b0;
      rm_q2        <= '0;
      a_nan_q2     <= 1'b0;
      b_nan_q2     <= 1'b0;
      c_nan_q2     <= 1'b0;
      any_snan_q2  <= 1'b0;
      inf_zero_q2  <= 1'b0;
      a_inf_q2     <= 1'b0;
      b_inf_q2     <= 1'b0;
      c_inf_q2     <= 1'b0;
    end else if (core_en) begin
      v_part_q2    <= v_part;
      n_part_q2    <= n_part;
      lim_q2       <= lim;
      deep_q2      <= deep;
      e_top_q2     <= e_top_q1;
      res_sign_q2  <= res_sign;
      zero_sign_q2 <= zero_sign;
      mag_nz_q2    <= mag != '0;
      sub_q2       <= sub_q1;
      sp_q2        <= sp_q1;
      sc_q2        <= sc_q1;
      rm_q2        <= rm_q1;
      a_nan_q2     <= a_nan_q1;
      b_nan_q2     <= b_nan_q1;
      c_nan_q2     <= c_nan_q1;
      any_snan_q2  <= any_snan_q1;
      inf_zero_q2  <= inf_zero_q1;
      a_inf_q2     <= a_inf_q1;
      b_inf_q2     <= b_inf_q1;
      c_inf_q2     <= c_inf_q1;
    end
  end

  always_comb begin
    logic [SumW-1:0] v;
    logic [ ShW-1:0] n;
    v = v_part_q2;
    n = n_part_q2;
    for (int i = NormSplit - 1; i >= 0; i--) begin
      if (((v >> (SumW - (1 << i))) == '0) && ((ExpSW'(n) + ExpSW'(1 << i)) <= lim_q2)) begin
        v = v << (1 << i);
        n = n | ShW'(1 << i);
      end
    end
    norm = v;
    nsh  = n;
  end

  assign rsrc = deep_q2 ? '0 : norm;
  assign e_norm = e_top_q2 - ExpSW'(nsh);
  assign is_norm = rsrc[SumW-1];

  assign frac = rsrc[SumW-2-:FracW];
  assign g = rsrc[SumW-2-FracW];
  assign st = deep_q2 ? mag_nz_q2 : (rsrc[SumW-3-FracW:0] != '0);
  assign inc = fp_round_up(rm_q2, res_sign_q2, frac[0], g, st);

  assign rnd = {(is_norm ? e_norm[ExpW-1:0] : ExpW'(0)), frac} + (FLEN - 1)'(inc);

  assign ovf = is_norm && ((e_norm >= ExpMax) || (rnd[FLEN-2-:ExpW] == '1));

  // Tininess after rounding
  assign inc_wide = fp_round_up(
      rm_q2, res_sign_q2, rsrc[SumW-2-FracW], rsrc[SumW-3-FracW], rsrc[SumW-4-FracW:0] != '0
  );
  assign tiny = !is_norm && !((rsrc[SumW-2-:SigW] == '1) && inc_wide);
  assign inexact = g || st;

  assign to_inf = (rm_q2 == RmRne) || (rm_q2 == RmRmm) || ((rm_q2 == RmRdn) && res_sign_q2) ||
      ((rm_q2 == RmRup) && !res_sign_q2);

  always_comb begin
    fflags_next = '0;
    if (a_nan_q2 || b_nan_q2 || c_nan_q2 || inf_zero_q2) begin
      result_next = CanonNan;
      fflags_next = (any_snan_q2 || inf_zero_q2) ? FlagNv : '0;
    end else if (a_inf_q2 || b_inf_q2) begin
      if (c_inf_q2 && sub_q2) begin
        result_next = CanonNan;
        fflags_next = FlagNv;
      end else begin
        result_next = {sp_q2, InfMag};
      end
    end else if (c_inf_q2) begin
      result_next = {sc_q2, InfMag};
    end else if (!mag_nz_q2) begin
      result_next = {zero_sign_q2, (FLEN - 1)'(0)};
    end else if (ovf) begin
      result_next = {res_sign_q2, to_inf ? InfMag : MaxMag};
      fflags_next = FlagOf | FlagNx;
    end else begin
      result_next = {res_sign_q2, rnd};
      if (tiny && inexact) fflags_next = fflags_next | FlagUf;
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
