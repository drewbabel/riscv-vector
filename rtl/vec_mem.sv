`default_nettype none

module vec_mem #(
    parameter int AWIDTH = 5,
    parameter int VLEN   = 128
) (
    input logic clk,
    input logic rst_n,
    input logic core_en,

    // Issued instruction
    input logic              start,
    input logic              load,
    input logic              vm,
    input logic [AWIDTH-1:0] vd,
    input logic [       7:0] count,
    input logic [       1:0] width,
    input logic [      31:0] base,
    input logic [      31:0] stride,

    // Register file
    input  logic [  VLEN-1:0] v0,
    input  logic [  VLEN-1:0] rdata,
    output logic [AWIDTH-1:0] raddr,
    output logic              wen,
    output logic [  VLEN-1:0] wstrb,
    output logic [  VLEN-1:0] wdata,

    // Memory port
    input  logic [31:0] mem_rdata,
    input  logic        mem_ready,
    output logic        mem_req,
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    output logic [ 3:0] mem_wstrb,

    output logic busy,
    output logic done
);

  logic [ 7:0] elem;
  logic [31:0] addr;

  logic [ 3:0] reg_idx;
  logic [ 6:0] bit_pos;
  logic [ 4:0] byte_shift;
  logic [31:0] elem_mask;
  logic [ 3:0] byte_mask;
  logic [31:0] elem_out;
  logic [31:0] elem_in;
  logic        live;

  // Element geometry
  assign reg_idx = 4'(elem >> (3'd4 - 3'(width)));
  assign bit_pos = 7'(elem << (3'd3 + 3'(width)));
  assign byte_shift = {addr[1:0], 3'b000};

  always_comb begin
    case (width)
      2'd0: begin
        elem_mask = 32'h0000_00FF;
        byte_mask = 4'b0001;
      end
      2'd1: begin
        elem_mask = 32'h0000_FFFF;
        byte_mask = 4'b0011;
      end
      default: begin
        elem_mask = 32'hFFFF_FFFF;
        byte_mask = 4'b1111;
      end
    endcase
  end

  assign live = vm || v0[elem[6:0]];

  // Store beat
  assign raddr = vd + AWIDTH'(reg_idx);
  assign elem_out = 32'(rdata >> bit_pos);
  assign mem_req = busy;
  assign mem_addr = {addr[31:2], 2'b00};
  assign mem_wdata = load ? 32'h0 : (elem_out << byte_shift);
  assign mem_wstrb = (load || !live) ? 4'h0 : 4'(byte_mask << addr[1:0]);

  // Load beat
  assign elem_in = (mem_rdata >> byte_shift) & elem_mask;
  assign wen = busy && load && live && mem_ready;
  assign wstrb = VLEN'(elem_mask) << bit_pos;
  assign wdata = VLEN'(elem_in) << bit_pos;

  // Walk the elements
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      elem <= 8'd0;
      addr <= 32'h0;
      busy <= 1'b0;
      done <= 1'b0;
    end else if (core_en) begin
      done <= 1'b0;
      if (!busy) begin
        if (start) begin
          elem <= 8'd0;
          addr <= base;
          if (count == 8'd0) done <= 1'b1;
          else busy <= 1'b1;
        end
      end else if (mem_ready) begin
        elem <= elem + 8'd1;
        addr <= addr + stride;
        if (elem == count - 8'd1) begin
          busy <= 1'b0;
          done <= 1'b1;
        end
      end
    end
  end

endmodule

`default_nettype wire
