`default_nettype none

module riscv_pipelined
  import alu_pkg::*;
  import cache_pkg::*;
#(
    parameter  int XLEN      = arch_pkg::XLEN,
    parameter  int VLEN      = arch_pkg::VLEN,
    parameter  int ELEN      = arch_pkg::ELEN,
    parameter  int MUL_LANES = arch_pkg::MulLanes,
    parameter  bit GSHARE_EN = 1'b1,
`ifdef RISCV_FORMAL
    localparam int VlW       = $clog2(VLEN + 1),
    localparam int VstartW   = $clog2(VLEN),
`endif
    localparam int StrbW     = XLEN / 8,
    localparam int ILEN      = arch_pkg::ILEN
) (
`ifdef SIM_BACKDOOR
    output logic                          sim_branch,
    output logic                          sim_branch_taken,
    output logic                          sim_mispredict,
    output logic                          sim_muldiv_hold,
`endif
`ifdef RISCV_FORMAL
    output logic                          dbg_valid,
    output logic [              ILEN-1:0] dbg_insn,
    output logic [              XLEN-1:0] dbg_pc_rdata,
    output logic [              XLEN-1:0] dbg_pc_wdata,
    output logic [              XLEN-1:0] dbg_rs1_rdata,
    output logic [              XLEN-1:0] dbg_rs2_rdata,
    output logic [              XLEN-1:0] dbg_rd_wdata,
    output logic                          dbg_reg_write,
    output logic [              XLEN-1:0] dbg_mem_addr,
    output logic [             StrbW-1:0] dbg_mem_wmask,
    output logic [              XLEN-1:0] dbg_mem_wdata,
    output logic [              XLEN-1:0] dbg_mem_rdata,
    output logic                          dbg_trap,
    output logic [              XLEN-1:0] dbg_csr_wdata,
    output logic [              XLEN-1:0] dbg_mscratch,
    output logic [              XLEN-1:0] dbg_mstatus,
    output logic [              XLEN-1:0] dbg_mtvec,
    output logic [              XLEN-1:0] dbg_mepc,
    output logic [              XLEN-1:0] dbg_mcause,
    output logic [              XLEN-1:0] dbg_mtval,
    output logic [              XLEN-1:0] dbg_mie,
    output logic [              XLEN-1:0] dbg_mip,
    output logic [              XLEN-1:0] dbg_mcycle,
    output logic [              XLEN-1:0] dbg_minstret,
    output logic [              XLEN-1:0] dbg_mcycleh,
    output logic [              XLEN-1:0] dbg_minstreth,
    output logic [     fp_pkg::FlagW-1:0] dbg_fflags,
    output logic [               VlW-1:0] dbg_vl,
    output logic [                   7:0] dbg_vtype_bits,
    output logic                          dbg_vtype_ill,
    output logic [           VstartW-1:0] dbg_vstart,
    output logic [  vec_pkg::VecTagW-1:0] dbg_vec_tag,
    output logic                          dbg_vec_retire,
    output logic [ arch_pkg::NumRegs-1:0] dbg_vec_wregs,
    output logic                          dbg_vec_idle,
    output logic                          dbg_ex_commit,
    output logic [              ILEN-1:0] dbg_ex_insn,
    output logic                          dbg_vec_accept,
    output logic                          dbg_fetch_en,
    output logic                          dbg_id_en,
    output logic                          dbg_fp_idle,
    output logic                          dbg_fp_wb_valid,
    output logic [arch_pkg::RegAddrW-1:0] dbg_fp_wb_rd,
    output logic [      fp_pkg::FLEN-1:0] dbg_fp_wb_data,
    output logic                          dbg_fp_load_wb,
    output logic [arch_pkg::RegAddrW-1:0] dbg_fp_load_rd,
    output logic [              XLEN-1:0] dbg_fp_load_data,
    output logic [       fp_pkg::RmW-1:0] dbg_frm,
    output logic                          dbg_s_take,
    output logic                          dbg_v_take,
`endif
    input  wire                           clk,
    input  wire                           core_en,
    input  wire                           rst_n,
    input  wire  [              ILEN-1:0] instr,
    input  wire  [          LineBits-1:0] read_data,
    input  wire                           timer_irq,
    input  wire                           ext_irq,
    input  wire                           imem_ready,
    input  wire                           dmem_ready,
    output logic                          dmem_req,
    output logic [              XLEN-1:0] pc,
    output logic                          mem_write,
    output logic [              XLEN-1:0] alu_result,
    output logic [              XLEN-1:0] write_data,
    output logic [         LineBytes-1:0] store_wstrb,
    output logic [          LineBits-1:0] store_data,
    output logic [              XLEN-1:0] mem_addr
);

  logic                 s_req;
  logic                 s_ready;
  logic [     XLEN-1:0] s_addr;
  logic [     XLEN-1:0] s_wdata;
  logic [    StrbW-1:0] s_wstrb;
  logic                 v_req;
  logic                 v_ready;
  logic [     XLEN-1:0] v_addr;

  logic [ LineBits-1:0] s_line_wdata;
  logic [LineBytes-1:0] s_line_wstrb;
  logic [ LineBits-1:0] v_wdata;
  logic [LineBytes-1:0] v_wstrb;

  datapath #(
      .XLEN     (XLEN),
      .VLEN     (VLEN),
      .ELEN     (ELEN),
      .MUL_LANES(MUL_LANES),
      .GSHARE_EN(GSHARE_EN)
  ) datapath_inst (
`ifdef SIM_BACKDOOR
      .sim_branch      (sim_branch),
      .sim_branch_taken(sim_branch_taken),
      .sim_mispredict  (sim_mispredict),
      .sim_muldiv_hold (sim_muldiv_hold),
