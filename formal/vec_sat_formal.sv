`default_nettype none

module vec_sat_formal
  import vec_pkg::*;
();

  localparam int ELEN = arch_pkg::ELEN;
  localparam int Widths = $clog2(ELEN / 8) + 1;
  localparam int SelW = $clog2(Widths);
  localparam logic [2:0] SewTop = 3'(Widths - 1);

  logic                 clk;

  (* anyseq *)logic                 core_en;
  (* anyseq *)vec_op_e              op;
  (* anyseq *)logic    [       2:0] vsew;
  (* anyseq *)logic    [       1:0] vxrm;
  (* anyseq *)logic    [  ELEN-1:0] a;
  (* anyseq *)logic    [  ELEN-1:0] b;
  (* anyseq *)logic    [2*ELEN-1:0] product;

  logic    [  ELEN-1:0] result;
  logic                 sat;

  vec_sat_lane #(
      .ELEN(ELEN)
  ) dut (
      .clk    (clk),
      .core_en(core_en),
      .op     (op),
      .vsew   (vsew),
      .vxrm   (vxrm),
      .a      (a),
      .b      (b),
      .product(product),
      .result (result),
      .sat    (sat)
  );

  function automatic logic is_fx(input vec_op_e o);
    return (o == VEC_SADDU) || (o == VEC_SADD) || (o == VEC_SSUBU) || (o == VEC_SSUB) ||
        (o == VEC_AADDU) || (o == VEC_AADD) || (o == VEC_ASUBU) || (o == VEC_ASUB) ||
        (o == VEC_SMUL) || (o == VEC_SSRL) || (o == VEC_SSRA) || (o == VEC_NCLIPU) ||
        (o == VEC_NCLIP);
  endfunction

  function automatic logic is_narrow(input vec_op_e o);
    return (o == VEC_NCLIPU) || (o == VEC_NCLIP);
  endfunction

  function automatic logic is_round(input vec_op_e o);
    return is_fx(o) && (o != VEC_SADDU) && (o != VEC_SADD) && (o != VEC_SSUBU) && (o != VEC_SSUB);
  endfunction

  // Spec reference per SEW
  logic [ELEN-1:0] ref_res [Widths];
  logic            ref_sat [Widths];
  logic            ref_inc [Widths];
  logic            ref_lost[Widths];
  logic            ref_tie [Widths];
  logic            ref_odd [Widths];
  logic            ref_hi  [Widths];

  for (genvar w = 0; w < Widths; w++) begin : g_ref
    localparam int S = 8 << w;
    localparam int R = 2 * S + 4;
    localparam int Lg = $clog2(S);
    localparam bit Narrow = (2 * S <= ELEN);
    localparam logic signed [R-1:0] UMax = (R'(1) << S) - R'(1);
    localparam logic signed [R-1:0] SMax = (R'(1) << (S - 1)) - R'(1);
    localparam logic signed [R-1:0] SMin = -(R'(1) << (S - 1));

    // Table 5 increment
    function automatic logic rinc(input logic [R-1:0] v, input int d, input logic [1:0] mode);
      logic vd;
      logic vd1;
      logic low;
      vd  = 1'b0;
      vd1 = 1'b0;
      low = 1'b0;
      for (int i = 0; i < R; i++) begin
        if (i == d) vd = v[i];
        if (i == d - 1) vd1 = v[i];
        if (i < d - 1) low = low | v[i];
      end
      case (mode)
        2'b00:   return vd1;
        2'b01:   return vd1 && (low || vd);
        2'b10:   return 1'b0;
        default: return !vd && (vd1 || low);
      endcase
    endfunction

    logic        [R-1:0] ua;
    logic        [R-1:0] ub;
    logic signed [R-1:0] sa;
    logic signed [R-1:0] sb;
    logic        [R-1:0] uw;
    logic signed [R-1:0] sw;
    logic signed [R-1:0] prod;

    assign ua   = R'(a[S-1:0]);
    assign ub   = R'(b[S-1:0]);
    assign sa   = {{(R - S) {a[S-1]}}, a[S-1:0]};
    assign sb   = {{(R - S) {b[S-1]}}, b[S-1:0]};
    assign prod = sa * sb;

    if (Narrow) begin : g_wide
      assign uw = R'(a[2*S-1:0]);
      assign sw = {{(R - 2 * S) {a[2*S-1]}}, a[2*S-1:0]};
    end else begin : g_no_wide
      assign uw = '0;
      assign sw = '0;
    end

    // Chapter 12 roundoff operands
    logic [R-1:0] v;
    int           d;
    logic         arith;
    always_comb begin
      v = '0;
      d = 0;
      arith = 1'b0;
      case (op)
        VEC_AADDU: begin
          v = ua + ub;
          d = 1;
        end
        VEC_AADD: begin
          v = sa + sb;
          d = 1;
          arith = 1'b1;
        end
        VEC_ASUBU: begin
          v = ua - ub;
          d = 1;
        end
        VEC_ASUB: begin
          v = sa - sb;
          d = 1;
          arith = 1'b1;
        end
        VEC_SMUL: begin
          v = prod;
          d = S - 1;
          arith = 1'b1;
        end
        VEC_SSRL: begin
          v = ua;
          d = int'(b[Lg-1:0]);
        end
        VEC_SSRA: begin
          v = sa;
          d = int'(b[Lg-1:0]);
          arith = 1'b1;
        end
        VEC_NCLIPU: begin
          v = uw;
          d = int'(b[Lg:0]);
        end
        VEC_NCLIP: begin
          v = sw;
          d = int'(b[Lg:0]);
          arith = 1'b1;
        end
        default: ;
      endcase
    end

    logic                r;
    logic signed [R-1:0] sh_s;
    logic        [R-1:0] sh_u;
    logic signed [R-1:0] rounded;
    assign r = rinc(v, d, vxrm);
    assign sh_s = $signed(v) >>> d;
    assign sh_u = v >> d;
    assign rounded = (arith ? sh_s : sh_u) + R'(r);

    // Clip bounds
    logic signed [R-1:0] t;
    logic signed [R-1:0] lo;
    logic signed [R-1:0] hi;
    logic                clip;
    always_comb begin
      t    = rounded;
      lo   = '0;
      hi   = UMax;
      clip = 1'b0;
      case (op)
        VEC_SADDU: begin
          t    = ua + ub;
          clip = 1'b1;
        end
        VEC_SSUBU: begin
          t    = ua - ub;
          clip = 1'b1;
        end
        VEC_SADD: begin
          t    = sa + sb;
          lo   = SMin;
          hi   = SMax;
          clip = 1'b1;
        end
        VEC_SSUB: begin
          t    = sa - sb;
          lo   = SMin;
          hi   = SMax;
          clip = 1'b1;
        end
        VEC_NCLIPU: clip = 1'b1;
        VEC_SMUL, VEC_NCLIP: begin
          lo   = SMin;
          hi   = SMax;
          clip = 1'b1;
        end
        default: ;
      endcase
    end

    logic signed [R-1:0] clipped;
    assign clipped = !clip ? t : ((t > hi) ? hi : ((t < lo) ? lo : t));

    assign ref_res[w] = ELEN'(clipped[S-1:0]);
    assign ref_sat[w] = clip && ((t > hi) || (t < lo));
    assign ref_hi[w] = clip && (t > hi);
    assign ref_inc[w] = r;
    assign ref_odd[w] = v[d];
    assign ref_lost[w] = (d != 0) && ((v & ((R'(1) << d) - R'(1))) != '0);
    assign ref_tie[w] = (d != 0) && ((v & ((R'(1) << d) - R'(1))) == (R'(1) << (d - 1)));

    // vec_mul_lane product contract
    always @(posedge clk)
      if (op == VEC_SMUL && vsew == 3'(w))
        assume (product[2*S-1:0] == prod[2*S-1:0]);
  end

  // Accepted element
  logic               f_valid = 1'b0;
  logic               f_held = 1'b0;
  vec_op_e            chk_op;
  logic    [     2:0] chk_sew;
  logic    [     1:0] chk_vxrm;
  logic    [ELEN-1:0] exp_res;
  logic               exp_sat;
  logic               exp_inc;
  logic               exp_lost;
  logic               exp_tie;
  logic               exp_odd;
  logic               exp_hi;

  always @(posedge clk) begin
    f_held <= f_valid && !core_en;
    if (core_en) begin
      f_valid  <= 1'b1;
      chk_op   <= op;
      chk_sew  <= vsew;
      chk_vxrm <= vxrm;
      if (vsew <= SewTop) begin
        exp_res  <= ref_res[vsew[SelW-1:0]];
        exp_sat  <= ref_sat[vsew[SelW-1:0]];
        exp_inc  <= ref_inc[vsew[SelW-1:0]];
        exp_lost <= ref_lost[vsew[SelW-1:0]];
        exp_tie  <= ref_tie[vsew[SelW-1:0]];
        exp_odd  <= ref_odd[vsew[SelW-1:0]];
        exp_hi   <= ref_hi[vsew[SelW-1:0]];
      end
    end
  end

  logic [ELEN-1:0] sew_mask;
  assign sew_mask = ELEN'((64'(1) << (8 << chk_sew)) - 64'(1));

  // Legal SEW and EEW
  logic sew_ok;
  logic checked;
  assign sew_ok  = is_narrow(chk_op) ? (chk_sew < SewTop) : (chk_sew <= SewTop);
  assign checked = f_valid && is_fx(chk_op) && sew_ok;

  always @(posedge clk) begin
    if (checked) begin
      assert ((result & sew_mask) == exp_res);
      assert (sat == exp_sat);
    end

    // Clip outcomes
    for (int s = 0; s < Widths; s++) begin
      cover (checked && chk_sew == 3'(s) && chk_op == VEC_SADDU && sat);
      cover (checked && chk_sew == 3'(s) && chk_op == VEC_SADD && sat && exp_hi);
      cover (checked && chk_sew == 3'(s) && chk_op == VEC_SADD && sat && !exp_hi);
      cover (checked && chk_sew == 3'(s) && chk_op == VEC_SSUBU && sat);
      cover (checked && chk_sew == 3'(s) && chk_op == VEC_SSUB && sat && exp_hi);
      cover (checked && chk_sew == 3'(s) && chk_op == VEC_SSUB && sat && !exp_hi);
      cover (checked && chk_sew == 3'(s) && chk_op == VEC_SMUL && sat);
      cover (checked && chk_sew == 3'(s) && chk_op == VEC_SMUL && !sat && exp_inc);
      if (s < Widths - 1) begin
        cover (checked && chk_sew == 3'(s) && chk_op == VEC_NCLIPU && sat);
        cover (checked && chk_sew == 3'(s) && chk_op == VEC_NCLIP && sat && exp_hi);
        cover (checked && chk_sew == 3'(s) && chk_op == VEC_NCLIP && sat && !exp_hi);
        cover (checked && chk_sew == 3'(s) && chk_op == VEC_NCLIP && !sat && exp_inc);
      end
    end
    cover (checked && chk_op == VEC_SADDU && !sat);
    cover (checked && chk_op == VEC_SADD && !sat);
    cover (checked && chk_op == VEC_SSUBU && !sat);
    cover (checked && chk_op == VEC_SSUB && !sat);
    cover (checked && chk_op == VEC_NCLIPU && !sat && exp_inc);

    // Increment per op
    cover (checked && chk_op == VEC_AADDU && chk_vxrm == 2'b00 && exp_inc);
    cover (checked && chk_op == VEC_AADD && chk_vxrm == 2'b01 && exp_inc);
    cover (checked && chk_op == VEC_ASUBU && chk_vxrm == 2'b11 && exp_inc);
    cover (checked && chk_op == VEC_ASUB && chk_vxrm == 2'b00 && exp_inc);
    cover (checked && chk_op == VEC_SSRL && chk_vxrm == 2'b01 && exp_inc);
    cover (checked && chk_op == VEC_SSRA && chk_vxrm == 2'b11 && exp_inc);

    // Mode corners
    cover (checked && is_round(chk_op) && chk_vxrm == 2'b00 && exp_tie && !exp_odd && exp_inc);
    cover (checked && is_round(chk_op) && chk_vxrm == 2'b01 && exp_tie && !exp_odd && !exp_inc);
    cover (checked && is_round(chk_op) && chk_vxrm == 2'b01 && exp_tie && exp_odd && exp_inc);
    cover (checked && is_round(chk_op) && chk_vxrm == 2'b01 && exp_lost && !exp_tie && exp_inc);
    cover (checked && is_round(chk_op) && chk_vxrm == 2'b10 && exp_lost);
    cover (checked && is_round(chk_op) && chk_vxrm == 2'b11 && exp_lost && exp_odd && !exp_inc);
    cover (checked && is_round(chk_op) && chk_vxrm == 2'b11 && exp_lost && !exp_odd && exp_inc);
    cover (checked && chk_op == VEC_SSRA && !exp_lost && chk_vxrm == 2'b11 && result != '0);
    cover (checked && chk_op == VEC_ASUB && chk_sew == 3'd0 && exp_res == ELEN'(8'h80) && !sat);

    // Stall hold
    cover (checked && f_held && sat);
  end

endmodule

`default_nettype wire
