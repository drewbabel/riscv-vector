`default_nettype none

module fp_unit_stub
  import fp_pkg::*;
#(
    parameter  int XLEN  = arch_pkg::XLEN,
    parameter  int NREGS = arch_pkg::NumRegs,
    localparam int AddrW = $clog2(NREGS)
) (
    input wire clk,
    input wire rst_n,
    input wire core_en,

    input wire                  start,
    input wire                  xstart,
    input wire                  xack,
    input fp_unit_e             unit,
    input wire                  sub,
    input wire                  neg_prod,
    input wire                  neg_add,
    input wire                  to_int,
    input wire                  is_unsigned,
    input wire                  sqrt,
    input wire      [      4:0] funct5,
    input wire      [      2:0] funct3,
    input wire      [      2:0] rm,
    input wire      [AddrW-1:0] rd,
    input wire      [ FLEN-1:0] a,
    input wire      [ FLEN-1:0] b,
    input wire      [ FLEN-1:0] c,
    input wire      [ XLEN-1:0] xa,

    output logic ready,
    output logic idle,
    output logic [NREGS-1:0] reg_busy,

    output logic             wb_valid,
    output logic [AddrW-1:0] wb_rd,
    output logic [ FLEN-1:0] wb_data,
    output logic [      4:0] wb_flags,

    output logic            xvalid,
    output logic [XLEN-1:0] xresult,
    output logic [     4:0] xflags
);

  assign ready    = 1'b1;
  assign idle     = 1'b1;
  assign reg_busy = '0;
  assign wb_valid = 1'b0;
  assign wb_rd    = '0;
  assign wb_data  = '0;
  assign wb_flags = '0;
  assign xvalid   = 1'b0;
  assign xresult  = '0;
  assign xflags   = '0;

endmodule

`default_nettype wire
