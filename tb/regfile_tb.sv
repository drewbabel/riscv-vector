`default_nettype none

module regfile_tb ();

  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int XLEN = arch_pkg::XLEN;
  localparam int Depth = 2 ** AWIDTH;
  localparam int MinChecks = 2000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic rst_n = 1'b1;
  logic we;
  logic [AWIDTH-1:0] waddr;
  logic [XLEN-1:0] wdata;
  logic [AWIDTH-1:0] raddr1;
  logic [AWIDTH-1:0] raddr2;
  logic [XLEN-1:0] rdata1;
  logic [XLEN-1:0] rdata2;

  logic [XLEN-1:0] shadow[Depth];

  always #5 clk = ~clk;

  regfile #(
      .AWIDTH(AWIDTH),
      .XLEN  (XLEN)
  ) dut (
      .clk(clk),
      .core_en(1'b1),
      .rst_n(rst_n),
      .we(we),
      .waddr(waddr),
      .wdata(wdata),
      .raddr1(raddr1),
      .raddr2(raddr2),
      .rdata1(rdata1),
      .rdata2(rdata2)
  );

  task automatic check(input string name, input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  // Stimulus
  task automatic do_reset();
    @(negedge clk);
    rst_n  = 0;
    we     = 1'b0;
    waddr  = '0;
    wdata  = '0;
    raddr1 = '0;
    raddr2 = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
  endtask  // Automatic

  task automatic write_reg(input logic [AWIDTH-1:0] addr, input logic [XLEN-1:0] data);
    @(negedge clk);
    waddr = addr;
    wdata = data;
    we = 1'b1;
    @(posedge clk);
    @(negedge clk);
    we = 1'b0;
  endtask  // Automatic

  task automatic check_read(input string port, input logic [AWIDTH-1:0] addr,
                            input logic [XLEN-1:0] got);
    check($sformatf("%s addr %0d", port, addr), got, (addr == 0) ? '0 : shadow[addr]);
  endtask  // Automatic

  task automatic check_reads(input logic [AWIDTH-1:0] addr1, input logic [AWIDTH-1:0] addr2);
    @(negedge clk);
    raddr1 = addr1;
    raddr2 = addr2;
    @(posedge clk);
    check_read("rdata1", raddr1, rdata1);
    check_read("rdata2", raddr2, rdata2);
  endtask  // Automatic

  task automatic random_sweep(input int n);
    repeat (n) begin
      write_reg(AWIDTH'($urandom), XLEN'($urandom));
      check_reads(AWIDTH'($urandom), AWIDTH'($urandom));
    end
  endtask  // Automatic

  task automatic do_verdict();
    @(posedge clk);
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    $dumpfile("regfile_tb.vcd");
    $dumpvars(0, regfile_tb);
    do_reset();

    // Same register both ports
    write_reg(AWIDTH'(5), XLEN'('hDEAD_BEEF));
    check_reads(AWIDTH'(5), AWIDTH'(5));

    write_reg(AWIDTH'(0), XLEN'('hFFFF_FFFF));
    check_reads(AWIDTH'(0), AWIDTH'(0));

    // Two registers at once
    write_reg(AWIDTH'(7), XLEN'('h0000_00AA));
    write_reg(AWIDTH'(9), XLEN'('h0000_00BB));
    check_reads(AWIDTH'(7), AWIDTH'(9));

    do_reset();
    check_reads(AWIDTH'(5), AWIDTH'(9));

    random_sweep(1000);
    do_verdict();
  end

  // Reference model
  always @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < Depth; i++) shadow[i] <= '0;
    end else if (we && waddr != 0) begin
      shadow[waddr] <= wdata;
    end
  end

endmodule

`default_nettype wire
