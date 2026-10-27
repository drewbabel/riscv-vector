`default_nettype none

module board_run_tb ();

  import cache_pkg::*;

  localparam int Xlen = arch_pkg::XLEN;
  localparam int ClkDiv = arch_pkg::ClkDiv;
  localparam int BaudRate = arch_pkg::BaudRate;
  localparam int ClksPerBit = (arch_pkg::BoardClkHz + BaudRate / 2) / BaudRate;
  localparam int BootCycles = 2000;
  localparam int DrainCycles = 200;
  localparam longint DefaultLimit = 20_000_000;
  localparam int MinChecks = 8;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic rst;
  logic [7:0] sw;
  logic [7:0] led;
  logic uart_rx;
  logic uart_tx;
  wire [15:0] ddr3_dq;
  wire [1:0] ddr3_dqs_p;
  wire [1:0] ddr3_dqs_n;
  string hexfile;
  string pass_token = "";
  string line = "";
  logic saw_token = 1'b0;
  logic done = 1'b0;
  longint limit;

  always #5 clk = ~clk;

  board_top #(
      .ClkDiv(ClkDiv)
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

  task automatic check(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic read_args();
    if (!$value$plusargs("HEX=%s", hexfile)) $fatal(1, "no +HEX");
    void'($value$plusargs("PASS=%s", pass_token));
    void'($value$plusargs("max_errors=%d", max_errors));
  endtask  // Automatic

  task automatic load_image();
    int fd;
    int n = 0;
    logic [Xlen-1:0] word;
    logic [Xlen-1:0] first = '0;
    logic [LineBits-1:0] pline = '0;
    fd = $fopen(hexfile, "r");
    if (fd == 0) $fatal(1, "%s missing or empty", hexfile);
    while ($fscanf(
        fd, "%h", word
    ) == 1) begin
      if (n == 0) first = word;
      pline[Xlen*(n%LineWords)+:Xlen] = word;
      n++;
      if (n % LineWords == 0) begin
        dut.mig_inst.mem[n/LineWords-1] = pline;
        pline = '0;
      end
    end
    if (n % LineWords != 0) dut.mig_inst.mem[n/LineWords] = pline;
    $fclose(fd);
    if (first == '0) $fatal(1, "%s missing or empty", hexfile);
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
    repeat (Xlen / 8) send_byte('0);
  endtask  // Automatic

  task automatic recv_byte(output logic [7:0] ch);
    @(negedge uart_tx);
    repeat (ClksPerBit / 2) @(negedge clk);
    check("start bit", uart_tx, 1'b0);
    for (int i = 0; i < $bits(ch); i++) begin
      repeat (ClksPerBit) @(negedge clk);
      ch[i] = uart_tx;
    end
    repeat (ClksPerBit) @(negedge clk);
    check("stop bit", uart_tx, 1'b1);
  endtask  // Automatic

  // Console monitor
  task automatic console();
    logic [7:0] ch;
    forever begin
      recv_byte(ch);
      $write("%c", ch);
      $fflush();
      if (ch == "\n") begin
        if (line == pass_token) saw_token = 1'b1;
        if (line == "END") done = 1'b1;
        line = "";
      end else line = {line, string'(ch)};
    end
  endtask  // Automatic

  task automatic wait_end();
    wait (done);
    repeat (DrainCycles) @(posedge clk);
  endtask  // Automatic

  // Core cycle limit
  task automatic watchdog();
    if (!$value$plusargs("LIMIT=%d", limit)) limit = DefaultLimit;
    for (longint m = 0; m < limit; m++) repeat (ClkDiv) @(posedge clk);
    $fatal(1, "TIMEOUT");
  endtask  // Automatic

  task automatic do_verdict();
    if (pass_token != "") check("PASS token", saw_token, 1'b1);
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    read_args();
    load_image();
    do_reset();
    start_core();
    wait_end();
    do_verdict();
  end

  initial console();

  initial watchdog();

endmodule

`default_nettype wire
