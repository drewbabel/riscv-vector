`default_nettype none

module mem_delay_formal
  import cache_pkg::*;
();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int Lines = 2;
  localparam int DEPTH = Lines * LineWords;
  localparam int Latency = arch_pkg::MemLatency;
  localparam int LineIdxLen = $clog2(Lines);
  localparam int AgeW = $clog2(Latency + 2);

  logic                  clk;

  (* anyconst *)logic [LineIdxLen-1:0] f_line;

  (* anyseq *)logic                  core_en;
  (* anyseq *)logic                  req_valid;
  (* anyseq *)logic                  req_rw;
  (* anyseq *)logic [      XLEN-1:0] req_addr;
  (* anyseq *)logic [  LineBits-1:0] req_wdata;
  (* anyseq *)logic                  boot_we;
  (* anyseq *)logic [      XLEN-1:0] boot_addr;
  (* anyseq *)logic [      XLEN-1:0] boot_wdata;

  logic [  LineBits-1:0] resp_rdata;
  logic                  resp_ready;

  logic                  rst_n;
  logic [           1:0] t = 2'd0;
  logic                  f_past_valid = 1'b0;

  initial assume (t == 2'd0);
  always @(posedge clk) begin
    t <= (t == 2'd3) ? 2'd3 : t + 2'd1;
    f_past_valid <= 1'b1;
  end
  assign rst_n = (t != 2'd0);

  mem_delay #(
      .XLEN(XLEN),
      .DEPTH(DEPTH),
      .Latency(Latency)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .req_valid(req_valid),
      .req_rw(req_rw),
      .req_addr(req_addr),
      .req_wdata(req_wdata),
      .resp_rdata(resp_rdata),
      .resp_ready(resp_ready),
      .boot_we(boot_we),
      .boot_addr(boot_addr),
      .boot_wdata(boot_wdata)
  );

  // Outstanding request
  logic            f_pend;
  logic            f_rw;
  logic            f_hit;
  logic [AgeW-1:0] f_age;
  logic            f_used;
  logic            f_take;

  assign f_take = rst_n && core_en && req_valid && !f_pend;

  always @(posedge clk) begin
    if (!rst_n) begin
      f_pend <= 1'b0;
      f_used <= 1'b0;
      f_age  <= '0;
    end else if (core_en) begin
      if (f_take) begin
        f_pend <= 1'b1;
        f_used <= 1'b1;
        f_rw   <= req_rw;
        f_hit  <= req_addr[IdxLsb+:LineIdxLen] == f_line;
        f_age  <= AgeW'(1);
      end else if (resp_ready) begin
        f_pend <= 1'b0;
        f_age  <= '0;
      end else if (f_pend) begin
        f_age <= f_age + 1'b1;
      end
    end
  end

  // Boot before requests
  always @(posedge clk) if (rst_n && (f_used || req_valid)) assume (!boot_we);

  // Watched line
  logic [ LineBits-1:0] f_data;
  logic [LineWords-1:0] f_known = '0;

  always @(posedge clk)
    if (core_en) begin
      if (boot_we && boot_addr[IdxLsb+:LineIdxLen] == f_line) begin
        f_data[boot_addr[WordLsb+:BlkOffLen]*XLEN+:XLEN] <= boot_wdata;
        f_known[boot_addr[WordLsb+:BlkOffLen]] <= 1'b1;
      end
      if (f_take && req_rw && req_addr[IdxLsb+:LineIdxLen] == f_line) begin
        f_data  <= req_wdata;
        f_known <= '1;
      end
    end

  always @(posedge clk)
    if (rst_n) begin
      if (resp_ready) assert (f_pend && f_age == AgeW'(Latency));
      assert (f_age <= AgeW'(Latency));
      for (int w = 0; w < LineWords; w++)
      if (resp_ready && !f_rw && f_hit && f_known[w])
        assert (resp_rdata[w*XLEN+:XLEN] == f_data[w*XLEN+:XLEN]);
    end

  // Covers
  always @(posedge clk)
    if (rst_n && f_past_valid) begin
      cover (resp_ready && !f_rw && f_hit && f_known == '1 && resp_rdata != '0);
      cover (f_take && $past(resp_ready && req_valid && core_en));
      cover (resp_ready && $past(!core_en) && !f_rw);
      cover (resp_ready && f_rw && f_hit);
    end

endmodule

`default_nettype wire
