`default_nettype none

module boot_loader_tb ();

  localparam int MinChecks = 450000;
  localparam int MinClampChecks = 390000;
  localparam int MinShortChecks = 415000;
  localparam int Depth = 20000;
  localparam int SmallDepth = 32;
  localparam int DefaultDepth = 16384;
  localparam int ShortDepth = 4096;
  localparam int LongDepth = 65536;
  localparam int Words = 16400;
  // Comparator bit window
  localparam int DeepWords = 19712;

  int checks;
  int errors;
  int max_errors;
  int live_errors;

  boot_loader_bench #(
      .DEPTH(Depth),
      .WORDS(DeepWords),
      .CLAMP(Depth + 1)
  ) deep_bench ();

  // Depth clamps load
  boot_loader_bench #(
      .DEPTH(SmallDepth),
      .WORDS(Words)
  ) small_bench ();

  boot_loader_bench #(
      .DEPTH(DefaultDepth),
      .WORDS(Words)
  ) default_bench ();

  boot_loader_bench #(
      .DEPTH(ShortDepth),
      .WORDS(Words)
  ) short_bench ();

  boot_loader_bench #(
      .DEPTH(LongDepth),
      .WORDS(Words)
  ) long_bench ();

  task automatic check_floor(input string name, input int got, input int floor);
    if (got < floor)
      $fatal(1, "TB UNDER-RAN: %s %0d checks, expected at least %0d", name, got, floor);
  endtask  // Automatic

  task automatic do_verdict();
    checks = deep_bench.checks + small_bench.checks + default_bench.checks + short_bench.checks +
        long_bench.checks;
    errors = deep_bench.errors + small_bench.errors + default_bench.errors + short_bench.errors +
        long_bench.errors;
    check_floor("deep_bench", deep_bench.checks, MinChecks);
    check_floor("small_bench", small_bench.checks, MinClampChecks);
    check_floor("default_bench", default_bench.checks, MinChecks);
    check_floor("short_bench", short_bench.checks, MinShortChecks);
    check_floor("long_bench", long_bench.checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("boot_loader_tb.vcd");
    $dumpvars(0, boot_loader_tb);
    wait (deep_bench.done && small_bench.done && default_bench.done && short_bench.done &&
          long_bench.done);
    do_verdict();
  end

  always_comb
    live_errors = deep_bench.errors + small_bench.errors + default_bench.errors +
        short_bench.errors + long_bench.errors;

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (live_errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", live_errors);
    end
  end

endmodule

module boot_loader_bench #(
    parameter int DEPTH = 16384,
    parameter int WORDS = 16400,
    parameter int CLAMP = 0
) ();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int WordBytes = XLEN / 8;
  localparam int DataBits = arch_pkg::UartDataBits;
  localparam int Frames = XLEN / DataBits;
  localparam int OldCap = 16384;
  localparam int Loads = (WORDS < DEPTH) ? WORDS : DEPTH;
  localparam int PartWords = 12;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;

  logic clk = 1'b0;
  logic rst_n = 1'b1;
  logic core_en = 1'b1;
  logic rx_valid;
  logic [DataBits-1:0] rx_data;
  logic we;
  logic [XLEN-1:0] waddr;
  logic [XLEN-1:0] wdata;
  logic loading;

  logic [XLEN-1:0] prog[];
  logic [XLEN-1:0] write_idx = '0;
  int gap_pct = 0;
  int stall_pct = 0;
  logic from_prog = 1'b1;

  logic model_on = 1'b0;
  logic model_done;
  int model_bytes;
  logic [XLEN-1:0] model_acc;
  logic [XLEN-1:0] model_limit;

  always #5 clk = ~clk;

  boot_loader #(
      .XLEN (XLEN),
      .DEPTH(DEPTH)
  ) dut (
      .clk     (clk),
      .core_en (core_en),
      .rst_n   (rst_n),
      .rx_valid(rx_valid),
      .rx_data (rx_data),
      .we      (we),
      .waddr   (waddr),
      .wdata   (wdata),
      .loading (loading)
  );

  task automatic check(input string name, input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL DEPTH %0d %s: got %h, expected %h", DEPTH, name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    rst_n    = 1'b0;
    core_en  = 1'b1;
    rx_valid = 1'b0;
    rx_data  = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic random_cycle();
    core_en = $urandom_range(99) >= stall_pct;
    @(negedge clk);
  endtask  // Automatic

  task automatic send_byte(input logic [DataBits-1:0] data);
    while ($urandom_range(99) < gap_pct) random_cycle();
    rx_data  = data;
    rx_valid = 1'b1;
    do begin
      core_en = $urandom_range(99) >= stall_pct;
      @(negedge clk);
    end while (!core_en);
    rx_valid = 1'b0;
    core_en  = 1'b1;
  endtask  // Automatic

  task automatic send_word(input logic [XLEN-1:0] w);
    for (int j = 0; j < XLEN; j += DataBits) send_byte(w[j+:DataBits]);
  endtask  // Automatic

  // Past old cap
  task automatic build_prog(input int n);
    prog = new[n];
    prog[0] = XLEN'('hAABB_CCDD);
    for (int i = 1; i < n; i++) prog[i] = XLEN'($urandom);
    if (n > OldCap) begin
      prog[OldCap-1] = XLEN'('h1234_5678);
      prog[OldCap]   = XLEN'('h9ABC_DEF0);
    end
  endtask  // Automatic

  task automatic load_data();
    send_word(XLEN'(prog.size()));
    for (int i = 0; i < prog.size(); i++) send_word(prog[i]);
  endtask  // Automatic

  task automatic check_finished();
    repeat (2) @(posedge clk);
    check("loading", XLEN'(loading), '0);
    check("write_idx", write_idx, XLEN'(Loads));
  endtask  // Automatic

  // Bytes after done
  task automatic trailing_bytes();
    send_word(XLEN'($urandom));
    send_word(XLEN'($urandom));
    repeat (4) @(negedge clk);
  endtask  // Automatic

  // Header then words
  task automatic load_count(input logic [XLEN-1:0] count, input int words, input int pause);
    do_reset();
    send_word(count);
    core_en = 1'b0;
    repeat (pause) @(negedge clk);
    core_en = 1'b1;
    for (int i = 0; i < words; i++) send_word(XLEN'($urandom));
    repeat (4) @(negedge clk);
  endtask  // Automatic

  task automatic load_exact(input logic [XLEN-1:0] count, input int pause);
    int lim = (count > XLEN'(DEPTH)) ? DEPTH : int'(count);
    load_count(count, lim + 2, pause);
  endtask  // Automatic

  // Both stall parities
  task automatic parity_pair(input logic [XLEN-1:0] count);
    load_exact(count, 0);
    load_exact(count, 1);
  endtask  // Automatic

  task automatic load_part(input logic [XLEN-1:0] count);
    int lim = (count > XLEN'(DEPTH)) ? DEPTH : int'(count);
    load_count(count, (lim < PartWords) ? lim + 2 : PartWords, 0);
  endtask  // Automatic

  // Count each bit
  task automatic count_bits();
    for (int b = 0; b < XLEN; b++) load_part((XLEN'(1) << b) | XLEN'(3));
    for (int i = 0; i < 8; i++) load_part(XLEN'($urandom));
  endtask  // Automatic

  task automatic mark_done();
    done = 1'b1;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    do_reset();
    gap_pct   = 5;
    stall_pct = 5;
    build_prog(WORDS);
    load_data();
    check_finished();
    trailing_bytes();
    from_prog = 1'b0;
    gap_pct   = 25;
    stall_pct = 25;
    load_exact(0, 0);
    load_exact(5, 0);
    count_bits();
    gap_pct   = 0;
    stall_pct = 0;
    parity_pair(256);
    parity_pair(4100);
    if (CLAMP > 0) begin
      gap_pct   = 5;
      stall_pct = 5;
      load_exact(CLAMP, 0);
    end
    mark_done();
  end

  // Reference model
  always @(posedge clk) begin
    if (model_on) check("loading", XLEN'(loading), XLEN'(!model_done));
    if (!rst_n) begin
      model_on = 1'b1;
      model_done = 1'b0;
      model_bytes = 0;
    end else if (model_on && core_en) begin
      logic exp_we;
      exp_we = rx_valid && (model_bytes >= Frames) && !model_done &&
          (model_bytes % Frames == Frames - 1);
      check("we", XLEN'(we), XLEN'(exp_we));
      if (we) begin
        check("waddr", waddr, write_idx * WordBytes);
        check("wdata", wdata, {rx_data, model_acc[XLEN-1:DataBits]});
        if (from_prog) check("prog", wdata, prog[write_idx]);
      end
      if ((model_bytes >= Frames) && !model_done && (write_idx == model_limit)) model_done = 1'b1;
      if (rx_valid) begin
        model_acc = {rx_data, model_acc[XLEN-1:DataBits]};
        if (model_bytes == Frames - 1)
          model_limit = (model_acc > XLEN'(DEPTH)) ? XLEN'(DEPTH) : model_acc;
        model_bytes++;
      end
      if (we) write_idx++;
    end
    if (!rst_n) write_idx = '0;
  end

endmodule

`default_nettype wire
