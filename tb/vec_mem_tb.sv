`default_nettype none

module vec_mem_tb ();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int VLEN = arch_pkg::VLEN;
  localparam int ELEN = arch_pkg::ELEN;
  localparam int VlW = $clog2(VLEN + 1);
  localparam int LineB = VLEN / 8;
  localparam int Regs = arch_pkg::NumRegs;
  localparam int Bytes = 256;
  localparam int Timeout = 2000000;
  localparam logic [1:0] Eew8 = 2'd0;
  localparam logic [1:0] Eew16 = 2'd1;
  localparam logic [1:0] Eew32 = 2'd2;
  localparam int RandomRuns = 300;
  localparam int DirectedRuns = 14;
  localparam int Runs = 3 * RandomRuns + DirectedRuns;
  localparam int MinChecks = Runs * (Regs + Bytes + 2) + 270 * VLEN + 14000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int ready_pct = 100;
  int enable_pct = 100;
  int beats = 0;
  int dones = 0;

  logic clk = 1'b0;
  logic rst_n;
  logic core_en;

  logic start;
  logic load;
  logic vm;
  logic [AWIDTH-1:0] vd;
  logic [VlW-1:0] count;
  logic [1:0] width;
  logic [XLEN-1:0] base;
  logic [XLEN-1:0] stride;

  logic [VLEN-1:0] rdata;
  logic [AWIDTH-1:0] raddr;
  logic wen;
  logic [VLEN-1:0] wstrb;
  logic [VLEN-1:0] wdata;

  logic [VLEN-1:0] mem_rdata;
  logic mem_ready;
  logic mem_req;
  logic [XLEN-1:0] mem_addr;
  logic [VLEN-1:0] mem_wdata;
  logic [LineB-1:0] mem_wstrb;
  logic busy;
  logic done;

  logic [VLEN-1:0] regs[Regs];
  logic [VLEN-1:0] golden_regs[Regs];
  logic [7:0] mem[Bytes];
  logic [7:0] golden_mem[Bytes];

  logic past_req = 1'b0;
  logic past_ready = 1'b0;
  logic past_en = 1'b0;
  logic [XLEN-1:0] past_addr;
  logic [VLEN-1:0] past_wdata;
  logic [LineB-1:0] past_wstrb;
  logic [XLEN-1:0] line_base;

  always #5 clk = ~clk;

  vec_mem #(
      .XLEN  (XLEN),
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(start),
      .load(load),
      .vm(vm),
      .vd(vd),
      .count(count),
      .width(width),
      .base(base),
      .stride(stride),
      .v0(regs[0]),
      .rdata(rdata),
      .raddr(raddr),
      .wen(wen),
      .wstrb(wstrb),
      .wdata(wdata),
      .mem_rdata(mem_rdata),
      .mem_ready(mem_ready),
      .mem_req(mem_req),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
      .mem_wstrb(mem_wstrb),
      .reg_done(),
      .busy(busy),
      .done(done)
  );

  // Checks
  task automatic check(input string name, input logic [VLEN-1:0] got, input logic [VLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  // Drive
  task automatic do_reset();
    @(negedge clk);
    rst_n  = 1'b0;
    start  = 1'b0;
    load   = 1'b0;
    vm     = 1'b1;
    vd     = '0;
    count  = '0;
    width  = Eew8;
    base   = '0;
    stride = '0;
    set_pace(100, 100);
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic set_pace(input int ready, input int enable);
    ready_pct  = ready;
    enable_pct = enable;
  endtask  // Automatic

  task automatic drive_pace();
    mem_ready <= ($urandom_range(99) < ready_pct);
    core_en   <= ($urandom_range(99) < enable_pct);
  endtask  // Automatic

  task automatic watchdog();
    repeat (Timeout) @(posedge clk);
    $fatal(1, "FAIL: timeout, %0d mismatches, %0d checks", errors, checks);
  endtask  // Automatic

  task automatic fill_state();
    for (int r = 0; r < Regs; r++) begin
      for (int k = 0; k < VLEN; k += 32) regs[r][k+:32] = 32'($urandom);
      golden_regs[r] = regs[r];
    end
    for (int b = 0; b < Bytes; b++) begin
      mem[b] = 8'($urandom);
      golden_mem[b] = mem[b];
    end
  endtask  // Automatic

  task automatic check_state();
    for (int r = 0; r < Regs; r++) check("register", regs[r], golden_regs[r]);
    for (int b = 0; b < Bytes; b++) check("memory byte", VLEN'(mem[b]), VLEN'(golden_mem[b]));
  endtask  // Automatic

  task automatic run_one(input logic l, input logic [1:0] w, input int n, input int b, input int s,
                         input logic m, input int d);
    int want;
    load = l;
    width = w;
    count = VlW'(n);
    base = XLEN'(b);
    stride = XLEN'(s);
    vm = m;
    vd = AWIDTH'(d);
    want = want_beats();
    apply_golden();
    beats = 0;
    dones = 0;
    @(negedge clk);
    start = 1'b1;
    @(posedge clk);
    while (!core_en) @(posedge clk);
    @(negedge clk);
    start = 1'b0;
    while (!done) @(negedge clk);
    while (done) @(negedge clk);
    check("beat count", VLEN'(beats), VLEN'(want));
    check("done pulses", VLEN'(dones), VLEN'(1));
    check_state();
  endtask  // Automatic

  function automatic logic [XLEN-1:0] aligned(input logic [1:0] w);
    return XLEN'($urandom_range(Bytes - 1)) & ~((XLEN'(1) << w) - XLEN'(1));
  endfunction

  task automatic run_random(input logic l, input logic whole, input logic strided);
    logic [1:0] w;
    logic [VlW-1:0] n;
    logic [XLEN-1:0] s;
    logic m;
    logic [AWIDTH-1:0] d;
    w = 2'($urandom_range(Eew32));
    n = whole ? VlW'(VLEN >> (3 + w)) : VlW'($urandom_range(LineB >> w));
    if ($urandom_range(7) == 0 && !whole) n = VlW'($urandom_range(VLEN >> (3 + w)));
    s = strided ? XLEN'($signed($urandom_range(12)) - 6) << w : XLEN'(1) << w;
    m = whole ? 1'b1 : 1'($urandom);
    d = (!m && l) ? AWIDTH'($urandom_range(Regs > 23 ? 23 : Regs - 1, 1)) : AWIDTH'($urandom);
    if (!m && !l && 1'($urandom)) d = '0;
    run_one(l, w, int'(n), int'(aligned(w)), int'(s), m, int'(d));
  endtask  // Automatic

  task automatic run_many(input int n);
    for (int i = 0; i < n; i++) run_random(1'($urandom), $urandom_range(3) == 0, 1'($urandom));
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial watchdog();

  initial begin
    $dumpfile("vec_mem_tb.vcd");
    $dumpvars(0, vec_mem_tb);
    fill_state();
    do_reset();

    // Directed forms
    run_one(1'b1, Eew8, 3, 8, 1, 1'b1, 1);
    run_one(1'b1, Eew16, 3, 8, 2, 1'b1, 2);
    run_one(1'b1, Eew32, 4, 12, 4, 1'b1, 3);
    run_one(1'b0, Eew8, 16, 40, 1, 1'b1, 4);
    run_one(1'b0, Eew16, 5, 80, -2, 1'b0, 5);
    run_one(1'b1, Eew8, 3, 5, -2, 1'b0, 6);

    // Whole line beats
    run_one(1'b1, Eew32, 4, 32, 4, 1'b1, 9);
    run_one(1'b0, Eew8, 16, 48, 1, 1'b1, 10);
    run_one(1'b1, Eew32, 4, 40, 4, 1'b0, 11);
    run_one(1'b0, Eew16, 24, 70, 2, 1'b0, 12);

    // Zero count
    run_one(1'b1, Eew32, 0, 0, 4, 1'b1, 7);
    run_one(1'b0, Eew8, 0, 0, 1, 1'b0, 8);

    // Group spill
    run_one(1'b1, Eew8, 40, 100, 1, 1'b1, 30);
    run_one(1'b0, Eew32, 9, 128, 4, 1'b1, 31);

    // Instant memory
    set_pace(100, 100);
    run_many(RandomRuns);

    // Slow memory
    set_pace(30, 100);
    run_many(RandomRuns);

    // Clock enable gaps
    set_pace(50, 60);
    run_many(RandomRuns);

    do_verdict();
  end

  // Reference semantics
  task automatic apply_golden();
    int bytes;
    logic [XLEN-1:0] a;
    logic [ELEN-1:0] e;
    int bit0;
    int r;
    bytes = 1 << width;
    for (int i = 0; i < int'(count); i++) begin
      a = base + XLEN'(i) * stride;
      r = (int'(vd) + i / (LineB >> width)) % Regs;
      bit0 = (i % (LineB >> width)) * bytes * 8;
      if (!(vm || golden_regs[0][i])) continue;
      if (load) begin
        e = '0;
        for (int k = 0; k < bytes; k++) e[k*8+:8] = golden_mem[(a+XLEN'(k))%Bytes];
        for (int k = 0; k < bytes * 8; k++) golden_regs[r][bit0+k] = e[k];
      end else begin
        for (int k = 0; k < bytes * 8; k++) e[k] = golden_regs[r][bit0+k];
        for (int k = 0; k < bytes; k++) golden_mem[(a+XLEN'(k))%Bytes] = e[k*8+:8];
      end
    end
  endtask  // Automatic

  function automatic int want_beats();
    int n;
    logic [XLEN-1:0] a;
    logic [XLEN-1:0] key;
    logic [XLEN-1:0] last;
    if (stride != (XLEN'(1) << width)) return int'(count);
    n = 0;
    for (int i = 0; i < int'(count); i++) begin
      a   = base + XLEN'(i) * stride;
      key = (a / LineB) * XLEN'(VLEN) + XLEN'(i / (LineB >> width));
      if (i == 0 || key != last) n++;
      last = key;
    end
    return n;
  endfunction

  // Pace and models
  always @(posedge clk) drive_pace();

  assign line_base = mem_addr & ~XLEN'(LineB - 1);
  assign rdata = regs[raddr];
  always_comb begin
    for (int k = 0; k < LineB; k++) mem_rdata[k*8+:8] = mem[(line_base+XLEN'(k))%Bytes];
  end

  always @(posedge clk) begin
    if (rst_n && core_en) begin
      if (wen) regs[raddr] <= (regs[raddr] & ~wstrb) | (wdata & wstrb);
      if (mem_req && mem_ready) begin
        beats++;
        for (int k = 0; k < LineB; k++)
        if (mem_wstrb[k]) mem[(line_base+XLEN'(k))%Bytes] <= mem_wdata[k*8+:8];
      end
      if (done) dones++;
    end
  end

  // Comparison
  always @(negedge clk) begin
    if (rst_n) begin
      check("request while idle", VLEN'(mem_req && !busy), VLEN'(0));
      check("write outside load", VLEN'(wen && !load), VLEN'(0));
      check("write before ready", VLEN'(wen && !mem_ready), VLEN'(0));
      if (mem_req)
        check("element aligned address", VLEN'(XLEN'(mem_addr & ((XLEN'(1) << width) - XLEN'(1)))),
              VLEN'(0));
      if (past_req && past_en && !past_ready) begin
        check("request held", VLEN'(mem_req), VLEN'(1));
        check("address held", VLEN'(mem_addr), VLEN'(past_addr));
        check("data held", VLEN'(mem_wdata), VLEN'(past_wdata));
        check("strobe held", VLEN'(mem_wstrb), VLEN'(past_wstrb));
      end
    end
  end

  always @(posedge clk) begin
    past_req   <= mem_req;
    past_ready <= mem_ready;
    past_en    <= core_en;
    past_addr  <= mem_addr;
    past_wdata <= mem_wdata;
    past_wstrb <= mem_wstrb;
    if (!core_en) past_req <= 1'b0;
  end

endmodule

`default_nettype wire
