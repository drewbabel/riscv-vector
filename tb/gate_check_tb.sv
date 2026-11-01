`default_nettype none

module gate_check_tb ();
  import cache_pkg::*;
  localparam int Xlen = arch_pkg::XLEN;
  localparam int DEPTH = 16384, ClkDiv = 32, MaxChars = 2;
  localparam int IdxW = $clog2(DEPTH / LineWords);
  localparam int DataBits = arch_pkg::UartDataBits;
  localparam int BootCycles = 400;
  localparam int TimeoutCycles = 200_000;
  localparam int MinChecks = MaxChars;
  localparam logic [DataBits*MaxChars-1:0] Expect = {8'h44, 8'h43};

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic rst = 1'b1;
  logic [15:0] sw;
  logic [15:0] led;
  logic uart_rx = 1'b1;
  logic uart_tx;
  logic tx_valid;
  logic [DataBits-1:0] tx_data;
  logic [Xlen-1:0] img[DEPTH];
  string hexfile;
  always #5 clk = ~clk;
  board_top #(
      .XLEN  (Xlen),
      .DEPTH (DEPTH),
      .ClkDiv(ClkDiv)
  ) dut (
      .clk,
      .rst,
      .sw,
      .led,
      .uart_rx,
      .uart_tx,
      .sim_branch      (),
      .sim_branch_taken(),
      .sim_mispredict  (),
      .sim_muldiv_hold (),
      .sim_tx_valid    (tx_valid),
      .sim_tx_data     (tx_data)
  );

  task automatic read_args();
    if (!$value$plusargs("HEX=%s", hexfile)) hexfile = "build/jalret.hex";
    void'($value$plusargs("max_errors=%d", max_errors));
  endtask  // Automatic

  task automatic check(input string name, input logic [DataBits-1:0] got,
                       input logic [DataBits-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic load_image(input string path);
    logic [LineBits-1:0] pline;
    for (int k = 0; k < DEPTH; k++) img[k] = '0;
    $readmemh(path, img);
    if (img[0] == '0) $fatal(1, "%s missing or empty", path);
    for (int l = 0; l < DEPTH / LineWords; l++) begin
      for (int w = 0; w < LineWords; w++) pline[Xlen*w+:Xlen] = img[l*LineWords+w];
      @(negedge clk);
      dut.imem_inst.u_line.bd_idx  = IdxW'(l);
      dut.imem_inst.u_line.bd_data = pline;
      dut.imem_inst.u_line.bd_we   = 1'b1;
      dut.dmem_inst.u_line.bd_idx  = IdxW'(l);
      dut.dmem_inst.u_line.bd_data = pline;
      dut.dmem_inst.u_line.bd_we   = 1'b1;
    end
    @(negedge clk);
    dut.imem_inst.u_line.bd_we = 1'b0;
    dut.dmem_inst.u_line.bd_we = 1'b0;
  endtask  // Automatic

  task automatic do_reset();
    rst = 1'b1;
    sw = '0;
    uart_rx = 1'b1;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
  endtask  // Automatic

  // Preloaded image runs
  task automatic skip_boot();
    repeat (BootCycles) @(posedge clk);
    dut.bd_skip_boot = 1'b1;
  endtask  // Automatic

  task automatic expect_chars();
    for (int k = 0; k < MaxChars; k++) begin
      do @(posedge clk); while (tx_valid !== 1'b1);
      $write("%c", tx_data);
      $fflush();
      check($sformatf("char %0d", k), tx_data, Expect[DataBits*k+:DataBits]);
    end
    $display("");
  endtask  // Automatic

  task automatic watchdog();
    repeat (TimeoutCycles) @(posedge clk);
    $fatal(1, "TIMEOUT after %0d checks", checks);
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    read_args();
    load_image(hexfile);
    do_reset();
    fork
      skip_boot();
      expect_chars();
    join
    do_verdict();
  end

  initial watchdog();
endmodule

`default_nettype wire
