`default_nettype none

module hazard_unit #(
    parameter  int XLEN  = arch_pkg::XLEN,
    localparam int NRegs = arch_pkg::NumRegs
) (
    input wire clk,
    input wire core_en,
    input wire rst_n,

    input wire [4:0] rs1_id,
    input wire [4:0] rs2_id,
    input wire [4:0] rs1_ex,
    input wire [4:0] rs2_ex,

    input wire [4:0] rd_id,
    input wire [4:0] rd_ex,
    input wire [4:0] rd_mem,
    input wire [4:0] rd_wb,

    input wire reg_write_mem,
    input wire reg_write_wb,
    input wire mem_write_ex,

    input wire [1:0] result_src_ex,
    input wire [1:0] result_src_mem,
    input wire [1:0] result_src_wb,

    input wire fp_op_id,
    input wire frs1_read_id,
    input wire frs2_read_id,
    input wire frs3_read_id,
    input wire frd_write_id,
    input wire [4:0] rs3_id,
    input wire [NRegs-1:0] fp_busy,
    input wire frd_write_ex,
    input wire frm_write_ex,

    output logic stall,
    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

  localparam logic [1:0] ResMem = 2'd1;  // lw

  logic load_stall;
  logic fp_stall;
  logic [NRegs-1:0] fp_need;
  logic [NRegs-1:0] fp_pending;

  assign load_stall = (result_src_ex == ResMem) && (rd_ex != 0) &&
      (rd_ex == rs1_id || rd_ex == rs2_id);

  assign fp_need = (frs1_read_id ? (NRegs'(1) << rs1_id) : '0) |
      (frs2_read_id ? (NRegs'(1) << rs2_id) : '0) | (frs3_read_id ? (NRegs'(1) << rs3_id) : '0) |
      (frd_write_id ? (NRegs'(1) << rd_id) : '0);
  assign fp_pending = fp_busy | (frd_write_ex ? (NRegs'(1) << rd_ex) : '0);
  assign fp_stall = fp_op_id && ((|(fp_need & fp_pending)) || frm_write_ex);

  assign stall = load_stall || fp_stall;


  always_comb begin
    // Forwarding for rs1
    if (reg_write_mem && (rd_mem != 0) && (rd_mem == rs1_ex)) begin
      forward_a = 2'b01;  // Forward from MEM stage
    end else if (reg_write_wb && (rd_wb != 0) && (rd_wb == rs1_ex)) begin
      forward_a = 2'b10;  // Forward from WB stage
    end else begin
      forward_a = 2'b00;  // No forwarding
    end

    // Forwarding for rs2
    if (reg_write_mem && (rd_mem != 0) && (rd_mem == rs2_ex)) begin
      forward_b = 2'b01;  // Forward from MEM stage
    end else if (reg_write_wb && (rd_wb != 0) && (rd_wb == rs2_ex)) begin
      forward_b = 2'b10;  // Forward from WB stage
    end else begin
      forward_b = 2'b00;  // No forwarding
    end
  end

endmodule

`default_nettype wire
