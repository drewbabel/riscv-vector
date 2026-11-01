`default_nettype none

module pmu_tb ();

  localparam int MinChecks = 11;

  int checks;
  int errors;
  int max_errors;
  int live_errors;

  pmu_bench core_bench ();

  pmu_bench #(.CLK_FREQ_HZ(3_125_000)) slow_bench ();

  pmu_bench #(.CLK_FREQ_HZ(25_000_000)) quarter_bench ();

  pmu_bench #(.CLK_FREQ_HZ(100_000_000)) board_bench ();

  task automatic check_floor(input string name, input int got, input int floor);
    if (got < floor)
      $fatal(1, "TB UNDER-RAN: %s %0d checks, expected at least %0d", name, got, floor);
  endtask  // Automatic

  task automatic do_verdict();
    checks = core_bench.checks + slow_bench.checks + quarter_bench.checks + board_bench.checks;
    errors = core_bench.errors + slow_bench.errors + quarter_bench.errors + board_bench.errors;
    check_floor("core_bench", core_bench.checks, MinChecks);
    check_floor("slow_bench", slow_bench.checks, MinChecks);
    check_floor("quarter_bench", quarter_bench.checks, MinChecks);
    check_floor("board_bench", board_bench.checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("pmu_tb.vcd");
    $dumpvars(0, pmu_tb);
    wait (core_bench.done && slow_bench.done && quarter_bench.done && board_bench.done);
    do_verdict();
  end

  always_comb
    live_errors = core_bench.errors + slow_bench.errors + quarter_bench.errors + board_bench.errors;

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (live_errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", live_errors);
    end
  end

endmodule

module pmu_bench #(
    parameter int CLK_FREQ_HZ = arch_pkg::BoardClkHz / arch_pkg::ClkDiv
) ();

  localparam int Xlen = arch_pkg::XLEN;
  localparam int ClkFreqHz = CLK_FREQ_HZ;
  localparam int TagW = $bits(arch_pkg::PmuTag);
  localparam int WordBytes = Xlen / 8;
  localparam logic [Xlen-1:0] PmuBase = {arch_pkg::PmuTag, (Xlen - TagW)'(0)};

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;

  logic [Xlen-1:0] addr;
  logic [Xlen-1:0] rdata;
  logic [Xlen-1:0] ic_hits;
  logic [Xlen-1:0] ic_misses;
  logic [Xlen-1:0] dc_hits;
  logic [Xlen-1:0] dc_misses;

  pmu #(
      .XLEN(Xlen),
      .CLK_FREQ_HZ(ClkFreqHz)
  ) dut (
      .addr     (addr),
      .rdata    (rdata),
      .ic_hits  (ic_hits),
      .ic_misses(ic_misses),
      .dc_hits  (dc_hits),
      .dc_misses(dc_misses)
  );

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %m %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    addr = PmuBase;
    set_counters(Xlen'('h1111_1111), Xlen'('h2222_2222), Xlen'('h3333_3333), Xlen'('h4444_4444));
  endtask  // Automatic

  task automatic set_counters(input logic [Xlen-1:0] ih, input logic [Xlen-1:0] im,
                              input logic [Xlen-1:0] dh, input logic [Xlen-1:0] dm);
    ic_hits   = ih;
    ic_misses = im;
    dc_hits   = dh;
    dc_misses = dm;
  endtask  // Automatic

  function automatic logic [Xlen-1:0] reg_addr(input int index, input int offset);
    return PmuBase + Xlen'(index * WordBytes + offset);
  endfunction

  task automatic read_check(input string name, input logic [Xlen-1:0] a,
                            input logic [Xlen-1:0] exp);
    addr = a;
    #1;
    check(name, rdata, exp);
  endtask  // Automatic

  task automatic check_map();
    read_check("ic_hits", reg_addr(0, 0), ic_hits);
    read_check("ic_misses", reg_addr(1, 0), ic_misses);
    read_check("dc_hits", reg_addr(2, 0), dc_hits);
    read_check("dc_misses", reg_addr(3, 0), dc_misses);
    read_check("clk_hz", reg_addr(4, 0), Xlen'(ClkFreqHz));
    read_check("reserved_reads_zero", reg_addr(5, 0), '0);
  endtask  // Automatic

  task automatic check_decode();
    read_check("byte_offset_ignored", reg_addr(0, 1), ic_hits);
    read_check("clk_hz_byte_offset", reg_addr(4, 2), Xlen'(ClkFreqHz));
    read_check("upper_addr_ignored", reg_addr(65, 0), ic_misses);
  endtask  // Automatic

  task automatic check_update();
    set_counters(Xlen'('hAAAA_AAAA), ic_misses, dc_hits, Xlen'('hBBBB_BBBB));
    read_check("ic_hits_updated", reg_addr(0, 0), Xlen'('hAAAA_AAAA));
    read_check("dc_misses_updated", reg_addr(3, 0), Xlen'('hBBBB_BBBB));
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    do_reset();
    check_map();
    check_decode();
    check_update();
    done = 1'b1;
  end

endmodule

`default_nettype wire
