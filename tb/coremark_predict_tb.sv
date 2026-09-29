`default_nettype none

module coremark_predict_tb ();

  import cache_pkg::*;
  localparam int XLEN = arch_pkg::XLEN;
  localparam int DEPTH = 16384;
  localparam int ClkDiv = arch_pkg::ClkDiv;
  localparam int FastClkHz = arch_pkg::BoardClkHz;
  localparam int BaudRate = arch_pkg::BaudRate;
  localparam int ClksPerBit = (FastClkHz + BaudRate / 2) / BaudRate;

  logic clk = 0, rst;
  logic [15:0] sw, led;
  logic uart_rx = 1, uart_tx;
  logic [XLEN-1:0] img[DEPTH];
  logic [LineBits-1:0] pline;

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

  task automatic send_byte(input logic [7:0] b);
    uart_rx = 0;
    repeat (ClksPerBit) @(posedge clk);
    for (int i = 0; i < 8; i++) begin
      uart_rx = b[i];
      repeat (ClksPerBit) @(posedge clk);
    end
    uart_rx = 1;
    repeat (ClksPerBit) @(posedge clk);
  endtask  // Automatic

  logic v_ex, b_ex, mis, c_en;
  assign v_ex = dut.riscv_pipelined_inst.datapath_inst.valid_ex;
  assign b_ex = dut.riscv_pipelined_inst.datapath_inst.branch_ex;
  assign mis  = dut.riscv_pipelined_inst.datapath_inst.mispredict;
  assign c_en = dut.core_en;

  always @(posedge clk) begin
    if (!rst && c_en && v_ex && b_ex) begin
      branches++;
      if (mis) mispredicts++;
    end
  end

  initial begin
    rst = 1;
    for (int k = 0; k < DEPTH; k++) img[k] = '0;
    $readmemh("sw/coremark/coremark_sim.hex", img);
    if (img[0] == '0) $fatal(1, "coremark_sim.hex missing or empty, run make -C sw/coremark all");
    #1;  // After mem init
    for (int l = 0; l < DEPTH / LineWords; l++) begin
      for (int w = 0; w < LineWords; w++) pline[XLEN*w+:XLEN] = img[l*LineWords+w];
      @(negedge clk);
      dut.imem_inst.u_line.bd_idx  = l;
      dut.imem_inst.u_line.bd_data = pline;
      dut.imem_inst.u_line.bd_we   = 1'b1;
      dut.dmem_inst.u_line.bd_idx  = l;
      dut.dmem_inst.u_line.bd_data = pline;
      dut.dmem_inst.u_line.bd_we   = 1'b1;
    end
    @(negedge clk);
    dut.imem_inst.u_line.bd_we = 1'b0;
    dut.dmem_inst.u_line.bd_we = 1'b0;
    rst = 1;
    sw  = 0;
    repeat (2) @(posedge clk);
    rst = 0;
    repeat (2000) @(posedge clk);
    repeat (XLEN / 8) send_byte(8'd0);

    wait (branches >= 30_000);
    $display("PROBE branches=%0d mispredicts=%0d rate=%0d.%02d%% pc=%08x", branches, mispredicts,
             (100 * mispredicts) / branches, ((10000 * mispredicts) / branches) % 100,
             dut.riscv_pipelined_inst.pc);
    $finish;
  end

  initial begin
    repeat (60_000_000) @(posedge clk);
    $fatal(1, "TIMEOUT");
  end
endmodule

`default_nettype wire
