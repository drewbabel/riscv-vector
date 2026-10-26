`default_nettype none

module prog_tb ();

  localparam int Xlen = arch_pkg::XLEN;
  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int MaxCycles = 45;
  localparam int MinChecks = 11;
  localparam int MinHexChecks = 1;
  localparam int HexCycles = 100_000;
  localparam logic [Xlen-1:0] Nop = Xlen'(opcode_pkg::OpcodeOpImm);

  int               checks = 0;
  int               errors = 0;
  int               max_errors = 0;

  logic             clk = 1'b0;
  logic             rst_n;
  logic  [Xlen-1:0] pc;
  logic  [Xlen-1:0] alu_result;
  logic  [Xlen-1:0] write_data;
  logic             mem_write;

  string            hex;
  logic             hex_given = 1'b0;

  always #5 clk = ~clk;

  top #(
      .XLEN(Xlen)
  ) dut (
      .clk       (clk),
      .rst_n     (rst_n),
      .pc        (pc),
      .alu_result(alu_result),
      .write_data(write_data),
      .mem_write (mem_write)
  );

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    rst_n = 0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
  endtask  // Automatic

  task automatic load_image(input string path);
    for (int i = 0; i < $size(dut.imem_inst.mem); i++) dut.imem_inst.mem[i] = Nop;
    $readmemh(path, dut.imem_inst.mem);
  endtask  // Automatic

  task automatic run(input int cycles);
    repeat (cycles) @(posedge clk);
    @(negedge clk);
  endtask  // Automatic

  task automatic check_reg(input logic [AWIDTH-1:0] r, input logic [Xlen-1:0] exp);
    check($sformatf("x%0d", r), dut.riscv_pipelined_inst.datapath_inst.regfile_inst.regfile_mem[r],
          exp);
  endtask  // Automatic

  task automatic run_to_sentinel(input int cycles);
    int n = 0;
    while (dut.riscv_pipelined_inst.datapath_inst.regfile_inst.regfile_mem[28] !== Xlen'(1) &&
           n < cycles) begin
      @(posedge clk);
      n++;
    end
    @(negedge clk);
  endtask  // Automatic

  task automatic check_immediates();
    check_reg(AWIDTH'(1), Xlen'(5));
    check_reg(AWIDTH'(2), Xlen'(3));
    check_reg(AWIDTH'(11), Xlen'(15));
    check_reg(AWIDTH'(12), Xlen'(1));
  endtask  // Automatic

  task automatic check_alu();
    check_reg(AWIDTH'(3), Xlen'(8));
    check_reg(AWIDTH'(4), Xlen'(2));
    check_reg(AWIDTH'(6), Xlen'(6));
    check_reg(AWIDTH'(7), Xlen'(7));
    check_reg(AWIDTH'(8), Xlen'(5));
    check_reg(AWIDTH'(9), Xlen'(10));
  endtask  // Automatic

  task automatic check_load();
    check_reg(AWIDTH'(5), Xlen'(8));
  endtask  // Automatic

  task automatic run_nodep();
    load_image("tests/pl_nodep.hex");
    do_reset();
    run(MaxCycles);
    check_immediates();
    check_alu();
    check_load();
  endtask  // Automatic

  // PASS sets x28
  task automatic run_hex(input string path);
    load_image(path);
    do_reset();
    run_to_sentinel(HexCycles);
    check_reg(AWIDTH'(28), Xlen'(1));
  endtask  // Automatic

  task automatic run_program();
    hex_given = $value$plusargs("HEX=%s", hex);
    if (hex_given) run_hex(hex);
    else run_nodep();
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < (hex_given ? MinHexChecks : MinChecks))
      $fatal(
          1,
          "TB UNDER-RAN: %0d checks, expected at least %0d",
          checks,
          hex_given ? MinHexChecks : MinChecks
      );
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    run_program();
    do_verdict();
  end

endmodule

`default_nettype wire
