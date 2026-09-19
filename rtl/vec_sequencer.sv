`default_nettype none

module vec_sequencer
  import vec_pkg::*;
#(
    parameter int AWIDTH = 5,
    parameter int VLEN = 128,
    localparam int MaxElems = VLEN / 8
) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                core_en,
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

    // Element geometry
    input vec_rel_e d_rel,
    input vec_rel_e s1_rel,
    input vec_rel_e s2_rel,
    input logic     mul_rate,
    input logic     single_write,

    // Register ports
    output logic [AWIDTH-1:0] raddr1,
    output logic [AWIDTH-1:0] raddr2,
    output logic [AWIDTH-1:0] raddr3,
    output logic [AWIDTH-1:0] waddr,
    output logic [  VLEN-1:0] wstrb,
    output logic              wen,

    // Element slices
    output logic [         6:0] s1_off,
    output logic [         6:0] s2_off,
    output logic [         6:0] d_off,
    output logic [         7:0] elem_base,
    output logic [         4:0] elem_count,
    output logic [MaxElems-1:0] elem_active,

    output logic last,
    output logic busy,
    output logic done
);

  // Element widths
  logic [2:0] lsew;
  logic [2:0] ld;
  logic [2:0] ls1;
  logic [2:0] ls2;
  logic [2:0] lmax;
  logic [2:0] ln;

  assign lsew = vsew + 3'd3;

  assign ld  = vec_rel_log2(d_rel, lsew);
  assign ls1 = vec_rel_log2(s1_rel, lsew);
  assign ls2 = vec_rel_log2(s2_rel, lsew);

  // Widest port
  always_comb begin
    if (single_write) begin
      lmax = ls2;
    end else begin
      lmax = ld;
      if (ls1 > lmax) lmax = ls1;
      if (ls2 > lmax) lmax = ls2;
    end
  end

  // Elements per phase
  always_comb begin
    ln = 3'd7 - lmax;
    if (mul_rate && (ln > 3'd2)) ln = 3'd2;
  end

  assign elem_count = 5'(5'd1 << ln);

  // Group geometry
  logic [4:0] regs_per_group;
  logic [7:0] total_elems;

  assign regs_per_group = vlmul[2] ? 5'd1 : 5'(5'd1 << vlmul[1:0]);
  assign total_elems = 8'(regs_per_group) << (3'd7 - lsew);

  // Element counter
  logic [7:0] elem_q;
  logic [7:0] elem_next;

  assign elem_base = elem_q;
  assign elem_next = elem_q + 8'(elem_count);
  assign last = (elem_next >= total_elems);

  // Port offsets
  logic [12:0] prod1;
  logic [12:0] prod2;
  logic [12:0] prodd;

  assign prod1 = single_write ? 13'd0 : (13'(elem_base) << ls1);
  assign prod2 = 13'(elem_base) << ls2;
  assign prodd = single_write ? 13'd0 : (13'(elem_base) << ld);

  assign s1_off = prod1[6:0];
  assign s2_off = prod2[6:0];
  assign d_off  = prodd[6:0];

  assign raddr1 = vs1 + AWIDTH'(prod1[12:7]);
  assign raddr2 = vs2 + AWIDTH'(prod2[12:7]);
  assign raddr3 = reads_vd ? (vd + AWIDTH'(prodd[12:7])) : '0;
  assign waddr = vd + AWIDTH'(prodd[12:7]);
  assign wen = busy && (wstrb != '0);

  // Destination bits
  logic [5:0] dbits;
  assign dbits = 6'(6'd1 << ld);

  // Live elements
  always_comb begin
    for (int e = 0; e < MaxElems; e++) begin
      elem_active[e] = (5'(e) < elem_count) && ((elem_base + 8'(e)) < vl) && (vm || mask_bits[e]);
    end
  end

  // Tail plus mask
  logic [7:0] base_bit;
  always_comb begin
    wstrb = '0;
    base_bit = 8'd0;
    if (single_write) begin
      if (last) begin
        for (int b = 0; b < 32; b++) begin
          if (6'(b) < dbits) wstrb[b[6:0]] = 1'b1;
        end
      end
    end else begin
      for (int e = 0; e < MaxElems; e++) begin
        if (elem_active[e]) begin
          base_bit = 8'(d_off) + 8'(e) * 8'(dbits);
          for (int b = 0; b < 32; b++) begin
            if (6'(b) < dbits) wstrb[7'(base_bit + 8'(b))] = 1'b1;
          end
        end
      end
    end
  end

  // Walk the group
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      elem_q <= 8'd0;
      busy   <= 1'b0;
      done   <= 1'b0;
    end else if (core_en) begin
      done <= 1'b0;
      if (!busy) begin
        if (start) begin
          elem_q <= 8'd0;
          if (vl == 8'd0) done <= 1'b1;
          else busy <= 1'b1;
        end
      end else begin
        if (last) begin
          busy <= 1'b0;
          done <= 1'b1;
        end else begin
          elem_q <= elem_next;
        end
      end
    end
  end

endmodule

`default_nettype wire
