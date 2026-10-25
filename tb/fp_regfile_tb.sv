`default_nettype none

module fp_regfile_tb ();

  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int FLEN = fp_pkg::FLEN;
  localparam int Depth = 2 ** AWIDTH;
  localparam int MinChecks = 12000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic rst_n = 1'b1;
  logic core_en;
  logic we;
  logic [AWIDTH-1:0] waddr;
  logic [FLEN-1:0] wdata;
  logic we2;
  logic [AWIDTH-1:0] waddr2;
  logic [FLEN-1:0] wdata2;
  logic [AWIDTH-1:0] raddr1;
  logic [AWIDTH-1:0] raddr2;
  logic [AWIDTH-1:0] raddr3;
  logic [FLEN-1:0] rdata1;
  logic [FLEN-1:0] rdata2;
  logic [FLEN-1:0] rdata3;

  logic [FLEN-1:0] shadow[Depth];

  always #5 clk = ~clk;

  fp_regfile #(
      .AWIDTH(AWIDTH),
      .FLEN  (FLEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .we(we),
      .waddr(waddr),
      .wdata(wdata),
      .we2(we2),
      .waddr2(waddr2),
      .wdata2(wdata2),
      .raddr1(raddr1),
      .raddr2(raddr2),
      .raddr3(raddr3),
      .rdata1(rdata1),
      .rdata2(rdata2),
      .rdata3(rdata3)
  );

  task automatic check(input string name, input logic [FLEN-1:0] got, input logic [FLEN-1:0] exp);
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
    core_en = 1'b1;
    we = 1'b0;
    waddr = '0;
    wdata = '0;
    we2 = 1'b0;
    waddr2 = '0;
    wdata2 = '0;
    raddr1 = '0;
    raddr2 = '0;
    raddr3 = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  function automatic logic [FLEN-1:0] exp_read(input logic [AWIDTH-1:0] ra);
    if (we2 && waddr2 == ra) return wdata2;
    if (we && waddr == ra) return wdata;
    return shadow[ra];
  endfunction

  task automatic check_ports(input string name);
    @(posedge clk);
    check({name, " port1"}, rdata1, exp_read(raddr1));
    check({name, " port2"}, rdata2, exp_read(raddr2));
    check({name, " port3"}, rdata3, exp_read(raddr3));
    @(negedge clk);
  endtask  // Automatic

  task automatic step(input logic w, input logic [AWIDTH-1:0] wa, input logic [FLEN-1:0] wd,
                      input logic [AWIDTH-1:0] r1, input logic [AWIDTH-1:0] r2,
                      input logic [AWIDTH-1:0] r3, input string name);
    we     = w;
    waddr  = wa;
    wdata  = wd;
    raddr1 = r1;
    raddr2 = r2;
    raddr3 = r3;
    check_ports(name);
  endtask  // Automatic

  task automatic step_two(input logic w2, input logic [AWIDTH-1:0] wa2, input logic [FLEN-1:0] wd2,
                          input logic w, input logic [AWIDTH-1:0] wa, input logic [FLEN-1:0] wd,
                          input logic [AWIDTH-1:0] r1, input logic [AWIDTH-1:0] r2,
                          input logic [AWIDTH-1:0] r3, input string name);
    we2    = w2;
    waddr2 = wa2;
    wdata2 = wd2;
    step(w, wa, wd, r1, r2, r3, name);
    we2 = 1'b0;
  endtask  // Automatic

  task automatic read_all(input string name);
    for (int r = 0; r < Depth; r++) step(1'b0, '0, '0, AWIDTH'(r), AWIDTH'(r), AWIDTH'(r), name);
  endtask  // Automatic

  task automatic test_bypass();
    step(1'b1, AWIDTH'(0), FLEN'('h3F80_0000), AWIDTH'(0), AWIDTH'(1), AWIDTH'(2),
         "f0_write_bypass");
    step(1'b0, '0, '0, AWIDTH'(0), AWIDTH'(0), AWIDTH'(0), "f0_is_a_register");

    step(1'b1, AWIDTH'(7), FLEN'('hDEAD_BEEF), AWIDTH'(7), AWIDTH'(7), AWIDTH'(7),
         "bypass_all_ports");
    step(1'b0, '0, '0, AWIDTH'(7), AWIDTH'(8), AWIDTH'(7), "held_after_write");

    step(1'b1, AWIDTH'(9), FLEN'('h4040_0000), AWIDTH'(1), AWIDTH'(9), AWIDTH'(3),
         "bypass_port2_only");
    step(1'b1, AWIDTH'(10), FLEN'('hC000_0000), AWIDTH'(1), AWIDTH'(2), AWIDTH'(10),
         "bypass_port3_only");
    step(1'b0, '0, '0, AWIDTH'(9), AWIDTH'(10), AWIDTH'(7), "three_distinct");
  endtask  // Automatic

  task automatic test_core_en();
    core_en = 1'b0;
    step(1'b1, AWIDTH'(9), FLEN'('h1234_5678), AWIDTH'(9), AWIDTH'(9), AWIDTH'(9),
         "core_en_low_bypass");
    core_en = 1'b1;
    step(1'b0, '0, '0, AWIDTH'(9), AWIDTH'(9), AWIDTH'(9), "core_en_low_blocks_write");
  endtask  // Automatic

  task automatic fill();
    for (int r = 0; r < Depth; r++)
      step(1'b1, AWIDTH'(r), FLEN'($urandom), AWIDTH'(r), AWIDTH'((r + 1) % Depth), AWIDTH'(r ^ 5),
           "fill");
  endtask  // Automatic

  task automatic random_steps(input int n);
    repeat (n)
      step(1'($urandom), AWIDTH'($urandom), FLEN'($urandom), AWIDTH'($urandom), AWIDTH'($urandom),
           AWIDTH'($urandom), "random");
  endtask  // Automatic

  task automatic test_second_port();
    step_two(1'b1, AWIDTH'(12), FLEN'('h4120_0000), 1'b1, AWIDTH'(13), FLEN'('h4130_0000),
             AWIDTH'(12), AWIDTH'(13), AWIDTH'(12), "two_writes_bypass");
    step(1'b0, '0, '0, AWIDTH'(12), AWIDTH'(13), AWIDTH'(14), "two_writes_held");

    step_two(1'b1, AWIDTH'(14), FLEN'('hAAAA_5555), 1'b1, AWIDTH'(14), FLEN'('h5555_AAAA),
             AWIDTH'(14), AWIDTH'(14), AWIDTH'(1), "port2_wins_tie");
    step(1'b0, '0, '0, AWIDTH'(14), AWIDTH'(1), AWIDTH'(2), "port2_tie_held");
  endtask  // Automatic

  task automatic random_two_port(input int n);
    repeat (n)
      step_two(1'($urandom), AWIDTH'($urandom), FLEN'($urandom), 1'($urandom), AWIDTH'($urandom),
               FLEN'($urandom), AWIDTH'($urandom), AWIDTH'($urandom), AWIDTH'($urandom),
               "random_two_port");
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
    $dumpfile("fp_regfile_tb.vcd");
    $dumpvars(0, fp_regfile_tb);
    do_reset();

    read_all("reset");
    test_bypass();
    test_core_en();
    fill();
    random_steps(2000);
    test_second_port();
    random_two_port(2000);

    do_reset();
    read_all("rereset");

    do_verdict();
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < Depth; i++) shadow[i] <= '0;
    end else if (core_en) begin
      if (we) shadow[waddr] <= wdata;
      if (we2) shadow[waddr2] <= wdata2;
    end
  end

endmodule

`default_nettype wire
