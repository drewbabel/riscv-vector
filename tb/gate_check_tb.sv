`default_nettype none

module gate_check_tb ();
  import cache_pkg::*;
  localparam int Xlen = arch_pkg::XLEN;
  localparam int DEPTH = 16384, ClkDiv = 32, MaxChars = 2;
  localparam int IdxW = $clog2(DEPTH / LineWords);
  localparam int BootCycles = 400;
  localparam int RunCycles = 200_000;
  logic clk = 1'b0;
  logic rst = 1'b1;
  logic [15:0] sw;
  logic [15:0] led;
  logic uart_rx = 1'b1;
  logic uart_tx;
  logic [Xlen-1:0] img[DEPTH];
  string hexfile;
  int nchars = 0;
  logic boot_skip = 1'b0;
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
      .uart_tx
  );

  task automatic read_args();
    if (!$value$plusargs("HEX=%s", hexfile)) hexfile = "build/jalret.hex";
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

  task automatic monitor();
    forever begin
      @(posedge clk);
      if (dut.tx_valid) begin
        $write("%c", dut.store_data[7:0]);
        $fflush();
        nchars++;
        if (nchars >= MaxChars) $finish;
      end
    end
  endtask  // Automatic

  task automatic skip_boot(input int cycles);
    boot_skip = 1'b1;
    repeat (cycles) @(posedge clk);
  endtask  // Automatic

  task automatic run(input int cycles);
    repeat (cycles) @(posedge clk);
    $finish;
  endtask  // Automatic

  initial begin
    read_args();
    load_image(hexfile);
    do_reset();
    skip_boot(BootCycles);
    run(RunCycles);
  end

  initial monitor();

  always @(posedge boot_skip) force dut.loading = 1'b0;
endmodule

`default_nettype wire
