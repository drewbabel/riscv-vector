`default_nettype none

module clint_tb;

  localparam int MinChecks = 8000;
  localparam int Xlen = arch_pkg::XLEN;
  localparam int StrbW = Xlen / 8;
  localparam int TagW = $bits(arch_pkg::ClintTag);
  localparam logic [Xlen-1:0] Base = {arch_pkg::ClintTag, {(Xlen - TagW) {1'b0}}};
  localparam logic [Xlen-1:0] MtimecmpLo = Base | Xlen'('h4000);
  localparam logic [Xlen-1:0] MtimecmpHi = Base | Xlen'('h4004);
  localparam logic [Xlen-1:0] MtimeLo = Base | Xlen'('hBFF8);
  localparam logic [Xlen-1:0] MtimeHi = Base | Xlen'('hBFFC);
  localparam int Compare = 50;
  localparam int Boundary = 200;
  localparam int SoakOps = 4000;
  localparam int TimeWords = 64 / Xlen;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic rst_n = 1'b1;
  logic sel;
  logic [StrbW-1:0] wstrb;
  logic [Xlen-1:0] addr;
  logic [Xlen-1:0] wdata;
  logic [Xlen-1:0] rdata;
  logic timer_irq;
  logic core_en = 1'b1;
  logic [63:0] m_time;
  logic [63:0] m_cmp;

  always #5 clk = ~clk;

  clint #(
      .XLEN(Xlen)
  ) dut (
      .clk      (clk),
      .core_en  (core_en),
      .rst_n    (rst_n),
      .sel      (sel),
      .wstrb    (wstrb),
      .addr     (addr),
      .wdata    (wdata),
      .rdata    (rdata),
      .timer_irq(timer_irq)
  );

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    rst_n = 1'b0;
    sel   = 1'b0;
    wstrb = '0;
    addr  = '0;
    wdata = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic mmio_write(input logic [Xlen-1:0] a, input logic [Xlen-1:0] d,
                            input logic [StrbW-1:0] s);
    sel   = 1'b1;
    wstrb = s;
    addr  = a;
    wdata = d;
    @(negedge clk);
    sel   = 1'b0;
    wstrb = '0;
  endtask  // Automatic

  task automatic check_read(input string name, input logic [Xlen-1:0] a,
                            input logic [Xlen-1:0] exp);
    sel  = 1'b1;
    addr = a;
    @(posedge clk);
    check(name, rdata, exp);
    @(negedge clk);
    sel = 1'b0;
  endtask  // Automatic

  task automatic check_irq(input string name, input logic exp);
    check(name, Xlen'(timer_irq), Xlen'(exp));
  endtask  // Automatic

  task automatic idle(input int n);
    repeat (n) @(negedge clk);
  endtask  // Automatic

  task automatic test_compare();
    check_irq("irq_at_reset", 1'b0);
    mmio_write(MtimecmpLo, Xlen'(Compare), '1);
    mmio_write(MtimecmpHi, '0, '1);
    check_read("mtimecmp_readback", MtimecmpLo, Xlen'(Compare));
    check_read("mtimecmp_hi_readback", MtimecmpHi, '0);
    check_irq("irq_before_compare", 1'b0);
    idle(Compare);
    check_irq("irq_after_compare", 1'b1);
  endtask  // Automatic

  task automatic test_byte_write();
    mmio_write(MtimecmpLo, Xlen'('hAA00), StrbW'(2));
    check_read("mtimecmp_byte_write", MtimecmpLo, Xlen'('hAA00 | Compare));
  endtask  // Automatic

  task automatic test_mtime_write();
    mmio_write(MtimeHi, '0, '1);
    mmio_write(MtimeLo, Xlen'(Boundary), '1);
    check_read("mtime_readback", MtimeLo, Xlen'(Boundary));
    check_read("mtime_hi_readback", MtimeHi, '0);
  endtask  // Automatic

  task automatic test_boundary();
    mmio_write(MtimecmpLo, Xlen'(Boundary), '1);
    mmio_write(MtimeLo, Xlen'(Boundary - 1), '1);
    check_irq("irq_below_boundary", 1'b0);
    idle(1);
    check_irq("irq_at_boundary", 1'b1);
  endtask  // Automatic

  function automatic logic [Xlen-1:0] reg_addr(input int r);
    logic [Xlen-1:0] hi;
    hi = Xlen'($urandom) & ~Xlen'('hFFFF);
    case (r)
      0: return hi | Xlen'('h4000);
      1: return hi | Xlen'('h4000 + 4 * (TimeWords - 1));
      2: return hi | Xlen'('hBFF8);
      3: return hi | Xlen'('hBFF8 + 4 * (TimeWords - 1));
      default: return hi | Xlen'(16'($urandom));
    endcase
  endfunction

  function automatic logic [Xlen-1:0] ref_read();
    logic [15:0] off;
    off = addr[15:0];
    if (!sel) return '0;
    for (int w = 0; w < TimeWords; w++) begin
      if (off == 16'('h4000 + 4 * w)) return m_cmp[w*Xlen+:Xlen];
      if (off == 16'('hBFF8 + 4 * w)) return m_time[w*Xlen+:Xlen];
    end
    return '0;
  endfunction

  task automatic ref_edge();
    logic [63:0] t;
    logic [15:0] off;
    if (!core_en) return;
    t   = m_time + 64'd1;
    off = addr[15:0];
    if (sel)
      for (int w = 0; w < TimeWords; w++)
        for (int b = 0; b < StrbW; b++)
          if (wstrb[b]) begin
            if (off == 16'('h4000 + 4 * w)) m_cmp[w*Xlen+8*b+:8] = wdata[8*b+:8];
            if (off == 16'('hBFF8 + 4 * w)) t[w*Xlen+8*b+:8] = wdata[8*b+:8];
          end
    m_time = t;
  endtask  // Automatic

  task automatic soak(input int n);
    do_reset();
    m_time = '0;
    m_cmp  = '1;
    repeat (n) begin
      core_en = $urandom_range(3) != 0;
      sel     = 1'($urandom);
      addr    = reg_addr(int'($urandom_range(5)));
      wstrb   = ($urandom_range(2) == 0) ? '0 : StrbW'($urandom);
      wdata   = Xlen'($urandom);
      if ($urandom_range(7) == 0) wdata = '1 - Xlen'($urandom_range(3));
      #1;
      check("soak rdata", rdata, ref_read());
      check("soak irq", Xlen'(timer_irq), Xlen'(m_time >= m_cmp));
      @(posedge clk);
      ref_edge();
      @(negedge clk);
    end
    core_en = 1'b1;
    sel     = 1'b0;
    wstrb   = '0;
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    $dumpfile("clint_tb.vcd");
    $dumpvars(0, clint_tb);
    do_reset();

    test_compare();
    test_byte_write();
    test_mtime_write();
    test_boundary();
    soak(SoakOps);

    do_verdict();
  end

endmodule

`default_nettype wire
