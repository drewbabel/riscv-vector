`default_nettype none

module vec_config
  import opcode_pkg::*;
#(
    parameter int XLEN = 32,
    parameter int VLEN = 128
) (
    input  wire  [XLEN-1:0] instr,
    input  wire  [XLEN-1:0] rs1_data,
    input  wire  [XLEN-1:0] rs2_data,
    input  wire  [     7:0] vl_q,
    input  wire  [XLEN-1:0] vtype_q,

    output logic            is_vset,
    output logic [     7:0] vl_d,
    output logic [XLEN-1:0] vtype_d
);



endmodule

`default_nettype wire
