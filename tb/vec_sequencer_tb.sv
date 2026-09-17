`default_nettype none

module vec_sequencer_tb ();

  localparam int AWIDTH = 5;
  localparam int VLEN = 128;
  localparam int MaxElems = VLEN / 8;

  int                  checks = 0;
  int                  errors = 0;

  logic                clk = 1'b0;
  logic                rst_n;
  logic                start;
  logic [         4:0] vs1;
  logic [         4:0] vs2;
  logic [         4:0] vd;
  logic                reads_vd;
  logic [         7:0] vl;
  logic [         2:0] vsew;
  logic [         2:0] vlmul;
  logic                vm;
  logic [MaxElems-1:0] mask_bits;
  logic [         1:0] pass_log2;
  logic [  AWIDTH-1:0] raddr1;
  logic [  AWIDTH-1:0] raddr2;
  logic [  AWIDTH-1:0] raddr3;
  logic [  AWIDTH-1:0] waddr;
  logic [    VLEN-1:0] wstrb;
  logic                wen;
  logic [         7:0] elem_base;
  logic                busy;
  logic                done;

  always #5 clk = ~clk;

  vec_sequencer #(
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) dut (
      .clk      (clk),
      .rst_n    (rst_n),
      .start    (start),
      .vs1      (vs1),
      .vs2      (vs2),
      .vd       (vd),
      .reads_vd (reads_vd),
      .vl       (vl),
      .vsew     (vsew),
      .vlmul    (vlmul),
      .vm       (vm),
      .mask_bits(mask_bits),
      .pass_log2(pass_log2),
      .raddr1   (raddr1),
      .raddr2   (raddr2),
      .raddr3   (raddr3),
      .waddr    (waddr),
      .wstrb    (wstrb),
      .wen      (wen),
      .elem_base(elem_base),
      .busy     (busy),
      .done     (done)
  );

  // Reference model
  function automatic int ref_regs(input logic [2:0] lmul);
    if (lmul[2]) return 1;
    return 1 << lmul[1:0];
  endfunction

  function automatic int ref_bits(input logic [2:0] sew);
    return 8 << sew;
  endfunction

  function automatic int ref_elems_reg(input logic [2:0] sew);
    return VLEN / (8 << sew);
  endfunction

  function automatic logic [VLEN-1:0] ref_strb(
      input int r, input int p, input logic [2:0] sew, input logic [7:0] len, input logic use_all,
      input logic [MaxElems-1:0] msk, input logic [1:0] plog);
    logic [VLEN-1:0] out;
    int bits, epr, epp, pos, gidx;
    out  = '0;
    bits = ref_bits(sew);
    epr  = ref_elems_reg(sew);
    epp  = epr >> plog;
    for (int e = 0; e < epp; e++) begin
      pos  = p * epp + e;
      gidx = r * epr + pos;
      if ((gidx < int'(len)) && (use_all || msk[e])) begin
        for (int b = 0; b < bits; b++) out[pos*bits+b] = 1'b1;
      end
    end
    return out;
  endfunction

  task automatic init_signals();
    rst_n     = 1'b0;
    start     = 1'b0;
    vs1       = 5'd0;
    vs2       = 5'd0;
    vd        = 5'd0;
    reads_vd  = 1'b0;
    vl        = 8'd0;
    vsew      = 3'd0;
    vlmul     = 3'd0;
    vm        = 1'b1;
    mask_bits = '1;
    pass_log2 = 2'd0;
  endtask

  task automatic do_reset();
    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  // Checks
  task automatic fail(input string what);
    errors++;
    $display("FAIL %s at %0t", what, $time);
  endtask

  task automatic check_tick(input int r, input int p, input logic [4:0] a1, input logic [4:0] a2,
                            input logic [4:0] dst, input logic rd_vd, input logic [2:0] sew,
                            input logic [7:0] len, input logic use_all,
                            input logic [MaxElems-1:0] msk, input logic [1:0] plog);
    logic [VLEN-1:0] exp_strb;
    int epr, epp;
    epr      = ref_elems_reg(sew);
    epp      = epr >> plog;
    exp_strb = ref_strb(r, p, sew, len, use_all, msk, plog);
    checks++;
    if (raddr1 !== a1 + 5'(r)) fail("raddr1");
    else if (raddr2 !== a2 + 5'(r)) fail("raddr2");
    else if (raddr3 !== (rd_vd ? dst + 5'(r) : 5'd0)) fail("raddr3");
    else if (waddr !== dst + 5'(r)) fail("waddr");
    else if (wstrb !== exp_strb) fail("wstrb");
    else if (elem_base !== 8'(r * epr + p * epp)) fail("elem_base");
    else if (wen !== (exp_strb != '0)) fail("wen");
  endtask

  task automatic run_case(input logic [4:0] a1, input logic [4:0] a2, input logic [4:0] dst,
                          input logic rd_vd, input logic [7:0] len, input logic [2:0] sew,
                          input logic [2:0] lmul, input logic use_all,
                          input logic [MaxElems-1:0] msk, input logic [1:0] plog);
    int regs, passes;
    regs      = ref_regs(lmul);
    passes    = 1 << plog;

    vs1       = a1;
    vs2       = a2;
    vd        = dst;
    reads_vd  = rd_vd;
    vl        = len;
    vsew      = sew;
    vlmul     = lmul;
    vm        = use_all;
    mask_bits = msk;
    pass_log2 = plog;

    start     = 1'b1;
    @(posedge clk);
    @(negedge clk);
    start = 1'b0;

    if (len == 8'd0) begin
      checks++;
      if (busy !== 1'b0) fail("busy at zero length");
      checks++;
      if (done !== 1'b1) fail("done at zero length");
      @(negedge clk);
      return;
    end

    for (int r = 0; r < regs; r++) begin
      for (int p = 0; p < passes; p++) begin
        checks++;
        if (busy !== 1'b1) fail("busy during walk");
        check_tick(r, p, a1, a2, dst, rd_vd, sew, len, use_all, msk, plog);
        @(negedge clk);
      end
    end

    checks++;
    if (busy !== 1'b0) fail("busy after walk");
    checks++;
    if (done !== 1'b1) fail("done after walk");
    @(negedge clk);
    checks++;
    if (done !== 1'b0) fail("done stuck high");
  endtask

  task automatic sweep();
    for (int sew = 0; sew < 3; sew++) begin
      for (int lm = 0; lm < 4; lm++) begin
        for (int plog = 0; plog < 3; plog++) begin
          for (int t = 0; t < 3; t++) begin
            int vmax;
            vmax = (VLEN / (8 << sew)) * (1 << lm);
            run_case(5'd1, 5'd8, 5'd16, 1'b0, 8'(t == 0 ? vmax : (t == 1 ? vmax / 2 : 1)), 3'(sew),
                     3'(lm), 1'b1, '1, 2'(plog));
          end
        end
      end
    end
  endtask

  task automatic verdict();
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask

  initial begin
    $dumpfile("vec_sequencer_tb.vcd");
    $dumpvars(0, vec_sequencer_tb);

    init_signals();
    do_reset();

    // Single register
    run_case(5'd1, 5'd8, 5'd16, 1'b0, 8'd4, 3'd2, 3'd0, 1'b1, '1, 2'd0);

    // Four registers ganged
    run_case(5'd16, 5'd24, 5'd8, 1'b0, 8'd16, 3'd2, 3'd2, 1'b1, '1, 2'd0);

    // Tail cut
    run_case(5'd16, 5'd24, 5'd8, 1'b0, 8'd10, 3'd2, 3'd2, 1'b1, '1, 2'd0);

    // Zero length
    run_case(5'd1, 5'd2, 5'd3, 1'b0, 8'd0, 3'd2, 3'd0, 1'b1, '1, 2'd0);

    // Accumulator read
    run_case(5'd1, 5'd8, 5'd16, 1'b1, 8'd8, 3'd1, 3'd1, 1'b1, '1, 2'd0);

    // Four passes
    run_case(5'd1, 5'd8, 5'd16, 1'b0, 8'd16, 3'd0, 3'd0, 1'b1, '1, 2'd2);

    // Mask holes
    run_case(5'd1, 5'd8, 5'd16, 1'b0, 8'd4, 3'd2, 3'd0, 1'b0, 16'b0000_0000_0000_1010, 2'd0);

    // Fractional grouping
    run_case(5'd1, 5'd8, 5'd16, 1'b0, 8'd2, 3'd2, 3'd7, 1'b1, '1, 2'd0);

    // Byte elements
    run_case(5'd2, 5'd4, 5'd6, 1'b0, 8'd16, 3'd0, 3'd0, 1'b1, '1, 2'd0);

    // Exhaustive sweep
    sweep();

    verdict();
  end

endmodule

`default_nettype wire
