`default_nettype none

module vec_mem_tb ();

  localparam int VLEN = 128;
  localparam int Regs = 32;
  localparam int Bytes = 256;
  localparam int Timeout = 2000000;

  int checks = 0;
  int errors = 0;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic core_en = 1'b1;

  logic start = 1'b0;
  logic load = 1'b0;
  logic vm = 1'b1;
  logic [4:0] vd = '0;
  logic [7:0] count = '0;
  logic [1:0] width = '0;
  logic [31:0] base = '0;
  logic [31:0] stride = '0;

  logic [VLEN-1:0] rdata;
  logic [4:0] raddr;
  logic wen;
  logic [VLEN-1:0] wstrb;
  logic [VLEN-1:0] wdata;

  logic [31:0] mem_rdata;
  logic mem_ready;
  logic mem_req;
  logic [31:0] mem_addr;
  logic [31:0] mem_wdata;
  logic [3:0] mem_wstrb;
  logic busy;
  logic done;

  logic [VLEN-1:0] regs[Regs];
  logic [VLEN-1:0] golden_regs[Regs];
  logic [7:0] mem[Bytes];
  logic [7:0] golden_mem[Bytes];

  int ready_pct = 100;
  int enable_pct = 100;
  int beats = 0;
  int dones = 0;

  logic past_req = 1'b0;
  logic past_ready = 1'b0;
  logic past_en = 1'b0;
  logic [31:0] past_addr;
  logic [31:0] past_wdata;
  logic [3:0] past_wstrb;

  always #5 clk = ~clk;

  vec_mem #(
      .VLEN(VLEN)
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
      .busy(busy),
      .done(done)
  );

  // Checks
  task automatic check(input string name, input logic [VLEN-1:0] got, input logic [VLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("%s: got %h, expected %h", name, got, exp);
    end
  endtask  // Automatic

  task automatic check_state();
    for (int r = 0; r < Regs; r++) check("register", regs[r], golden_regs[r]);
    for (int b = 0; b < Bytes; b++) check("memory byte", VLEN'(mem[b]), VLEN'(golden_mem[b]));
  endtask  // Automatic

  task automatic verdict();
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  // Drive
  task automatic do_reset();
    rst_n = 0;
    repeat (2) @(posedge clk);
    rst_n = 1;
  endtask  // Automatic

  task automatic set_pace(input int ready, input int enable);
    ready_pct  = ready;
    enable_pct = enable;
  endtask  // Automatic

  task automatic fill_state();
    for (int r = 0; r < Regs; r++) begin
      regs[r] = {$urandom, $urandom, $urandom, $urandom};
      golden_regs[r] = regs[r];
    end
    for (int b = 0; b < Bytes; b++) begin
      mem[b] = 8'($urandom);
      golden_mem[b] = mem[b];
    end
  endtask  // Automatic

  // Reference semantics
  task automatic apply_golden();
    int bytes;
    logic [31:0] a;
    logic [31:0] e;
    int bit0;
    int r;
    bytes = 1 << width;
    for (int i = 0; i < int'(count); i++) begin
      a = base + 32'(i) * stride;
      r = (int'(vd) + i / (16 >> width)) % Regs;
      bit0 = (i % (16 >> width)) * bytes * 8;
      if (!(vm || golden_regs[0][i])) continue;
      if (load) begin
        e = 32'h0;
        for (int k = 0; k < bytes; k++) e[k*8+:8] = golden_mem[(a+32'(k))%Bytes];
        for (int k = 0; k < bytes * 8; k++) golden_regs[r][bit0+k] = e[k];
      end else begin
        for (int k = 0; k < bytes * 8; k++) e[k] = golden_regs[r][bit0+k];
        for (int k = 0; k < bytes; k++) golden_mem[(a+32'(k))%Bytes] = e[k*8+:8];
      end
    end
  endtask  // Automatic

  task automatic run_one(input logic l, input logic [1:0] w, input logic [7:0] n,
                         input logic [31:0] b, input logic [31:0] s, input logic m,
                         input logic [4:0] d);
    int want;
    load = l;
    width = w;
    count = n;
    base = b;
    stride = s;
    vm = m;
    vd = d;
    apply_golden();
    beats = 0;
    dones = 0;
    want  = int'(n);
    @(negedge clk);
    start = 1'b1;
    @(posedge clk);
    while (!core_en) @(posedge clk);
    #1;
    start = 1'b0;
    while (!done) @(negedge clk);
    while (done) @(negedge clk);
    check("beat count", VLEN'(beats), VLEN'(want));
    check("done pulses", VLEN'(dones), VLEN'(1));
    check_state();
  endtask  // Automatic

  function automatic logic [31:0] aligned(input logic [1:0] w);
    return 32'($urandom_range(Bytes - 1)) & ~((32'd1 << w) - 32'd1);
  endfunction

  task automatic run_random(input logic l, input logic whole, input logic strided);
    logic [1:0] w;
    logic [7:0] n;
    logic [31:0] s;
    logic m;
    logic [4:0] d;
    w = 2'($urandom_range(2));
    n = whole ? 8'(VLEN >> (3 + w)) : 8'($urandom_range(16 >> w));
    if ($urandom_range(7) == 0 && !whole) n = 8'($urandom_range(VLEN >> (3 + w)));
    s = strided ? 32'($signed($urandom_range(12)) - 6) << w : 32'd1 << w;
    m = whole ? 1'b1 : 1'($urandom_range(1));
    d = (!m && l) ? 5'($urandom_range(23, 1)) : 5'($urandom_range(Regs - 1));
    if (!m && !l && ($urandom_range(1) == 1)) d = 5'd0;
    run_one(l, w, n, aligned(w), s, m, d);
  endtask  // Automatic

  task automatic run_many(input int n);
    for (int i = 0; i < n; i++)
      run_random(1'($urandom_range(1)), $urandom_range(3) == 0, 1'($urandom_range(1)));
  endtask  // Automatic

  // Pace and models
  always @(posedge clk) begin
    #2;
    mem_ready = ($urandom_range(99) < ready_pct);
    core_en   = ($urandom_range(99) < enable_pct);
  end

  assign rdata = regs[raddr];
  assign mem_rdata = {
    mem[(mem_addr+3)%Bytes], mem[(mem_addr+2)%Bytes], mem[(mem_addr+1)%Bytes], mem[mem_addr%Bytes]
  };

  always @(posedge clk) begin
    if (rst_n && core_en) begin
      if (wen) regs[raddr] <= (regs[raddr] & ~wstrb) | (wdata & wstrb);
      if (mem_req && mem_ready) begin
        beats++;
        for (int k = 0; k < 4; k++)
        if (mem_wstrb[k]) mem[(mem_addr+32'(k))%Bytes] <= mem_wdata[k*8+:8];
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
      check("word aligned address", VLEN'(mem_addr[1:0]), VLEN'(0));
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

  initial begin
    repeat (Timeout) @(posedge clk);
    $fatal(1, "FAIL: timeout, %0d mismatches, %0d checks", errors, checks);
  end

  initial begin
    $dumpfile("vec_mem_tb.vcd");
    $dumpvars(0, vec_mem_tb);
    fill_state();
    do_reset();

    // Directed forms
    run_one(1'b1, 2'd0, 8'd3, 32'd8, 32'd1, 1'b1, 5'd1);
    run_one(1'b1, 2'd1, 8'd3, 32'd8, 32'd2, 1'b1, 5'd2);
    run_one(1'b1, 2'd2, 8'd4, 32'd12, 32'd4, 1'b1, 5'd3);
    run_one(1'b0, 2'd0, 8'd16, 32'd40, 32'd1, 1'b1, 5'd4);
    run_one(1'b0, 2'd1, 8'd5, 32'd80, -32'sd2, 1'b0, 5'd5);
    run_one(1'b1, 2'd0, 8'd3, 32'd5, -32'sd2, 1'b0, 5'd6);

    // Zero count
    run_one(1'b1, 2'd2, 8'd0, 32'd0, 32'd4, 1'b1, 5'd7);
    run_one(1'b0, 2'd0, 8'd0, 32'd0, 32'd1, 1'b0, 5'd8);

    // Group spill
    run_one(1'b1, 2'd0, 8'd40, 32'd100, 32'd1, 1'b1, 5'd30);
    run_one(1'b0, 2'd2, 8'd9, 32'd128, 32'd4, 1'b1, 5'd31);

    // Instant memory
    run_many(300);

    // Slow memory
    set_pace(30, 100);
    run_many(300);

    // Clock enable gaps
    set_pace(50, 60);
    run_many(300);

    verdict();
  end

endmodule

`default_nettype wire
