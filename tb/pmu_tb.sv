`default_nettype none

module pmu_tb;

  localparam int Xlen = arch_pkg::XLEN;
  localparam int ClkFreqHz = 3_125_000;
  localparam int TagW = $bits(arch_pkg::PmuTag);
  localparam int WordBytes = Xlen / 8;
  localparam logic [Xlen-1:0] PmuBase = {arch_pkg::PmuTag, (Xlen - TagW)'(0)};
  localparam int MinChecks = 11;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

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
      $display("FAIL %s: got %h, expected %h", name, got, exp);
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

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    $dumpfile("pmu_tb.vcd");
    $dumpvars(0, pmu_tb);
    do_reset();
    check_map();
    check_decode();
    check_update();
    do_verdict();
  end

endmodule

`default_nettype wire
