`default_nettype none

module vec_fp_reduce_tb ();
  import vec_pkg::*;
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNv, fp_pkg::FlagOf, fp_pkg::FlagUf, fp_pkg::FlagNx;
  import fp_pkg::ExpW, fp_pkg::FracW, fp_pkg::SigW, fp_pkg::Bias;

  localparam int DLEN = arch_pkg::VLEN;
  localparam int FLEN = fp_pkg::FLEN;
  localparam int Elems = DLEN / FLEN;
  localparam int FlagW = fp_pkg::FlagW;
  localparam int RmW = fp_pkg::RmW;
  localparam int MinChecks = 74_000;
  localparam int AddLat = fp_pkg::FpAddLatency;
  localparam int MaxSum = 32;
  localparam int DirElems = 4;
  localparam int DirW = DirElems * FLEN;
  localparam int DirPhases = (DirElems + Elems - 1) / Elems;
  localparam int ExactW = (1 << ExpW) + SigW + 2;
  localparam logic [FLEN-1:0] Qnan = {1'b0, {ExpW{1'b1}}, 1'b1, {(FracW - 1) {1'b0}}};
  localparam logic [FLEN-2:0] InfMag = {{ExpW{1'b1}}, {FracW{1'b0}}};
  localparam logic [FLEN-2:0] MaxMag = {{(ExpW - 1) {1'b1}}, 1'b0, {FracW{1'b1}}};
  localparam logic [FLEN-1:0] SignBit = FLEN'(1) << (FLEN - 1);
  localparam logic [FLEN-1:0] PosInf = {1'b0, InfMag};
  localparam logic [FLEN-1:0] NegInf = {1'b1, InfMag};
  localparam logic [FLEN-1:0] MaxFin = {1'b0, MaxMag};
  localparam logic [FLEN-1:0] Snan = {1'b0, {ExpW{1'b1}}, 1'b0, {(FracW - 2) {1'b0}}, 1'b1};
  localparam logic [FLEN-1:0] PayNan = Qnan | FLEN'('h1234);
  localparam logic [FLEN-1:0] One = FLEN'(Bias) << FracW;
  localparam logic [FLEN-1:0] NegOne = One | SignBit;
  localparam logic [FLEN-1:0] Two = FLEN'(Bias + 1) << FracW;
  localparam logic [FLEN-1:0] Three = Two | (FLEN'(1) << (FracW - 1));
  localparam logic [FLEN-1:0] Five = (FLEN'(Bias + 2) << FracW) | (FLEN'(1) << (FracW - 2));
  localparam logic [FLEN-1:0] Big = FLEN'(Bias + FracW + 1) << FracW;

  int                   checks = 0;
  int                   errors = 0;
  int                   max_errors = 0;

  logic                 clk = 1'b0;
  logic                 rst_n;
  logic                 core_en;
  vec_fop_e             op;
  logic                 first;
  logic                 step;
  logic     [ DLEN-1:0] vs2_data;
  logic     [ DLEN-1:0] vs1_data;
  logic     [Elems-1:0] elem_active;
  logic     [ DLEN-1:0] result;
  logic     [FlagW-1:0] fflags;
  logic     [  RmW-1:0] rm;
  logic     [ FLEN-1:0] sum_result;

  logic     [ FLEN-1:0] model;
  logic     [FlagW-1:0] model_flags;
  logic     [FlagW-1:0] sum_seen = '0;
  logic     [ FLEN-1:0] vals           [$];

  always #5 clk = ~clk;

  vec_fp_reduce #(
      .DLEN(DLEN)
  ) dut (
      .clk        (clk),
      .rst_n      (rst_n),
      .core_en    (core_en),
      .op         (op),
      .first      (first),
      .step       (step),
      .vs2_data   (vs2_data),
      .vs1_data   (vs1_data),
      .elem_active(elem_active),
      .result     (result),
      .rm         (rm),
      .sum_result (sum_result),
      .fflags     (fflags)
  );

  task automatic check(input string name, input logic [FLEN-1:0] got, input logic [FLEN-1:0] exp);
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
    op          = VEC_FMIN;
    vs2_data    = '0;
    vs1_data    = '0;
    elem_active = '0;
    rm          = RmRne;
    repeat (2) @(negedge clk);
    check_quiet("in reset");
    rst_n = 1'b1;
    @(negedge clk);
    check_quiet("after reset");
  endtask  // Automatic

  task automatic check_step(input string tag, input logic [FLEN-1:0] exp_res,
                            input logic [FlagW-1:0] exp_flags);
    check({tag, " result"}, result[FLEN-1:0], exp_res);
    check({tag, " fflags"}, FLEN'(fflags), FLEN'(exp_flags));
  endtask  // Automatic

  // Bubble cycle quiet
  task automatic check_quiet(input string tag);
    check({tag, " quiet fflags"}, FLEN'(fflags), '0);
  endtask  // Automatic

  // Special heavy values
  function automatic logic [FLEN-1:0] pick();
    logic [FLEN-1:0] x;
    x = FLEN'($urandom);
    case ($urandom_range(
        11
    ))
      0: x = 1'($urandom) ? '0 : SignBit;
      1: x = 1'($urandom) ? PosInf : NegInf;
      2: x = {x[FLEN-1], {ExpW{1'b1}}, 1'b1, x[FracW-2:0]};
      3: x = {x[FLEN-1], {ExpW{1'b1}}, 1'b0, x[FracW-2:1], 1'b1};
      4: x = Qnan;
      5: x = {x[FLEN-1], ExpW'(0), x[FracW-1:0]};
      6: x = {x[FLEN-1], ExpW'(Bias / 2), FracW'(0)};
      7: x = 1'($urandom) ? One : NegOne;
      default: x[FracW+:ExpW] = ExpW'(Bias - 7 + $urandom_range(14));
    endcase
    return x;
  endfunction

  function automatic logic [DLEN-1:0] pick_vec();
    for (int e = 0; e < Elems; e++) pick_vec[e*FLEN+:FLEN] = pick();
  endfunction

  function automatic logic [Elems-1:0] pick_mask();
    case ($urandom_range(
        4
    ))
      0: return '0;
      1: return '1;
      2: return Elems'(1) << $urandom_range(Elems - 1);
      default: return Elems'($urandom);
    endcase
  endfunction

  function automatic vec_fop_e pick_op();
    if (1'($urandom)) return VEC_FMAX;
    return VEC_FMIN;
  endfunction

  task automatic scramble();
    vs2_data    = pick_vec();
    vs1_data    = pick_vec();
    elem_active = pick_mask();
    op          = pick_op();
    first       = 1'($urandom);
    rm          = RmW'($urandom);
    step        = 1'b0;
  endtask  // Automatic

  task automatic idle();
    @(posedge clk);
    @(negedge clk);
    scramble();
  endtask  // Automatic

  task automatic bubble(input string tag);
    scramble();
    @(posedge clk);
    @(negedge clk);
    check_quiet(tag);
  endtask  // Automatic

  task automatic freeze(input int cycles);
    core_en = 1'b0;
    repeat (cycles) @(posedge clk);
    @(negedge clk);
    core_en = 1'b1;
  endtask  // Automatic

  task automatic stall_hold(input string tag, input int cycles);
    core_en = 1'b0;
    repeat (cycles) begin
      @(posedge clk);
      @(negedge clk);
      check_step(tag, model, model_flags);
    end
    core_en = 1'b1;
  endtask  // Automatic

  // Walk one group
  task automatic run_group(input vec_fop_e o, input int phases, input logic stall, input int gaps,
                           input string tag);
    string name;
    name = {tag, " ", o.name()};
    vs1_data = pick_vec();
    for (int p = 0; p < phases; p++) begin
      op          = o;
      vs2_data    = pick_vec();
      elem_active = pick_mask();
      first       = (p == 0);
      step        = 1'b1;
      ref_step(p == 0, o, vs1_data, vs2_data, elem_active);
      @(posedge clk);
      @(negedge clk);
      check_step(name, model, model_flags);
      scramble();
      if (stall) stall_hold(name, $urandom_range(3, 1));
      repeat ($urandom_range(gaps)) bubble(tag);
    end
  endtask  // Automatic

  task automatic check_random(input int groups);
    vec_fop_e o;
    int ph;
    repeat (groups) begin
      if (1'($urandom)) o = VEC_FMAX;
      else o = VEC_FMIN;
      ph = 1 << $urandom_range(3);
      run_group(o, ph, ($urandom_range(7) == 0), ($urandom_range(3) == 0) ? 2 : 0, "random");
    end
  endtask  // Automatic

  function automatic logic [DirW-1:0] elems4(input logic [FLEN-1:0] e3, input logic [FLEN-1:0] e2,
                                             input logic [FLEN-1:0] e1, input logic [FLEN-1:0] e0);
    return {e3, e2, e1, e0};
  endfunction

  function automatic logic [DirW-1:0] splat(input logic [FLEN-1:0] x);
    return {DirElems{x}};
  endfunction

  // Fixed inputs
  task automatic directed(input vec_fop_e o, input logic [FLEN-1:0] s, input logic [DirW-1:0] v,
                          input logic [DirElems-1:0] act, input logic [FLEN-1:0] want,
                          input logic [FlagW-1:0] wflags, input string tag);
    logic [FlagW-1:0] seen;
    seen     = '0;
    op       = o;
    vs1_data = DLEN'(s);
    for (int p = 0; p < DirPhases; p++) begin
      vs2_data    = DLEN'(v >> (p * DLEN));
      elem_active = Elems'(act >> (p * Elems));
      first       = (p == 0);
      step        = 1'b1;
      @(posedge clk);
      @(negedge clk);
      seen = seen | fflags;
    end
    check({tag, " ", o.name(), " result"}, result[FLEN-1:0], want);
    check({tag, " ", o.name(), " fflags"}, FLEN'(seen), FLEN'(wflags));
    step  = 1'b0;
    first = 1'b0;
  endtask  // Automatic

  task automatic check_directed();
    directed(VEC_FMIN, 'h0000_0000, elems4(Five, Two, NegOne, Three), 'hF, NegOne, '0,
             "min of four");
    directed(VEC_FMAX, 'h0000_0000, elems4(Five, Two, NegOne, Three), 'hF, Five, '0, "max of four");
    directed(VEC_FMAX, 'h0000_0000, elems4(Five, Two, NegOne, Three), 'h2, 'h0000_0000, '0,
             "max one live");
    directed(VEC_FMIN, 'h0000_0000, splat(SignBit), 'h1, SignBit, '0, "min of zeros");
    directed(VEC_FMAX, SignBit, splat('h0000_0000), 'h8, 'h0000_0000, '0, "max of zeros");
    directed(VEC_FMAX, 'h0000_0000, splat(SignBit), 'hF, 'h0000_0000, '0, "max keeps plus zero");
    directed(VEC_FMIN, Snan, splat(One), 'h0, Snan, '0, "signaling scalar alone");
    directed(VEC_FMIN, PayNan, splat(One), 'h0, PayNan, '0, "payload scalar alone");
    directed(VEC_FMIN, Snan, splat(One), 'h4, One, FlagNv, "signaling scalar meets live");
    directed(VEC_FMAX, PayNan, splat(Snan | SignBit), 'hF, Qnan, FlagNv, "all NaN canonical");
    directed(VEC_FMAX, One, elems4(Snan | SignBit, Qnan, Qnan, Qnan), 'h7, One, '0,
             "signaling element masked");
    directed(VEC_FMIN, NegInf, elems4(Qnan, Qnan, Qnan, Snan | FLEN'(4)), 'h9, NegInf, FlagNv,
             "signaling element live");
  endtask  // Automatic

  // Sum operand values
  function automatic logic [FLEN-1:0] pick_sum();
    logic [FLEN-1:0] x;
    x = FLEN'($urandom);
    case ($urandom_range(
        31
    ))
      0: x[FLEN-2:0] = '0;
      1: x[FLEN-2:0] = InfMag;
      2: x = Qnan;
      3: x = {x[FLEN-1], {ExpW{1'b1}}, 1'b0, x[FracW-2:1], 1'b1};
      4, 5: x[FracW+:ExpW] = '0;
      6, 7: x[FracW+:ExpW] = ExpW'((1 << ExpW) - 6 + $urandom_range(4));
      8: x = 1'($urandom) ? Big : Big | SignBit;
      9: x = One;
      default: x[FracW+:ExpW] = ExpW'(Bias - 7 + $urandom_range(14));
    endcase
    return x;
  endfunction

  // Element order sum
  task automatic run_sum(input vec_fop_e o, input logic [FLEN-1:0] seed,
                         input logic [MaxSum-1:0] live, input logic [RmW-1:0] r, input int gaps,
                         input logic stall, input string tag);
    logic [FLEN-1:0] acc;
    logic [FlagW-1:0] want_flags;
    logic [FlagW+FLEN-1:0] step_out;
    logic seen;
    acc                = seed;
    want_flags         = '0;
    seen               = 1'b0;
    vs1_data           = pick_vec();
    vs1_data[FLEN-1:0] = seed;
    for (int k = 0; k < vals.size(); k++) begin
      if (live[k]) begin
        step_out   = ref_add(acc, vals[k], r);
        acc        = step_out[FLEN-1:0];
        want_flags = want_flags | step_out[FLEN+:FlagW];
        seen       = 1'b1;
      end
      op                 = o;
      rm                 = r;
      vs2_data           = pick_vec();
      vs2_data[FLEN-1:0] = vals[k];
      elem_active        = pick_mask();
      elem_active[0]     = live[k];
      first              = (k == 0);
      step               = 1'b1;
      @(posedge clk);
      if (k == 0) sum_seen = '0;
      @(negedge clk);
      scramble();
      if (stall && ($urandom_range(3) == 0)) freeze($urandom_range(3, 1));
      if (k != vals.size() - 1) repeat (1 + $urandom_range(gaps)) idle();
    end
    repeat (AddLat) @(posedge clk);
    @(negedge clk);
    if (!seen && (o == VEC_FREDUSUM) && is_nan(acc)) begin
      if (is_snan(acc)) want_flags = FlagNv;
      acc = Qnan;
    end
    check({tag, " ", o.name(), " sum"}, sum_result, acc);
    check({tag, " ", o.name(), " sum fflags"}, FLEN'(sum_seen | fflags), FLEN'(want_flags));
    repeat (AddLat + 1) begin
      scramble();
      op = VEC_FREDUSUM;
      @(posedge clk);
      @(negedge clk);
      check_quiet(tag);
    end
  endtask  // Automatic

  task automatic check_sums(input int random_sums);
    logic     [MaxSum-1:0] live;
    vec_fop_e              o;
    int                    n;
    vals = '{Big, One, One, SignBit | Big};
    for (int r = 0; r <= RmRmm; r++) begin
      run_sum(VEC_FREDOSUM, '0, '1, RmW'(r), 0, 1'b0, "ordered rounding");
      run_sum(VEC_FREDUSUM, '0, '1, RmW'(r), 0, 1'b0, "unordered rounding");
    end
    vals = '{One, Snan};
    run_sum(VEC_FREDOSUM, Snan, '0, RmRne, 0, 1'b0, "ordered empty signaling");
    run_sum(VEC_FREDUSUM, Snan, '0, RmRne, 0, 1'b0, "unordered empty signaling");
    run_sum(VEC_FREDOSUM, PayNan, '0, RmRne, 0, 1'b0, "ordered empty payload");
    run_sum(VEC_FREDUSUM, SignBit | PayNan, '0, RmRne, 0, 1'b0, "unordered empty payload");
    run_sum(VEC_FREDUSUM, SignBit, '0, RmRne, 0, 1'b0, "unordered empty zero");
    vals = '{MaxFin, MaxFin};
    for (int r = 0; r <= RmRmm; r++) run_sum(VEC_FREDOSUM, '0, '1, RmW'(r), 0, 1'b0, "overflow");
    vals = '{One, NegOne};
    for (int r = 0; r <= RmRmm; r++) run_sum(VEC_FREDUSUM, '0, '1, RmW'(r), 0, 1'b0, "exact zero");
    repeat (random_sums) begin
      n = 1 << $urandom_range($clog2(MaxSum));
      if (1'($urandom)) n = $urandom_range(n, 1);
      vals.delete();
      for (int k = 0; k < n; k++) vals.push_back(pick_sum());
      case ($urandom_range(
          3
      ))
        0: live = '1;
        1: live = '0;
        default: live = MaxSum'($urandom);
      endcase
      if (1'($urandom)) o = VEC_FREDUSUM;
      else o = VEC_FREDOSUM;
      run_sum(o, pick_sum(), live, RmW'($urandom_range(RmRmm)), 2, ($urandom_range(3) == 0),
              "random");
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
    $dumpfile("vec_fp_reduce_tb.vcd");
    $dumpvars(0, vec_fp_reduce_tb);

    do_reset();
    check_directed();
    check_random(6300);
    check_sums(2500);
    do_verdict();
  end

  function automatic logic is_nan(input logic [FLEN-1:0] x);
    return (x[FracW+:ExpW] == '1) && (x[FracW-1:0] != '0);
  endfunction

  function automatic logic is_snan(input logic [FLEN-1:0] x);
    return is_nan(x) && !x[FracW-1];
  endfunction

  // Numeric order key
  function automatic logic signed [FLEN:0] key(input logic [FLEN-1:0] x);
    return x[FLEN-1] ? -($bits(key))'(x[FLEN-2:0]) : ($bits(key))'(x[FLEN-2:0]);
  endfunction

  // Minimum number pair
  function automatic logic [FLEN-1:0] ref_pair(input vec_fop_e o, input logic [FLEN-1:0] x,
                                               input logic [FLEN-1:0] y);
    logic x_first;
    if (is_nan(x) && is_nan(y)) return Qnan;
    if (is_nan(x)) return y;
    if (is_nan(y)) return x;
    if (key(x) == key(y)) x_first = (o == VEC_FMAX) ? !x[FLEN-1] : x[FLEN-1];
    else x_first = (o == VEC_FMAX) ? (key(x) > key(y)) : (key(x) < key(y));
    return x_first ? x : y;
  endfunction

  // Element order fold
  task automatic ref_step(input logic is_first, input vec_fop_e o, input logic [DLEN-1:0] vs1,
                          input logic [DLEN-1:0] vs2, input logic [Elems-1:0] act);
    logic [FLEN-1:0] v;
    model_flags = '0;
    if (is_first) model = vs1[FLEN-1:0];
    for (int e = 0; e < Elems; e++) begin
      if (act[e]) begin
        v = vs2[e*FLEN+:FLEN];
        if (is_snan(model) || is_snan(v)) model_flags = FlagNv;
        model = ref_pair(o, model, v);
      end
    end
  endtask  // Automatic

  // Exact rounded sum
  function automatic logic [FlagW+FLEN-1:0] ref_add(
      input logic [FLEN-1:0] a, input logic [FLEN-1:0] b, input logic [RmW-1:0] rm);
    logic signed [ExactW-1:0] xa;
    logic signed [ExactW-1:0] xb;
    logic signed [ExactW-1:0] sum;
    logic        [ExactW-1:0] mag;
    logic        [ExactW-1:0] rem;
    logic        [ExactW-1:0] half;
    logic        [ExactW-1:0] q;
    logic                     a_nan;
    logic                     b_nan;
    logic                     sign;
    logic                     up;
    int                       p;
    int                       shift;
    int                       e;
    a_nan = is_nan(a);
    b_nan = is_nan(b);
    if (a_nan || b_nan) return {(is_snan(a) || is_snan(b)) ? FlagNv : '0, Qnan};
    if ((a[FLEN-2:0] == InfMag) && (b[FLEN-2:0] == InfMag))
      return (a[FLEN-1] != b[FLEN-1]) ? {FlagNv, Qnan} : {FlagW'(0), a};
    if (a[FLEN-2:0] == InfMag) return {FlagW'(0), a};
    if (b[FLEN-2:0] == InfMag) return {FlagW'(0), b};
    xa = (a[FracW+:ExpW] == 0) ? ExactW'(a[FracW-1:0]) :
        (ExactW'({1'b1, a[FracW-1:0]}) << (a[FracW+:ExpW] - 1));
    xb = (b[FracW+:ExpW] == 0) ? ExactW'(b[FracW-1:0]) :
        (ExactW'({1'b1, b[FracW-1:0]}) << (b[FracW+:ExpW] - 1));
    if (a[FLEN-1]) xa = -xa;
    if (b[FLEN-1]) xb = -xb;
    sum = xa + xb;
    if (sum == 0)
      return {FlagW'(0), (a[FLEN-1] == b[FLEN-1]) ? a[FLEN-1] : (rm == RmRdn), (FLEN - 1)'(0)};
    sign = sum < 0;
    mag = sign ? -sum : sum;
    p = 0;
    for (int i = 0; i < ExactW; i++) if (mag[i]) p = i;
    shift = (p > FracW) ? p - FracW : 0;
    q = mag >> shift;
    rem = (shift > 0) ? (mag & ((ExactW'(1) << shift) - 1)) : '0;
    half = (shift > 0) ? (ExactW'(1) << (shift - 1)) : '0;
    case (rm)
      RmRne:   up = (rem > half) || ((rem == half) && (rem != 0) && q[0]);
      RmRtz:   up = 1'b0;
      RmRdn:   up = (rem != 0) && sign;
      RmRup:   up = (rem != 0) && !sign;
      default: up = (rem != 0) && (rem >= half);
    endcase
    q = q + ExactW'(up);
    e = shift;
    if (q[SigW]) begin
      q = q >> 1;
      e = e + 1;
    end
    if (!q[FracW]) return {(rem != 0) ? (FlagUf | FlagNx) : '0, sign, ExpW'(0), q[FracW-1:0]};
    if (e + 1 >= (1 << ExpW) - 1) begin
      if ((rm == RmRtz) || ((rm == RmRdn) && !sign) || ((rm == RmRup) && sign))
        return {FlagOf | FlagNx, sign, MaxMag};
      return {FlagOf | FlagNx, sign, InfMag};
    end
    return {(rem != 0) ? FlagNx : '0, sign, ExpW'(e + 1), q[FracW-1:0]};
  endfunction

  always @(negedge clk) if (rst_n && core_en) sum_seen = sum_seen | fflags;

endmodule

`default_nettype wire
