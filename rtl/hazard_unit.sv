`default_nettype none

module hazard_unit
  import opcode_pkg::*;
#(
    parameter  int XLEN     = arch_pkg::XLEN,
    localparam int RegAddrW = arch_pkg::RegAddrW,
    localparam int NRegs    = arch_pkg::NumRegs
) (
    input wire clk,
    input wire core_en,
    input wire rst_n,

    input wire [RegAddrW-1:0] rs1_id,
    input wire [RegAddrW-1:0] rs2_id,
    input wire [RegAddrW-1:0] rs1_ex,
    input wire [RegAddrW-1:0] rs2_ex,

    input wire [RegAddrW-1:0] rd_id,
    input wire [RegAddrW-1:0] rd_ex,
    input wire [RegAddrW-1:0] rd_mem,
    input wire [RegAddrW-1:0] rd_wb,

    input wire reg_write_ex,
    input wire reg_write_mem,
    input wire reg_write_wb,
    input wire mem_write_ex,

    input wire [ResSrcW-1:0] result_src_ex,
    input wire [ResSrcW-1:0] result_src_mem,
    input wire [ResSrcW-1:0] result_src_wb,

    input wire fp_op_id,
    input wire frs1_read_id,
    input wire frs2_read_id,
    input wire frs3_read_id,
    input wire frd_write_id,
    input wire [RegAddrW-1:0] rs3_id,
    input wire [NRegs-1:0] fp_busy,
    input wire frd_write_ex,
    input wire frd_write_mem,
    input wire frm_write_ex,

    output logic stall,
    output logic [FwdW-1:0] forward_a,
    output logic [FwdW-1:0] forward_b
);

  logic load_stall;
  logic fp_stall;
  logic [NRegs-1:0] fp_need;
  logic [NRegs-1:0] fp_pending;
  logic mem_writes_rd;
  logic wb_writes_rd;

  assign load_stall = (result_src_ex == ResMem) && reg_write_ex && (rd_ex != '0) &&
      (rd_ex == rs1_id || rd_ex == rs2_id);

  function automatic logic [NRegs-1:0] reg_bit(input logic en, input logic [RegAddrW-1:0] idx);
    return NRegs'(en) << idx;
  endfunction

  assign fp_need = reg_bit(
      frs1_read_id, rs1_id
  ) | reg_bit(
      frs2_read_id, rs2_id
  ) | reg_bit(
      frs3_read_id, rs3_id
  ) | reg_bit(
      frd_write_id, rd_id
  );
  assign fp_pending = fp_busy | reg_bit(frd_write_ex, rd_ex) | reg_bit(frd_write_mem, rd_mem);
  assign fp_stall = fp_op_id && ((|(fp_need & fp_pending)) || frm_write_ex);

  assign stall = load_stall || fp_stall;

  assign mem_writes_rd = reg_write_mem && (rd_mem != '0);
  assign wb_writes_rd = reg_write_wb && (rd_wb != '0);

  always_comb begin
    // Forwarding for rs1
    if (mem_writes_rd && (rd_mem == rs1_ex)) begin
      forward_a = FwdMem;  // Forward from MEM stage
    end else if (wb_writes_rd && (rd_wb == rs1_ex)) begin
      forward_a = FwdWb;  // Forward from WB stage
    end else begin
      forward_a = FwdNone;  // No forwarding
    end

    // Forwarding for rs2
    if (mem_writes_rd && (rd_mem == rs2_ex)) begin
      forward_b = FwdMem;  // Forward from MEM stage
    end else if (wb_writes_rd && (rd_wb == rs2_ex)) begin
      forward_b = FwdWb;  // Forward from WB stage
    end else begin
      forward_b = FwdNone;  // No forwarding
    end
  end

endmodule

`default_nettype wire
