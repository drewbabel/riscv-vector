`default_nettype none

module mem_delay_tb ();

  localparam int MinChecks = 5 + 3000;

  int checks;
  int errors;
  int max_errors;
  int live_errors;

  mem_delay_bench pkg_bench ();

  mem_delay_bench #(
      .DEPTH  (256),
      .LATENCY(5)
  ) small_bench ();

  mem_delay_bench #(.DEPTH(4096)) short_bench ();

  mem_delay_bench #(.DEPTH(65536)) long_bench ();

  mem_delay_bench #(.LATENCY(5)) mid_bench ();

  task automatic check_floor(input string name, input int got, input int floor);
    if (got < floor)
      $fatal(1, "TB UNDER-RAN: %s %0d checks, expected at least %0d", name, got, floor);
  endtask  // Automatic

  task automatic do_verdict();
    checks = pkg_bench.checks + small_bench.checks + short_bench.checks + long_bench.checks +
        mid_bench.checks;
    errors = pkg_bench.errors + small_bench.errors + short_bench.errors + long_bench.errors +
        mid_bench.errors;
    check_floor("pkg_bench", pkg_bench.checks, MinChecks);
    check_floor("small_bench", small_bench.checks, MinChecks);
    check_floor("short_bench", short_bench.checks, MinChecks);
    check_floor("long_bench", long_bench.checks, MinChecks);
    check_floor("mid_bench", mid_bench.checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("mem_delay_tb.vcd");
    $dumpvars(0, mem_delay_tb);
    wait (pkg_bench.done && small_bench.done && short_bench.done && long_bench.done &&
          mid_bench.done);
    do_verdict();
  end

  always_comb
    live_errors = pkg_bench.errors + small_bench.errors + short_bench.errors + long_bench.errors +
        mid_bench.errors;

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (live_errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", live_errors);
    end
  end

endmodule

module mem_delay_bench #(
    parameter int DEPTH   = arch_pkg::MemWords,
    parameter int LATENCY = arch_pkg::MemLatency
) ();

  import cache_pkg::*;

  localparam int Xlen = arch_pkg::XLEN;
  localparam int Second = (LineWords > 1) ? 1 : 0;
  localparam int Depth = DEPTH;
  localparam int Latency = LATENCY;
  localparam int MaxWait = 100;
  localparam int SoakCycles = 3000;
  localparam int Lines = Depth / LineWords;
  localparam int LineIdxLen = $clog2(Lines);
  localparam int RstOdds = 400;
  localparam int BootOdds = 10;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;
  int waited = 0;

  logic clk = 1'b0;
  logic core_en;
  logic rst_n = 1'b1;

  logic req_valid;
  logic req_rw;
  logic [Xlen-1:0] req_addr;
  logic [LineBits-1:0] req_wdata;
  logic [LineBits-1:0] resp_rdata;
  logic resp_ready;

  logic boot_we;
  logic [Xlen-1:0] boot_addr;
  logic [Xlen-1:0] boot_wdata;

  // Cycle model
  logic m_busy = 1'b0;
  int m_cnt = 0;
  logic m_ready = 1'b0;
  logic m_done;
  logic m_rw_q;
  logic [Xlen-1:0] m_addr_q;
  logic [LineBits-1:0] m_wdata_q;
  logic [LineBits-1:0] m_rdata;
  logic [LineBits-1:0] m_mem[Lines];

  always #5 clk = ~clk;

  mem_delay #(
      .XLEN(Xlen),
      .DEPTH(Depth),
      .Latency(Latency)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .req_valid(req_valid),
      .req_rw(req_rw),
      .req_addr(req_addr),
      .req_wdata(req_wdata),
      .resp_rdata(resp_rdata),
      .resp_ready(resp_ready),
      .boot_we(boot_we),
      .boot_addr(boot_addr),
      .boot_wdata(boot_wdata)
  );

  task automatic check(input string name, input logic [LineBits-1:0] got,
                       input logic [LineBits-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %m %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    rst_n      = 1'b0;
    core_en    = 1'b1;
    req_valid  = 1'b0;
    req_rw     = 1'b0;
    req_addr   = '0;
    req_wdata  = '0;
    boot_we    = 1'b0;
    boot_addr  = '0;
    boot_wdata = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
  endtask  // Automatic

  task automatic boot_word(input logic [Xlen-1:0] addr, input logic [Xlen-1:0] data);
    boot_we    = 1'b1;
    boot_addr  = addr;
    boot_wdata = data;
    @(negedge clk);
    boot_we = 1'b0;
    @(negedge clk);
  endtask  // Automatic

  task automatic request(input logic rw, input logic [Xlen-1:0] addr,
                         input logic [LineBits-1:0] wdata);
    req_valid = 1'b1;
    req_rw    = rw;
    req_addr  = addr;
    req_wdata = wdata;
    waited    = 0;
    @(posedge clk);
    while (!resp_ready) begin
      waited++;
      @(posedge clk);
      if (waited > MaxWait) $fatal(1, "resp_ready never arrived");
    end
    @(negedge clk);
    req_valid = 1'b0;
    @(negedge clk);
  endtask  // Automatic

  task automatic check_read(input string name, input logic [Xlen-1:0] addr,
                            input logic [LineBits-1:0] exp);
    request(1'b0, addr, '0);
    check(name, resp_rdata, exp);
  endtask  // Automatic

  task automatic test_boot_line();
    for (int w = 0; w < LineWords; w++)
      boot_word(Xlen'(w * WordBytes), Xlen'('hAAAA_0000) + Xlen'(w));
    check_read("boot line", '0, line_of(Xlen'('hAAAA_0000)));
    check("latency", LineBits'(waited), LineBits'(Latency));
  endtask  // Automatic

  task automatic test_line_write();
    request(1'b1, Xlen'(LineBytes), line_of(Xlen'('hBBBB_0000)));
    check_read("line write", Xlen'(LineBytes), line_of(Xlen'('hBBBB_0000)));
    check_read("untouched", Xlen'(2 * LineBytes), '0);
  endtask  // Automatic

  task automatic test_word_select();
    request(1'b0, Xlen'(LineBytes + Second * WordBytes), '0);
    check("word select", LineBits'(resp_rdata[Second*Xlen+:Xlen]),
          LineBits'(Xlen'('hBBBB_0000) + Xlen'(Second)));
  endtask  // Automatic

  task automatic model_init();
    for (int i = 0; i < Lines; i++) m_mem[i] = '0;
  endtask  // Automatic

  task automatic test_soak();
    logic pending;
    pending = 1'b0;
    for (int i = 0; i < SoakCycles; i++) begin
      @(negedge clk);
      rst_n      = $urandom_range(RstOdds - 1) != 0;
      core_en    = $urandom_range(4) != 0;
      boot_we    = $urandom_range(BootOdds - 1) == 0;
      boot_addr  = 1'($urandom) ? req_addr : rand_addr();
      boot_wdata = Xlen'($urandom);
      if (!pending) begin
        pending   = $urandom_range(2) != 0;
        req_valid = pending;
        req_rw    = 1'($urandom);
        req_addr  = rand_addr();
        req_wdata = rand_line();
      end
      #1;
      check("soak ready", LineBits'(resp_ready), LineBits'(m_ready));
      if (pending && resp_ready && core_en) begin
        if (!req_rw) check("soak rdata", resp_rdata, m_rdata);
        pending = 1'b0;
      end
    end
    @(negedge clk);
    rst_n     = 1'b1;
    core_en   = 1'b1;
    boot_we   = 1'b0;
    req_valid = 1'b0;
  endtask  // Automatic

  task automatic finish();
    @(negedge clk);
    done = 1'b1;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    model_init();
    do_reset();

    test_boot_line();
    test_line_write();
    test_word_select();
    test_soak();

    finish();
  end

  function automatic logic [Xlen-1:0] rand_addr();
    rand_addr = Xlen'($urandom);
    if ($urandom_range(3) != 0) rand_addr[IdxLsb+:LineIdxLen] = LineIdxLen'($urandom_range(15));
  endfunction

  function automatic logic [LineBits-1:0] rand_line();
    for (int w = 0; w < LineWords; w++) rand_line[w*Xlen+:Xlen] = Xlen'($urandom);
  endfunction

  function automatic int word_of(input logic [Xlen-1:0] addr);
    return int'((addr >> WordLsb) % LineWords);
  endfunction

  always @(posedge clk) begin
    m_done = m_busy && (m_cnt >= Latency - 1);
    if (core_en && m_done) m_rdata = m_mem[m_addr_q[IdxLsb+:LineIdxLen]];
    if (core_en && boot_we)
      m_mem[boot_addr[IdxLsb+:LineIdxLen]][word_of(boot_addr)*Xlen+:Xlen] = boot_wdata;
    else if (core_en && m_done && m_rw_q) m_mem[m_addr_q[IdxLsb+:LineIdxLen]] = m_wdata_q;
    if (!rst_n) begin
      m_busy  = 1'b0;
      m_cnt   = 0;
      m_ready = 1'b0;
    end else if (core_en) begin
      if (boot_we) begin
        m_busy = 1'b0;
      end else if (!m_busy) begin
        if (req_valid && !m_ready) begin
          m_busy    = 1'b1;
          m_cnt     = 1;
          m_rw_q    = req_rw;
          m_addr_q  = req_addr;
          m_wdata_q = req_wdata;
        end
      end else if (m_done) begin
        m_busy = 1'b0;
      end else begin
        m_cnt++;
      end
      m_ready = !boot_we && m_done;
    end
  end

  function automatic logic [LineBits-1:0] line_of(input logic [Xlen-1:0] seed);
    for (int w = 0; w < LineWords; w++) line_of[w*Xlen+:Xlen] = seed + Xlen'(w);
  endfunction

endmodule

`default_nettype wire
