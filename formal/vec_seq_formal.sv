`default_nettype none

module vec_seq_formal
  import vec_pkg::*;
();

  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int VLEN = arch_pkg::VLEN;
  localparam int ELEN = arch_pkg::ELEN;
  localparam int MaxElems = VLEN / 8;
  localparam int VlW = $clog2(VLEN + 1);
  localparam int OffW = $clog2(VLEN);
  localparam int CntW = $clog2(MaxElems + 1);
  localparam int LnW = $clog2(OffW + 1);
  localparam int PosW = VlW + $clog2(ELEN);
  localparam int DbW = $clog2(ELEN + 1);
  localparam int DiffW = VlW + 1;
  localparam int RegW = AWIDTH + 1;

  logic                    clk;
  logic                    rst_n;
  logic                    core_en;
  logic                    start;
  logic     [  AWIDTH-1:0] vs1;
  logic     [  AWIDTH-1:0] vs2;
  logic     [  AWIDTH-1:0] vd;
  logic                    reads_vd;
  logic     [     VlW-1:0] vl;
  logic     [         2:0] vsew;
  logic     [         2:0] vlmul;
  logic                    vm;
  logic     [MaxElems-1:0] mask_bits;

  vec_rel_e                d_rel;
  vec_rel_e                s1_rel;
  vec_rel_e                s2_rel;
  logic                    mul_rate;
  logic                    single_write;
  logic                    mask_dest;
  logic                    mask_whole;
  logic                    mask_src;

  logic     [  AWIDTH-1:0] raddr1;
  logic     [  AWIDTH-1:0] raddr2;
  logic     [  AWIDTH-1:0] raddr3;
  logic     [  AWIDTH-1:0] waddr;
  logic     [    VLEN-1:0] wstrb;
  logic                    wen;

  logic     [    OffW-1:0] s1_off;
  logic     [    OffW-1:0] s2_off;
  logic     [    OffW-1:0] d_off;
  logic     [     VlW-1:0] elem_base;
  logic     [    CntW-1:0] elem_count;
  logic     [MaxElems-1:0] elem_active;

  logic                    last;
  logic                    busy;
  logic                    done;

  vec_sequencer #(
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN),
      .ELEN  (ELEN)
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
  logic [VlW-1:0] total_elems;
  logic [DbW-1:0] dbits;

  assign lsew = vsew + 3'd3;
  assign ld = vec_rel_log2(d_rel, lsew);
  assign ls1 = vec_rel_log2(s1_rel, lsew);
  assign ls2 = vec_rel_log2(s2_rel, lsew);
  assign group_regs = vlmul[2] ? 5'd1 : 5'(5'd1 << vlmul[1:0]);
  assign d_regs = (single_write || mask_dest) ? 5'd1 : vec_rel_regs(d_rel, group_regs[3:0]);
  assign s1_regs = (single_write || mask_src) ? 5'd1 : vec_rel_regs(s1_rel, group_regs[3:0]);
  assign s2_regs = mask_src ? 5'd1 : vec_rel_regs(s2_rel, group_regs[3:0]);
  assign total_elems = VlW'(group_regs) << (LnW'(OffW) - LnW'(lsew));
  assign dbits = DbW'(DbW'(1) << ld);

  // Absolute bit position
  logic [PosW-1:0] dest_pos;
  logic [PosW-1:0] src2_pos;

  assign dest_pos = (PosW'(waddr - vd) << OffW) + PosW'(d_off);
  assign src2_pos = (PosW'(raddr2 - vs2) << OffW) + PosW'(s2_off);

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
    assume (!mask_whole || (vl <= VlW'(VLEN)));
  end

  // Legal configuration
  always_comb begin
    assume (vsew <= 3'($clog2(ELEN / 8)));
    assume (vlmul != 3'b100);
    assume (ld >= 3'd3 && ld <= 3'($clog2(ELEN)));
    assume (ls1 >= 3'd3 && ls1 <= 3'($clog2(ELEN)));
    assume (ls2 >= 3'd3 && ls2 <= 3'($clog2(ELEN)));
    assume (vl <= total_elems);
    assume (d_regs <= 5'd8 && s1_regs <= 5'd8 && s2_regs <= 5'd8);
    assume ((vd & (d_regs - 5'd1)) == 5'd0);
    assume ((vs1 & (s1_regs - 5'd1)) == 5'd0);
    assume ((vs2 & (s2_regs - 5'd1)) == 5'd0);
    assume (RegW'(vd) + RegW'(d_regs) <= RegW'(1 << AWIDTH));
    assume (RegW'(vs1) + RegW'(s1_regs) <= RegW'(1 << AWIDTH));
    assume (RegW'(vs2) + RegW'(s2_regs) <= RegW'(1 << AWIDTH));
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
      assert (AWIDTH'(waddr - vd) < d_regs);
      assert (AWIDTH'(raddr2 - vs2) < s2_regs);
      assert (single_write || (AWIDTH'(raddr1 - vs1) < s1_regs));
      assert (reads_vd ? (AWIDTH'(raddr3 - vd) < d_regs) : (raddr3 == '0));
    end
  end

  // Clean counter steps
  always_comb begin
    if (f_past_valid && busy) begin
      assert (elem_base < total_elems);
      assert ((elem_base & VlW'(elem_count - CntW'(1))) == '0);
      assert (elem_count != '0);
    end
  end

  // Twice the rate
  always_comb begin
    if (f_past_valid && busy && !single_write && !mask_dest && !mask_src &&
        (d_rel == VEC_REL_WIDE) && (s2_rel == VEC_REL_SAME)) begin
      assert (dest_pos == (src2_pos << 1));
    end
  end

  // Two source phases
  always_comb begin
    if (f_past_valid && busy && !single_write && !mul_rate && !mask_dest && !mask_src &&
        (d_rel == VEC_REL_SAME) && (s1_rel == VEC_REL_SAME) && (s2_rel == VEC_REL_WIDE)) begin
      assert (src2_pos == (dest_pos << 1));
      assert ((PosW'(elem_count) << ld) == PosW'(VLEN / 2));
    end
  end

  // One reduction write
  always_comb begin
    if (f_past_valid && single_write && wen) begin
      assert (last);
      assert (waddr == vd);
      assert (d_off == '0);
      assert (wstrb == VLEN'({ELEN{1'b1}} >> (DbW'(ELEN) - dbits)));
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
      assert (DiffW'(d_off) < DiffW'(VLEN));
      assert (DiffW'(d_off) == DiffW'(elem_base));
    end
  end

  // Inside the length
  logic [VLEN-1:0] live_mask;
  assign live_mask = VLEN'({VLEN{1'b1}} >> (DiffW'(VLEN) - DiffW'(vl)));

  always_comb begin
    if (f_past_valid && mask_whole && !single_write && wen) begin
      assert ((wstrb & ~live_mask) == '0);
      assert (last);
    end
  end

  // Reachable shapes
  always_comb begin
    cover (busy && (d_rel == VEC_REL_WIDE) && (waddr != vd));
    cover (busy && (s2_rel == VEC_REL_WIDE) && (d_off == OffW'(VLEN / 2)));
    cover (done && single_write);
    cover (busy && (elem_count == CntW'(MaxElems)));
    cover (busy && mask_dest && !mask_whole && (elem_base != '0));
    cover (wen && mask_whole && !single_write);
  end

endmodule

`default_nettype wire
