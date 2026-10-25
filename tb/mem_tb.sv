`default_nettype none

module mem_tb ();

  localparam int MinChecks = 12;
  localparam int XLEN = arch_pkg::XLEN;
  localparam int DEPTH = 8192;
  localparam int StrbW = XLEN / 8;
  localparam logic [StrbW-1:0] Lane1 = StrbW'(1) << 1;
  localparam logic [XLEN-1:0] TopAddr = XLEN'((DEPTH - 1) * StrbW);

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic core_en;
  logic [XLEN-1:0] iaddr;
  logic [XLEN-1:0] instr;
  logic [StrbW-1:0] wstrb;
  logic [XLEN-1:0] daddr;
  logic [XLEN-1:0] wdata;
  logic [XLEN-1:0] rdata;

  always #5 clk = ~clk;

  mem #(
      .XLEN (XLEN),
      .DEPTH(DEPTH)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .iaddr(iaddr),
      .instr(instr),
      .wstrb(wstrb),
      .daddr(daddr),
      .wdata(wdata),
      .rdata(rdata)
  );

  task automatic check(input string name, input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    core_en = 1'b1;
    iaddr   = '0;
    daddr   = '0;
    wdata   = '0;
    wstrb   = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
  endtask  // Automatic

  task automatic write_lanes(input logic [XLEN-1:0] addr, input logic [XLEN-1:0] data,
                             input logic [StrbW-1:0] mask);
    daddr = addr;
    wdata = data;
    wstrb = mask;
    @(negedge clk);
    wstrb = '0;
  endtask  // Automatic

  task automatic write_word(input logic [XLEN-1:0] addr, input logic [XLEN-1:0] data);
    write_lanes(addr, data, '1);
  endtask  // Automatic

  task automatic write_stalled(input logic [XLEN-1:0] addr, input logic [XLEN-1:0] data);
    core_en = 1'b0;
    write_lanes(addr, data, '1);
    core_en = 1'b1;
  endtask  // Automatic

  task automatic check_data(input string name, input logic [XLEN-1:0] addr,
                            input logic [XLEN-1:0] exp);
    daddr = addr;
    wstrb = '0;
    @(negedge clk);
    check(name, rdata, exp);
  endtask  // Automatic

  task automatic check_fetch(input string name, input logic [XLEN-1:0] addr,
                             input logic [XLEN-1:0] exp);
    iaddr = addr;
    @(negedge clk);
    check(name, instr, exp);
  endtask  // Automatic

  task automatic test_byte_lanes();
    write_word(XLEN'('h10), XLEN'('h1122_3344));
    write_word(XLEN'('h20), XLEN'('hAABB_CCDD));
    check_data("word 0x10", XLEN'('h10), XLEN'('h1122_3344));
    check_data("word 0x20", XLEN'('h20), XLEN'('hAABB_CCDD));
    write_lanes(XLEN'('h10), XLEN'('hEE00), Lane1);
    check_data("lane 0x10", XLEN'('h10), XLEN'('h1122_EE44));
    check_data("lane 0x10 neighbour", XLEN'('h20), XLEN'('hAABB_CCDD));
    write_lanes(XLEN'('h20), XLEN'('h9900), Lane1);
    check_data("lane 0x20", XLEN'('h20), XLEN'('hAABB_99DD));
    check_data("lane 0x20 neighbour", XLEN'('h10), XLEN'('h1122_EE44));
  endtask  // Automatic

  task automatic test_shared_array();
    write_word(XLEN'('h30), XLEN'('hCAFE_BABE));
    check_data("port B readback", XLEN'('h30), XLEN'('hCAFE_BABE));
    check_fetch("port A shared", XLEN'('h30), XLEN'('hCAFE_BABE));
    check_fetch("port A lane", XLEN'('h10), XLEN'('h1122_EE44));
  endtask  // Automatic

  task automatic test_top_word();
    write_word(TopAddr, XLEN'('h5A5A_A5A5));
    check_fetch("top word", TopAddr, XLEN'('h5A5A_A5A5));
    check_data("bottom word", '0, '0);
  endtask  // Automatic

  task automatic test_core_stall();
    write_stalled(XLEN'('h30), XLEN'('h0BAD_F00D));
    check_data("stalled write ignored", XLEN'('h30), XLEN'('hCAFE_BABE));
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
    $dumpfile("mem_tb.vcd");
    $dumpvars(0, mem_tb);
    do_reset();

    test_byte_lanes();
    test_shared_array();
    test_top_word();
    test_core_stall();

    do_verdict();
  end

endmodule

`default_nettype wire
