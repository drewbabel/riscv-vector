`default_nettype none

module vec_alu_lane
  import vec_pkg::*;
#(
    parameter int W = 32
) (
    input  vec_op_e         op,
    input  logic            vm,
    input  logic            mask_bit,
    input  logic    [W-1:0] a,
    input  logic    [W-1:0] b,
    output logic    [W-1:0] result
);

  localparam int Shamt = $clog2(W);

  logic [Shamt-1:0] shamt;
  logic             sel;

  // Shift amount
  assign shamt = b[Shamt-1:0];

  // Merge select
  assign sel   = vm || mask_bit;

  // One element
  always_comb begin
    case (op)
      VEC_ADD:   result = a + b;
      VEC_SUB:   result = a - b;
      VEC_RSUB:  result = b - a;
      VEC_AND:   result = a & b;
      VEC_OR:    result = a | b;
      VEC_XOR:   result = a ^ b;
      VEC_SLL:   result = W'(a << shamt);
      VEC_SRL:   result = W'(a >> shamt);
      VEC_SRA:   result = W'($signed(a) >>> shamt);
      VEC_MINU:  result = (a < b) ? a : b;
      VEC_MIN:   result = ($signed(a) < $signed(b)) ? a : b;
      VEC_MAXU:  result = (a > b) ? a : b;
      VEC_MAX:   result = ($signed(a) > $signed(b)) ? a : b;
      VEC_ADC:   result = a + b + W'(mask_bit);
      VEC_SBC:   result = a - b - W'(mask_bit);
      VEC_MERGE: result = sel ? b : a;
      default:   result = '0;
    endcase
  end

endmodule

`default_nettype wire
