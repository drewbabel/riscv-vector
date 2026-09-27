`default_nettype none

module hazard_unit #(
    parameter int XLEN = 32
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

    output logic stall,
    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

  localparam logic [1:0] ResMem = 2'd1;  // lw

  assign stall = (result_src_ex == ResMem) && (rd_ex != 0) && (rd_ex == rs1_id || rd_ex == rs2_id);


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
