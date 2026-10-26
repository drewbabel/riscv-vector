`default_nettype none

module dmem_arb_tb ();

  localparam int MinChecks = 38000;

  int checks;
  int errors;
  int max_errors;
  int live_errors;

  dmem_arb_bench xlen_bench ();

  dmem_arb_bench #(.DATA_W(64)) w64_bench ();

  dmem_arb_bench #(.DATA_W(128)) w128_bench ();

  task automatic check_floor(input string name, input int got, input int floor);
    if (got < floor)
      $fatal(1, "TB UNDER-RAN: %s %0d checks, expected at least %0d", name, got, floor);
  endtask  // Automatic

  task automatic do_verdict();
    checks = xlen_bench.checks + w64_bench.checks + w128_bench.checks;
    errors = xlen_bench.errors + w64_bench.errors + w128_bench.errors;
    check_floor("xlen_bench", xlen_bench.checks, MinChecks);
    check_floor("w64_bench", w64_bench.checks, MinChecks);
    check_floor("w128_bench", w128_bench.checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("dmem_arb_tb.vcd");
    $dumpvars(0, dmem_arb_tb);
    wait (xlen_bench.done && w64_bench.done && w128_bench.done);
    do_verdict();
  end

  always_comb live_errors = xlen_bench.errors + w64_bench.errors + w128_bench.errors;

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (live_errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", live_errors);
    end
  end

endmodule

module dmem_arb_bench #(
    parameter int DATA_W = arch_pkg::XLEN
) ();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int StrbW = DATA_W / 8;
  localparam int WordLsb = $clog2(StrbW);
  localparam int Words = 16;
  localparam int WordHi = $clog2(Words) + WordLsb - 1;
  localparam int Timeout = 200000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  logic s_req;
  logic [XLEN-1:0] s_addr;
  logic [DATA_W-1:0] s_wdata;
  logic [StrbW-1:0] s_wstrb;
  logic s_ready;

  logic v_req;
  logic [XLEN-1:0] v_addr;
  logic [DATA_W-1:0] v_wdata;
  logic [StrbW-1:0] v_wstrb;
  logic v_ready;

  logic req;
  logic [XLEN-1:0] addr;
  logic [DATA_W-1:0] wdata;
  logic [StrbW-1:0] wstrb;
  logic ready;
  logic [DATA_W-1:0] rdata;

  int lat_min = 0;
  int lat_max = 0;

  logic [DATA_W-1:0] mem[Words];
  logic [DATA_W-1:0] golden[Words];

  logic last_vec = 1'b1;
  int s_passed = 0;
  int v_passed = 0;

  logic m_busy;
  int m_left;
  int m_next;
  logic [XLEN-1:0] m_addr;
  logic [DATA_W-1:0] m_wdata;
  logic [StrbW-1:0] m_wstrb;

  always #5 clk = ~clk;

  dmem_arb #(
      .XLEN  (XLEN),
      .DATA_W(DATA_W)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(1'b1),
      .s_req(s_req),
      .s_addr(s_addr),
      .s_wdata(s_wdata),
      .s_wstrb(s_wstrb),
      .s_ready(s_ready),
      .v_req(v_req),
      .v_addr(v_addr),
      .v_wdata(v_wdata),
      .v_wstrb(v_wstrb),
      .v_ready(v_ready),
      .req(req),
      .addr(addr),
      .wdata(wdata),
      .wstrb(wstrb),
      .ready(ready)
  );

  // Checks
  task automatic check(input string name, input logic [DATA_W-1:0] got,
                       input logic [DATA_W-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %m %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  // Drive
  task automatic do_reset();
    rst_n   = 1'b0;
    s_req   = 1'b0;
    s_addr  = '0;
    s_wdata = '0;
    s_wstrb = '0;
    v_req   = 1'b0;
    v_addr  = '0;
    v_wdata = '0;
    v_wstrb = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic idle(input int n);
    repeat (n) @(negedge clk);
  endtask  // Automatic

  task automatic set_latency(input int lo, input int hi);
    lat_min = lo;
    lat_max = hi;
  endtask  // Automatic

  task automatic fill_memory();
    for (int i = 0; i < Words; i++) begin
      mem[i] = rand_data();
      golden[i] = mem[i];
    end
  endtask  // Automatic

  task automatic s_access(input logic [XLEN-1:0] a, input logic [DATA_W-1:0] d,
                          input logic [StrbW-1:0] st);
    s_req   = 1'b1;
    s_addr  = a;
    s_wdata = d;
    s_wstrb = st;
    do @(posedge clk); while (!s_ready);
    @(negedge clk);
    s_req = 1'b0;
  endtask  // Automatic

  task automatic v_access(input logic [XLEN-1:0] a, input logic [DATA_W-1:0] d,
                          input logic [StrbW-1:0] st);
    v_req   = 1'b1;
    v_addr  = a;
    v_wdata = d;
    v_wstrb = st;
    do @(posedge clk); while (!v_ready);
    @(negedge clk);
    v_req = 1'b0;
  endtask  // Automatic

  function automatic logic [XLEN-1:0] rand_addr();
    return XLEN'($urandom_range(Words - 1) << WordLsb);
  endfunction

  function automatic logic [DATA_W-1:0] rand_data();
    return DATA_W'({32'($urandom), 32'($urandom), 32'($urandom), 32'($urandom)});
  endfunction

  function automatic logic [StrbW-1:0] rand_strobe();
    logic [StrbW-1:0] choices[4] = '{'0, '0, '1, StrbW'('b0011)};
    return choices[$urandom_range($size(choices)-1)];
  endfunction

  task automatic s_random(input int n);
    for (int i = 0; i < n; i++) begin
      s_access(rand_addr(), rand_data(), rand_strobe());
      idle($urandom_range(2));
    end
  endtask  // Automatic

  task automatic v_random(input int n);
    for (int i = 0; i < n; i++) begin
      v_access(rand_addr(), rand_data(), rand_strobe());
      idle($urandom_range(2));
    end
  endtask  // Automatic

  task automatic both_random(input int n);
    fork
      s_random(n);
      v_random(n);
    join
  endtask  // Automatic

  task automatic same_cycle_request();
    fork
      s_access(XLEN'('h4), '0, '0);
      v_access(XLEN'('h8), '0, '0);
      check_first_grant(!last_vec);
    join
  endtask  // Automatic

  task automatic s_burst(input int n);
    for (int i = 0; i < n; i++) s_access(rand_addr(), rand_data(), rand_strobe());
  endtask  // Automatic

  task automatic v_burst(input int n);
    for (int i = 0; i < n; i++) v_access(rand_addr(), rand_data(), rand_strobe());
  endtask  // Automatic

  task automatic vector_behind_flood();
    fork
      s_burst(20);
      begin
        idle(3);
        v_access(rand_addr(), '0, '0);
      end
    join
  endtask  // Automatic

  task automatic scalar_behind_flood();
    fork
      v_burst(20);
      begin
        idle(3);
        s_access(rand_addr(), '0, '0);
      end
    join
  endtask  // Automatic

  task automatic scalar_behind_vector();
    fork
      v_access(XLEN'('hC), '0, '0);
      begin
        idle(1);
        s_access(XLEN'('h10), '0, '0);
      end
      check_first_grant(1'b1);
    join
  endtask  // Automatic

  task automatic check_memory();
    for (int i = 0; i < Words; i++) check("final word", mem[i], golden[i]);
  endtask  // Automatic

  task automatic check_first_grant(input logic exp_vec);
    do @(posedge clk); while (!(s_ready || v_ready));
    check("first grant vector", DATA_W'(v_ready), DATA_W'(exp_vec));
  endtask  // Automatic

  task automatic watchdog(input int n);
    repeat (n) @(posedge clk);
    $fatal(1, "FAIL: timeout, %0d mismatches, %0d checks", errors, checks);
  endtask  // Automatic

  task automatic finish();
    @(negedge clk);
    done = 1'b1;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial watchdog(Timeout);

  initial begin
    fill_memory();
    do_reset();

    // Instant memory
    set_latency(0, 0);
    same_cycle_request();
    both_random(500);

    // Slow memory
    set_latency(1, 4);
    same_cycle_request();
    set_latency(3, 3);
    idle(2);
    scalar_behind_vector();
    set_latency(1, 4);
    both_random(500);

    // Mixed latency
    set_latency(0, 3);
    s_random(100);
    v_random(100);
    both_random(1000);

    // Flood fairness
    vector_behind_flood();
    scalar_behind_flood();
    set_latency(0, 0);
    vector_behind_flood();
    scalar_behind_flood();

    check_memory();
    finish();
  end

  // Memory model
  function automatic logic [DATA_W-1:0] apply(
      input logic [DATA_W-1:0] old, input logic [DATA_W-1:0] d, input logic [StrbW-1:0] st);
    logic [DATA_W-1:0] result;
    result = old;
    for (int b = 0; b < StrbW; b++) if (st[b]) result[b*8+:8] = d[b*8+:8];
    return result;
  endfunction

  assign ready = m_busy ? (m_left == 0) : (req && m_next == 0);
  assign rdata = m_busy ? mem[m_addr[WordHi:WordLsb]] : mem[addr[WordHi:WordLsb]];

  always @(posedge clk) begin
    if (!rst_n) begin
      m_busy <= 1'b0;
      m_next <= 0;
    end else if (ready) begin
      if (m_busy)
        mem[m_addr[WordHi:WordLsb]] <= apply(mem[m_addr[WordHi:WordLsb]], m_wdata, m_wstrb);
      else mem[addr[WordHi:WordLsb]] <= apply(mem[addr[WordHi:WordLsb]], wdata, wstrb);
      m_busy <= 1'b0;
      m_next <= $urandom_range(lat_max, lat_min);
    end else if (!m_busy && req) begin
      m_busy  <= 1'b1;
      m_left  <= m_next - 1;
      m_addr  <= addr;
      m_wdata <= wdata;
      m_wstrb <= wstrb;
    end else if (m_busy) begin
      m_left <= m_left - 1;
    end else begin
      m_next <= $urandom_range(lat_max, lat_min);
    end
  end

  // Comparison
  always @(posedge clk) begin
    if (rst_n) begin
      check("one ready", DATA_W'(s_ready && v_ready), '0);
      check("scalar ready unasked", DATA_W'(s_ready && !s_req), '0);
      check("vector ready unasked", DATA_W'(v_ready && !v_req), '0);
      if (s_req && s_ready) begin
        if (s_wstrb == '0) check("scalar read", rdata, golden[s_addr[WordHi:WordLsb]]);
        golden[s_addr[WordHi:WordLsb]] = apply(golden[s_addr[WordHi:WordLsb]], s_wdata, s_wstrb);
        if (v_req) v_passed++;
        s_passed = 0;
        last_vec = 1'b0;
        check("vector wait bound", DATA_W'(v_passed > 1), '0);
      end
      if (v_req && v_ready) begin
        if (v_wstrb == '0) check("vector read", rdata, golden[v_addr[WordHi:WordLsb]]);
        golden[v_addr[WordHi:WordLsb]] = apply(golden[v_addr[WordHi:WordLsb]], v_wdata, v_wstrb);
        if (s_req) s_passed++;
        v_passed = 0;
        last_vec = 1'b1;
        check("scalar wait bound", DATA_W'(s_passed > 1), '0);
      end
    end
  end

endmodule

`default_nettype wire
