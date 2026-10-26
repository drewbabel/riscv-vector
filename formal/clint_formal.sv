`default_nettype none

module clint_formal ();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int WordBytes = XLEN / 8;
  localparam int TimeW = 64;
  localparam int TimeWords = TimeW / XLEN;
  localparam logic [15:0] MtimecmpOff = 16'h4000;
  localparam logic [15:0] MtimeOff = 16'hBFF8;

  logic                 clk;

  (* anyseq *)logic                 core_en;
  (* anyseq *)logic                 sel;
  (* anyseq *)logic [WordBytes-1:0] wstrb;
  (* anyseq *)logic [     XLEN-1:0] addr;
  (* anyseq *)logic [     XLEN-1:0] wdata;

  logic [     XLEN-1:0] rdata;
  logic                 timer_irq;

  logic                 rst_n;
  logic [          1:0] t = 2'd0;
  logic                 f_past_valid = 1'b0;

  initial assume (t == 2'd0);
  always @(posedge clk) begin
    t <= (t == 2'd3) ? 2'd3 : t + 2'd1;
    f_past_valid <= 1'b1;
  end
  assign rst_n = (t != 2'd0);

  clint #(
      .XLEN(XLEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .sel(sel),
      .wstrb(wstrb),
      .addr(addr),
      .wdata(wdata),
      .rdata(rdata),
      .timer_irq(timer_irq)
  );

  // Architectural timer
  logic [TimeW-1:0] f_mtime;
  logic [TimeW-1:0] f_cmp;
  logic [TimeW-1:0] f_mtime_next;
  logic [TimeW-1:0] f_cmp_next;

  always_comb begin
    f_mtime_next = f_mtime + 1'b1;
    f_cmp_next   = f_cmp;
    for (int w = 0; w < TimeWords; w++) begin
      for (int b = 0; b < WordBytes; b++) begin
        if (sel && wstrb[b] && addr[15:0] == MtimeOff + 16'(w * WordBytes))
          f_mtime_next[w*XLEN+8*b+:8] = wdata[8*b+:8];
        if (sel && wstrb[b] && addr[15:0] == MtimecmpOff + 16'(w * WordBytes))
          f_cmp_next[w*XLEN+8*b+:8] = wdata[8*b+:8];
      end
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      f_mtime <= '0;
      f_cmp   <= '1;
    end else if (core_en) begin
      f_mtime <= f_mtime_next;
      f_cmp   <= f_cmp_next;
    end
  end

  always @(posedge clk)
    if (rst_n) begin
      assert (timer_irq == (f_mtime >= f_cmp));
      for (int w = 0; w < TimeWords; w++) begin
        if (sel && addr[15:0] == MtimeOff + 16'(w * WordBytes))
          assert (rdata == f_mtime[w*XLEN+:XLEN]);
        if (sel && addr[15:0] == MtimecmpOff + 16'(w * WordBytes))
          assert (rdata == f_cmp[w*XLEN+:XLEN]);
      end
    end

  // Covers
  always @(posedge clk)
    if (rst_n && f_past_valid) begin
      cover (timer_irq && !$past(timer_irq) && $past(core_en && !(sel && wstrb != '0)));
      cover (!timer_irq && $past(timer_irq) && $past(sel && addr[15:0] == MtimecmpOff));
      cover (timer_irq && $past(sel && wstrb != '0 && addr[15:0] == MtimeOff + 16'(WordBytes)));
      cover (sel && addr[15:0] == MtimeOff && rdata != '0 && !timer_irq);
    end

endmodule

`default_nettype wire
