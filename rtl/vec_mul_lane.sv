`default_nettype none

module vec_mul_lane
  import vec_pkg::*;
#(
    parameter int ELEN = 32
) (
    input  vec_op_e              op,      //operation
    input  logic    [       2:0] vsew,    //[000 -> 8 bits] [001 -> 16 bits] [010 -> 32 bits]
    input  logic    [  ELEN-1:0] a,       //multiplicand vector
    input  logic    [  ELEN-1:0] b,       //multiplier vector
    input  logic    [  ELEN-1:0] c,       //ignore for now
    output logic    [  ELEN-1:0] result,  //vsew chosen product
    output logic    [2*ELEN-1:0] product  //total product
);

  typedef enum logic [2:0] {
    SEW_8  = 3'b000,
    SEW_16 = 3'b001,
    SEW_32 = 3'b010
  } vsew_e;


  logic signed [ELEN:0] mult_a, mult_b;  //ELEN+1 bit
  logic signed [2*ELEN+1:0] full_product;  //2*(ELEN+1) bit

  //multiplicand and multiplier assign combinational blcok
  always_comb begin
    mult_a = '0;
    mult_b = '0;


    case (vsew)
      SEW_8: begin
        case (op)
          VEC_MUL, VEC_MULH: begin
            mult_a = {{(ELEN + 1 - 8) {a[7]}}, a[7:0]};
            mult_b = {{(ELEN + 1 - 8) {b[7]}}, b[7:0]};
          end

          VEC_MULHU: begin
            mult_a = {{(ELEN + 1 - 8) {1'b0}}, a[7:0]};
            mult_b = {{(ELEN + 1 - 8) {1'b0}}, b[7:0]};
          end

          VEC_MULHSU: begin
            mult_a = {{(ELEN + 1 - 8) {a[7]}}, a[7:0]};
            mult_b = {{(ELEN + 1 - 8) {1'b0}}, b[7:0]};
          end

          default: begin
          end

        endcase
      end

      SEW_16: begin
        case (op)
          VEC_MUL, VEC_MULH: begin
            mult_a = {{(ELEN + 1 - 16) {a[15]}}, a[15:0]};
            mult_b = {{(ELEN + 1 - 16) {b[15]}}, b[15:0]};
          end

          VEC_MULHU: begin
            mult_a = {{(ELEN + 1 - 16) {1'b0}}, a[15:0]};
            mult_b = {{(ELEN + 1 - 16) {1'b0}}, b[15:0]};
          end

          VEC_MULHSU: begin
            mult_a = {{(ELEN + 1 - 16) {a[15]}}, a[15:0]};
            mult_b = {{(ELEN + 1 - 16) {1'b0}}, b[15:0]};
          end

          default: begin
          end

        endcase
      end

      SEW_32: begin
        case (op)
          VEC_MUL, VEC_MULH: begin
            mult_a = {{(ELEN + 1 - 32) {a[31]}}, a[31:0]};
            mult_b = {{(ELEN + 1 - 32) {b[31]}}, b[31:0]};
          end

          VEC_MULHU: begin
            mult_a = {{(ELEN + 1 - 32) {1'b0}}, a[31:0]};
            mult_b = {{(ELEN + 1 - 32) {1'b0}}, b[31:0]};
          end

          VEC_MULHSU: begin
            mult_a = {{(ELEN + 1 - 32) {a[31]}}, a[31:0]};
            mult_b = {{(ELEN + 1 - 32) {1'b0}}, b[31:0]};
          end

          default: begin
          end

        endcase
      end

      default: begin
      end

    endcase
  end

  //multiplier
  assign full_product = mult_a * mult_b;

  //combinational block to select significant parts
  always_comb begin
    result  = '0;
    product = '0;

    case (vsew)
      SEW_8: begin
        product[15:0] = full_product[15:0];
        case (op)
          VEC_MUL: begin
            result[7:0] = full_product[7:0];
          end

          VEC_MULH, VEC_MULHU, VEC_MULHSU: begin
            result[7:0] = full_product[15:8];
          end

          default: begin
          end

        endcase
      end

      SEW_16: begin
        product[31:0] = full_product[31:0];

        case (op)
          VEC_MUL: begin
            result[15:0] = full_product[15:0];
          end

          VEC_MULH, VEC_MULHU, VEC_MULHSU: begin
            result[15:0] = full_product[31:16];
          end

          default: begin
          end

        endcase

      end

      SEW_32: begin
        product[63:0] = full_product[63:0];

        case (op)
          VEC_MUL: begin
            result[31:0] = full_product[31:0];
          end

          VEC_MULH, VEC_MULHU, VEC_MULHSU: begin
            result[31:0] = full_product[63:32];
          end

          default: begin
          end

        endcase
      end

      default: begin
      end

    endcase
  end


endmodule

`default_nettype wire
