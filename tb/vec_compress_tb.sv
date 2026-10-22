`default_nettype none

module vec_compress_tb #(
    parameter int VLEN = arch_pkg::VLEN
) ();

  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int VlW = $clog2(VLEN + 1);
  localparam int MaxElems = VLEN / 8;

  int                checks = 0;
  int                errors = 0;

  logic              clk = 1'b0;
  logic              rst_n;
  logic              core_en;
  logic              start;
  logic [AWIDTH-1:0] vs1;
  logic [AWIDTH-1:0] vs2;
  logic [AWIDTH-1:0] vd;
  logic [   VlW-1:0] vl;
  logic [       2:0] vsew;
  logic [  VLEN-1:0] rdata_mask;
  logic [  VLEN-1:0] rdata_src;
  logic [AWIDTH-1:0] raddr_mask;
  logic [AWIDTH-1:0] raddr_src;
  logic              wen;
  logic [AWIDTH-1:0] waddr;
  logic [  VLEN-1:0] wstrb;
  logic [  VLEN-1:0] wdata;
  logic              busy;
  logic              done;

  always #5 clk = ~clk;

  vec_compress #(
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) dut (
      .clk       (clk),
      .rst_n     (rst_n),
      .core_en   (core_en),
      .start     (start),
      .vs1       (vs1),
      .vs2       (vs2),
      .vd        (vd),
      .vl        (vl),
      .vsew      (vsew),
      .rdata_mask(rdata_mask),
      .rdata_src (rdata_src),
      .raddr_mask(raddr_mask),
      .raddr_src (raddr_src),
      .wen       (wen),
      .waddr     (waddr),
      .wstrb     (wstrb),
      .wdata     (wdata),
      .busy      (busy),
      .done      (done)
  );

  logic [VLEN-1:0] regs[32];

  assign rdata_src  = regs[raddr_src];
  assign rdata_mask = regs[raddr_mask];

  always @(posedge clk) begin
    if (core_en && wen) regs[waddr] <= (regs[waddr] & ~wstrb) | (wdata & wstrb);
  end

  task automatic fail(input string msg);
    errors = errors + 1;
    if (errors < 12) $display("FAIL %0s at %0t", msg, $time);
  endtask

  function automatic logic [VLEN-1:0] rand_reg();
    logic [VLEN-1:0] x;
    for (int i = 0; i < VLEN / 32; i++) x[i*32+:32] = $urandom;
    return x;
  endfunction

  task automatic do_reset();
    rst_n   = 1'b0;
    core_en = 1'b1;
    start   = 1'b0;
    vs1     = '0;
    vs2     = '0;
    vd      = '0;
    vl      = '0;
    vsew    = '0;
    for (int r = 0; r < 32; r++) regs[r] = '0;
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
  endtask

  logic [VLEN-1:0] orig[32];
  logic [VLEN-1:0] want[32];

  function automatic logic [31:0] get_elem(input int base, input int w, input int idx);
    int per;
    logic [31:0] v;
    per = VLEN / w;
    v   = '0;
    for (int b = 0; b < w; b++) v[b] = orig[base+idx/per][(idx%per)*w+b];
    return v;
  endfunction

  task automatic set_elem(input int base, input int w, input int idx, input logic [31:0] v);
    int per;
    per = VLEN / w;
    for (int b = 0; b < w; b++) want[base+idx/per][(idx%per)*w+b] = v[b];
  endtask

  // Fire start with garbage operands while busy
  bit poke_start = 1'b0;

  task automatic run_compress(input int sew, input int lmul, input int n, input int s1,
                              input int s2, input int d, input logic [VLEN-1:0] mask,
                              input int stall_pct, input string tag);
    int w, per, nsrc, npack, cycles, dones, writes;
    logic flush_wen;

    w   = 8 << sew;
    per = VLEN / w;

    for (int r = 0; r < 32; r++) regs[r] = rand_reg();
    regs[s1] = mask;
    for (int r = 0; r < 32; r++) orig[r] = regs[r];

    // Reference
    for (int r = 0; r < 32; r++) want[r] = orig[r];
    npack = 0;
    for (int i = 0; i < n; i++) begin
      if (mask[i]) begin
        set_elem(d, w, npack, get_elem(s2, w, i));
        npack++;
      end
    end
    nsrc = (n + per - 1) / per;


    vs1   = AWIDTH'(s1);
    vs2   = AWIDTH'(s2);
    vd    = AWIDTH'(d);
    vl    = VlW'(n);
    vsew  = 3'(sew);
    start = 1'b1;
    @(negedge clk);
    start     = 1'b0;
    vs1       = AWIDTH'($urandom);
    vs2       = AWIDTH'($urandom);
    vd        = AWIDTH'($urandom);
    vl        = VlW'($urandom);
    vsew      = 3'($urandom);

    cycles    = 0;
    dones     = 0;
    writes    = 0;
    flush_wen = 1'b0;
    while (busy && (cycles < 200)) begin
      core_en = ($urandom_range(99) >= stall_pct);
      start   = poke_start && $urandom_range(1);
      if (start) begin
        vs1  = AWIDTH'($urandom);
        vs2  = AWIDTH'($urandom);
        vd   = AWIDTH'($urandom);
        vl   = VlW'($urandom);
        vsew = 3'($urandom_range(2));
      end
      #1;
      if (core_en) begin
        cycles++;
        if (wen) begin
          writes++;
          if ((int'(waddr) < d) || (int'(waddr) >= d + lmul))
            fail($sformatf("%0s waddr %0d outside vd group", tag, waddr));
        end
        if (done) begin
          dones++;
          flush_wen = wen;
        end
      end
      @(negedge clk);
    end
    core_en = 1'b1;
    start   = 1'b0;

    checks++;
    if (busy) fail($sformatf("%0s hung", tag));
    checks++;
    if (dones != 1) fail($sformatf("%0s done pulsed %0d times", tag, dones));
    checks++;
    if (cycles != nsrc + 1) fail($sformatf("%0s took %0d cycles want %0d", tag, cycles, nsrc + 1));
    checks++;
    if ((npack % per != 0) && !flush_wen) fail($sformatf("%0s no flush write with done", tag));
    checks++;
    if (writes != (npack + per - 1) / per)
      fail($sformatf("%0s %0d writes want %0d", tag, writes, (npack + per - 1) / per));
    checks++;
    if (done) fail($sformatf("%0s done stuck high", tag));
    for (int r = 0; r < 32; r++) begin
      checks++;
      if (regs[r] !== want[r]) fail($sformatf("%0s v%0d got=%h want=%h", tag, r, regs[r], want[r]));
    end
  endtask

  // vsew=2 vl=4 mask=1010 -> vd[0]=src[1], vd[1]=src[3], rest of vd undisturbed
  task automatic check_directed();
    logic [VLEN-1:0] exp;
    for (int r = 0; r < 32; r++) regs[r] = '0;
    regs[2] = VLEN'(128'h4444_4444_3333_3333_2222_2222_1111_1111);
    regs[3] = VLEN'(128'h4444_4444_3333_3333);
    regs[1] = VLEN'(4'b1010);
    regs[4] = VLEN'(128'hdead_beef_dead_beef_dead_beef_dead_beef);
    exp     = regs[4];
    vs1     = AWIDTH'(1);
    vs2     = AWIDTH'(2);
    vd      = AWIDTH'(4);
    vl      = VlW'(4);
    vsew    = 3'd2;
    start   = 1'b1;
    @(negedge clk);
    start = 1'b0;
    while (busy) @(negedge clk);
    exp[63:0] = {32'h4444_4444, 32'h2222_2222};
    checks++;
    if (regs[4] !== exp) fail($sformatf("directed got=%h want=%h", regs[4], exp));
  endtask

  task automatic check_gated_start();
    for (int r = 0; r < 32; r++) regs[r] = rand_reg();
    for (int r = 0; r < 32; r++) orig[r] = regs[r];
    vs1     = AWIDTH'(0);
    vs2     = AWIDTH'(8);
    vd      = AWIDTH'(16);
    vl      = VlW'(MaxElems);
    vsew    = 3'd0;
    start   = 1'b1;
    core_en = 1'b0;
    repeat (3) begin
      @(negedge clk);
      checks++;
      if (busy || done || wen) fail("gated start began work");
    end
    start   = 1'b0;
    core_en = 1'b1;
    @(negedge clk);
    checks++;
    if (busy || done || wen) fail("gated start began late");
    for (int r = 0; r < 32; r++) begin
      checks++;
      if (regs[r] !== orig[r]) fail($sformatf("gated start wrote v%0d", r));
    end
  endtask

  // Reset after k busy cycles
  task automatic check_reset_mid();
    for (int k = 0; k <= 9; k++) begin
      for (int r = 0; r < 32; r++) regs[r] = rand_reg();
      vs1   = AWIDTH'(0);
      vs2   = AWIDTH'(8);
      vd    = AWIDTH'(16);
      vl    = VlW'(MaxElems * 8);
      vsew  = 3'd0;
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
      repeat (k) @(negedge clk);
      rst_n = 1'b0;
      @(negedge clk);
      for (int r = 0; r < 32; r++) orig[r] = regs[r];
      checks++;
      if (busy || done || wen)
        fail($sformatf("reset at %0d left busy=%b done=%b wen=%b", k, busy, done, wen));
      @(negedge clk);
      rst_n = 1'b1;
      @(negedge clk);
      checks++;
      if (busy || done || wen) fail($sformatf("reset at %0d woke busy", k));
      for (int r = 0; r < 32; r++) begin
        checks++;
        if (regs[r] !== orig[r]) fail($sformatf("reset at %0d wrote v%0d", k, r));
      end
      run_compress(0, 2, MaxElems + 3, 0, 8, 16, rand_reg(), 0, $sformatf("after reset %0d", k));
    end
  endtask

  // Every SEW and LMUL at VLMAX with fixed masks
  task automatic check_sweep();
    for (int sew = 0; sew < 3; sew++) begin
      for (int lg = 0; lg < 4; lg++) begin
        int vlmax;
        vlmax = (MaxElems >> sew) << lg;
        run_compress(sew, 1 << lg, vlmax, 0, 8, 16, '1, 0, "all set");
        run_compress(sew, 1 << lg, vlmax, 0, 8, 16, '0, 0, "none set");
        run_compress(sew, 1 << lg, vlmax, 0, 8, 16, {(VLEN / 2) {2'b01}}, 0, "every other");
      end
    end
  endtask

  task automatic check_random(input int iters);
    for (int it = 0; it < iters; it++) begin
      int sew, lg, lmul, vlmax, n, s1, s2, d, stall;
      logic [VLEN-1:0] mask;
      sew   = $urandom_range(2);
      lg    = $urandom_range(3);
      lmul  = 1 << lg;
      vlmax = (MaxElems >> sew) * lmul;
      case ($urandom_range(
          5
      ))
        0:       n = vlmax;
        1:       n = 0;
        2:       n = $urandom_range((vlmax < 3) ? vlmax : 3);
        default: n = $urandom_range(vlmax);
      endcase

      s2 = lmul * $urandom_range(32 / lmul - 1);
      if ($urandom_range(7) == 0) begin
        d = s2;
      end else begin
        do d = lmul * $urandom_range(32 / lmul - 1); while (d == s2);
      end
      do
      s1 = $urandom_range(31);
      while (((s1 >= s2) && (s1 < s2 + lmul)) || ((s1 >= d) && (s1 < d + lmul)));
      case ($urandom_range(
          4
      ))
        0:       mask = '1;
        1:       mask = '0;
        2:       mask = rand_reg() & rand_reg() & rand_reg();
        3:       mask = rand_reg() | rand_reg();
        default: mask = rand_reg();
      endcase
      stall = $urandom_range(1) ? 0 : 30;
      run_compress(sew, lmul, n, s1, s2, d, mask, stall, $sformatf(
                   "it%0d sew%0d lmul%0d vl%0d", it, sew, lmul, n));
    end
  endtask

  task automatic verdict();
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask

  initial begin
    $dumpfile("vec_compress_tb.vcd");
    $dumpvars(0, vec_compress_tb);

    do_reset();
    check_directed();
    check_sweep();
    check_gated_start();
    check_reset_mid();
    check_random(400);
    poke_start = 1'b1;
    check_random(200);
    poke_start = 1'b0;
    verdict();
  end

endmodule

`default_nettype wire