`endif
`ifdef RISCV_FORMAL
      .dbg_valid       (dbg_valid),
      .dbg_insn        (dbg_insn),
      .dbg_pc_rdata    (dbg_pc_rdata),
      .dbg_pc_wdata    (dbg_pc_wdata),
      .dbg_rs1_rdata   (dbg_rs1_rdata),
      .dbg_rs2_rdata   (dbg_rs2_rdata),
      .dbg_rd_wdata    (dbg_rd_wdata),
      .dbg_reg_write   (dbg_reg_write),
      .dbg_mem_addr    (dbg_mem_addr),
      .dbg_mem_wmask   (dbg_mem_wmask),
      .dbg_mem_wdata   (dbg_mem_wdata),
      .dbg_mem_rdata   (dbg_mem_rdata),
      .dbg_trap        (dbg_trap),
      .dbg_csr_wdata   (dbg_csr_wdata),
      .dbg_mscratch    (dbg_mscratch),
      .dbg_mstatus     (dbg_mstatus),
      .dbg_mtvec       (dbg_mtvec),
      .dbg_mepc        (dbg_mepc),
      .dbg_mcause      (dbg_mcause),
      .dbg_mtval       (dbg_mtval),
      .dbg_mie         (dbg_mie),
      .dbg_mip         (dbg_mip),
      .dbg_mcycle      (dbg_mcycle),
      .dbg_minstret    (dbg_minstret),
      .dbg_mcycleh     (dbg_mcycleh),
      .dbg_minstreth   (dbg_minstreth),
      .dbg_fflags      (dbg_fflags),
      .dbg_vl          (dbg_vl),
      .dbg_vtype_bits  (dbg_vtype_bits),
      .dbg_vtype_ill   (dbg_vtype_ill),
      .dbg_vstart      (dbg_vstart),
      .dbg_vec_tag     (dbg_vec_tag),
      .dbg_vec_retire  (dbg_vec_retire),
      .dbg_vec_wregs   (dbg_vec_wregs),
      .dbg_vec_idle    (dbg_vec_idle),
      .dbg_ex_commit   (dbg_ex_commit),
      .dbg_ex_insn     (dbg_ex_insn),
      .dbg_vec_accept  (dbg_vec_accept),
      .dbg_fetch_en    (dbg_fetch_en),
      .dbg_id_en       (dbg_id_en),
      .dbg_fp_idle     (dbg_fp_idle),
      .dbg_fp_wb_valid (dbg_fp_wb_valid),
      .dbg_fp_wb_rd    (dbg_fp_wb_rd),
      .dbg_fp_wb_data  (dbg_fp_wb_data),
      .dbg_fp_load_wb  (dbg_fp_load_wb),
      .dbg_fp_load_rd  (dbg_fp_load_rd),
      .dbg_fp_load_data(dbg_fp_load_data),
      .dbg_frm         (dbg_frm),
`endif
      .clk             (clk),
      .core_en         (core_en),
      .rst_n           (rst_n),
      .instr           (instr),
      .read_line       (read_data),
      .timer_irq       (timer_irq),
      .ext_irq         (ext_irq),
      .imem_ready      (imem_ready),
      .dmem_ready      (s_ready),
      .dmem_req        (s_req),
      .pc              (pc),
      .mem_write       (mem_write),
      .alu_result      (alu_result),
      .write_data      (write_data),
      .store_wstrb     (s_wstrb),
      .store_data      (s_wdata),
      .mem_addr        (s_addr),
      .vmem_ready      (v_ready),
      .vmem_req        (v_req),
      .vmem_addr       (v_addr),
      .vmem_wdata      (v_wdata),
      .vmem_wstrb      (v_wstrb)
  );

  // Scalar word into line
  assign s_line_wdata = {LineWords{s_wdata}};
  assign s_line_wstrb = LineBytes'(s_wstrb) << (WordBytes * s_addr[WordLsb+:BlkOffLen]);

  dmem_arb #(
      .XLEN  (XLEN),
      .DATA_W(LineBits)
  ) dmem_arb_inst (
      .clk    (clk),
      .rst_n  (rst_n),
      .core_en(core_en),
      .s_req  (s_req),
      .s_addr (s_addr),
      .s_wdata(s_line_wdata),
      .s_wstrb(s_line_wstrb),
      .s_ready(s_ready),
      .v_req  (v_req),
      .v_addr (v_addr),
      .v_wdata(v_wdata),
      .v_wstrb(v_wstrb),
      .v_ready(v_ready),
      .req    (dmem_req),
      .addr   (mem_addr),
      .wdata  (store_data),
      .wstrb  (store_wstrb),
      .ready  (dmem_ready)
  );

`ifdef RISCV_FORMAL
  assign dbg_s_take = s_req && s_ready;
  assign dbg_v_take = v_req && v_ready;
`endif

endmodule

`default_nettype wire
