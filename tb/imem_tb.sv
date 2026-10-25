`default_nettype none

module imem_tb ();

  localparam int Xlen = arch_pkg::XLEN;
  localparam int Depth = 64;
  localparam int WordBytes = Xlen / 8;
  localparam int SoakOps = 1000;
  localparam int MinChecks = 1100;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic we;
  logic [Xlen-1:0] waddr;
  logic [Xlen-1:0] wdata;
  logic [Xlen-1:0] addr;
  logic [Xlen-1:0] instr;

  logic [Xlen-1:0] shadow[Depth];

  always #5 clk = ~clk;

  imem #(
      .XLEN (Xlen),
      .DEPTH(Depth)
  ) dut (
      .clk  (clk),
      .we   (we),
      .waddr(waddr),
      .wdata(wdata),
      .addr (addr),
      .instr(instr)
  );

  initial void'($value$plusargs("max_errors=%d", max_errors));

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    we = 1'b0;
    waddr = '0;
    wdata = '0;
    addr = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
  endtask  // Automatic

  function automatic logic [Xlen-1:0] byte_addr(input int word);
    byte_addr = Xlen'(word * WordBytes + $urandom_range(WordBytes - 1));
  endfunction

  task automatic drive_write(input logic en, input int word, input logic [Xlen-1:0] data);
    @(negedge clk);
    we = en;
    waddr = byte_addr(word);
    wdata = data;
    @(negedge clk);
    we = 1'b0;
  endtask  // Automatic

  task automatic read_word(input int word);
    @(negedge clk);
    addr = byte_addr(word);
    @(negedge clk);
    check($sformatf("read word %0d", word), instr, shadow[word]);
  endtask  // Automatic

  task automatic check_all();
    for (int i = 0; i < Depth; i++) begin
      read_word(i);
    end
  endtask  // Automatic

  task automatic fill();
    for (int i = 0; i < Depth; i++) begin
      drive_write(1'b1, i, Xlen'($urandom));
    end
  endtask  // Automatic

  task automatic blocked_writes();
    for (int i = 0; i < Depth; i++) begin
      drive_write(1'b0, i, ~shadow[i]);
    end
  endtask  // Automatic

  task automatic soak(input int n);
    repeat (n) begin
      drive_write(1'($urandom), $urandom_range(Depth - 1), Xlen'($urandom));
      read_word($urandom_range(Depth - 1));
    end
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("imem_tb.vcd");
    $dumpvars(0, imem_tb);
    do_reset();
    fill();
    check_all();
    blocked_writes();
    check_all();
    soak(SoakOps);
    check_all();
    do_verdict();
  end

  always @(posedge clk) begin
    if (we) shadow[waddr/WordBytes] <= wdata;
  end

endmodule

`default_nettype wire
