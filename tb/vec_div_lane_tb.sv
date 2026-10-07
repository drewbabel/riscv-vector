`default_nettype none

module vec_div_lane_tb
  import vec_pkg::*;
();

  localparam int ELEN = arch_pkg::ELEN;
  localparam int Timeout = 2000000;

  int checks = 0;
  int errors = 0;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic core_en = 1'b1;
  logic start = 1'b0;
  vec_op_e op = VEC_DIVU;
  logic [2:0] vsew = 3'd0;
  logic [ELEN-1:0] a = '0;
  logic [ELEN-1:0] b = '0;
  logic [ELEN-1:0] result;
  logic busy;
  logic done;

  int stall_pct = 0;

  always #5 clk = ~clk;

  vec_div_lane #(
      .ELEN(ELEN)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(start),
      .op(op),
      .vsew(vsew),
      .a(a),
      .b(b),
      .result(result),
      .busy(busy),
      .done(done)
  );

  vec_op_e ops[4] = '{VEC_DIVU, VEC_DIV, VEC_REMU, VEC_REM};

  // Random stalls
  always @(negedge clk) core_en <= ($urandom_range(99) >= stall_pct);

  // Handshake rule
  always @(posedge clk)
    if (rst_n && busy && done) begin
      errors++;
      $display("FAIL busy and done both high at %0t", $time);
    end

  // Width helpers
  function automatic longint umask(input int w);
    umask = (64'sd1 <<< w) - 64'sd1;
  endfunction

  function automatic longint uval(input logic [ELEN-1:0] x, input int w);
    uval = longint'({{(64 - ELEN) {1'b0}}, x}) & umask(w);
  endfunction

  function automatic longint sval(input logic [ELEN-1:0] x, input int w);
    longint u;
    u = uval(x, w);
    sval = u[w-1] ? (u - (64'sd1 <<< w)) : u;
  endfunction

  // Reference model
  function automatic logic [ELEN-1:0] ref_lane(input vec_op_e o, input int w,
                                               input logic [ELEN-1:0] x, input logic [ELEN-1:0] y);
    longint ux;
    longint uy;
    longint sx;
    longint sy;
    longint smin;
    longint t;
    ux   = uval(x, w);
    uy   = uval(y, w);
    sx   = sval(x, w);
    sy   = sval(y, w);
    smin = -(64'sd1 <<< (w - 1));
    case (o)
      VEC_DIVU: t = (uy == 0) ? umask(w) : ux / uy;
      VEC_REMU: t = (uy == 0) ? ux : ux % uy;
      VEC_DIV:  t = (sy == 0) ? -1 : (sx == smin && sy == -1) ? sx : sx / sy;
      default:  t = (sy == 0) ? sx : (sx == smin && sy == -1) ? 0 : sx % sy;
    endcase
    ref_lane = ELEN'(t & umask(w));
  endfunction

  // Junk above the element
  function automatic logic [ELEN-1:0] junk(input logic [ELEN-1:0] x, input int w);
    logic [ELEN-1:0] keep;
    keep = ELEN'(umask(w));
    junk = (x & keep) | (ELEN'($urandom) & ~keep);
  endfunction

  // Raise start until an enabled edge takes it
  task automatic launch(input vec_op_e o, input logic [2:0] sew, input logic [ELEN-1:0] x,
                        input logic [ELEN-1:0] y);
    logic taken;
    @(negedge clk);
    // muldiv only takes start in IDLE (same rule as datapath.sv: !busy && !done)
    while (busy || done) @(negedge clk);
    op = o;
    vsew = sew;
    a = x;
    b = y;
    start = 1'b1;
    do begin
      @(posedge clk);
      taken = core_en;
      @(negedge clk);
    end while (!taken);
    start = 1'b0;
    // Scramble inputs: the lane must not depend on them after start
    vsew = 3'($urandom);
    a = ELEN'($urandom);
    b = ELEN'($urandom);
  endtask

  // One divide
  task automatic check(input vec_op_e o, input logic [2:0] sew, input logic [ELEN-1:0] x,
                       input logic [ELEN-1:0] y);
    logic [ELEN-1:0] exp_res;
    exp_res = ref_lane(o, 8 << sew, x, y);
    launch(o, sew, x, y);
    if (stall_pct == 0 && busy !== 1'b1) begin
      errors++;
      $display("FAIL %s sew=%0d busy not high after start", o.name(), 8 << sew);
    end
    while (done !== 1'b1) @(negedge clk);
    checks++;
    if (result !== exp_res) begin
      errors++;
      if (errors <= 10)
        $display(
            "FAIL %s sew=%0d a=%h b=%h got %h exp %h", o.name(), 8 << sew, x, y, result, exp_res
        );
    end
    // done pulses one enabled cycle, result holds
    if (stall_pct == 0) begin
      @(negedge clk);
      if (done !== 1'b0 || result !== exp_res) begin
        errors++;
        $display("FAIL %s sew=%0d done not a pulse or result not held", o.name(), 8 << sew);
      end
    end
  endtask

  // Edge values
  function automatic logic [ELEN-1:0] edge_val(input int idx, input int w);
    longint m;
    m = umask(w);
    case (idx)
      0: edge_val = ELEN'(0);
      1: edge_val = ELEN'(1);
      2: edge_val = ELEN'(2);
      3: edge_val = ELEN'(3);
      4: edge_val = ELEN'(7);
      5: edge_val = ELEN'(m);
      6: edge_val = ELEN'(m - 1);
      7: edge_val = ELEN'(m >> 1);
      8: edge_val = ELEN'((m >> 1) + 1);
      9: edge_val = ELEN'((m >> 1) + 2);
      default: edge_val = ELEN'((m >> 1) - 1);
    endcase
  endfunction

  task automatic edges(input logic [2:0] sew);
    int w;
    w = 8 << sew;
    for (int k = 0; k < $size(ops); k++)
      for (int i = 0; i < 11; i++)
        for (int j = 0; j < 11; j++)
          check(ops[k], sew, junk(edge_val(i, w), w), junk(edge_val(j, w), w));
  endtask

  task automatic random_cases(input logic [2:0] sew, input int n);
    for (int k = 0; k < $size(ops); k++)
      for (int i = 0; i < n; i++) check(ops[k], sew, ELEN'($urandom), ELEN'($urandom));
  endtask

  // A second start while busy must not disturb the first divide
  task automatic busy_start();
    logic [ELEN-1:0] exp_res;
    exp_res = ref_lane(VEC_DIV, 8, 32'h1234_56F0, 32'hABCD_EF10);
    launch(VEC_DIV, 3'd0, 32'h1234_56F0, 32'hABCD_EF10);
    repeat (5) @(negedge clk);
    op = VEC_DIVU;
    vsew = 3'd2;
    a = '1;
    b = 32'd3;
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    while (done !== 1'b1) @(negedge clk);
    checks++;
    if (result !== exp_res) begin
      errors++;
      $display("FAIL start while busy disturbed result: got %h exp %h", result, exp_res);
    end
    @(negedge clk);
  endtask

  // Reset in the middle of a divide
  task automatic reset_mid();
    launch(VEC_DIVU, 3'd2, 32'd1000, 32'd7);
    repeat (10) @(negedge clk);
    rst_n = 1'b0;
    repeat (2) @(negedge clk);
    checks++;
    if (busy !== 1'b0 || done !== 1'b0) begin
      errors++;
      $display("FAIL reset mid divide: busy=%b done=%b", busy, done);
    end
    rst_n = 1'b1;
  endtask

  task automatic verdict();
    $display("vec_div_lane: %0d checks, %0d errors", checks, errors);
    if (errors != 0) $fatal(1, "vec_div_lane FAILED");
    $finish;
  endtask

  initial begin
    repeat (Timeout) @(posedge clk);
    $fatal(1, "FAIL: timeout, %0d errors, %0d checks", errors, checks);
  end

  initial begin
    $dumpfile("vec_div_lane_tb.vcd");
    $dumpvars(0, vec_div_lane_tb);
  end

  initial begin
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    // Edge operands at every width
    edges(3'd0);
    edges(3'd1);
    edges(3'd2);

    // Random operands
    random_cases(3'd0, 300);
    random_cases(3'd1, 300);
    random_cases(3'd2, 300);

    // Handshake corners
    busy_start();
    reset_mid();

    // Random core_en stalls
    stall_pct = 40;
    random_cases(3'd0, 50);
    random_cases(3'd2, 50);
    stall_pct = 0;

    verdict();
  end

endmodule

`default_nettype wire
