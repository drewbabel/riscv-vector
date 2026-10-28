`default_nettype none

module vec_alu
  import vec_pkg::*;
#(
    parameter  int DLEN     = arch_pkg::VLEN,
    parameter  int ELEN     = arch_pkg::ELEN,
    parameter  int XLEN     = arch_pkg::XLEN,
    localparam int MaxElems = DLEN / 8,
    localparam int Widths   = $clog2(ELEN / 8) + 1
) (
    input  wire vec_op_e                       op,
    input  wire vec_src_e                      src,
    input  wire           [vec_pkg::VsewW-1:0] vsew,
    input  wire                                vm,
    input  wire           [      MaxElems-1:0] mask_bits,
    input  wire           [          DLEN-1:0] vs2_data,
    input  wire           [          DLEN-1:0] vs1_data,
    input  wire           [          XLEN-1:0] xdata,
    input  wire           [               4:0] simm,
    output logic          [          DLEN-1:0] result
);

  if (ELEN != 32) begin : g_elen
    $error("ELEN must be 32 (Zve32f)");
  end

  logic [DLEN-1:0] res_w [Widths];
  logic            is_vv;

  assign is_vv = (src == VEC_SRC_VV);

  // Scalar operand
  logic [XLEN-1:0] scalar;
  assign scalar = (src == VEC_SRC_VI) ? {{(XLEN - 5) {simm[4]}}, simm} : xdata;

  for (genvar w = 0; w < Widths; w++) begin : g_w
    localparam int EW = 8 << w;
    for (genvar e = 0; e < DLEN / EW; e++) begin : g_e
      logic [EW-1:0] b;
      assign b = is_vv ? vs1_data[e*EW+:EW] : EW'($signed(scalar));
      vec_alu_lane #(
          .W(EW)
      ) u_lane (
          .op(op),
          .vm(vm),
          .mask_bit(mask_bits[e]),
          .a(vs2_data[e*EW+:EW]),
          .b(b),
          .result(res_w[w][e*EW+:EW])
      );
    end
  end

  assign result = res_w[vec_sew_index(vsew, Widths)];

endmodule

`default_nettype wire
