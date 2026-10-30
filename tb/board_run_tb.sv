`default_nettype none

module board_run_tb ();

  import cache_pkg::*;

  localparam int DEPTH = 16777216;
  localparam int BaudRate = arch_pkg::BaudRate;
  localparam int ClksPerBit = (arch_pkg::BoardClkHz + BaudRate / 2) / BaudRate;

  logic clk = 0;
  logic rst;
  logic [7:0] sw;
  logic [7:0] led;
  logic uart_rx = 1;
  logic uart_tx;
  wire [15:0] ddr3_dq;
  wire [1:0] ddr3_dqs_p;
  wire [1:0] ddr3_dqs_n;
  logic [31:0] img[DEPTH];
  logic [LineBits-1:0] pline;
  string hexfile;
  longint limit;

  always #5 clk = ~clk;

  board_top #(
      .DEPTH(DEPTH)
  ) dut (
      .clk         (clk),
      .rst         (rst),
      .sw          (sw),
      .led         (led),
      .uart_rx     (uart_rx),
      .uart_tx     (uart_tx),
      .ddr3_addr   (),
      .ddr3_ba     (),
      .ddr3_ras_n  (),
      .ddr3_cas_n  (),
      .ddr3_we_n   (),
      .ddr3_reset_n(),
      .ddr3_ck_p   (),
      .ddr3_ck_n   (),
      .ddr3_cke    (),
      .ddr3_odt    (),
      .ddr3_dm     (),
      .ddr3_dq     (ddr3_dq),
      .ddr3_dqs_p  (ddr3_dqs_p),
      .ddr3_dqs_n  (ddr3_dqs_n)
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
  endtask

  // Console monitor
  logic [23:0] tail = '0;
  logic done = 0;
  initial begin
    logic [7:0] ch;
    forever begin
      @(negedge uart_tx);
      repeat (ClksPerBit + ClksPerBit / 2) @(posedge clk);
      for (int i = 0; i < 8; i++) begin
        ch[i] = uart_tx;
        repeat (ClksPerBit) @(posedge clk);
      end
      $write("%c", ch);
      $fflush();
      tail = {tail[15:0], ch};
      if (tail == "END") done = 1;
    end
  end

  initial begin
    rst = 1;
    if (!$value$plusargs("HEX=%s", hexfile)) $fatal(1, "no +HEX");
    for (int k = 0; k < DEPTH; k++) img[k] = 32'h0;
    $readmemh(hexfile, img);
    if (img[0] == 32'h0) $fatal(1, "%s missing or empty", hexfile);
    for (int l = 0; l < DEPTH / LineWords; l++) begin
      for (int w = 0; w < LineWords; w++) pline[32*w+:32] = img[l*LineWords+w];
      if (pline != '0) dut.mig_inst.mem[l] = pline;
    end
    sw = 0;
    repeat (2) @(posedge clk);
    rst = 0;
    repeat (2000) @(posedge clk);
    // Zero count starts core
    repeat (4) send_byte(8'd0);
    wait (done);
    repeat (200) @(posedge clk);
    $finish;
  end

  // +LIMIT counts core cycles
  initial begin
    if (!$value$plusargs("LIMIT=%d", limit)) limit = 64'd20_000_000;
    for (longint m = 0; m < limit; m++) @(posedge dut.core_en);
    $fatal(1, "TIMEOUT");
  end

endmodule

`default_nettype wire
