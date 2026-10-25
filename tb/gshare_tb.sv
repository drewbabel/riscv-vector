`default_nettype none

module gshare_tb;

  import bp_pkg::*;

  localparam int MinChecks = 2400;
  localparam int Xlen = arch_pkg::XLEN;
  localparam int PcLsb = 2;
  localparam int CtrW = 2;
  localparam logic [CtrW-1:0] WeakNotTaken = CtrW'(1);
  localparam int Saturate = 6;
  localparam logic [GhistLen-1:0] Entry = GhistLen'(5);

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic core_en;
  logic rst_n = 1'b1;
  logic [Xlen-1:0] predict_pc;
  logic predict_taken;
  logic [GhistLen-1:0] predict_index;
  logic update_valid;
  logic update_taken;
  logic [GhistLen-1:0] update_index;

  // Reference model
  logic [GhistLen-1:0] ref_ghr;
  logic [CtrW-1:0] ref_pht[PhtDepth];

  always #5 clk = ~clk;

  gshare #(
      .XLEN(Xlen)
  ) dut (
      .clk          (clk),
      .core_en      (core_en),
      .rst_n        (rst_n),
      .predict_pc   (predict_pc),
      .predict_taken(predict_taken),
      .predict_index(predict_index),
      .update_valid (update_valid),
      .update_taken (update_taken),
      .update_index (update_index)
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
    @(negedge clk);
    rst_n        = 1'b0;
    core_en      = 1'b1;
    predict_pc   = '0;
    update_valid = 1'b0;
    update_taken = 1'b0;
    update_index = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic lookup(input logic [Xlen-1:0] pc);
    logic [GhistLen-1:0] exp_index;
    exp_index  = pc[PcLsb+:GhistLen] ^ ref_ghr;
    predict_pc = pc;
    @(posedge clk);
    check($sformatf("index pc %h", pc), Xlen'(predict_index), Xlen'(exp_index));
    check($sformatf("taken pc %h", pc), Xlen'(predict_taken), Xlen'(ref_pht[exp_index][CtrW-1]));
    @(negedge clk);
  endtask  // Automatic

  task automatic check_entry(input logic [GhistLen-1:0] idx);
    lookup(Xlen'(idx ^ ref_ghr) << PcLsb);
  endtask  // Automatic

  task automatic step(input logic uv, input logic ut, input logic [GhistLen-1:0] ui);
    update_valid = uv;
    update_taken = ut;
    update_index = ui;
    @(negedge clk);
    update_valid = 1'b0;
    lookup('0);
    check_entry(ui);
  endtask  // Automatic

  task automatic step_stalled(input logic ut, input logic [GhistLen-1:0] ui);
    core_en = 1'b0;
    step(1'b1, ut, ui);
    core_en = 1'b1;
  endtask  // Automatic

  task automatic test_cold();
    lookup('0);
    check("cold not taken", Xlen'(predict_taken), '0);
  endtask  // Automatic

  task automatic test_saturate();
    repeat (Saturate) step(1'b1, 1'b1, Entry);
    repeat (Saturate) step(1'b1, 1'b0, Entry);
    step(1'b0, 1'b1, Entry);
    step_stalled(1'b1, Entry);
    step(1'b1, 1'b1, Entry);
    step(1'b1, 1'b1, Entry);
  endtask  // Automatic

  task automatic random_sweep(input int n);
    repeat (n) begin
      step(1'($urandom), 1'($urandom), GhistLen'($urandom));
      lookup(Xlen'($urandom));
    end
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
    $dumpfile("gshare_tb.vcd");
    $dumpvars(0, gshare_tb);
    do_reset();

    test_cold();
    test_saturate();
    random_sweep(400);

    do_verdict();
  end

  initial for (int i = 0; i < PhtDepth; i++) ref_pht[i] = WeakNotTaken;

  always @(posedge clk) begin
    if (!rst_n) begin
      ref_ghr <= '0;
    end else if (core_en && update_valid) begin
      if (update_taken && ref_pht[update_index] != '1)
        ref_pht[update_index] <= ref_pht[update_index] + 1'b1;
      if (!update_taken && ref_pht[update_index] != '0)
        ref_pht[update_index] <= ref_pht[update_index] - 1'b1;
      ref_ghr <= {ref_ghr[GhistLen-2:0], update_taken};
    end
  end

endmodule

`default_nettype wire
