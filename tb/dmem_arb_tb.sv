`default_nettype none

module dmem_arb_tb ();

  localparam int XLEN = 32;
  localparam int Words = 16;
  localparam int Timeout = 200000;

  int checks = 0;
  int errors = 0;

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  logic s_req = 1'b0;
  logic [XLEN-1:0] s_addr = '0;
  logic [XLEN-1:0] s_wdata = '0;
  logic [3:0] s_wstrb = '0;
  logic s_ready;

  logic v_req = 1'b0;
  logic [XLEN-1:0] v_addr = '0;
  logic [XLEN-1:0] v_wdata = '0;
  logic [3:0] v_wstrb = '0;
  logic v_ready;

  logic req;
  logic [XLEN-1:0] addr;
  logic [XLEN-1:0] wdata;
  logic [3:0] wstrb;
  logic ready;
  logic [XLEN-1:0] rdata;

  int lat_min = 0;
  int lat_max = 0;

  logic [XLEN-1:0] mem[Words];
  logic [XLEN-1:0] golden[Words];

  logic last_vec = 1'b1;
  int s_passed = 0;
  int v_passed = 0;

  logic m_busy;
  int m_left;
  int m_next;
  logic [XLEN-1:0] m_addr;
  logic [XLEN-1:0] m_wdata;
  logic [3:0] m_wstrb;

  always #5 clk = ~clk;

  dmem_arb #(
      .XLEN(XLEN)
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
  task automatic check(input string name, input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("%s: got %h, expected %h", name, got, exp);
    end
  endtask  // Automatic

  task automatic check_memory();
    for (int i = 0; i < Words; i++) check("final word", mem[i], golden[i]);
  endtask  // Automatic

  task automatic check_first_grant(input logic exp_vec);
    @(negedge clk);
    while (!(s_ready || v_ready)) @(negedge clk);
    check("first grant vector", 32'(v_ready), 32'(exp_vec));
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

  task automatic set_latency(input int lo, input int hi);
    lat_min = lo;
    lat_max = hi;
  endtask  // Automatic

  task automatic fill_memory();
    for (int i = 0; i < Words; i++) begin
      mem[i] = XLEN'($urandom);
      golden[i] = mem[i];
    end
  endtask  // Automatic

  task automatic s_access(input logic [XLEN-1:0] a, input logic [XLEN-1:0] d,
                          input logic [3:0] st);
    #1;
    s_req = 1'b1;
    s_addr = a;
    s_wdata = d;
    s_wstrb = st;
    @(negedge clk);
    while (!s_ready) @(negedge clk);
    @(posedge clk);
    #1;
    s_req = 1'b0;
  endtask  // Automatic

  task automatic v_access(input logic [XLEN-1:0] a, input logic [XLEN-1:0] d,
                          input logic [3:0] st);
    #1;
    v_req = 1'b1;
    v_addr = a;
    v_wdata = d;
    v_wstrb = st;
    @(negedge clk);
    while (!v_ready) @(negedge clk);
    @(posedge clk);
    #1;
    v_req = 1'b0;
  endtask  // Automatic

  function automatic logic [XLEN-1:0] rand_addr();
    return XLEN'({$urandom_range(Words - 1), 2'b00});
  endfunction

  function automatic logic [3:0] rand_strobe();
    logic [3:0] choices[4] = '{4'h0, 4'h0, 4'hF, 4'b0011};
    return choices[$urandom_range(3)];
  endfunction

  task automatic s_random(input int n);
    for (int i = 0; i < n; i++) begin
      s_access(rand_addr(), XLEN'($urandom), rand_strobe());
      repeat ($urandom_range(2)) @(posedge clk);
    end
  endtask  // Automatic

  task automatic v_random(input int n);
    for (int i = 0; i < n; i++) begin
      v_access(rand_addr(), XLEN'($urandom), rand_strobe());
      repeat ($urandom_range(2)) @(posedge clk);
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
      s_access(32'h0000_0004, 32'h0, 4'h0);
      v_access(32'h0000_0008, 32'h0, 4'h0);
      check_first_grant(!last_vec);
    join
  endtask  // Automatic

  task automatic s_burst(input int n);
    for (int i = 0; i < n; i++) s_access(rand_addr(), XLEN'($urandom), rand_strobe());
  endtask  // Automatic

  task automatic v_burst(input int n);
    for (int i = 0; i < n; i++) v_access(rand_addr(), XLEN'($urandom), rand_strobe());
  endtask  // Automatic

  task automatic vector_behind_flood();
    fork
      s_burst(20);
      begin
        repeat (3) @(posedge clk);
        v_access(rand_addr(), 32'h0, 4'h0);
      end
    join
  endtask  // Automatic

  task automatic scalar_behind_flood();
    fork
      v_burst(20);
      begin
        repeat (3) @(posedge clk);
        s_access(rand_addr(), 32'h0, 4'h0);
      end
    join
  endtask  // Automatic

  task automatic scalar_behind_vector();
    fork
      v_access(32'h0000_000C, 32'h0, 4'h0);
      begin
        @(posedge clk);
        s_access(32'h0000_0010, 32'h0, 4'h0);
      end
      check_first_grant(1'b1);
    join
  endtask  // Automatic

  // Memory model
  function automatic logic [XLEN-1:0] apply(input logic [XLEN-1:0] old, input logic [XLEN-1:0] d,
                                            input logic [3:0] st);
    logic [XLEN-1:0] result;
    result = old;
    for (int b = 0; b < 4; b++) if (st[b]) result[b*8+:8] = d[b*8+:8];
    return result;
  endfunction

  assign ready = m_busy ? (m_left == 0) : (req && m_next == 0);
  assign rdata = m_busy ? mem[m_addr[5:2]] : mem[addr[5:2]];

  always @(posedge clk) begin
    if (!rst_n) begin
      m_busy <= 1'b0;
      m_next <= 0;
    end else if (ready) begin
      if (m_busy) mem[m_addr[5:2]] <= apply(mem[m_addr[5:2]], m_wdata, m_wstrb);
      else mem[addr[5:2]] <= apply(mem[addr[5:2]], wdata, wstrb);
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
  always @(negedge clk) begin
    if (rst_n) begin
      check("one ready", 32'(s_ready && v_ready), 32'h0);
      check("scalar ready unasked", 32'(s_ready && !s_req), 32'h0);
      check("vector ready unasked", 32'(v_ready && !v_req), 32'h0);
      if (s_req && s_ready) begin
        if (s_wstrb == 4'h0) check("scalar read", rdata, golden[s_addr[5:2]]);
        golden[s_addr[5:2]] = apply(golden[s_addr[5:2]], s_wdata, s_wstrb);
        if (v_req) v_passed++;
        s_passed = 0;
        last_vec = 1'b0;
        check("vector wait bound", 32'(v_passed > 1), 32'h0);
      end
      if (v_req && v_ready) begin
        if (v_wstrb == 4'h0) check("vector read", rdata, golden[v_addr[5:2]]);
        golden[v_addr[5:2]] = apply(golden[v_addr[5:2]], v_wdata, v_wstrb);
        if (s_req) s_passed++;
        v_passed = 0;
        last_vec = 1'b1;
        check("scalar wait bound", 32'(s_passed > 1), 32'h0);
      end
    end
  end

  initial begin
    repeat (Timeout) @(posedge clk);
    $fatal(1, "FAIL: timeout, %0d mismatches, %0d checks", errors, checks);
  end

  initial begin
    $dumpfile("dmem_arb_tb.vcd");
    $dumpvars(0, dmem_arb_tb);
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
    repeat (2) @(posedge clk);
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
    verdict();
  end

endmodule

`default_nettype wire
