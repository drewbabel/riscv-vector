`default_nettype none

module bram_sdp_tb ();

  localparam int MinChecks = 60000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  bram_sdp_bench #(
      .Width(8),
      .Depth(256),
      .Block(1'b1)
  ) byte_bench ();

  bram_sdp_bench #(
      .Width(20),
      .Depth(16),
      .Block(1'b1)
  ) odd_bench ();

  bram_sdp_bench #(
      .Width(32),
      .Depth(64),
      .Block(1'b0)
  ) dist_bench ();

  initial void'($value$plusargs("max_errors=%d", max_errors));

  task automatic do_verdict();
    checks = byte_bench.checks + odd_bench.checks + dist_bench.checks;
    errors = byte_bench.errors + odd_bench.errors + dist_bench.errors;
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("bram_sdp_tb.vcd");
    $dumpvars(0, bram_sdp_tb);
    wait (byte_bench.finished && odd_bench.finished && dist_bench.finished);
    do_verdict();
  end

endmodule

module bram_sdp_bench #(
    parameter int Width = 8,
    parameter int Depth = 256,
    parameter bit Block = 1'b1
) ();

  localparam int AddrW = $clog2(Depth);
  localparam int Lanes = (Width + 7) / 8;
  localparam int Ops   = 20000;

  int checks = 0;
  int errors = 0;
  logic finished = 1'b0;

  logic clk = 1'b0;
  logic we;
  logic [Lanes-1:0] wlane;
  logic [AddrW-1:0] widx;
  logic [Width-1:0] wdata;
  logic re;
  logic [AddrW-1:0] ridx;
  logic [Width-1:0] rdata;

  logic [Width-1:0] model[Depth];
  logic [Width-1:0] exp_q;

  bram_sdp #(
      .Width(Width),
      .Depth(Depth),
      .Block(Block)
  ) dut (
      .clk(clk),
      .we(we),
      .wlane(wlane),
      .widx(widx),
      .wdata(wdata),
      .re(re),
      .ridx(ridx),
      .rdata(rdata)
  );

  always #5 clk = ~clk;

  task automatic check(input string name, input logic [Width-1:0] got, input logic [Width-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %m %s: got %h, expected %h", name, got, exp);
      if (errors == bram_sdp_tb.max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  function automatic logic [Width-1:0] lane_mask(input logic [Lanes-1:0] l);
    logic [Width-1:0] m;
    for (int i = 0; i < Width; i++) m[i] = l[i/8];
    return m;
  endfunction

  task automatic step();
    logic [Width-1:0] m;
    if (re) exp_q = model[ridx];
    if (we) begin
      m = lane_mask(wlane);
      model[widx] = (model[widx] & ~m) | (wdata & m);
    end
    @(posedge clk);
    #1;
    check($sformatf("rdata re=%b ridx=%0d", re, ridx), rdata, exp_q);
  endtask  // Automatic

  task automatic random_ops(input int n, input int span);
    repeat (n) begin
      we = 1'($urandom);
      re = 1'($urandom_range(3) != 0);
      wlane = Lanes'($urandom);
      widx = AddrW'($urandom_range(span - 1));
      ridx = 1'($urandom) ? widx : AddrW'($urandom_range(span - 1));
      wdata = Width'({32'($urandom), 32'($urandom)});
      step();
    end
  endtask  // Automatic

  task automatic test_fill();
    we = 1'b0;
    re = 1'b1;
    for (int i = 0; i < Depth; i++) begin
      ridx = AddrW'(i);
      step();
    end
    for (int i = 0; i < Depth; i++) begin
      we = 1'b1;
      re = 1'b0;
      wlane = '1;
      widx = AddrW'(i);
      wdata = Width'({32'($urandom), 32'($urandom)});
      step();
    end
    we = 1'b0;
    re = 1'b1;
    for (int i = 0; i < Depth; i++) begin
      ridx = AddrW'(i);
      step();
    end
  endtask  // Automatic

  task automatic do_reset();
    for (int i = 0; i < Depth; i++) model[i] = '0;
    exp_q = 'x;
    we = 1'b0;
    re = 1'b0;
    wlane = '0;
    widx = '0;
    ridx = '0;
    wdata = '0;
    @(posedge clk);
    #1;
  endtask  // Automatic

  initial begin
    do_reset();
    test_fill();
    random_ops(Ops / 2, Depth);
    random_ops(Ops / 2, 4);
    finished = 1'b1;
  end

endmodule

`default_nettype wire
