`default_nettype none

module coremark_predict_tb ();

  import cache_pkg::*;

  localparam int XLEN = arch_pkg::XLEN;
  localparam int DEPTH = 16384;
  localparam int IdxW = $clog2(DEPTH / LineWords);
  localparam int ClkDiv = arch_pkg::ClkDiv;
  localparam int FastClkHz = arch_pkg::BoardClkHz;
  localparam int BaudRate = arch_pkg::BaudRate;
  localparam int ClksPerBit = (FastClkHz + BaudRate / 2) / BaudRate;
  localparam int BootCycles = 2000;
  localparam int ProbeBranches = 30_000;
  localparam int TimeoutCycles = 60_000_000;

  logic clk = 1'b0;
  logic rst = 1'b1;
  logic [15:0] sw;
  logic [15:0] led;
  logic uart_rx = 1'b1;
  logic uart_tx;
  logic [XLEN-1:0] img[DEPTH];

  int branches = 0;
  int mispredicts = 0;

  always #5 clk = ~clk;

  board_top #(
      .DEPTH (DEPTH),
      .ClkDiv(ClkDiv)
  ) dut (
      .clk    (clk),
      .rst    (rst),
      .sw     (sw),
      .led    (led),
      .uart_rx(uart_rx),
      .uart_tx(uart_tx)
  );

  logic v_ex, b_ex, mis, c_en;
  assign v_ex = dut.riscv_pipelined_inst.datapath_inst.valid_ex;
  assign b_ex = dut.riscv_pipelined_inst.datapath_inst.branch_ex;
  assign mis  = dut.riscv_pipelined_inst.datapath_inst.mispredict;
  assign c_en = dut.core_en;

  task automatic load_image(input string path);
    logic [LineBits-1:0] pline;
    for (int k = 0; k < DEPTH; k++) img[k] = '0;
    $readmemh(path, img);
    if (img[0] == '0) $fatal(1, "%s missing or empty, run make -C sw/coremark all", path);
    for (int l = 0; l < DEPTH / LineWords; l++) begin
      for (int w = 0; w < LineWords; w++) pline[XLEN*w+:XLEN] = img[l*LineWords+w];
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

  task automatic send_byte(input logic [7:0] b);
    @(negedge clk);
    uart_rx = 1'b0;
    repeat (ClksPerBit) @(negedge clk);
    for (int i = 0; i < $bits(b); i++) begin
      uart_rx = b[i];
      repeat (ClksPerBit) @(negedge clk);
    end
    uart_rx = 1'b1;
    repeat (ClksPerBit) @(negedge clk);
  endtask  // Automatic

  // Zero length boot
  task automatic start_core();
    repeat (BootCycles) @(posedge clk);
    repeat (XLEN / 8) send_byte('0);
  endtask  // Automatic

  task automatic probe(input int n);
    wait (branches >= n);
    $display("PROBE branches=%0d mispredicts=%0d rate=%0d.%02d%% pc=%08x", branches, mispredicts,
             (100 * mispredicts) / branches, ((10000 * mispredicts) / branches) % 100,
             dut.riscv_pipelined_inst.pc);
    $finish;
  endtask  // Automatic

  task automatic watchdog();
    repeat (TimeoutCycles) @(posedge clk);
    $fatal(1, "TIMEOUT");
  endtask  // Automatic

  initial begin
    load_image("sw/coremark/coremark_sim.hex");
    do_reset();
    start_core();
    probe(ProbeBranches);
  end

  initial watchdog();

  always @(posedge clk) begin
    if (!rst && c_en && v_ex && b_ex) begin
      branches++;
      if (mis) mispredicts++;
    end
  end

endmodule

`default_nettype wire
