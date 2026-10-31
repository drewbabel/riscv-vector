`default_nettype none

module mem_word_if_formal
  import cache_pkg::*;
();

  localparam int XLEN = arch_pkg::XLEN;
  localparam bit RW = 1'b1;
  localparam int CpuW = XLEN;
  localparam int CpuBytes = CpuW / 8;
  localparam int CpuLsb = $clog2(CpuBytes);
  localparam int Lanes = LineBits / CpuW;
  localparam int LaneW = $clog2(Lanes);
  localparam int LatMax = 4;
  localparam int AgeW = 4;

  logic                 clk;

  (* anyseq *)logic                 core_en;
  (* anyseq *)logic                 cpu_valid;
  (* anyseq *)logic                 cpu_rw;
  (* anyseq *)logic [     XLEN-1:0] cpu_addr;
  (* anyseq *)logic [     CpuW-1:0] cpu_wdata;
  (* anyseq *)logic [ CpuBytes-1:0] cpu_wstrb;
  (* anyseq *)logic [ LineBits-1:0] mem_rdata;
  (* anyseq *)logic                 mem_ready;

  logic [     CpuW-1:0] cpu_rdata;
  logic                 cpu_ready;
  logic                 mem_valid;
  logic                 mem_rw;
  logic [     XLEN-1:0] mem_addr;
  logic [ LineBits-1:0] mem_wdata;
  logic [LineBytes-1:0] mem_wstrb;
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

  mem_word_if #(
      .XLEN(XLEN),
      .RW(RW),
      .CPU_W(CpuW)
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
      .mem_wstrb(mem_wstrb),
      .mem_rdata(mem_rdata),
      .mem_ready(mem_ready),
      .hit_count(hit_count),
      .miss_count(miss_count)
  );

  // Outstanding request
  logic                f_pend;
  logic                f_rw;
  logic [    XLEN-1:0] f_addr;
  logic [    CpuW-1:0] f_wdata;
  logic [CpuBytes-1:0] f_wstrb;
  logic [    AgeW-1:0] f_age;
  logic [    AgeW-1:0] f_mwait;
  logic [   LaneW-1:0] f_lane;

  assign f_lane = f_addr[CpuLsb+:LaneW];

  always @(posedge clk) begin
    if (!rst_n) begin
      f_pend  <= 1'b0;
      f_age   <= '0;
      f_mwait <= '0;
    end else if (core_en) begin
      f_mwait <= (mem_valid && !mem_ready) ? f_mwait + 1'b1 : '0;
      if (!f_pend && cpu_valid) begin
        f_pend  <= 1'b1;
        f_rw    <= cpu_rw;
        f_addr  <= cpu_addr;
        f_wdata <= cpu_wdata;
        f_wstrb <= cpu_wstrb;
        f_age   <= '0;
      end else if (cpu_ready) begin
        f_pend <= 1'b0;
      end else if (f_pend) begin
        f_age <= f_age + 1'b1;
      end
    end
  end

  // Memory latency contract
  always @(posedge clk) if (rst_n) assume (f_mwait <= AgeW'(LatMax));

  always @(posedge clk)
    if (rst_n) begin
      if (cpu_ready) assert (f_pend);
      assert (mem_valid == f_pend);
      assert (f_age <= AgeW'(LatMax));
      if (f_pend) begin
        assert (mem_addr == f_addr);
        assert (mem_rw == f_rw);
        assert (mem_wdata == {Lanes{f_wdata}});
        assert (mem_wstrb == LineBytes'(f_wstrb) << (f_lane * CpuBytes));
        assert (cpu_rdata == mem_rdata[f_lane*CpuW+:CpuW]);
      end
    end

  // Covers
  always @(posedge clk)
    if (rst_n && f_past_valid) begin
      cover (core_en && cpu_ready && f_age == AgeW'(LatMax));
      cover (core_en && f_pend && $past(
          core_en && cpu_valid && !f_pend
      ) && $past(
          core_en && cpu_ready, 2
      ));
      cover (core_en && cpu_ready && f_rw && f_lane == LaneW'(Lanes - 1));
      cover (core_en && cpu_ready && $past(cpu_ready && !core_en));
      cover (miss_count == XLEN'(2) && cpu_ready && core_en);
    end

endmodule

`default_nettype wire
