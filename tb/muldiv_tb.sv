`default_nettype none

module muldiv_tb
  import muldiv_pkg::*;
();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int MaxCycles = XLEN + 4;
  localparam int NumOps = 8;
  localparam int MinChecks = 100000;
  localparam logic [XLEN-1:0] MinNeg = {1'b1, {(XLEN - 1) {1'b0}}};

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int stall_pct = 0;

  logic clk = 1'b0;
  logic core_en;
  logic rst_n;
  logic start;
  muldiv_op_e op;
  logic [XLEN-1:0] a;
  logic [XLEN-1:0] b;
  logic [XLEN-1:0] result;
  logic busy;
  logic done;

  muldiv #(
      .XLEN(XLEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .start(start),
      .op(op),
      .a(a),
      .b(b),
      .result(result),
      .busy(busy),
      .done(done)
  );

  always #5 clk = ~clk;

  initial void'($value$plusargs("max_errors=%d", max_errors));

  task automatic check(input string name, input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    rst_n = 1'b0;
    core_en = 1'b1;
    start = 1'b0;
    op = MD_MUL;
    a = '0;
    b = '0;
    repeat (2) @(posedge clk);
    #1;
    rst_n = 1'b1;
    check("reset busy", XLEN'(busy), '0);
    check("reset done", XLEN'(done), '0);
    check("reset result", result, '0);
  endtask  // Automatic

  task automatic stall_edges();
    while ($urandom_range(
        99
    ) < stall_pct) begin
      logic [XLEN-1:0] r;
      logic bz;
      logic dn;
      r = result;
      bz = busy;
      dn = done;
      core_en = 1'b0;
      start = 1'($urandom);
      a = XLEN'($urandom);
      b = XLEN'($urandom);
      @(posedge clk);
      #1;
      check("stall result", result, r);
      check("stall busy", XLEN'(busy), XLEN'(bz));
      check("stall done", XLEN'(done), XLEN'(dn));
      core_en = 1'b1;
      start   = 1'b0;
    end
  endtask  // Automatic

  task automatic run_op(input muldiv_op_e o, input logic [XLEN-1:0] x, input logic [XLEN-1:0] y);
    logic [XLEN-1:0] exp;
    string tag;
    int n;
    exp = md_ref(o, x, y);
    tag = $sformatf("%s a=%h b=%h", o.name(), x, y);
    stall_edges();
    op = o;
    a = x;
    b = y;
    start = 1'b1;
    @(posedge clk);
    #1;
    start = 1'b0;
    op = muldiv_op_e'($urandom);
    a = XLEN'($urandom);
    b = XLEN'($urandom);
    n = 0;
    while (!done) begin
      check({tag, " busy"}, XLEN'(busy), XLEN'(1'b1));
      stall_edges();
      @(posedge clk);
      #1;
      n++;
      if (n > MaxCycles) begin
        check({tag, " timeout"}, XLEN'(done), XLEN'(1'b1));
        return;
      end
    end
    check({tag, " latency bound"}, XLEN'(n <= latency_ref(o, x, y)), XLEN'(1'b1));
    check({tag, " busy at done"}, XLEN'(busy), XLEN'(1'b0));
    check({tag, " result"}, result, exp);
    stall_edges();
    @(posedge clk);
    #1;
    check({tag, " done pulse"}, XLEN'(done), XLEN'(1'b0));
    check({tag, " busy after"}, XLEN'(busy), XLEN'(1'b0));
    check({tag, " result held"}, result, exp);
    stall_edges();
    @(posedge clk);
    #1;
    check({tag, " idle done"}, XLEN'(done), XLEN'(1'b0));
    check({tag, " result idle"}, result, exp);
  endtask  // Automatic

  function automatic logic [XLEN-1:0] operand();
    case ($urandom_range(
        7
    ))
      0: return '0;
      1: return '1;
      2: return MinNeg;
      3: return ~MinNeg;
      4: return XLEN'($urandom_range(15));
      5: return -XLEN'($urandom_range(15));
      6: return XLEN'(1) << $urandom_range(XLEN - 1);
      default: return XLEN'($urandom);
    endcase
  endfunction

  task automatic test_edges();
    logic [XLEN-1:0] vals[6] = '{'0, '1, MinNeg, ~MinNeg, XLEN'(1), XLEN'(7)};
    for (int o = 0; o < NumOps; o++)
      for (int i = 0; i < $size(vals); i++)
        for (int j = 0; j < $size(vals); j++) run_op(muldiv_op_e'(o), vals[i], vals[j]);
  endtask  // Automatic

  task automatic random_ops(input int n);
    repeat (n) run_op(muldiv_op_e'($urandom_range(NumOps - 1)), operand(), operand());
  endtask  // Automatic

  task automatic test_idle_start();
    for (int o = 0; o < NumOps; o++) begin
      run_op(muldiv_op_e'(o), XLEN'($urandom), XLEN'($urandom));
      start = 1'b0;
      repeat ($urandom_range(
          3
      )) begin
        @(posedge clk);
        #1;
        check("idle busy", XLEN'(busy), '0);
        check("idle done", XLEN'(done), '0);
      end
    end
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("muldiv_tb.vcd");
    $dumpvars(0, muldiv_tb);
    do_reset();

    test_edges();
    test_idle_start();
    random_ops(2000);
    stall_pct = 30;
    random_ops(1000);
    do_reset();
    test_edges();

    do_verdict();
  end

  // Golden reference
  function automatic int latency_ref(input muldiv_op_e o, input logic [XLEN-1:0] x,
                                     input logic [XLEN-1:0] y);
    if (o == MD_MUL || o == MD_MULH || o == MD_MULHSU || o == MD_MULHU) return 1;
    if (y == '0) return 1;
    if ((o == MD_DIV || o == MD_REM) && x == MinNeg && y == '1) return 1;
    return XLEN + 1;
  endfunction

  function automatic logic [XLEN-1:0] md_ref(input muldiv_op_e o, input logic [XLEN-1:0] x,
                                             input logic [XLEN-1:0] y);
    logic signed [2*XLEN-1:0] sx;
    logic signed [2*XLEN-1:0] sy;
    logic [2*XLEN-1:0] ux;
    logic [2*XLEN-1:0] uy;
    logic [2*XLEN-1:0] p;
    sx = {{XLEN{x[XLEN-1]}}, x};
    sy = {{XLEN{y[XLEN-1]}}, y};
    ux = {{XLEN{1'b0}}, x};
    uy = {{XLEN{1'b0}}, y};
    case (o)
      MD_MUL:  return x * y;
      MD_MULH: begin
        p = sx * sy;
        return p[2*XLEN-1:XLEN];
      end
      MD_MULHSU: begin
        p = sx * uy;
        return p[2*XLEN-1:XLEN];
      end
      MD_MULHU: begin
        p = ux * uy;
        return p[2*XLEN-1:XLEN];
      end
      MD_DIV: begin
        if (y == '0) return '1;
        if (x == MinNeg && y == '1) return x;
        return XLEN'($signed(x) / $signed(y));
      end
      MD_DIVU: return (y == '0) ? '1 : x / y;
      MD_REM: begin
        if (y == '0) return x;
        if (x == MinNeg && y == '1) return '0;
        return XLEN'($signed(x) % $signed(y));
      end
      default: return (y == '0) ? x : x % y;
    endcase
  endfunction

endmodule

`default_nettype wire
