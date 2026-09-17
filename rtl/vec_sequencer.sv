`default_nettype none

module vec_sequencer #(
    parameter int AWIDTH = 5,
    parameter int VLEN = 128,
    localparam int MaxElems = VLEN / 8
) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                start,
    input  logic [         4:0] vs1,
    input  logic [         4:0] vs2,
    input  logic [         4:0] vd,
    input  logic                reads_vd,
    input  logic [         7:0] vl,
    input  logic [         2:0] vsew,
    input  logic [         2:0] vlmul,
    input  logic                vm,
    input  logic [MaxElems-1:0] mask_bits,
    input  logic [         1:0] pass_log2,
    output logic [  AWIDTH-1:0] raddr1,
    output logic [  AWIDTH-1:0] raddr2,
    output logic [  AWIDTH-1:0] raddr3,
    output logic [  AWIDTH-1:0] waddr,
    output logic [    VLEN-1:0] wstrb,
    output logic                wen,
    output logic [         7:0] elem_base,
    output logic                busy,
    output logic                done
);

  // Counters
  logic [3:0] reg_idx;
  logic [3:0] pass_idx;

  logic [4:0] regs_per_group;
  logic [5:0] bits_per_elem;
  logic [4:0] elems_per_reg;
  logic [4:0] passes_per_reg;
  logic [4:0] elems_per_pass;
  logic [7:0] group_base;

  logic last_pass;
  logic last_reg;

  logic [7:0] idx;
  logic [4:0] pos;
  logic [9:0] base_bit;
  logic [6:0] bit_sel;

  // Group geometry
  assign regs_per_group = vlmul[2] ? 5'd1 : 5'(5'd1 << vlmul[1:0]);
  assign bits_per_elem = 6'(6'd8 << vsew);
  assign elems_per_reg = 5'(5'd16 >> vsew);
  assign passes_per_reg = 5'(5'd1 << pass_log2);
  assign elems_per_pass = elems_per_reg >> pass_log2;

  assign group_base = 8'(reg_idx) * 8'(elems_per_reg);
  assign elem_base = group_base + 8'(pass_idx) * 8'(elems_per_pass);

  assign last_pass = (pass_idx == 4'(passes_per_reg - 5'd1));
  assign last_reg = (reg_idx == 4'(regs_per_group - 5'd1));

  // Port addresses
  assign raddr1 = vs1 + AWIDTH'(reg_idx);
  assign raddr2 = vs2 + AWIDTH'(reg_idx);
  assign raddr3 = reads_vd ? (vd + AWIDTH'(reg_idx)) : '0;
  assign waddr = vd + AWIDTH'(reg_idx);
  assign wen = busy && (wstrb != '0);

  // Tail plus mask
  always_comb begin
    wstrb = '0;
    idx = 8'd0;
    pos = 5'd0;
    base_bit = 10'd0;
    bit_sel = 7'd0;
    for (int e = 0; e < MaxElems; e++) begin
      if (5'(e) < elems_per_pass) begin
        idx = elem_base + 8'(e);
        pos = 5'(pass_idx) * elems_per_pass + 5'(e);
        base_bit = 10'(pos) * 10'(bits_per_elem);
        if ((idx < vl) && (vm || mask_bits[e])) begin
          for (int b = 0; b < 32; b++) begin
            if (6'(b) < bits_per_elem) begin
              bit_sel = 7'(base_bit + 10'(b));
              wstrb[bit_sel] = 1'b1;
            end
          end
        end
      end
    end
  end

  // Walk the group
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      reg_idx  <= 4'd0;
      pass_idx <= 4'd0;
      busy     <= 1'b0;
      done     <= 1'b0;
    end else begin
      done <= 1'b0;
      if (!busy) begin
        if (start) begin
          reg_idx  <= 4'd0;
          pass_idx <= 4'd0;
          if (vl == 8'd0) done <= 1'b1;
          else busy <= 1'b1;
        end
      end else begin
        if (last_pass) begin
          pass_idx <= 4'd0;
          if (last_reg) begin
            busy <= 1'b0;
            done <= 1'b1;
          end else begin
            reg_idx <= reg_idx + 4'd1;
          end
        end else begin
          pass_idx <= pass_idx + 4'd1;
        end
      end
    end
  end

endmodule

`default_nettype wire
