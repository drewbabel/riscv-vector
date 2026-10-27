`default_nettype none

module vec_reduce_tb ();
  import vec_pkg::*;

  localparam int DLEN = arch_pkg::VLEN;
  localparam int ELEN = arch_pkg::ELEN;
  localparam int MaxElems = DLEN / 8;
  localparam logic [2:0] Sew8 = 3'd0;
  localparam logic [2:0] Sew32 = 3'd2;
  localparam logic [2:0] SewTop = 3'($clog2(ELEN / 8));
  localparam int MinChecks = 580;

  int                     checks = 0;
  int                     errors = 0;
  int                     max_errors = 0;

  logic                   clk = 1'b0;
  logic                   rst_n;
  logic                   core_en;
  vec_op_e                op;
  logic    [         2:0] vsew;
  logic                   widen;
  logic                   first;
  logic                   step;
  logic    [    DLEN-1:0] vs2_data;
  logic    [    DLEN-1:0] vs1_data;
  logic    [MaxElems-1:0] elem_active;
  logic    [    DLEN-1:0] result;
  logic    [    ELEN-1:0] model;

  always #5 clk = ~clk;

  vec_reduce #(
      .DLEN(DLEN),
      .ELEN(ELEN)
  ) dut (
      .clk        (clk),
      .rst_n      (rst_n),
      .core_en    (core_en),
      .op         (op),
      .vsew       (vsew),
      .widen      (widen),
      .first      (first),
      .step       (step),
      .vs2_data   (vs2_data),
      .vs1_data   (vs1_data),
      .elem_active(elem_active),
      .result     (result)
  );

  task automatic check(input string name, input logic [DLEN-1:0] got, input logic [DLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    rst_n       = 1'b0;
    core_en     = 1'b1;
    first       = 1'b0;
    step        = 1'b0;
    op          = VEC_REDSUM;
    vsew        = Sew32;
    widen       = 1'b0;
    vs2_data    = '0;
    vs1_data    = '0;
    elem_active = '0;
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
  endtask  // Automatic

  task automatic check_result(input string name);
    logic [ELEN-1:0] mask;
    mask = {ELEN{1'b1}} >> (ELEN - acc_bits());
    check(name, result, DLEN'(model & mask));
  endtask  // Automatic

  task automatic drive_phase(input logic is_first, input logic [MaxElems-1:0] act,
                             input string name);
    vs2_data    = rand_data();
    elem_active = act;
    first       = is_first;
    step        = 1'b1;
    ref_phase(is_first);
    @(negedge clk);
    check_result(name);
  endtask  // Automatic

  // Inputs ignored
  task automatic stall(input int n, input string name);
    logic [DLEN-1:0] keep_vs2;
    logic [DLEN-1:0] keep_vs1;
    logic [MaxElems-1:0] keep_act;
    keep_vs2 = vs2_data;
    keep_vs1 = vs1_data;
    keep_act = elem_active;
    core_en  = 1'b0;
    repeat (n) begin
      vs2_data    = rand_data();
      vs1_data    = rand_data();
      elem_active = MaxElems'(rand_data());
      first       = 1'($urandom);
      step        = 1'($urandom);
      @(negedge clk);
      check_result({name, " held"});
    end
    vs2_data    = keep_vs2;
    vs1_data    = keep_vs1;
    elem_active = keep_act;
    core_en     = 1'b1;
  endtask  // Automatic

  task automatic bubble();
    vs2_data    = rand_data();
    elem_active = MaxElems'(rand_data());
    first       = 1'b0;
    step        = 1'b0;
    @(negedge clk);
  endtask  // Automatic

  task automatic gap(input string name);
    case ($urandom_range(
        3
    ))
      0: stall($urandom_range(1, 3), name);
      1: bubble();
      default: ;
    endcase
  endtask  // Automatic

  task automatic run_fold(input vec_op_e o, input logic [2:0] sew, input logic wide,
                          input int phases, input logic [MaxElems-1:0] act, input string tag);
    string name;
    name     = $sformatf("%s sew %0d %s", o.name(), sew, tag);
    op       = o;
    vsew     = sew;
    widen    = wide;
    vs1_data = rand_data();
    for (int p = 0; p < phases; p++) begin
      drive_phase(p == 0, act, name);
      gap(name);
    end
    step  = 1'b0;
    first = 1'b0;
  endtask  // Automatic

  // Seed plus count
  task automatic test_seed();
    op       = VEC_REDSUM;
    vsew     = Sew32;
    widen    = 1'b0;
    vs1_data = DLEN'(7);
    vs2_data = '0;
    model    = 7;
    for (int e = 0; e < DLEN / 32; e++) begin
      vs2_data[32*e+:32] = 32'(e + 1);
      model += ELEN'(e + 1);
    end
    elem_active = '1;
    first       = 1'b1;
    step        = 1'b1;
    @(negedge clk);
    check_result("directed sum");
    step  = 1'b0;
    first = 1'b0;
  endtask  // Automatic

  task automatic test_ops();
    vec_op_e list[10];
    list[0] = VEC_REDSUM;
    list[1] = VEC_REDAND;
    list[2] = VEC_REDOR;
    list[3] = VEC_REDXOR;
    list[4] = VEC_REDMINU;
    list[5] = VEC_REDMIN;
    list[6] = VEC_REDMAXU;
    list[7] = VEC_REDMAX;
    list[8] = VEC_WREDSUMU;
    list[9] = VEC_WREDSUM;
    for (int i = 0; i < $size(list); i++) begin
      for (int sew = int'(Sew8); sew <= int'(SewTop); sew++) begin
        logic wide;
        wide = (list[i] == VEC_WREDSUMU) || (list[i] == VEC_WREDSUM);
        if (!(wide && (sew == int'(SewTop)))) begin
          run_fold(list[i], 3'(sew), wide, 4, '1, "all live");
          run_fold(list[i], 3'(sew), wide, 2, MaxElems'({(MaxElems / 2) {1'b1}}), "half live");
          run_fold(list[i], 3'(sew), wide, 1, MaxElems'(1), "one live");
          run_fold(list[i], 3'(sew), wide, 3, '0, "none live");
          run_fold(list[i], 3'(sew), wide, 4, MaxElems'(rand_data()), "random live");
        end
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

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    $dumpfile("vec_reduce_tb.vcd");
    $dumpvars(0, vec_reduce_tb);

    do_reset();
    test_seed();
    test_ops();
    do_verdict();
  end

  function automatic logic [DLEN-1:0] rand_data();
    rand_data = '0;
    for (int i = 0; i < DLEN; i += ELEN) rand_data[i+:ELEN] = ELEN'({$urandom, $urandom});
  endfunction

  function automatic int sew_bits();
    return 8 << vsew;
  endfunction

  function automatic int acc_bits();
    return widen ? sew_bits() * 2 : sew_bits();
  endfunction

  function automatic logic signed_op();
    return (op == VEC_REDMIN) || (op == VEC_REDMAX) || (op == VEC_WREDSUM);
  endfunction

  function automatic logic [ELEN-1:0] elem_of(input logic [DLEN-1:0] data, input int width,
                                              input int idx);
    logic [ELEN-1:0] out;
    out = '0;
    for (int b = 0; b < width; b++) out[b] = data[idx*width+b];
    for (int b = width; b < ELEN; b++) out[b] = signed_op() ? out[width-1] : 1'b0;
    return out;
  endfunction

  function automatic logic [ELEN-1:0] fold(input logic [ELEN-1:0] x, input logic [ELEN-1:0] y);
    case (op)
      VEC_REDSUM, VEC_WREDSUM, VEC_WREDSUMU: return x + y;
      VEC_REDAND: return x & y;
      VEC_REDOR: return x | y;
      VEC_REDXOR: return x ^ y;
      VEC_REDMINU: return (x < y) ? x : y;
      VEC_REDMIN: return ($signed(x) < $signed(y)) ? x : y;
      VEC_REDMAXU: return (x > y) ? x : y;
      VEC_REDMAX: return ($signed(x) > $signed(y)) ? x : y;
      default: return x;
    endcase
  endfunction

  task automatic ref_phase(input logic is_first);
    logic [ELEN-1:0] acc;
    acc = is_first ? elem_of(vs1_data, acc_bits(), 0) : model;
    for (int e = 0; e < MaxElems; e++) begin
      if (elem_active[e] && (e < (DLEN / sew_bits())))
        acc = fold(acc, elem_of(vs2_data, sew_bits(), e));
    end
    model = acc;
  endtask  // Automatic

endmodule

`default_nettype wire
