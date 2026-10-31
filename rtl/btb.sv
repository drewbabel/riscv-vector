`default_nettype none

module btb
  import bp_pkg::*;
#(
    parameter  int XLEN     = arch_pkg::XLEN,
    localparam int InstrLsb = arch_pkg::InstrLsb,
    localparam int TagLen   = XLEN - InstrLsb - BtbIdxLen
) (
    input wire clk,
    input wire core_en,
    input wire rst_n,

    // IF lookup
    input  wire  [XLEN-1:0] lookup_pc,
    output logic            hit,
    output logic [XLEN-1:0] target,
    output logic            is_cond,

    // EX update
    input wire            update_valid,
    input wire [XLEN-1:0] update_pc,
    input wire [XLEN-1:0] update_target,
    input wire            update_is_cond
);

  logic                 valid         [BtbDepth];
  logic [   TagLen-1:0] tag           [BtbDepth];
  logic [     XLEN-1:0] targ          [BtbDepth];
  logic                 cond          [BtbDepth];

  logic [BtbIdxLen-1:0] lookup_idx;
  logic [BtbIdxLen-1:0] update_idx;
  logic                 unused_pc_lsb;

  assign unused_pc_lsb = ^{lookup_pc[InstrLsb-1:0], update_pc[InstrLsb-1:0]};

  assign lookup_idx = lookup_pc[InstrLsb+:BtbIdxLen];
  assign update_idx = update_pc[InstrLsb+:BtbIdxLen];

  assign hit = (valid[lookup_idx] && tag[lookup_idx] == lookup_pc[BtbIdxLen+InstrLsb+:TagLen]);

  assign target = targ[lookup_idx];
  assign is_cond = cond[lookup_idx];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < BtbDepth; i++) valid[i] <= 1'b0;
    end else if (core_en) begin
      if (update_valid) begin
        valid[update_idx] <= 1'b1;
        tag[update_idx]   <= update_pc[BtbIdxLen+InstrLsb+:TagLen];
        targ[update_idx]  <= update_target;
        cond[update_idx]  <= update_is_cond;
      end
    end
  end

endmodule

`default_nettype wire
