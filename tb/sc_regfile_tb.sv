`default_nettype none

module sc_regfile_tb ();

  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int XLEN = arch_pkg::XLEN;
  localparam int Depth = 2 ** AWIDTH;
  localparam int RandSteps = 4000;
  localparam int MinChecks = 8000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic rst_n = 1'b1;
  logic core_en;
  logic we;
  logic [AWIDTH-1:0] waddr;
  logic [XLEN-1:0] wdata;
  logic [AWIDTH-1:0] raddr1;
  logic [AWIDTH-1:0] raddr2;
  logic [XLEN-1:0] rdata1;
  logic [XLEN-1:0] rdata2;

  logic [XLEN-1:0] shadow[Depth];

  always #5 clk = ~clk;

  sc_regfile #(
      .AWIDTH(AWIDTH),
      .XLEN  (XLEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
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

  task automatic do_reset();
    @(negedge clk);
    rst_n = 1'b0;
    core_en = 1'b1;
    we = 1'b0;
    waddr = '0;
    wdata = '0;
    raddr1 = '0;
    raddr2 = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  function automatic logic [XLEN-1:0] rand_word();
    logic [XLEN-1:0] w;
    w = '0;
    for (int i = 0; i < XLEN; i += 32) w = (w << 32) | XLEN'($urandom);
    return w;
  endfunction

  task automatic step(input logic w, input logic [AWIDTH-1:0] wa, input logic [XLEN-1:0] wd,
                      input logic [AWIDTH-1:0] r1, input logic [AWIDTH-1:0] r2, input string name);
    we     = w;
    waddr  = wa;
    wdata  = wd;
    raddr1 = r1;
    raddr2 = r2;
    @(posedge clk);
    check({name, " port1"}, rdata1, shadow[r1]);
    check({name, " port2"}, rdata2, shadow[r2]);
    @(negedge clk);
  endtask  // Automatic

  task automatic read_all(input string name);
    for (int r = 0; r < Depth; r++) step(1'b0, '0, '0, AWIDTH'(r), AWIDTH'(Depth - 1 - r), name);
  endtask  // Automatic

  task automatic test_zero_register();
    step(1'b1, AWIDTH'(0), '1, AWIDTH'(0), AWIDTH'(0), "x0_write_same_cycle");
    step(1'b0, '0, '0, AWIDTH'(0), AWIDTH'(0), "x0_stays_zero");
  endtask  // Automatic

  task automatic test_no_bypass();
    logic [XLEN-1:0] v;
    v = rand_word();
    step(1'b1, AWIDTH'(Depth - 1), v, AWIDTH'(Depth - 1), AWIDTH'(1), "write_reads_old");
    step(1'b0, '0, '0, AWIDTH'(1), AWIDTH'(Depth - 1), "write_lands_next");
  endtask  // Automatic

  task automatic test_core_en();
    core_en = 1'b0;
    step(1'b1, AWIDTH'(1), rand_word(), AWIDTH'(1), AWIDTH'(1), "core_en_low_write");
    core_en = 1'b1;
    step(1'b0, '0, '0, AWIDTH'(1), AWIDTH'(1), "core_en_low_blocks_write");
  endtask  // Automatic

  task automatic fill();
    for (int r = 0; r < Depth; r++)
      step(1'b1, AWIDTH'(r), rand_word(), AWIDTH'(r), AWIDTH'((r + 1) % Depth), "fill");
  endtask  // Automatic

  task automatic random_steps(input int n);
    repeat (n) begin
      core_en = ($urandom_range(7) != 0);
      step(1'($urandom), AWIDTH'($urandom), rand_word(), AWIDTH'($urandom), AWIDTH'($urandom),
           "random");
    end
    core_en = 1'b1;
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
    $dumpfile("sc_regfile_tb.vcd");
    $dumpvars(0, sc_regfile_tb);
    do_reset();

    read_all("reset");
    test_zero_register();
    test_no_bypass();
    test_core_en();
    fill();
    read_all("filled");
    random_steps(RandSteps);

    do_reset();
    read_all("rereset");

    do_verdict();
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < Depth; i++) shadow[i] <= '0;
    end else if (core_en && we && (waddr != '0)) begin
      shadow[waddr] <= wdata;
    end
  end

endmodule

`default_nettype wire
