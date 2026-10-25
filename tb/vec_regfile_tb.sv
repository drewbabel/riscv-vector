`default_nettype none

module vec_regfile_tb ();

  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int VLEN = arch_pkg::VLEN;
  localparam int Words = VLEN / 32;
  localparam int Depth = 2 ** AWIDTH;
  localparam int MinChecks = 8100;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic core_en;
  logic we;
  logic [VLEN-1:0] wstrb;
  logic [AWIDTH-1:0] waddr;
  logic [VLEN-1:0] wdata;
  logic [AWIDTH-1:0] raddr1;
  logic [AWIDTH-1:0] raddr2;
  logic [AWIDTH-1:0] raddr3;
  logic [VLEN-1:0] rdata1;
  logic [VLEN-1:0] rdata2;
  logic [VLEN-1:0] rdata3;
  logic [VLEN-1:0] rdata0;

  logic [VLEN-1:0] shadow[Depth];

  always #5 clk = ~clk;

  vec_regfile #(
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .we(we),
      .wstrb(wstrb),
      .waddr(waddr),
      .wdata(wdata),
      .raddr1(raddr1),
      .raddr2(raddr2),
      .raddr3(raddr3),
      .rdata1(rdata1),
      .rdata2(rdata2),
      .rdata3(rdata3),
      .rdata0(rdata0)
  );

  // Checks
  task automatic check(input string name, input logic [VLEN-1:0] got, input logic [VLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    core_en = 1'b1;
    we      = 1'b0;
    wstrb   = '0;
    waddr   = '0;
    wdata   = '0;
    raddr1  = '0;
    raddr2  = '0;
    raddr3  = '0;
    for (int i = 0; i < Depth; i++) shadow[i] = '0;
    @(negedge clk);
  endtask  // Automatic

  // Stimulus
  task automatic drive_write(input logic [AWIDTH-1:0] addr, input logic [VLEN-1:0] data,
                             input logic [VLEN-1:0] strb, input logic en, input logic wen);
    core_en = en;
    waddr   = addr;
    wdata   = data;
    wstrb   = strb;
    we      = wen;
    @(posedge clk);
    if (en && wen) model_write(addr, data, strb);
    @(negedge clk);
    we      = 1'b0;
    wstrb   = '0;
    core_en = 1'b1;
  endtask  // Automatic

  task automatic write_full(input logic [AWIDTH-1:0] addr, input logic [VLEN-1:0] data);
    drive_write(addr, data, '1, 1'b1, 1'b1);
  endtask  // Automatic

  task automatic write_masked(input logic [AWIDTH-1:0] addr, input logic [VLEN-1:0] data,
                              input logic [VLEN-1:0] strb);
    drive_write(addr, data, strb, 1'b1, 1'b1);
  endtask  // Automatic

  task automatic write_core_off(input logic [AWIDTH-1:0] addr, input logic [VLEN-1:0] data);
    drive_write(addr, data, '1, 1'b0, 1'b1);
  endtask  // Automatic

  task automatic write_we_off(input logic [AWIDTH-1:0] addr, input logic [VLEN-1:0] data);
    drive_write(addr, data, '1, 1'b1, 1'b0);
  endtask  // Automatic

  task automatic check_reads(input logic [AWIDTH-1:0] a1, input logic [AWIDTH-1:0] a2,
                             input logic [AWIDTH-1:0] a3);
    raddr1 = a1;
    raddr2 = a2;
    raddr3 = a3;
    @(negedge clk);
    check($sformatf("rdata1 addr=%0d", a1), rdata1, shadow[a1]);
    check($sformatf("rdata2 addr=%0d", a2), rdata2, shadow[a2]);
    check($sformatf("rdata3 addr=%0d", a3), rdata3, shadow[a3]);
    check("rdata0", rdata0, shadow[0]);
  endtask  // Automatic

  task automatic check_all();
    for (int i = 0; i < Depth; i++) check_reads(AWIDTH'(i), AWIDTH'(i), AWIDTH'(i));
  endtask  // Automatic

  task automatic check_field(input logic [AWIDTH-1:0] addr, input int lo, input logic [3:0] exp);
    raddr1 = addr;
    @(negedge clk);
    check($sformatf("field addr=%0d lo=%0d", addr, lo), VLEN'(rdata1[lo+:4]), VLEN'(exp));
  endtask  // Automatic

  task automatic check_read_first(input logic [AWIDTH-1:0] addr, input logic [VLEN-1:0] data);
    logic [VLEN-1:0] prev;
    write_full(addr, ~data);
    prev   = shadow[addr];
    raddr1 = addr;
    waddr  = addr;
    wdata  = data;
    wstrb  = '1;
    we     = 1'b1;
    @(posedge clk);
    check($sformatf("read first addr=%0d", addr), rdata1, prev);
    model_write(addr, data, '1);
    @(negedge clk);
    we    = 1'b0;
    wstrb = '0;
    check_reads(addr, addr, addr);
  endtask  // Automatic

  // Zero at startup
  task automatic test_startup_zero();
    check_all();
  endtask  // Automatic

  // Full width write
  task automatic test_full_write();
    write_full(5, {Words{32'hDEAD_BEEF}});
    check_reads(5, 5, 5);
  endtask  // Automatic

  // v0 holds data
  task automatic test_v0();
    write_full(0, {Words{32'hA5A5_5A5A}});
    check_reads(0, 0, 0);
  endtask  // Automatic

  // Three ports differ
  task automatic test_three_ports();
    write_full(7, {Words{32'h0000_0007}});
    write_full(9, {Words{32'h0000_0009}});
    check_reads(5, 7, 9);
  endtask  // Automatic

  // Byte strobe
  task automatic test_byte_strobe();
    write_full(12, '1);
    write_masked(12, '0, VLEN'(8'hFF));
    check_reads(12, 12, 12);
  endtask  // Automatic

  // Single bit strobe
  task automatic test_bit_strobe();
    write_full(13, '1);
    write_masked(13, '0, VLEN'(4'b0010));
    check_reads(13, 13, 13);
    check_field(13, 0, 4'b1101);
  endtask  // Automatic

  // Read before write
  task automatic test_read_first();
    check_read_first(17, {Words{32'h2222_2222}});
  endtask  // Automatic

  // Core disabled
  task automatic test_core_off();
    write_core_off(21, '1);
    check_reads(21, 21, 21);
  endtask  // Automatic

  // Strobe without we
  task automatic test_we_off();
    write_we_off(25, '1);
    check_reads(25, 25, 25);
  endtask  // Automatic

  // Randomized soak
  task automatic soak(input int n);
    logic [VLEN-1:0] data;
    logic [VLEN-1:0] strb;
    for (int i = 0; i < n; i++) begin
      for (int w = 0; w < VLEN; w += 32) data[w+:32] = 32'($urandom);
      for (int w = 0; w < VLEN; w += 32) strb[w+:32] = 32'($urandom);
      write_masked(AWIDTH'($urandom), data, strb);
      check_reads(AWIDTH'($urandom), AWIDTH'($urandom), AWIDTH'($urandom));
    end
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
    $dumpfile("vec_regfile_tb.vcd");
    $dumpvars(0, vec_regfile_tb);
    do_reset();

    test_startup_zero();
    test_full_write();
    test_v0();
    test_three_ports();
    test_byte_strobe();
    test_bit_strobe();
    test_read_first();
    test_core_off();
    test_we_off();
    soak(2000);

    do_verdict();
  end

  // Reference model
  task automatic model_write(input logic [AWIDTH-1:0] addr, input logic [VLEN-1:0] data,
                             input logic [VLEN-1:0] strb);
    for (int b = 0; b < VLEN; b++) if (strb[b]) shadow[addr][b] = data[b];
  endtask  // Automatic

endmodule

`default_nettype wire
