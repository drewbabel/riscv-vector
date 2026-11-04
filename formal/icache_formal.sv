`default_nettype none

module icache_formal
  import cache_pkg::*;
();

  localparam int XLEN  = arch_pkg::XLEN;
  localparam int LineW = XLEN - IdxLsb;

  logic                clk;

  // Watched line
  (* anyconst *)logic [   LineW-1:0] f_line;
  (* anyconst *)logic [LineBits-1:0] f_data;

  (* anyseq *)logic                core_en;
  (* anyseq *)logic                cpu_valid;
  (* anyseq *)logic [    XLEN-1:0] cpu_addr;
  (* anyseq *)logic [LineBits-1:0] mem_rdata;
  (* anyseq *)logic                mem_ready;

  logic [    XLEN-1:0] cpu_rdata;
  logic                cpu_ready;
  logic                mem_valid;
  logic [    XLEN-1:0] mem_addr;
  logic [    XLEN-1:0] hit_count;
  logic [    XLEN-1:0] miss_count;

  logic                rst_n;
  logic [         1:0] t = 2'd0;
  logic                f_past_valid = 1'b0;

  initial assume (t == 2'd0);
  always @(posedge clk) begin
    t <= (t == 2'd3) ? 2'd3 : t + 2'd1;
    f_past_valid <= 1'b1;
  end
  assign rst_n = (t != 2'd0);

  icache #(
      .XLEN(XLEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .cpu_valid(cpu_valid),
      .cpu_addr(cpu_addr),
      .cpu_rdata(cpu_rdata),
      .cpu_ready(cpu_ready),
      .mem_valid(mem_valid),
      .mem_addr(mem_addr),
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
        assume (cpu_addr == $past(cpu_addr));
      end

  // Memory holds line
  logic f_mem_hit;
  assign f_mem_hit = mem_valid && (mem_addr[XLEN-1:IdxLsb] == f_line);

  always @(posedge clk) if (rst_n && f_mem_hit && mem_ready) assume (mem_rdata == f_data);

  // Fill and hit
  logic                 f_cpu_hit;
  logic [BlkOffLen-1:0] f_word;
  logic                 f_filled;
  logic                 f_again;

  assign f_cpu_hit = cpu_valid && (cpu_addr[XLEN-1:IdxLsb] == f_line);
  assign f_word = cpu_addr[WordLsb+:BlkOffLen];

  always @(posedge clk) begin
    if (!rst_n) begin
      f_filled <= 1'b0;
      f_again  <= 1'b0;
    end else if (core_en) begin
      if (f_mem_hit && mem_ready) f_filled <= 1'b1;
      if (cpu_ready && f_cpu_hit && f_filled) f_again <= 1'b1;
    end
  end

  always @(posedge clk)
    if (rst_n) begin
      if (cpu_ready && f_cpu_hit) assert (cpu_rdata == f_data[f_word*XLEN+:XLEN]);
      if (mem_valid) assert (mem_addr[IdxLsb-1:0] == '0);
    end

  // Internal probes
  (* keep *)logic                h_en;
  (* keep *)logic [         1:0] h_state;
  (* keep *)logic [IcIdxLen-1:0] h_init;
  (* keep *)logic [    XLEN-1:0] h_req;
  (* keep *)logic                h_fill_q;
  (* keep *)logic [  IcTagLen:0] h_fill_tag;
  (* keep *)logic [LineBits-1:0] h_fill_line;
  (* keep *)logic [  IcTagLen:0] h_tag_rd;
  (* keep *)logic [LineBits-1:0] h_line_rd;
  (* keep *)logic [  IcTagLen:0] h_wtag;
  (* keep *)logic [LineBits-1:0] h_wline;

  localparam logic [1:0] StInit = 2'd0;
  localparam logic [1:0] StCompare = 2'd2;
  localparam logic [1:0] StAllocate = 2'd3;

  logic [IcIdxLen-1:0] f_idx;
  logic [IcTagLen-1:0] f_tag;
  logic                h_watch;
  assign f_idx   = f_line[IcIdxLen-1:0];
  assign f_tag   = f_line[LineW-1:IcIdxLen];
  assign h_watch = h_req[IdxLsb+:IcIdxLen] == f_idx;

  // Watched entry cleared
  logic h_cleared;
  assign h_cleared = (h_state != StInit) || (h_init > f_idx);

  // Helper invariants
  always @(posedge clk)
    if (rst_n && h_en) begin
      if (h_state != StInit) assert (h_init == '0);
      if (h_state == StInit && h_init > f_idx) assert (!h_wtag[IcTagLen]);
      if (h_fill_q) assert (h_state == StCompare);
      if (h_state == StCompare || h_state == StAllocate) assert (cpu_valid && cpu_addr == h_req);
      if (h_cleared && h_wtag[IcTagLen] && h_wtag[IcTagLen-1:0] == f_tag)
        assert (h_wline == f_data);
      if (h_fill_q && h_watch) assert (h_fill_tag == h_wtag && h_fill_line == h_wline);
      if (h_state == StCompare && h_watch && !h_fill_q)
        assert (h_tag_rd == h_wtag && h_line_rd == h_wline);
    end

  // Deep cover select
  (* keep *) logic h_deep;

  // Covers
  always @(posedge clk)
    if (rst_n && core_en) begin
      cover (cpu_ready && f_cpu_hit && $past(f_mem_hit && mem_ready));
      cover (cpu_ready && f_cpu_hit && f_again && f_word == '1);
      if (h_deep) cover (cpu_ready && !f_cpu_hit && f_filled);
    end

endmodule

`default_nettype wire
