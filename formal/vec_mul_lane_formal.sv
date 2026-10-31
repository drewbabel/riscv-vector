`default_nettype none

module vec_mul_lane_formal
  import vec_pkg::*;
();

  localparam int ELEN = arch_pkg::ELEN;
  localparam int Widths = $clog2(ELEN / 8) + 1;
  localparam logic [2:0] SewTop = 3'(Widths - 1);

  logic                 clk;

  (* anyseq *)logic                 core_en;
  (* anyseq *)vec_op_e              op;
  (* anyseq *)logic    [ VsewW-1:0] vsew;
  (* anyseq *)logic    [  ELEN-1:0] a;
  (* anyseq *)logic    [  ELEN-1:0] b;
  (* anyseq *)logic    [  ELEN-1:0] c;

  logic    [  ELEN-1:0] result;
  logic    [2*ELEN-1:0] product;

  vec_mul_lane #(
      .ELEN(ELEN)
  ) dut (
      .clk    (clk),
      .core_en(core_en),
      .op     (op),
      .vsew   (vsew),
      .a      (a),
      .b      (b),
      .c      (c),
      .result (result),
      .product(product)
  );

  function automatic logic is_widen(input vec_op_e o);
    return (o == VEC_WMUL) || (o == VEC_WMULU) || (o == VEC_WMULSU) || (o == VEC_WMACC) ||
        (o == VEC_WMACCU) || (o == VEC_WMACCSU) || (o == VEC_WMACCUS);
  endfunction

  function automatic logic is_mul(input vec_op_e o);
    return is_widen(o) || (o == VEC_MUL) || (o == VEC_MULH) || (o == VEC_MULHU) || (o == VEC_MULHSU)
        || (o == VEC_MACC) || (o == VEC_NMSAC) || (o == VEC_MADD) || (o == VEC_NMSUB);
  endfunction

  // vs2 times vs1
  logic a_sgn;
  logic b_sgn;
  assign a_sgn = (op == VEC_MUL) || (op == VEC_MULH) || (op == VEC_MULHSU) || (op == VEC_WMUL) ||
      (op == VEC_WMULSU) || (op == VEC_WMACC) || (op == VEC_WMACCUS);
  assign b_sgn = (op == VEC_MUL) || (op == VEC_MULH) || (op == VEC_WMUL) || (op == VEC_WMACC) ||
      (op == VEC_WMACCSU);

  // Extended operands
  logic signed [    ELEN:0] ext_a[Widths];
  logic signed [    ELEN:0] ext_b[Widths];
  logic signed [    ELEN:0] xa;
  logic signed [    ELEN:0] xb;
  logic signed [2*ELEN+1:0] full;

  for (genvar w = 0; w < Widths; w++) begin : g_ext
    localparam int S = 8 << w;
    assign ext_a[w] = {{(ELEN + 1 - S) {a_sgn && a[S-1]}}, a[S-1:0]};
    assign ext_b[w] = {{(ELEN + 1 - S) {b_sgn && b[S-1]}}, b[S-1:0]};
  end

  always_comb begin
    xa = '0;
    xb = '0;
    for (int s = 0; s < Widths; s++) begin
      if (vsew == 3'(s) && is_mul(op) && (!is_widen(op) || s < Widths - 1)) begin
        xa = ext_a[s];
        xb = ext_b[s];
      end
    end
  end

  assign full = xa * xb;

  // Accepted element
  logic                 f_valid = 1'b0;
  logic                 f_held = 1'b0;
  vec_op_e              chk_op;
  logic    [ VsewW-1:0] chk_sew;
  logic    [  ELEN-1:0] chk_a;
  logic    [  ELEN-1:0] chk_b;
  logic    [  ELEN-1:0] chk_c;
  logic    [2*ELEN-1:0] chk_full;

  always @(posedge clk) begin
    f_held <= f_valid && !core_en;
    if (core_en) begin
      f_valid  <= 1'b1;
      chk_op   <= op;
      chk_sew  <= vsew;
      chk_a    <= a;
      chk_b    <= b;
      chk_c    <= c;
      chk_full <= full[2*ELEN-1:0];
    end
  end

  // Reference per SEW
  logic [  ELEN-1:0] ref_res [Widths];
  logic [2*ELEN-1:0] ref_prod[Widths];

  for (genvar w = 0; w < Widths; w++) begin : g_ref
    localparam int S = 8 << w;
    localparam int P = 2 * S;

    logic [P-1:0] prod;
    logic [P-1:0] acc;

    assign prod = chk_full[P-1:0];

    if (P <= ELEN) begin : g_wide
      assign acc = chk_c[P-1:0];
    end else begin : g_no_wide
      assign acc = '0;
    end

    logic [     S-1:0] lo_sum;
    logic [     S-1:0] lo_dif;
    logic [     P-1:0] wide_sum;
    logic [2*ELEN-1:0] r;

    assign lo_sum   = prod[S-1:0] + chk_c[S-1:0];
    assign lo_dif   = chk_c[S-1:0] - prod[S-1:0];
    assign wide_sum = prod + acc;

    always_comb begin
      r = '0;
      if (chk_op == VEC_MUL) r[S-1:0] = prod[S-1:0];
      else if (chk_op == VEC_MULH) r[S-1:0] = prod[P-1:S];
      else if (chk_op == VEC_MULHU) r[S-1:0] = prod[P-1:S];
      else if (chk_op == VEC_MULHSU) r[S-1:0] = prod[P-1:S];
      else if (chk_op == VEC_MACC) r[S-1:0] = lo_sum;
      else if (chk_op == VEC_MADD) r[S-1:0] = lo_sum;
      else if (chk_op == VEC_NMSAC) r[S-1:0] = lo_dif;
      else if (chk_op == VEC_NMSUB) r[S-1:0] = lo_dif;
      else if (chk_op == VEC_WMUL || chk_op == VEC_WMULU || chk_op == VEC_WMULSU) r[P-1:0] = prod;
      else if (is_widen(chk_op)) r[P-1:0] = wide_sum;
    end

    assign ref_res[w]  = r[ELEN-1:0];
    assign ref_prod[w] = {{(2 * ELEN - P) {1'b0}}, prod};
  end

  // Legal SEW EEW
  logic [  ELEN-1:0] exp_res;
  logic [2*ELEN-1:0] exp_prod;
  logic [  ELEN-1:0] res_mask;
  logic [2*ELEN-1:0] prod_mask;
  logic              sew_ok;
  logic              checked;

  always_comb begin
    exp_res  = '0;
    exp_prod = '0;
    for (int s = 0; s < Widths; s++) begin
      if (chk_sew == 3'(s)) begin
        exp_res  = ref_res[s];
        exp_prod = ref_prod[s];
      end
    end
  end
  assign res_mask = is_widen(
      chk_op
  ) ? ELEN'((64'(1) << (16 << chk_sew)) - 64'(1)) : ELEN'((64'(1) << (8 << chk_sew)) - 64'(1));
  assign prod_mask = (is_widen(
      chk_op
  ) || chk_op == VEC_MULH || chk_op == VEC_MULHU || chk_op == VEC_MULHSU) ? (2 * ELEN)'
      ((128'(1) << (16 << chk_sew)) - 128'(1)) : (2 * ELEN)'((128'(1) << (8 << chk_sew)) - 128'(1));
  assign sew_ok = is_widen(chk_op) ? (chk_sew < SewTop) : (chk_sew <= SewTop);
  assign checked = f_valid && is_mul(chk_op) && sew_ok;

  always @(posedge clk) begin
    if (checked) begin
      assert ((result & res_mask) == (exp_res & res_mask));
      assert ((product & prod_mask) == (exp_prod & prod_mask));
    end

    // Ops per SEW
    for (int s = 0; s < Widths; s++) begin
      cover (checked && chk_sew == 3'(s) && chk_op == VEC_MUL && result[(8<<s)-1]);
      cover (checked && chk_sew == 3'(s) && chk_op == VEC_MULH && chk_a[(8<<s)-1] &&
             !chk_b[(8<<s)-1] && result != '0);
      cover (checked && chk_sew == 3'(s) && chk_op == VEC_MULHU && result[(8<<s)-1]);
      cover (checked && chk_sew == 3'(s) && chk_op == VEC_MULHSU && chk_a[(8<<s)-1] &&
             chk_b[(8<<s)-1]);
      cover (checked && chk_sew == 3'(s) && chk_op == VEC_MACC && chk_c != '0);
      cover (checked && chk_sew == 3'(s) && chk_op == VEC_NMSUB && chk_c != '0);
      if (s < Widths - 1) begin
        cover (checked && chk_sew == 3'(s) && chk_op == VEC_WMUL && result[(16<<s)-1]);
        cover (checked && chk_sew == 3'(s) && chk_op == VEC_WMULU && result[(16<<s)-1]);
        cover (checked && chk_sew == 3'(s) && chk_op == VEC_WMULSU && chk_a[(8<<s)-1]);
        cover (checked && chk_sew == 3'(s) && chk_op == VEC_WMACC && chk_c != '0);
        cover (checked && chk_sew == 3'(s) && chk_op == VEC_WMACCU && chk_c != '0);
        cover (checked && chk_sew == 3'(s) && chk_op == VEC_WMACCSU && chk_b[(8<<s)-1]);
        cover (checked && chk_sew == 3'(s) && chk_op == VEC_WMACCUS && chk_a[(8<<s)-1]);
      end
    end

    // Stall hold
    cover (checked && f_held && result != '0);
  end

endmodule

`default_nettype wire
