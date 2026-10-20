`default_nettype none

module fp_regfile_tb ();

  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int FLEN = fp_pkg::FLEN;
  localparam int Depth = 2 ** AWIDTH;
  localparam int MinChecks = 6000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic rst_n = 1'b1;
  logic core_en = 1'b1;
  logic we = 1'b0;
  logic [AWIDTH-1:0] waddr = '0;
  logic [FLEN-1:0] wdata = '0;
  logic we2 = 1'b0;
  logic [AWIDTH-1:0] waddr2 = '0;
  logic [FLEN-1:0] wdata2 = '0;
  logic [AWIDTH-1:0] raddr1 = '0;
  logic [AWIDTH-1:0] raddr2 = '0;
  logic [AWIDTH-1:0] raddr3 = '0;
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

  task automatic do_reset();
    @(negedge clk);
    rst_n = 0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
  endtask  // Automatic

  task automatic check(input string name, input logic [FLEN-1:0] got, input logic [FLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h exp %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  function automatic logic [FLEN-1:0] exp_read(input logic [AWIDTH-1:0] ra);
    if (we2 && waddr2 == ra) return wdata2;
    if (we && waddr == ra) return wdata;
    return shadow[ra];
  endfunction  // Automatic

  task automatic check_ports(input string name);
    #1;
    check({name, " port1"}, rdata1, exp_read(raddr1));
    check({name, " port2"}, rdata2, exp_read(raddr2));
    check({name, " port3"}, rdata3, exp_read(raddr3));
  endtask  // Automatic

  always @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < Depth; i++) shadow[i] <= '0;
    end else if (core_en) begin
      if (we) shadow[waddr] <= wdata;
      if (we2) shadow[waddr2] <= wdata2;
    end
  end

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
    @(negedge clk);
  endtask  // Automatic

  task automatic verdict();
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

    for (int r = 0; r < Depth; r++) step(1'b0, '0, '0, AWIDTH'(r), AWIDTH'(r), AWIDTH'(r), "reset");

    step(1'b1, 5'd0, 32'h3F80_0000, 5'd0, 5'd1, 5'd2, "f0_write_bypass");
    step(1'b0, '0, '0, 5'd0, 5'd0, 5'd0, "f0_is_a_register");

    step(1'b1, 5'd7, 32'hDEAD_BEEF, 5'd7, 5'd7, 5'd7, "bypass_all_ports");
    step(1'b0, '0, '0, 5'd7, 5'd8, 5'd7, "held_after_write");

    step(1'b1, 5'd9, 32'h4040_0000, 5'd1, 5'd9, 5'd3, "bypass_port2_only");
    step(1'b1, 5'd10, 32'hC000_0000, 5'd1, 5'd2, 5'd10, "bypass_port3_only");
    step(1'b0, '0, '0, 5'd9, 5'd10, 5'd7, "three_distinct");

    core_en = 1'b0;
    @(negedge clk);
    we = 1'b1;
    waddr = 5'd9;
    wdata = 32'h1234_5678;
    @(negedge clk);
    we = 1'b0;
    core_en = 1'b1;
    step(1'b0, '0, '0, 5'd9, 5'd9, 5'd9, "core_en_low_blocks_write");

    for (int r = 0; r < Depth; r++)
    step(1'b1, AWIDTH'(r), $urandom, AWIDTH'(r), AWIDTH'((r + 1) % Depth), AWIDTH'(r ^ 5), "fill");

    for (int i = 0; i < 2000; i++)
    step(1'($urandom_range(0, 1)), AWIDTH'($urandom), $urandom, AWIDTH'($urandom),
         AWIDTH'($urandom), AWIDTH'($urandom), "random");

    // Second write port
    we2    = 1'b1;
    waddr2 = 5'd12;
    wdata2 = 32'h4120_0000;
    step(1'b1, 5'd13, 32'h4130_0000, 5'd12, 5'd13, 5'd12, "two_writes_bypass");
    we2 = 1'b0;
    step(1'b0, '0, '0, 5'd12, 5'd13, 5'd14, "two_writes_held");

    we2    = 1'b1;
    waddr2 = 5'd14;
    wdata2 = 32'hAAAA_5555;
    step(1'b1, 5'd14, 32'h5555_AAAA, 5'd14, 5'd14, 5'd1, "port2_wins_tie");
    we2 = 1'b0;
    step(1'b0, '0, '0, 5'd14, 5'd1, 5'd2, "port2_tie_held");

    for (int i = 0; i < 2000; i++) begin
      we2    = 1'($urandom_range(0, 1));
      waddr2 = AWIDTH'($urandom);
      wdata2 = $urandom;
      step(1'($urandom_range(0, 1)), AWIDTH'($urandom), $urandom, AWIDTH'($urandom),
           AWIDTH'($urandom), AWIDTH'($urandom), "random_two_port");
    end
    we2 = 1'b0;

    do_reset();
    for (int r = 0; r < Depth; r++)
    step(1'b0, '0, '0, AWIDTH'(r), AWIDTH'(r), AWIDTH'(r), "rereset");

    verdict();
  end

endmodule

`default_nettype wire
