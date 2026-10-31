`default_nettype none

module vec_unit_stub
  import vec_pkg::*;
#(
    parameter  int XLEN      = arch_pkg::XLEN,
    parameter  int AWIDTH    = arch_pkg::RegAddrW,
    parameter  int VLEN      = arch_pkg::VLEN,
    parameter  int ELEN      = arch_pkg::ELEN,
    parameter  int MUL_LANES = arch_pkg::MulLanes,
    localparam int VlW       = $clog2(VLEN + 1),
    localparam int NRegs     = 1 << AWIDTH
) (
`ifdef RISCV_FORMAL
    output logic [VecTagW-1:0] dbg_vec_tag,
    output logic               dbg_vec_retire,
    output logic [  NRegs-1:0] dbg_vec_wregs,
    output logic               dbg_vec_idle,
    output logic               dbg_vec_accept,
`endif
    input  wire                clk,
    input  wire                rst_n,
    input  wire                core_en,

    input wire vec_dec_t            dec,
    input wire                      instr_valid,
    input wire                      cancel,
    input wire                      ex_advance,
    input wire           [XLEN-1:0] xdata,
    input wire           [XLEN-1:0] xstride,
    input wire           [XLEN-1:0] fdata,

    input wire           vill,
    input wire [VlW-1:0] vl,
    input wire [    2:0] vsew,
    input wire [    2:0] vlmul,

    input  wire  [  VLEN-1:0] mem_rdata,
    input  wire               mem_ready,
    output logic              mem_req,
    output logic [  XLEN-1:0] mem_addr,
    output logic [  VLEN-1:0] mem_wdata,
    output logic [VLEN/8-1:0] mem_wstrb,

    output logic            mem_misaligned,
    output logic [XLEN-1:0] mem_bad_addr,

    input  wire             csr_we,
    input  wire  [    11:0] csr_waddr,
    input  wire  [XLEN-1:0] csr_wdata,
    input  wire             csr_wait,
    output logic [     1:0] vxrm,
    output logic            vxsat,

    input  wire  [2:0] frm,
    output logic [4:0] fflags,

    input wire vstart_set,

    output logic            xreg_valid,
    output logic [XLEN-1:0] xreg_result,

    output logic is_vector,
    output logic vec_hold,
    output logic vec_idle,
    output logic load_pending,
    output logic store_pending
);

  if (MUL_LANES * ELEN > VLEN) begin : g_lanes
    $error("MUL_LANES * ELEN must not exceed VLEN");
  end

`ifdef RISCV_FORMAL
  assign dbg_vec_tag    = '0;
  assign dbg_vec_retire = 1'b0;
  assign dbg_vec_wregs  = '0;
  assign dbg_vec_idle   = 1'b1;
  assign dbg_vec_accept = 1'b0;
`endif
  assign mem_req        = 1'b0;
  assign mem_addr       = '0;
  assign mem_wdata      = '0;
  assign mem_wstrb      = '0;
  assign mem_misaligned = 1'b0;
  assign mem_bad_addr   = '0;
  assign vxrm           = '0;
  assign vxsat          = 1'b0;
  assign fflags         = '0;
  assign xreg_valid     = 1'b0;
  assign xreg_result    = '0;
  assign is_vector      = 1'b0;
  assign vec_hold       = 1'b0;
  assign vec_idle       = 1'b1;
  assign load_pending   = 1'b0;
  assign store_pending  = 1'b0;

endmodule

`default_nettype wire
