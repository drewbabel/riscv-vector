`default_nettype none

module icache_tb;

  import cache_pkg::*;

  localparam int MinChecks = 10 + LineWords;
  localparam int Xlen = arch_pkg::XLEN;
  localparam int Depth = 8192;
  localparam int Latency = 4;
  localparam int Stride = 1 << (IdxLsb + IcIdxLen);
  localparam int MaxWait = 200;
  localparam logic [Xlen-1:0] SeedA = Xlen'('hA000_0000);
  localparam logic [Xlen-1:0] SeedB = Xlen'('hB000_0000);
  localparam logic [Xlen-1:0] SeedC = Xlen'('hC000_0000);

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic core_en;
  logic rst_n = 1'b1;

  logic cpu_valid;
  logic [Xlen-1:0] cpu_addr;
  logic [Xlen-1:0] cpu_rdata;
  logic cpu_ready;

  logic mem_valid;
  logic [Xlen-1:0] mem_addr;
  logic [LineBits-1:0] mem_rdata;
  logic mem_ready;

  logic [Xlen-1:0] boot_addr;
  logic [Xlen-1:0] boot_wdata;
  logic boot_we;

  logic [Xlen-1:0] hit_count;
  logic [Xlen-1:0] miss_count;

  always #5 clk = ~clk;

  icache #(
      .XLEN(Xlen)
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

  mem_delay #(
      .XLEN(Xlen),
      .DEPTH(Depth),
      .Latency(Latency)
  ) memory (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .req_valid(mem_valid),
      .req_rw(1'b0),
      .req_addr(mem_addr),
      .req_wdata('0),
      .resp_rdata(mem_rdata),
      .resp_ready(mem_ready),
      .boot_we(boot_we),
      .boot_addr(boot_addr),
      .boot_wdata(boot_wdata)
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
    rst_n      = 1'b0;
    core_en    = 1'b1;
    cpu_valid  = 1'b0;
    cpu_addr   = '0;
    boot_we    = 1'b0;
    boot_addr  = '0;
    boot_wdata = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    // Wait reset walk
    repeat (IcSets + 2) @(posedge clk);
    @(negedge clk);
  endtask  // Automatic

  task automatic boot_word(input logic [Xlen-1:0] addr, input logic [Xlen-1:0] data);
    boot_we    = 1'b1;
    boot_addr  = addr;
    boot_wdata = data;
    @(negedge clk);
    boot_we = 1'b0;
    @(negedge clk);
  endtask  // Automatic

  task automatic boot_line(input logic [Xlen-1:0] base, input logic [Xlen-1:0] seed);
    for (int w = 0; w < LineWords; w++) boot_word(base + Xlen'(w * WordBytes), seed + Xlen'(w));
  endtask  // Automatic

  task automatic fetch(input logic [Xlen-1:0] addr);
    int guard;
    cpu_valid = 1'b1;
    cpu_addr  = addr;
    guard     = 0;
    @(posedge clk);
    while (!cpu_ready) begin
      guard++;
      if (guard > MaxWait) $fatal(1, "cpu_ready never arrived for %h", addr);
      @(posedge clk);
    end
    @(negedge clk);
    cpu_valid = 1'b0;
    @(negedge clk);
  endtask  // Automatic

  task automatic check_fetch(input string name, input logic [Xlen-1:0] addr,
                             input logic [Xlen-1:0] exp);
    fetch(addr);
    check(name, cpu_rdata, exp);
  endtask  // Automatic

  task automatic check_counts(input string name, input int hits, input int misses);
    check({name, " hits"}, Xlen'(hit_count), Xlen'(hits));
    check({name, " misses"}, Xlen'(miss_count), Xlen'(misses));
  endtask  // Automatic

  task automatic load_lines();
    boot_line('0, SeedA);
    boot_line(Xlen'(Stride), SeedB);
    boot_line(Xlen'(LineBytes), SeedC);
  endtask  // Automatic

  task automatic test_cold_miss();
    check_fetch("cold miss data", '0, SeedA);
    check_counts("cold", 0, 1);
  endtask  // Automatic

  task automatic test_neighbours();
    for (int w = 1; w < LineWords; w++)
      check_fetch($sformatf("neighbour %0d", w), Xlen'(w * WordBytes), SeedA + Xlen'(w));
    check_counts("neighbours", LineWords - 1, 1);
  endtask  // Automatic

  task automatic test_other_index();
    check_fetch("second index", Xlen'(LineBytes), SeedC);
    check_fetch("first index kept", '0, SeedA);
    check("two misses", Xlen'(miss_count), Xlen'(2));
  endtask  // Automatic

  task automatic test_conflict();
    check_fetch("conflicting tag", Xlen'(Stride), SeedB);
    check_fetch("conflict evicted", '0, SeedA);
    check("conflict misses", Xlen'(miss_count), Xlen'(4));
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
    $dumpfile("icache_tb.vcd");
    $dumpvars(0, icache_tb);
    do_reset();

    load_lines();
    test_cold_miss();
    test_neighbours();
    test_other_index();
    test_conflict();

    do_verdict();
  end

endmodule

`default_nettype wire
