`default_nettype none

module vec_alu
  import vec_pkg::*;
#(
    parameter  int DLEN     = 128,
    localparam int MaxElems = DLEN / 8
) (
    input  vec_op_e                 op,
    input  vec_src_e                src,
    input  logic     [         2:0] vsew,
    input  logic                    vm,
    input  logic     [MaxElems-1:0] mask_bits,
    input  logic     [    DLEN-1:0] vs2_data,
    input  logic     [    DLEN-1:0] vs1_data,
    input  logic     [        31:0] xdata,
    input  logic     [         4:0] simm,
    output logic     [    DLEN-1:0] result
);

  logic [DLEN-1:0] res8;
  logic [DLEN-1:0] res16;
  logic [DLEN-1:0] res32;

  // Scalar operand
  logic [31:0] scalar;
  assign scalar = (src == VEC_SRC_VI) ? {{27{simm[4]}}, simm} : xdata;

  // Byte elements
  for (genvar e = 0; e < DLEN / 8; e++) begin : g_e8
    logic [7:0] b8;
    assign b8 = (src == VEC_SRC_VV) ? vs1_data[e*8+:8] : scalar[7:0];
    vec_alu_lane #(
        .W(8)
    ) u_lane (
        .op(op),
        .vm(vm),
        .mask_bit(mask_bits[e]),
        .a(vs2_data[e*8+:8]),
        .b(b8),
        .result(res8[e*8+:8])
    );
  end

  // Half elements
  for (genvar e = 0; e < DLEN / 16; e++) begin : g_e16
    logic [15:0] b16;
    assign b16 = (src == VEC_SRC_VV) ? vs1_data[e*16+:16] : scalar[15:0];
    vec_alu_lane #(
        .W(16)
    ) u_lane (
        .op(op),
        .vm(vm),
        .mask_bit(mask_bits[e]),
        .a(vs2_data[e*16+:16]),
        .b(b16),
        .result(res16[e*16+:16])
    );
  end

  // Word elements
  for (genvar e = 0; e < DLEN / 32; e++) begin : g_e32
    logic [31:0] b32;
    assign b32 = (src == VEC_SRC_VV) ? vs1_data[e*32+:32] : scalar;
    vec_alu_lane #(
        .W(32)
    ) u_lane (
        .op(op),
        .vm(vm),
        .mask_bit(mask_bits[e]),
        .a(vs2_data[e*32+:32]),
        .b(b32),
        .result(res32[e*32+:32])
    );
  end

  // Width select
  always_comb begin
    case (vsew)
      3'd0:    result = res8;
      3'd1:    result = res16;
      default: result = res32;
    endcase
  end

endmodule

`default_nettype wire
