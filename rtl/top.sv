`default_nettype none

module top
  import cache_pkg::*;
#(
    parameter int XLEN      = arch_pkg::XLEN,
    parameter int VLEN      = arch_pkg::VLEN,
    parameter int ELEN      = arch_pkg::ELEN,
    parameter int MUL_LANES = arch_pkg::MulLanes,
    parameter int DEPTH     = 64
) (
    input  wire             clk,
    input  wire             rst_n,
    output logic [XLEN-1:0] pc,
    output logic [XLEN-1:0] alu_result,
    output logic [XLEN-1:0] write_data,
    output logic            mem_write
);

  logic [31:0] instr;
  logic [LineBits-1:0] read_data;
  logic [LineBytes-1:0] store_wstrb;
  logic [LineBits-1:0] store_data;
  logic [XLEN-1:0] mem_addr;

  riscv_pipelined #(
      .XLEN     (XLEN),
      .VLEN     (VLEN),
      .ELEN     (ELEN),
      .MUL_LANES(MUL_LANES)
  ) riscv_pipelined_inst (
`ifdef RISCV_FORMAL
      .dbg_valid     (),
      .dbg_insn      (),
      .dbg_pc_rdata  (),
      .dbg_pc_wdata  (),
      .dbg_rs1_rdata (),
      .dbg_rs2_rdata (),
      .dbg_rd_wdata  (),
      .dbg_reg_write (),
      .dbg_mem_addr  (),
      .dbg_mem_wmask (),
      .dbg_mem_wdata (),
      .dbg_mem_rdata (),
      .dbg_trap      (),
      .dbg_csr_wdata (),
      .dbg_mscratch  (),
      .dbg_mstatus   (),
      .dbg_mtvec     (),
      .dbg_mepc      (),
      .dbg_mcause    (),
      .dbg_mtval     (),
      .dbg_mie       (),
      .dbg_mip       (),
      .dbg_mcycle    (),
      .dbg_minstret  (),
      .dbg_mcycleh   (),
      .dbg_minstreth (),
      .dbg_fflags    (),
      .dbg_vl        (),
      .dbg_vtype_bits(),
      .dbg_vtype_ill (),
      .dbg_vstart    (),
      .dbg_vec_tag   (),
      .dbg_vec_retire(),
      .dbg_vec_wregs (),
      .dbg_vec_idle  (),
      .dbg_ex_commit (),
      .dbg_ex_insn   (),
      .dbg_s_take    (),
      .dbg_v_take    (),
`endif
      .clk           (clk),
      .core_en       (1'b1),
      .rst_n         (rst_n),
      .instr         (instr),
      .read_data     (read_data),
      .timer_irq     (1'b0),
      .ext_irq       (1'b0),
      .imem_ready    (1'b1),
      .dmem_ready    (1'b1),
      .dmem_req      (),
      .pc            (pc),
      .mem_write     (mem_write),
      .alu_result    (alu_result),
      .write_data    (write_data),
      .store_wstrb   (store_wstrb),
      .store_data    (store_data),
      .mem_addr      (mem_addr)
  );

  imem #(
      .XLEN (XLEN),
      .DEPTH(DEPTH)
  ) imem_inst (
      .clk  (clk),
      .we   (1'b0),
      .waddr('0),
      .wdata('0),
      .addr (pc),
      .instr(instr)
  );

  dmem #(
      .XLEN (XLEN),
      .DEPTH(DEPTH)
  ) dmem_inst (
      .clk  (clk),
      .wstrb(store_wstrb),
      .addr (mem_addr),
      .wdata(store_data),
      .rdata(read_data)
  );

endmodule

`default_nettype wire
