`default_nettype none

module board_top_tb ();

  localparam int MinChecks = 3;
  localparam int MinBramChecks = 4000;

  int checks;
  int errors;
  int max_errors;
  int live_errors;

  board_top_bench #(
      .DEPTH  (1024),
      .CLK_DIV(32)
  ) slow_bench ();

  board_top_bench core_bench ();

  board_top_bench #(
      .DEPTH  (4096),
      .PRELOAD(1'b1)
  ) short_bench ();

  board_top_bench #(
      .DEPTH  (65536),
      .PRELOAD(1'b1)
  ) long_bench ();

  bram_sdp_bench bram_bench ();

  bram_sdp_bench #(.WIDTH(1)) bit_bench ();

  bram_sdp_bench #(.WIDTH(32)) word_bench ();

  bram_sdp_bench #(.DEPTH(16)) shallow_bench ();

  bram_sdp_bench #(.DEPTH(1024)) deep_bench ();

  bram_sdp_bench #(.BLOCK(1'b0)) dist_bench ();

  task automatic check_floor(input string name, input int got, input int floor);
    if (got < floor)
      $fatal(1, "TB UNDER-RAN: %s %0d checks, expected at least %0d", name, got, floor);
  endtask  // Automatic

  task automatic do_verdict();
    checks = slow_bench.checks + core_bench.checks + short_bench.checks + long_bench.checks +
        bram_bench.checks + bit_bench.checks + word_bench.checks + shallow_bench.checks +
        deep_bench.checks + dist_bench.checks;
    errors = slow_bench.errors + core_bench.errors + short_bench.errors + long_bench.errors +
        bram_bench.errors + bit_bench.errors + word_bench.errors + shallow_bench.errors +
        deep_bench.errors + dist_bench.errors;
    check_floor("slow_bench", slow_bench.checks, MinChecks);
    check_floor("core_bench", core_bench.checks, MinChecks);
    check_floor("short_bench", short_bench.checks, MinChecks);
    check_floor("long_bench", long_bench.checks, MinChecks);
    check_floor("bram_bench", bram_bench.checks, MinBramChecks);
    check_floor("bit_bench", bit_bench.checks, MinBramChecks);
    check_floor("word_bench", word_bench.checks, MinBramChecks);
    check_floor("shallow_bench", shallow_bench.checks, MinBramChecks);
    check_floor("deep_bench", deep_bench.checks, MinBramChecks);
    check_floor("dist_bench", dist_bench.checks, MinBramChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("board_top_tb.vcd");
    $dumpvars(0, board_top_tb);
    wait (slow_bench.done && core_bench.done && short_bench.done && long_bench.done &&
          bram_bench.done && bit_bench.done && word_bench.done && shallow_bench.done &&
          deep_bench.done && dist_bench.done);
    do_verdict();
  end

  always_comb
    live_errors = slow_bench.errors + core_bench.errors + short_bench.errors + long_bench.errors +
        bram_bench.errors + bit_bench.errors + word_bench.errors + shallow_bench.errors +
        deep_bench.errors + dist_bench.errors;

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (live_errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", live_errors);
    end
  end

endmodule

module board_top_bench #(
    parameter int DEPTH   = arch_pkg::MemWords,
    parameter int CLK_DIV = arch_pkg::ClkDiv,
    parameter bit PRELOAD = 1'b0
) ();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int FastClkHz = arch_pkg::BoardClkHz;
  localparam int ClkDiv = CLK_DIV;
  localparam int CoreClkHz = FastClkHz / ClkDiv;
  localparam int BaudRate = arch_pkg::BaudRate;
  localparam int Depth = DEPTH;
  localparam int ResetCycles = 200;
  localparam int LedWait = 60_000;

  // Bit period
  localparam int ClksPerBit = (FastClkHz + BaudRate / 2) / BaudRate;

  localparam int NWords = 12;
  localparam int LineWords = cache_pkg::LineWords;
  localparam int IdxW = $clog2(Depth / LineWords);
  localparam int ProgLines = (NWords + LineWords - 1) / LineWords;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;

  logic clk = 1'b0;
  logic rst = 1'b1;
  logic [15:0] sw;
  logic [15:0] led;
  logic uart_rx = 1'b1;
  logic uart_tx;

  localparam int LedW = $bits(led);
  localparam logic [LedW-1:0] LoadingLed = LedW'('h5555);
  localparam logic [LedW-1:0] MemtestLed = LedW'('hABCD);

  logic [XLEN-1:0] prog[NWords];

  always #5 if (!done) clk = ~clk;

  board_top #(
      .DEPTH (Depth),
      .ClkDiv(ClkDiv)
  ) dut (
      .clk    (clk),
      .rst    (rst),
      .sw     (sw),
      .led    (led),
      .uart_rx(uart_rx),
      .uart_tx(uart_tx)
  );

  task automatic check(input string name, input logic [LedW-1:0] got, input logic [LedW-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %m %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    rst     = 1'b1;
    sw      = '0;
    uart_rx = 1'b1;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    repeat (ResetCycles) @(negedge clk);
  endtask  // Automatic

  task automatic load_image();
    $readmemh("tests/memtest.hex", prog);
    if ($isunknown(prog[0]) || prog[0] == '0)
      $fatal(1, "memtest.hex missing or empty, run make hex PROG=memtest");
  endtask  // Automatic

  task automatic send_byte(input logic [7:0] b);
    uart_rx = 1'b0;
    repeat (ClksPerBit) @(negedge clk);
    for (int i = 0; i < $bits(b); i++) begin
      uart_rx = b[i];
      repeat (ClksPerBit) @(negedge clk);
    end
    uart_rx = 1'b1;
    repeat (ClksPerBit) @(negedge clk);
  endtask  // Automatic

  task automatic send_word(input logic [XLEN-1:0] w);
    for (int j = 0; j < XLEN; j += 8) send_byte(w[j+:8]);
  endtask  // Automatic

  task automatic preload();
    logic [cache_pkg::LineBits-1:0] pline;
    for (int l = 0; l < ProgLines; l++) begin
      for (int w = 0; w < LineWords; w++)
      pline[XLEN*w+:XLEN] = (l * LineWords + w < NWords) ? prog[l*LineWords+w] : '0;
      @(negedge clk);
      dut.imem_inst.u_line.bd_idx  = IdxW'(l);
      dut.imem_inst.u_line.bd_data = pline;
      dut.imem_inst.u_line.bd_we   = 1'b1;
      dut.dmem_inst.u_line.bd_idx  = IdxW'(l);
      dut.dmem_inst.u_line.bd_data = pline;
      dut.dmem_inst.u_line.bd_we   = 1'b1;
    end
    @(negedge clk);
    dut.imem_inst.u_line.bd_we = 1'b0;
    dut.dmem_inst.u_line.bd_we = 1'b0;
  endtask  // Automatic

  task automatic boot_program();
    check("loading led", led, LoadingLed);
    if (PRELOAD) begin
      preload();
      send_word('0);
    end else begin
      send_word(XLEN'(NWords));
      for (int i = 0; i < NWords; i++) send_word(prog[i]);
    end
  endtask  // Automatic

  task automatic wait_led(input logic [LedW-1:0] exp, input int cycles);
    int i = 0;
    while (led !== exp && i < cycles) begin
      @(negedge clk);
      i++;
    end
  endtask  // Automatic

  task automatic wait_loaded();
    while (led === LoadingLed) @(negedge clk);
  endtask  // Automatic

  task automatic check_leds();
    wait_loaded();
    wait_led(MemtestLed, LedWait);
    check("led", led, MemtestLed);
    wait_led(LedW'(CoreClkHz), LedWait);
    check("core_clk_hz", led, LedW'(CoreClkHz));
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  // Word round trip
  initial begin
    load_image();
    do_reset();

    boot_program();
    check_leds();

    done = 1'b1;
  end

endmodule

module bram_sdp_bench #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 256,
    parameter bit BLOCK = 1'b1
) ();

  localparam int AddrW = $clog2(DEPTH);
  localparam int Lanes = (WIDTH + 7) / 8;
  localparam int RandomOps = 4000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;

  logic clk = 1'b0;
  logic we;
  logic [Lanes-1:0] wlane;
  logic [AddrW-1:0] widx;
  logic [WIDTH-1:0] wdata;
  logic re;
  logic [AddrW-1:0] ridx;
  logic [WIDTH-1:0] rdata;

  logic [WIDTH-1:0] shadow[DEPTH];
  logic [WIDTH-1:0] exp_rdata;

  always #5 if (!done) clk = ~clk;

  bram_sdp #(
      .Width(WIDTH),
      .Depth(DEPTH),
      .Block(BLOCK)
  ) dut (
      .clk  (clk),
      .we   (we),
      .wlane(wlane),
      .widx (widx),
      .wdata(wdata),
      .re   (re),
      .ridx (ridx),
      .rdata(rdata)
  );

  task automatic check(input string name, input logic [WIDTH-1:0] got, input logic [WIDTH-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %m %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    we    = 1'b0;
    wlane = '0;
    widx  = '0;
    wdata = '0;
    re    = 1'b0;
    ridx  = '0;
    for (int i = 0; i < DEPTH; i++) shadow[i] = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
  endtask  // Automatic

  function automatic logic [WIDTH-1:0] lane_mask(input logic [Lanes-1:0] lanes);
    logic [WIDTH-1:0] m;
    for (int b = 0; b < WIDTH; b++) m[b] = lanes[b/8];
    return m;
  endfunction

  function automatic logic [WIDTH-1:0] rand_data();
    return WIDTH'({$urandom, $urandom});
  endfunction

  task automatic step(input string name, input logic w, input logic [Lanes-1:0] lanes,
                      input logic [AddrW-1:0] wi, input logic [WIDTH-1:0] wd, input logic r,
                      input logic [AddrW-1:0] ri);
    logic [WIDTH-1:0] m;
    we    = w;
    wlane = lanes;
    widx  = wi;
    wdata = wd;
    re    = r;
    ridx  = ri;
    @(posedge clk);
    if (r) exp_rdata = shadow[ri];
    if (w) begin
      m = lane_mask(lanes);
      shadow[wi] = (shadow[wi] & ~m) | (wd & m);
    end
    @(negedge clk);
    check(name, rdata, exp_rdata);
    we = 1'b0;
    re = 1'b0;
  endtask  // Automatic

  task automatic read(input string name, input logic [AddrW-1:0] ri);
    step(name, 1'b0, '0, '0, '0, 1'b1, ri);
  endtask  // Automatic

  task automatic write(input logic [Lanes-1:0] lanes, input logic [AddrW-1:0] wi,
                       input logic [WIDTH-1:0] wd);
    step("hold during write", 1'b1, lanes, wi, wd, 1'b0, '0);
  endtask  // Automatic

  task automatic test_zero_init();
    for (int i = 0; i < DEPTH; i++) read("zero init", AddrW'(i));
  endtask  // Automatic

  task automatic test_fill();
    for (int i = 0; i < DEPTH; i++) write('1, AddrW'(i), rand_data());
    for (int i = 0; i < DEPTH; i++) read("fill readback", AddrW'(i));
  endtask  // Automatic

  task automatic test_lanes();
    for (int b = 0; b < Lanes; b++) begin
      write('1, AddrW'(b), '0);
      write(Lanes'(1) << b, AddrW'(b), '1);
      read("single lane write", AddrW'(b));
    end
  endtask  // Automatic

  task automatic test_read_hold();
    read("hold source", AddrW'(DEPTH - 1));
    for (int i = 0; i < 4; i++) step("held while re low", 1'b0, '0, '0, '0, 1'b0, AddrW'(i));
    write('1, AddrW'(DEPTH - 1), rand_data());
    step("held after write", 1'b0, '0, '0, '0, 1'b0, AddrW'(DEPTH - 1));
    read("written word", AddrW'(DEPTH - 1));
  endtask  // Automatic

  task automatic test_read_during_write();
    for (int i = 0; i < 8; i++)
      step("old data on collision", 1'b1, '1, AddrW'(i), rand_data(), 1'b1, AddrW'(i));
    for (int i = 0; i < 8; i++) read("collision landed", AddrW'(i));
  endtask  // Automatic

  task automatic test_random(input int n);
    repeat (n)
      step("random", 1'($urandom), Lanes'($urandom), AddrW'($urandom), rand_data(), 1'($urandom),
           AddrW'($urandom));
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    do_reset();
    exp_rdata = '0;

    test_zero_init();
    test_fill();
    test_lanes();
    test_read_hold();
    test_read_during_write();
    test_random(RandomOps);

    done = 1'b1;
  end

endmodule

`default_nettype wire
