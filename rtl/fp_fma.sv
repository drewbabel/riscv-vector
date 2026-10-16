`default_nettype none

module fp_fma (
    input  wire         neg_prod,
    input  wire         neg_add,
    input  wire  [ 2:0] rm,
    input  wire  [31:0] a,
    input  wire  [31:0] b,
    input  wire  [31:0] c,
    output logic [31:0] result,
    output logic [ 4:0] fflags
);

  localparam int ProdW = 48;
  localparam int DpW = 77;
  localparam int SumW = DpW + 1;
  localparam int AlnW = DpW + 24;
  localparam int ExpW = 10;

  localparam logic [ExpW-1:0] Bias = ExpW'(127);
  localparam logic [ExpW-1:0] AddSlot = ExpW'(27);
  localparam logic [ExpW-1:0] TopSlot = ExpW'(28);
  localparam logic [ExpW-1:0] MaxShift = ExpW'(77);

  localparam logic [2:0] RmRne = 3'd0;
  localparam logic [2:0] RmRdn = 3'd2;
  localparam logic [2:0] RmRup = 3'd3;
  localparam logic [2:0] RmRmm = 3'd4;

  localparam logic [31:0] QNan = 32'h7FC0_0000;
  localparam logic [30:0] Inf = 31'h7F80_0000;
  localparam logic [30:0] MaxFinite = 31'h7F7F_FFFF;

  logic [7:0] ea, eb, ec;
  logic [22:0] fa, fb, fc;
  logic a_zero, b_zero, c_zero;
  logic a_inf, b_inf, c_inf;
  logic a_nan, b_nan, c_nan;
  logic any_snan;
  logic inf_zero;
  logic sp, sc, sub;

  logic [23:0] ma, mb, mc;
  logic [ExpW-1:0] xa, xb, xc;
  logic [ProdW-1:0] prod_sig;
  logic [ ExpW-1:0] ep;
  logic [ ExpW-1:0] s_raw;
  logic s_le0, s_big, use_c;
  logic [6:0] shamt;
  logic [ExpW-1:0] e_top;

  logic [AlnW-1:0] aln;
  logic [DpW-1:0] addend, prod;
  logic [SumW:0] sum;
  logic neg;
  logic [SumW-1:0] mag;
  logic res_sign, zero_sign;

  logic deep;
  logic [ExpW-1:0] lim;
  logic [SumW-1:0] norm;
  logic [6:0] nsh;
  logic [SumW-1:0] rsrc;
  logic [ExpW-1:0] e_norm;
  logic is_norm;
  logic [22:0] frac;
  logic g, st, inc, inc_wide;
  logic [30:0] rnd;
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

  assign ea = a[30:23];
  assign eb = b[30:23];
  assign ec = c[30:23];
  assign fa = a[22:0];
  assign fb = b[22:0];
  assign fc = c[22:0];

  assign a_zero = (ea == 8'h00) && (fa == '0);
  assign b_zero = (eb == 8'h00) && (fb == '0);
  assign c_zero = (ec == 8'h00) && (fc == '0);
  assign a_inf = (ea == 8'hFF) && (fa == '0);
  assign b_inf = (eb == 8'hFF) && (fb == '0);
  assign c_inf = (ec == 8'hFF) && (fc == '0);
  assign a_nan = (ea == 8'hFF) && (fa != '0);
  assign b_nan = (eb == 8'hFF) && (fb != '0);
  assign c_nan = (ec == 8'hFF) && (fc != '0);
  assign any_snan = (a_nan && !fa[22]) || (b_nan && !fb[22]) || (c_nan && !fc[22]);
  assign inf_zero = (a_inf && b_zero) || (a_zero && b_inf);

  assign sp = a[31] ^ b[31] ^ neg_prod;
  assign sc = c[31] ^ neg_add;
  assign sub = sp ^ sc;

  assign ma = {ea != 8'h00, fa};
  assign mb = {eb != 8'h00, fb};
  assign mc = {ec != 8'h00, fc};
  assign xa = (ea == 8'h00) ? ExpW'(1) : ExpW'(ea);
  assign xb = (eb == 8'h00) ? ExpW'(1) : ExpW'(eb);
  assign xc = (ec == 8'h00) ? ExpW'(1) : ExpW'(ec);

  assign prod_sig = ProdW'(ma) * ProdW'(mb);

  // Addend shift amount
  assign ep = xa + xb - Bias;
  assign s_raw = ep + AddSlot - xc;
  assign s_le0 = s_raw[ExpW-1] || (s_raw == '0);
  assign s_big = !s_raw[ExpW-1] && (s_raw >= MaxShift);
  assign use_c = a_zero || b_zero || (s_le0 && !c_zero);
  assign shamt = (use_c || s_le0) ? 7'd0 : (s_big ? 7'(MaxShift) : s_raw[6:0]);

  // Top bit exponent
  assign e_top = use_c ? xc + ExpW'(1) : ep + TopSlot;

  assign aln = {mc, (AlnW - 24)'(0)} >> shamt;
  assign addend = aln[AlnW-1-:DpW] | DpW'(aln[AlnW-DpW-1:0] != '0);
  assign prod = {26'd0, prod_sig, 3'd0};

  assign sum = (SumW + 1)'(prod) + ((SumW + 1)'(addend) ^ {(SumW + 1) {sub}}) + (SumW + 1)'(sub);
  assign neg = sum[SumW];
  assign mag = neg ? (~sum[SumW-1:0] + SumW'(1)) : sum[SumW-1:0];

  assign res_sign = neg ? sc : sp;
  assign zero_sign = (sp == sc) ? sp : (rm == RmRdn);

  // Below subnormal guard
  assign deep = e_top[ExpW-1] || (e_top == '0);
  assign lim = deep ? '0 : e_top - ExpW'(1);

  // Normalize within lim
  always_comb begin
    logic [SumW-1:0] v;
    logic [6:0] n;
    v = mag;
    n = '0;
    for (int i = 6; i >= 0; i--) begin
      if (((v >> (SumW - (1 << i))) == '0) && ((ExpW'(n) + ExpW'(1 << i)) <= lim)) begin
        v = v << (1 << i);
        n = n | 7'(1 << i);
      end
    end
    norm = v;
    nsh  = n;
  end

  assign rsrc = deep ? '0 : norm;
  assign e_norm = e_top - ExpW'(nsh);
  assign is_norm = rsrc[SumW-1];

  assign frac = rsrc[SumW-2-:23];
  assign g = rsrc[SumW-25];
  assign st = deep ? (mag != '0) : (rsrc[SumW-26:0] != '0);
  assign inc = round_inc(rm, res_sign, frac[0], g, st);

  assign rnd = {(is_norm ? e_norm[7:0] : 8'h00), frac} + 31'(inc);

  assign ovf = is_norm && ((e_norm >= ExpW'(255)) || (rnd[30:23] == 8'hFF));

  // Tininess after rounding
  assign inc_wide = round_inc(rm, res_sign, rsrc[SumW-25], rsrc[SumW-26], rsrc[SumW-27:0] != '0);
  assign tiny = !is_norm && !((rsrc[SumW-2-:24] == '1) && inc_wide);
  assign inexact = g || st;

  assign to_inf = (rm == RmRne) || (rm == RmRmm) || ((rm == RmRdn) && res_sign) ||
      ((rm == RmRup) && !res_sign);

  always_comb begin
    fflags = '0;
    if (a_nan || b_nan || c_nan || inf_zero) begin
      result = QNan;
      fflags[4] = any_snan || inf_zero;
    end else if (a_inf || b_inf) begin
      if (c_inf && sub) begin
        result = QNan;
        fflags[4] = 1'b1;
      end else begin
        result = {sp, Inf};
      end
    end else if (c_inf) begin
      result = {sc, Inf};
    end else if (mag == '0) begin
      result = {zero_sign, 31'd0};
    end else if (ovf) begin
      result = {res_sign, to_inf ? Inf : MaxFinite};
      fflags[2] = 1'b1;
      fflags[0] = 1'b1;
    end else begin
      result = {res_sign, rnd};
      fflags[1] = tiny && inexact;
      fflags[0] = inexact;
    end
  end

endmodule

`default_nettype wire
