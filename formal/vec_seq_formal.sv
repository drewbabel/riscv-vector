`default_nettype none

module vec_seq_formal
  import vec_pkg::*;
();

  localparam int AWIDTH = 5;
  localparam int VLEN = 128;
  localparam int MaxElems = VLEN / 8;

  logic                clk;
  logic                rst_n;
  logic                core_en;
  logic                start;
  logic [         4:0] vs1;
  logic [         4:0] vs2;
  logic [         4:0] vd;
  logic                reads_vd;
  logic [         7:0] vl;
  logic [         2:0] vsew;
  logic [         2:0] vlmul;
  logic                vm;
  logic [MaxElems-1:0] mask_bits;

  vec_rel_e            d_rel;
  vec_rel_e            s1_rel;
  vec_rel_e            s2_rel;
  logic                mul_rate;
  logic                single_write;
  logic                mask_dest;
  logic                mask_whole;
  logic                mask_src;

  logic [  AWIDTH-1:0] raddr1;
  logic [  AWIDTH-1:0] raddr2;
  logic [  AWIDTH-1:0] raddr3;
  logic [  AWIDTH-1:0] waddr;
  logic [    VLEN-1:0] wstrb;
  logic                wen;

  logic [         6:0] s1_off;
  logic [         6:0] s2_off;
  logic [         6:0] d_off;
  logic [         7:0] elem_base;
  logic [         4:0] elem_count;
  logic [MaxElems-1:0] elem_active;

  logic                last;
  logic                busy;
  logic                done;

  vec_sequencer #(
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) dut (
      .clk         (clk),
      .rst_n       (rst_n),
      .core_en     (core_en),
      .start       (start),
      .vs1         (vs1),
      .vs2         (vs2),
      .vd          (vd),
      .reads_vd    (reads_vd),
      .vl          (vl),
      .vsew        (vsew),
      .vlmul       (vlmul),
      .vm          (vm),
      .mask_bits   (mask_bits),
      .d_rel       (d_rel),
      .s1_rel      (s1_rel),
      .s2_rel      (s2_rel),
      .mul_rate    (mul_rate),
      .single_write(single_write),
      .mask_dest   (mask_dest),
      .mask_whole  (mask_whole),
      .mask_src    (mask_src),
      .v0_bits     ({VLEN{1'b1}}),
      .raddr1      (raddr1),
      .raddr2      (raddr2),
      .raddr3      (raddr3),
      .waddr       (waddr),
      .wstrb       (wstrb),
      .wen         (wen),
      .s1_off      (s1_off),
      .s2_off      (s2_off),
      .d_off       (d_off),
      .elem_base   (elem_base),
      .elem_count  (elem_count),
      .elem_active (elem_active),
      .last        (last),
      .busy        (busy),
      .done        (done)
  );

  // Issued geometry
  logic [2:0] lsew;
  logic [2:0] ld;
  logic [2:0] ls1;
  logic [2:0] ls2;
  logic [4:0] group_regs;
  logic [4:0] d_regs;
  logic [4:0] s1_regs;
  logic [4:0] s2_regs;
  logic [7:0] total_elems;
  logic [5:0] dbits;

  assign lsew = vsew + 3'd3;
  assign ld = vec_rel_log2(d_rel, lsew);
  assign ls1 = vec_rel_log2(s1_rel, lsew);
  assign ls2 = vec_rel_log2(s2_rel, lsew);
  assign group_regs = vlmul[2] ? 5'd1 : 5'(5'd1 << vlmul[1:0]);
  assign d_regs = (single_write || mask_dest) ? 5'd1 : vec_rel_regs(d_rel, group_regs[3:0]);
  assign s1_regs = (single_write || mask_src) ? 5'd1 : vec_rel_regs(s1_rel, group_regs[3:0]);
  assign s2_regs = mask_src ? 5'd1 : vec_rel_regs(s2_rel, group_regs[3:0]);
  assign total_elems = 8'(group_regs) << (3'd7 - lsew);
  assign dbits = 6'(6'd1 << ld);

  // Absolute bit position
  logic [12:0] dest_pos;
  logic [12:0] src2_pos;

  assign dest_pos = (13'(waddr - vd) << 7) + 13'(d_off);
  assign src2_pos = (13'(raddr2 - vs2) << 7) + 13'(s2_off);

  // Reset once
  logic f_past_valid;
  initial f_past_valid = 1'b0;
  always_ff @(posedge clk) f_past_valid <= 1'b1;
  always_comb if (!f_past_valid) assume (!rst_n);
  always_ff @(posedge clk) if (f_past_valid) assume (rst_n);

  // Issued mask shapes
  always_comb begin
    assume (!(mask_dest && single_write));
    assume (!mask_whole || ((mask_dest && mask_src) || (single_write && mask_src)));
    assume (!mask_dest || (d_rel == VEC_REL_SAME));
    assume (!mask_src || ((s1_rel == VEC_REL_SAME) && (s2_rel == VEC_REL_SAME)));
    assume (!mask_whole || (vl <= 8'(VLEN)));
  end

  // Legal configuration
  always_comb begin
    assume (vsew <= 3'd2);
    assume (vlmul != 3'b100);
    assume (ld >= 3'd3 && ld <= 3'd5);
    assume (ls1 >= 3'd3 && ls1 <= 3'd5);
    assume (ls2 >= 3'd3 && ls2 <= 3'd5);
    assume (vl <= total_elems);
    assume (d_regs <= 5'd8 && s1_regs <= 5'd8 && s2_regs <= 5'd8);
    assume ((vd & (d_regs - 5'd1)) == 5'd0);
    assume ((vs1 & (s1_regs - 5'd1)) == 5'd0);
    assume ((vs2 & (s2_regs - 5'd1)) == 5'd0);
    assume (6'(vd) + 6'(d_regs) <= 6'd32);
    assume (6'(vs1) + 6'(s1_regs) <= 6'd32);
    assume (6'(vs2) + 6'(s2_regs) <= 6'd32);
  end

  // Snapshot holds
  always_ff @(posedge clk) begin
    if (f_past_valid && $past(busy)) begin
      assume (mask_dest == $past(mask_dest));
      assume (mask_whole == $past(mask_whole));
      assume (mask_src == $past(mask_src));
      assume (vl == $past(vl));
      assume (vsew == $past(vsew));
      assume (vlmul == $past(vlmul));
      assume (vd == $past(vd));
      assume (vs1 == $past(vs1));
      assume (vs2 == $past(vs2));
      assume (d_rel == $past(d_rel));
      assume (s1_rel == $past(s1_rel));
      assume (s2_rel == $past(s2_rel));
      assume (mul_rate == $past(mul_rate));
      assume (single_write == $past(single_write));
    end
  end

  // Counted writes
  logic [7:0] write_count;
  always_ff @(posedge clk) begin
    if (!rst_n) write_count <= 8'd0;
    else if (core_en) begin
      if (start && !busy) write_count <= 8'd0;
      else if (wen) write_count <= write_count + 8'd1;
    end
  end

  // Inside the group
  always_comb begin
    if (f_past_valid && busy) begin
      assert (5'(waddr - vd) < d_regs);
      assert (5'(raddr2 - vs2) < s2_regs);
      assert (single_write || (5'(raddr1 - vs1) < s1_regs));
      assert (reads_vd ? (5'(raddr3 - vd) < d_regs) : (raddr3 == 5'd0));
    end
  end

  // Clean counter steps
  always_comb begin
    if (f_past_valid && busy) begin
      assert (elem_base < total_elems);
      assert ((elem_base & 8'(elem_count - 5'd1)) == 8'd0);
      assert (elem_count != 5'd0);
    end
  end

  // Twice the rate
  always_comb begin
    if (f_past_valid && busy && !single_write && !mask_dest && !mask_src
        && (d_rel == VEC_REL_WIDE) && (s2_rel == VEC_REL_SAME)) begin
      assert (dest_pos == (src2_pos << 1));
    end
  end

  // Two source phases
  always_comb begin
    if (f_past_valid && busy && !single_write && !mul_rate && !mask_dest && !mask_src
        && (d_rel == VEC_REL_SAME) && (s1_rel == VEC_REL_SAME) && (s2_rel == VEC_REL_WIDE)) begin
      assert (src2_pos == (dest_pos << 1));
      assert ((13'(elem_count) << ld) == 13'(VLEN / 2));
    end
  end

  // One reduction write
  always_comb begin
    if (f_past_valid && single_write && wen) begin
      assert (last);
      assert (waddr == vd);
      assert (d_off == 7'd0);
      assert (wstrb == VLEN'({32{1'b1}} >> (6'd32 - dbits)));
    end
  end

  always_comb begin
    if (f_past_valid && busy && single_write) assert (write_count == 8'd0);
  end

  always_ff @(posedge clk) begin
    if (f_past_valid && rst_n && $past(core_en) && $past(single_write) && $past(busy) && done) begin
      assert (write_count == 8'd1);
    end
  end

  // One mask register
  always_comb begin
    if (f_past_valid && busy && mask_dest) begin
      assert (waddr == vd);
      assert (9'(d_off) < 9'(VLEN));
      assert (9'(d_off) == 9'(elem_base));
    end
  end

  // Inside the length
  logic [VLEN-1:0] live_mask;
  assign live_mask = VLEN'({VLEN{1'b1}} >> (9'(VLEN) - 9'(vl)));

  always_comb begin
    if (f_past_valid && mask_whole && !single_write && wen) begin
      assert ((wstrb & ~live_mask) == '0);
      assert (last);
    end
  end

  // Reachable shapes
  always_comb begin
    cover (busy && (d_rel == VEC_REL_WIDE) && (waddr != vd));
    cover (busy && (s2_rel == VEC_REL_WIDE) && (d_off == 7'd64));
    cover (done && single_write);
    cover (busy && (elem_count == 5'd16));
    cover (busy && mask_dest && !mask_whole && (elem_base != 8'd0));
    cover (wen && mask_whole && !single_write);
  end

endmodule

`default_nettype wire
