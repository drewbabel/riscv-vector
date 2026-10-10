`default_nettype none

module vec_mul_lane
  import vec_pkg::*;
#(
    parameter int ELEN = arch_pkg::ELEN
) (
    input  wire vec_op_e              op,
    input  wire          [       2:0] vsew,
    input  wire          [  ELEN-1:0] a,
    input  wire          [  ELEN-1:0] b,
    input  wire          [  ELEN-1:0] c,       //Addend for multiply-add operations (#34)
    output logic         [  ELEN-1:0] result,
    output logic         [2*ELEN-1:0] product
);

  typedef enum logic [2:0] {
    SEW_8  = 3'b000,
    SEW_16 = 3'b001,
    SEW_32 = 3'b010
  } vsew_e;


  logic signed [ELEN:0] mult_a, mult_b;
  logic signed [2*ELEN+1:0] full_product;

  logic a_signed, b_signed;

  int unsigned width;

  logic [ELEN-1:0] result_mask;
  logic [2*ELEN-1:0] product_mask;
  logic [ELEN:0] operand_mask;

  logic mul_valid;


  always_comb begin
    case (vsew)
      SEW_8:   width = 8;
      SEW_16:  width = 16;
      SEW_32:  width = 32;
      default: width = 0;
    endcase
  end


  assign a_signed = (op == VEC_MUL) || (op == VEC_MULH) || (op == VEC_MULHSU);
  assign b_signed = (op == VEC_MUL) || (op == VEC_MULH);


  assign mul_valid = (op == VEC_MUL) || (op == VEC_MULH) || (op == VEC_MULHU) || (op == VEC_MULHSU);


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


  always_comb begin
    result = '0;
    product = '0;
    result_mask = '0;
    product_mask = '0;

    if ((width != 0) && mul_valid) begin
      result_mask = {ELEN{1'b1}} >> (ELEN - width);
      product_mask = {2 * ELEN{1'b1}} >> (2 * ELEN - (2 * width));

      product = full_product[2*ELEN-1:0] & product_mask;

      case (op)
        VEC_MUL: begin
          result = full_product[ELEN-1:0] & result_mask;
        end

        VEC_MULH, VEC_MULHU, VEC_MULHSU: begin
          result = ELEN'(full_product >> width) & result_mask;
        end

        default: begin
          result = '0;
        end

      endcase
    end
  end


endmodule

`default_nettype wire
