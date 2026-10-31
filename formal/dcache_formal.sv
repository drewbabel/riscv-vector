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

  // Covers
  always @(posedge clk)
    if (rst_n && core_en) begin
      cover (cpu_ready && f_cpu_hit && !cpu_rw && f_filled && f_ref != f_init);
      cover (cpu_ready && f_cpu_hit && !cpu_rw && f_wrote && f_wb && f_filled);
      cover (cpu_ready && f_cpu_hit && cpu_rw && cpu_wstrb == '1 && !f_filled);
      cover (f_mem_hit && mem_rw && mem_ready && f_wrote);
    end

endmodule

`default_nettype wire
