`default_nettype none

module btb_tb;

  import bp_pkg::*;

  localparam int MinChecks = 580;
  localparam int Xlen = arch_pkg::XLEN;
  localparam int PcLsb = 2;
  localparam int TagLen = Xlen - PcLsb - BtbIdxLen;
  localparam int TagSpan = 4;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic core_en;
  logic rst_n = 1'b1;
  logic [Xlen-1:0] lookup_pc;
  logic hit;
  logic [Xlen-1:0] target;
  logic is_cond;
  logic update_valid;
  logic [Xlen-1:0] update_pc;
  logic [Xlen-1:0] update_target;
  logic update_is_cond;

  // Reference model
  logic ref_valid[BtbDepth];
  logic [TagLen-1:0] ref_tag[BtbDepth];
  logic [Xlen-1:0] ref_targ[BtbDepth];
  logic ref_cond[BtbDepth];

  always #5 clk = ~clk;

  btb #(
      .XLEN(Xlen)
  ) dut (
      .clk           (clk),
      .core_en       (core_en),
      .rst_n         (rst_n),
      .lookup_pc     (lookup_pc),
      .hit           (hit),
      .target        (target),
      .is_cond       (is_cond),
      .update_valid  (update_valid),
      .update_pc     (update_pc),
      .update_target (update_target),
      .update_is_cond(update_is_cond)
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
    rst_n          = 1'b0;
    core_en        = 1'b1;
    lookup_pc      = '0;
    update_valid   = 1'b0;
    update_pc      = '0;
    update_target  = '0;
    update_is_cond = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic install(input logic [Xlen-1:0] pc, input logic [Xlen-1:0] tgt, input logic c);
    update_valid   = 1'b1;
    update_pc      = pc;
    update_target  = tgt;
    update_is_cond = c;
    @(negedge clk);
    update_valid = 1'b0;
  endtask  // Automatic

  task automatic install_stalled(input logic [Xlen-1:0] pc, input logic [Xlen-1:0] tgt,
                                 input logic c);
    core_en = 1'b0;
    install(pc, tgt, c);
    core_en = 1'b1;
  endtask  // Automatic

  task automatic probe(input logic [Xlen-1:0] pc);
    logic [BtbIdxLen-1:0] idx;
    logic exp_hit;
    idx = pc[PcLsb+:BtbIdxLen];
    lookup_pc = pc;
    @(posedge clk);
    exp_hit = ref_valid[idx] && (ref_tag[idx] == pc[BtbIdxLen+PcLsb+:TagLen]);
    check($sformatf("hit %h", pc), Xlen'(hit), Xlen'(exp_hit));
    if (exp_hit) begin
      check($sformatf("target %h", pc), target, ref_targ[idx]);
      check($sformatf("is_cond %h", pc), Xlen'(is_cond), Xlen'(ref_cond[idx]));
    end
    @(negedge clk);
  endtask  // Automatic

  task automatic test_directed();
    probe(pc_of(0, 16));
    install(pc_of(0, 16), Xlen'('h1234), 1'b1);
    probe(pc_of(0, 16));
    probe(pc_of(4, 16));
    install(pc_of(4, 16), Xlen'('h5678), 1'b0);
    probe(pc_of(4, 16));
    probe(pc_of(0, 16));
    install(pc_of(0, 32), Xlen'('h9ABC), 1'b1);
    probe(pc_of(0, 32));
    probe(pc_of(4, 16));
  endtask  // Automatic

  task automatic test_reset_clears();
    do_reset();
    probe(pc_of(4, 16));
    probe(pc_of(0, 32));
  endtask  // Automatic

  task automatic test_core_stall();
    install(pc_of(1, 8), Xlen'('h1111), 1'b0);
    install_stalled(pc_of(2, 8), Xlen'('h2222), 1'b1);
    probe(pc_of(1, 8));
    probe(pc_of(2, 8));
  endtask  // Automatic

  task automatic random_sweep(input int n);
    repeat (n) begin
      install(rand_pc(), Xlen'($urandom), 1'($urandom));
      probe(rand_pc());
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
    $dumpfile("btb_tb.vcd");
    $dumpvars(0, btb_tb);
    do_reset();

    test_directed();
    test_reset_clears();
    test_core_stall();
    random_sweep(400);

    do_verdict();
  end

  function automatic logic [Xlen-1:0] pc_of(input int tag, input int idx);
    return {TagLen'(tag), BtbIdxLen'(idx), PcLsb'(0)};
  endfunction

  function automatic logic [Xlen-1:0] rand_pc();
    return pc_of($urandom_range(TagSpan - 1), $urandom_range(BtbDepth - 1));
  endfunction

  always @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < BtbDepth; i++) ref_valid[i] <= 1'b0;
    end else if (core_en && update_valid) begin
      ref_valid[update_pc[PcLsb+:BtbIdxLen]] <= 1'b1;
      ref_tag[update_pc[PcLsb+:BtbIdxLen]]   <= update_pc[BtbIdxLen+PcLsb+:TagLen];
      ref_targ[update_pc[PcLsb+:BtbIdxLen]]  <= update_target;
      ref_cond[update_pc[PcLsb+:BtbIdxLen]]  <= update_is_cond;
    end
  end

endmodule

`default_nettype wire
