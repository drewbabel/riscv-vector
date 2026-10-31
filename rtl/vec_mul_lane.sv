`default_nettype none

module vec_mul_lane
  import vec_pkg::*;
#(
    parameter int ELEN = arch_pkg::ELEN
) (
    input  wire                               clk,
    input  wire                               core_en,
    input  wire vec_op_e                      op,
    input  wire          [vec_pkg::VsewW-1:0] vsew,
    input  wire          [          ELEN-1:0] a,
    input  wire          [          ELEN-1:0] b,
    input  wire          [          ELEN-1:0] c,
    output logic         [          ELEN-1:0] result,
    output logic         [        2*ELEN-1:0] product
);

  if (ELEN != 32) begin : g_elen
    $error("ELEN must be 32 (Zve32f)");
  end

  localparam logic [2:0] SewTop = 3'($clog2(ELEN / 8));

  function automatic int unsigned sew_width(input logic [vec_pkg::VsewW-1:0] sew);
    sew_width = (sew <= SewTop) ? 8 << sew : 0;
  endfunction

  function automatic logic mul_op(input vec_op_e o);
    case (o)
      VEC_MUL, VEC_MULH, VEC_MULHU, VEC_MULHSU, VEC_MACC, VEC_NMSAC, VEC_MADD, VEC_NMSUB, VEC_WMUL,
          VEC_WMULU, VEC_WMULSU, VEC_WMACC, VEC_WMACCU, VEC_WMACCSU, VEC_WMACCUS:
      mul_op = 1'b1;
      default: mul_op = 1'b0;
    endcase
  endfunction

  function automatic logic widen_op(input vec_op_e o);
    case (o)
      VEC_WMUL, VEC_WMULU, VEC_WMULSU, VEC_WMACC, VEC_WMACCU, VEC_WMACCSU, VEC_WMACCUS:
      widen_op = 1'b1;
      default: widen_op = 1'b0;
    endcase
  endfunction

  function automatic logic lane_valid(input vec_op_e o, input int unsigned w);
    lane_valid = mul_op(o) && (!widen_op(o) || (2 * w <= ELEN));
  endfunction

  // Product stage
  logic signed [ELEN:0] mult_a, mult_b;
  logic signed [2*ELEN+1:0] full_product;
  logic a_signed, b_signed;
  int unsigned width;
  logic [ELEN:0] operand_mask;
  logic mul_valid;

  assign width = sew_width(vsew);
  assign mul_valid = lane_valid(op, width);
  assign a_signed = (op == VEC_MUL) || (op == VEC_MULH) || (op == VEC_MULHSU) || (op == VEC_WMUL) ||
      (op == VEC_WMULSU) || (op == VEC_WMACC) || (op == VEC_WMACCUS);
  assign b_signed = (op == VEC_MUL) || (op == VEC_MULH) || (op == VEC_WMUL) || (op == VEC_WMACC) ||
      (op == VEC_WMACCSU);

  always_comb begin
    mult_a = '0;
    mult_b = '0;
    operand_mask = '0;

    if ((width != 0) && mul_valid) begin
      operand_mask = {ELEN + 1{1'b1}} >> (ELEN + 1 - width);

      mult_a = {1'b0, a} & operand_mask;
      mult_b = {1'b0, b} & operand_mask;

      if (a_signed && a[width-1]) begin
        mult_a = mult_a | ~operand_mask;
      end

      if (b_signed && b[width-1]) begin
        mult_b = mult_b | ~operand_mask;
      end
    end
  end

  assign full_product = mult_a * mult_b;

  // Product register
  logic signed [2*ELEN+1:0] product_q;
  vec_op_e op_q;
  logic [vec_pkg::VsewW-1:0] vsew_q;
  logic [ELEN-1:0] c_q;

  always_ff @(posedge clk) begin
    if (core_en) begin
      product_q <= full_product;
      op_q      <= op;
      vsew_q    <= vsew;
      c_q       <= c;
    end
  end

  // Result stage
  int unsigned width_q;
  logic mul_valid_q;
  logic [ELEN-1:0] result_mask;
  logic [2*ELEN-1:0] product_mask;

  assign width_q = sew_width(vsew_q);
  assign mul_valid_q = lane_valid(op_q, width_q);

  always_comb begin
    result = '0;
    product = '0;
    result_mask = '0;
    product_mask = '0;

    if ((width_q != 0) && mul_valid_q) begin
      result_mask = {ELEN{1'b1}} >> (ELEN - width_q);
      product_mask = {2 * ELEN{1'b1}} >> (2 * ELEN - (2 * width_q));

      product = product_q[2*ELEN-1:0] & product_mask;

      case (op_q)
        VEC_MUL: begin
          result = product_q[ELEN-1:0] & result_mask;
        end

        VEC_MULH, VEC_MULHU, VEC_MULHSU: begin
          result = ELEN'(product_q >> width_q) & result_mask;
        end

        VEC_MACC, VEC_MADD: begin
          result = (product_q[ELEN-1:0] + c_q) & result_mask;
        end

        VEC_NMSAC, VEC_NMSUB: begin
          result = (c_q - product_q[ELEN-1:0]) & result_mask;
        end

        VEC_WMUL, VEC_WMULU, VEC_WMULSU: begin
          result = product[ELEN-1:0];
        end

        VEC_WMACC, VEC_WMACCU, VEC_WMACCSU, VEC_WMACCUS: begin
          result = (product[ELEN-1:0] + c_q) & product_mask[ELEN-1:0];
        end

        default: begin
          result = '0;
        end

      endcase
    end
  end

endmodule

`default_nettype wire
