`default_nettype none

module dcache_formal
  import cache_pkg::*;
();

  localparam int XLEN  = arch_pkg::XLEN;
  localparam int LineW = XLEN - IdxLsb;

  logic                 clk;

  // Watched line
  (* anyconst *)logic [    LineW-1:0] f_line;
  (* anyconst *)logic [ LineBits-1:0] f_init;

  (* anyseq *)logic                 core_en;
  (* anyseq *)logic                 cpu_valid;
  (* anyseq *)logic                 cpu_rw;
  (* anyseq *)logic [     XLEN-1:0] cpu_addr;
  (* anyseq *)logic [ LineBits-1:0] cpu_wdata;
  (* anyseq *)logic [LineBytes-1:0] cpu_wstrb;
  (* anyseq *)logic [ LineBits-1:0] mem_rdata;
  (* anyseq *)logic                 mem_ready;

  logic [ LineBits-1:0] cpu_rdata;
  logic                 cpu_ready;
  logic                 mem_valid;
  logic                 mem_rw;
  logic [     XLEN-1:0] mem_addr;
  logic [ LineBits-1:0] mem_wdata;
  logic [     XLEN-1:0] hit_count;
  logic [     XLEN-1:0] miss_count;

  logic                 rst_n;
  logic [          1:0] t = 2'd0;
  logic                 f_past_valid = 1'b0;

  initial assume (t == 2'd0);
  always @(posedge clk) begin
    t <= (t == 2'd3) ? 2'd3 : t + 2'd1;
    f_past_valid <= 1'b1;
  end
  assign rst_n = (t != 2'd0);

  dcache #(
      .XLEN(XLEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .cpu_valid(cpu_valid),
      .cpu_rw(cpu_rw),
      .cpu_addr(cpu_addr),
      .cpu_wdata(cpu_wdata),
      .cpu_wstrb(cpu_wstrb),
      .cpu_rdata(cpu_rdata),
      .cpu_ready(cpu_ready),
      .mem_valid(mem_valid),
      .mem_rw(mem_rw),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
      .mem_rdata(mem_rdata),
      .mem_ready(mem_ready),
      .hit_count(hit_count),
      .miss_count(miss_count)
  );

  // Request held until ready
  always @(posedge clk)
    if (f_past_valid && $past(rst_n) && rst_n)
      if ($past(cpu_valid && !(cpu_ready && core_en))) begin
        assume (cpu_valid);
        assume (cpu_rw == $past(cpu_rw));
        assume (cpu_addr == $past(cpu_addr));
        assume (cpu_wdata == $past(cpu_wdata));
        assume (cpu_wstrb == $past(cpu_wstrb));
      end

  // Shadow memory line
  logic                f_cpu_hit;
  logic                f_mem_hit;
  logic [LineBits-1:0] f_ref;
  logic [LineBits-1:0] f_mem;
  logic [LineBits-1:0] f_merged;
  logic                f_wb;
  logic                f_filled;
  logic                f_wrote;

  assign f_cpu_hit = cpu_valid && (cpu_addr[XLEN-1:IdxLsb] == f_line);
  assign f_mem_hit = mem_valid && (mem_addr[XLEN-1:IdxLsb] == f_line);

  always_comb begin
    f_merged = f_ref;
    for (int i = 0; i < LineBytes; i++) if (cpu_wstrb[i]) f_merged[i*8+:8] = cpu_wdata[i*8+:8];
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      f_ref    <= f_init;
      f_mem    <= f_init;
      f_wb     <= 1'b0;
      f_filled <= 1'b0;
      f_wrote  <= 1'b0;
    end else if (core_en) begin
      if (cpu_ready && f_cpu_hit && cpu_rw) begin
        f_ref   <= f_merged;
        f_wrote <= 1'b1;
      end
      if (f_mem_hit && mem_rw && mem_ready) begin
        f_mem <= mem_wdata;
        f_wb  <= 1'b1;
      end
      if (f_mem_hit && !mem_rw && mem_ready) f_filled <= 1'b1;
    end
  end

  always @(posedge clk) if (rst_n && f_mem_hit && !mem_rw) assume (mem_rdata == f_mem);

  always @(posedge clk)
    if (rst_n) begin
      if (cpu_ready && f_cpu_hit && !cpu_rw) assert (cpu_rdata == f_ref);
      if (f_mem_hit && mem_rw) assert (mem_wdata == f_ref);
      if (mem_valid) assert (mem_addr[IdxLsb-1:0] == '0);
    end

  // Internal probes
  localparam int TagW = DcTagLen + 2;

  (* keep *)logic                       h_en;
  (* keep *)logic [                2:0] h_state;
  (* keep *)logic [       DcIdxLen-1:0] h_init;
  (* keep *)logic [           XLEN-1:0] h_req;
  (* keep *)logic                       h_req_rw;
  (* keep *)logic [       LineBits-1:0] h_req_wdata;
  (* keep *)logic [      LineBytes-1:0] h_req_wstrb;
  (* keep *)logic                       h_fill_q;
  (* keep *)logic [       DcWaySel-1:0] h_victim_q;
  (* keep *)logic [       DcWaySel-1:0] h_victim;
  (* keep *)logic [           TagW-1:0] h_fill_tag;
  (* keep *)logic [       LineBits-1:0] h_fill_line;
  (* keep *)logic [    DcWays*TagW-1:0] h_tag_rd;
  (* keep *)logic [DcWays*LineBits-1:0] h_line_rd;
  (* keep *)logic [    DcWays*TagW-1:0] h_wtag;
  (* keep *)logic [DcWays*LineBits-1:0] h_wline;

  localparam logic [2:0] StInit = 3'd0;
  localparam logic [2:0] StCompare = 3'd2;
  localparam logic [2:0] StWriteBack = 3'd3;
  localparam logic [2:0] StAllocate = 3'd4;

  logic [DcIdxLen-1:0] f_idx;
  logic [DcTagLen-1:0] f_tag;
  logic                h_watch;
  logic                h_busy;
  logic [  DcWays-1:0] h_hit;
  logic [  DcWays-1:0] h_dirty;

  assign f_idx   = f_line[DcIdxLen-1:0];
  assign f_tag   = f_line[LineW-1:DcIdxLen];
  assign h_watch = h_req[IdxLsb+:DcIdxLen] == f_idx;

  // Watched entry cleared
  logic h_cleared;
  assign h_cleared = (h_state != StInit) || (h_init > f_idx);
  assign h_busy = (h_state == StCompare) || (h_state == StWriteBack) || (h_state == StAllocate);

  always_comb begin
    for (int w = 0; w < DcWays; w++) begin
      h_hit[w]   = h_wtag[w*TagW+TagW-1] && (h_wtag[w*TagW+:DcTagLen] == f_tag);
      h_dirty[w] = h_wtag[w*TagW+DcTagLen];
    end
  end

  // Helper invariants
  always @(posedge clk)
    if (rst_n && h_en) begin
      assert (h_state <= StAllocate);
      if (h_state != StInit) assert (h_init == '0);
      if (h_fill_q) assert (h_state == StCompare);
      if (h_busy) begin
        assert (cpu_valid && cpu_addr == h_req && cpu_rw == h_req_rw);
        assert (cpu_wdata == h_req_wdata && cpu_wstrb == h_req_wstrb);
      end
      if (h_hit == '0 || h_state == StInit) assert (f_mem == f_ref);
      if ((h_state == StWriteBack || h_state == StAllocate) && h_req[XLEN-1:IdxLsb] == f_line)
        assert (h_hit == '0);
      if (h_state == StAllocate && h_watch && h_hit[h_victim]) assert (f_mem == f_ref);
      if (h_fill_q && h_watch) begin
        assert (h_fill_tag == h_wtag[h_victim_q*TagW+:TagW]);
        assert (h_fill_line == h_wline[h_victim_q*LineBits+:LineBits]);
      end
      for (int w = 0; w < DcWays; w++) begin
        if (h_state == StInit && h_init > f_idx) assert (!h_wtag[w*TagW+TagW-1]);
        if (h_cleared && h_hit[w]) assert (h_wline[w*LineBits+:LineBits] == f_ref);
        if (h_cleared && h_hit[w] && !h_dirty[w]) assert (f_mem == f_ref);
        for (int v = w + 1; v < DcWays; v++) if (h_cleared) assert (!(h_hit[w] && h_hit[v]));
        if (h_busy && h_watch && !(h_fill_q && h_victim_q == DcWaySel'(w))) begin
          assert (h_tag_rd[w*TagW+:TagW] == h_wtag[w*TagW+:TagW]);
          assert (h_line_rd[w*LineBits+:LineBits] == h_wline[w*LineBits+:LineBits]);
        end
      end
    end

  // Deep cover select
  (* keep *) logic h_deep;

  // Covers
  always @(posedge clk)
    if (rst_n && core_en) begin
      cover (cpu_ready && f_cpu_hit && !cpu_rw && f_filled && f_ref != f_init);
      if (h_deep) cover (cpu_ready && f_cpu_hit && !cpu_rw && f_wrote && f_wb && f_filled);
      cover (cpu_ready && f_cpu_hit && cpu_rw && cpu_wstrb == '1 && !f_filled);
      if (h_deep) cover (f_mem_hit && mem_rw && mem_ready && f_wrote);
    end

endmodule

`default_nettype wire
