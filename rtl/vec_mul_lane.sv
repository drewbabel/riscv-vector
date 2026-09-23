`default_nettype none

module vec_mul_lane
  import vec_pkg::*;
(
    input  vec_op_e        op,          //operation
    input  logic    [ 2:0] vsew,        //[000 -> 8 bits] [001 -> 16 bits] [010 -> 32 bits]
    input  logic    [31:0] a,           //multiplicand vector
    input  logic    [31:0] b,           //multiplier vector
    input  logic    [31:0] c,           //ignore for now
    output logic    [31:0] result,      //vsew chosen product
    output logic    [63:0] product      //total product
);

  typedef enum logic [2:0] {
    SEW_8 = 3'b000,
    SEW_16 = 3'b001,
    SEW_32 = 3'b010
  } vsew_e;

  always_comb begin : multiply_logic_comb
    result = 32'b0;
    product = 64'b0;

    case (vsew)
      SEW_8: begin
        case (op)
          VEC_MUL: begin
            product = {{8{a[7]}}, a[7:0]} * {{8{b[7]}}, b[7:0]};
            result = product[7:0];
          end
          VEC_MULH: begin
            product = {{8{a[7]}}, a[7:0]} * {{8{b[7]}}, b[7:0]};
            result = product[15:8];
          end
          VEC_MULHU: begin
            product = {{8{1'b0}}, a[7:0]} * {{8{1'b0}}, b[7:0]};
            result = product[15:8];
          end
          VEC_MULHSU: begin
            product = {{8{a[7]}}, a[7:0]} * {{8{1'b0}}, b[7:0]};
            result = product[15:8];
          end
          default: begin
          end
        endcase
      end
      SEW_16: begin
        case (op)
          VEC_MUL: begin
            product = {{16{a[15]}}, a[15:0]} * {{16{b[15]}}, b[15:0]};
            result = product[15:0];
          end
          VEC_MULH: begin
            product = {{16{a[15]}}, a[15:0]} * {{16{b[15]}}, b[15:0]};
            result = product[31:16];
          end
          VEC_MULHU: begin
            product = {{16{1'b0}}, a[15:0]} * {{16{1'b0}}, b[15:0]};
            result = product[31:16];
          end
          VEC_MULHSU: begin
            product = {{16{a[15]}}, a[15:0]} * {{16{1'b0}}, b[15:0]};
            result = product[31:16];
          end
          default: begin
          end
        endcase
      end
      SEW_32: begin
        case (op)
          VEC_MUL: begin
            product = {{32{a[31]}}, a[31:0]} * {{32{b[31]}}, b[31:0]};
            result = product[31:0];
          end
          VEC_MULH: begin
            product = {{32{a[31]}}, a[31:0]} * {{32{b[31]}}, b[31:0]};
            result = product[63:32];
          end
          VEC_MULHU: begin
            product = {{32{1'b0}}, a[31:0]} * {{32{1'b0}}, b[31:0]};
            result = product[63:32];
          end
          VEC_MULHSU: begin
            product = {{32{a[31]}}, a[31:0]} * {{32{1'b0}}, b[31:0]};
            result = product[63:32];
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
