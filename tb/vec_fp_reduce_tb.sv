`default_nettype none

module vec_fp_reduce_tb ();
  import vec_pkg::*;

  localparam int DLEN = arch_pkg::VLEN;
  localparam int Elems = DLEN / 32;
  localparam int MinChecks = 65000;
  localparam int AddLat = fp_pkg::FpAddLatency;
  localparam logic [31:0] Qnan = 32'h7FC0_0000;
  localparam logic [4:0] Nv = 5'b10000;

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
  logic     [      4:0] fflags;
  logic     [      2:0] rm;
  logic     [     31:0] sum_result;

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

  function automatic logic is_nan(input logic [31:0] x);
    return (x[30:23] == 8'hFF) && (x[22:0] != '0);
  endfunction

  function automatic logic is_snan(input logic [31:0] x);
    return is_nan(x) && !x[22];
  endfunction

  // Numeric order key
  function automatic logic signed [32:0] key(input logic [31:0] x);
    return x[31] ? -33'(x[30:0]) : 33'(x[30:0]);
  endfunction

  // Minimum number pair
  function automatic logic [31:0] ref_pair(input vec_fop_e o, input logic [31:0] x,
                                           input logic [31:0] y);
    logic x_first;
    if (is_nan(x) && is_nan(y)) return Qnan;
    if (is_nan(x)) return y;
    if (is_nan(y)) return x;
    if (key(x) == key(y)) x_first = (o == VEC_FMAX) ? !x[31] : x[31];
    else x_first = (o == VEC_FMAX) ? (key(x) > key(y)) : (key(x) < key(y));
    return x_first ? x : y;
  endfunction

  logic [31:0] model;
  logic [ 4:0] model_flags;
  logic [31:0] want_res;
  logic [ 4:0] want_flags;

  // Element order fold
  task automatic ref_step(input logic is_first);
    logic [31:0] v;
    model_flags = '0;
    if (is_first) model = vs1_data[31:0];
    for (int e = 0; e < Elems; e++) begin
      if (elem_active[e]) begin
        v = vs2_data[e*32+:32];
        if (is_snan(model) || is_snan(v)) model_flags = Nv;
        model = ref_pair(op, model, v);
      end
    end
  endtask

  task automatic check(input string tag);
    want_res   = model;
    want_flags = model_flags;
    checks     = checks + 2;
    if ((result[31:0] !== want_res) || (fflags !== want_flags)) begin
      errors = errors + 1;
      if (errors < 12)
        $display(
            "FAIL %0s %0s got=%h/%b want=%h/%b at %0t",
            tag,
            op.name(),
            result[31:0],
            fflags,
            want_res,
            want_flags,
            $time
        );
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask

  task automatic do_reset();
    rst_n       = 1'b0;
    core_en     = 1'b1;
    first       = 1'b0;
    step        = 1'b0;
    op          = VEC_FMIN;
    vs2_data    = '0;
    vs1_data    = '0;
    elem_active = '0;
    rm          = 3'd0;
    repeat (2) @(negedge clk);
    check_quiet("in reset");
    rst_n = 1'b1;
    @(negedge clk);
    check_quiet("after reset");
  endtask

  // Special heavy values
  function automatic logic [31:0] pick();
    logic [31:0] x;
    x = $urandom;
    case ($urandom_range(
        11
    ))
      0: x = ($urandom_range(1) != 0) ? 32'h0000_0000 : 32'h8000_0000;
      1: x = ($urandom_range(1) != 0) ? 32'h7F80_0000 : 32'hFF80_0000;
      2: x = {x[31], 8'hFF, 1'b1, x[21:0]};
      3: x = {x[31], 8'hFF, 1'b0, x[21:1], 1'b1};
      4: x = Qnan;
      5: x = {x[31], 8'h00, x[22:0]};
      6: x = {x[31], 8'h3F, 23'h0};
      7: x = ($urandom_range(1) != 0) ? 32'h3F80_0000 : 32'hBF80_0000;
      default: x[30:23] = 8'(120 + $urandom_range(14));
    endcase
    return x;
  endfunction

  function automatic logic [DLEN-1:0] pick_vec();
    for (int e = 0; e < Elems; e++) pick_vec[e*32+:32] = pick();
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
    if ($urandom_range(1) != 0) return VEC_FMAX;
    return VEC_FMIN;
  endfunction

  // Bubble cycle quiet
  task automatic check_quiet(input string tag);
    checks = checks + 1;
    if (fflags !== '0) begin
      errors = errors + 1;
      if (errors < 12) $display("FAIL %0s flags=%b without a step at %0t", tag, fflags, $time);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask

  task automatic scramble();
    vs2_data    = pick_vec();
    vs1_data    = pick_vec();
    elem_active = pick_mask();
    op          = pick_op();
    first       = 1'($urandom);
    rm          = 3'($urandom);
    step        = 1'b0;
  endtask

  // Walk one group
  task automatic run_group(input vec_fop_e o, input int phases, input logic stall, input int gaps,
                           input string tag);
    vs1_data = pick_vec();
    for (int p = 0; p < phases; p++) begin
      op          = o;
      vs2_data    = pick_vec();
      elem_active = pick_mask();
      first       = (p == 0);
      step        = 1'b1;
      #1;
      ref_step(p == 0);
      @(posedge clk);
      #1;
      scramble();
      if (stall) begin
        core_en = 1'b0;
        repeat ($urandom_range(
            3, 1
        )) begin
          @(posedge clk);
          #1;
          check(tag);
        end
        core_en = 1'b1;
      end
      check(tag);
      repeat ($urandom_range(
          gaps
      )) begin
        @(negedge clk);
        scramble();
        @(posedge clk);
        #1;
        check_quiet(tag);
      end
      @(negedge clk);
    end
  endtask

  task automatic check_random();
    vec_fop_e o;
    int ph;
    for (int i = 0; i < 6000; i++) begin
      if ($urandom_range(1) != 0) o = VEC_FMAX;
      else o = VEC_FMIN;
      ph = 1 << $urandom_range(3);
      run_group(o, ph, ($urandom_range(7) == 0), ($urandom_range(3) == 0) ? 2 : 0, "random");
    end
  endtask

  // Fixed inputs
  task automatic directed(input vec_fop_e o, input logic [31:0] s, input logic [127:0] v,
                          input logic [3:0] act, input logic [31:0] want, input logic [4:0] wflags,
                          input string tag);
    op          = o;
    vs1_data    = DLEN'(s);
    vs2_data    = DLEN'(v);
    elem_active = Elems'(act);
    first       = 1'b1;
    step        = 1'b1;
    @(posedge clk);
    #1;
    model       = want;
    model_flags = wflags;
    check(tag);
    @(negedge clk);
    step  = 1'b0;
    first = 1'b0;
  endtask

  task automatic check_directed();
    directed(VEC_FMIN, 32'h0000_0000, {32'h40A0_0000, 32'h4000_0000, 32'hBF80_0000, 32'h4040_0000},
             4'hF, 32'hBF80_0000, '0, "min of four");
    directed(VEC_FMAX, 32'h0000_0000, {32'h40A0_0000, 32'h4000_0000, 32'hBF80_0000, 32'h4040_0000},
             4'hF, 32'h40A0_0000, '0, "max of four");
    directed(VEC_FMAX, 32'h0000_0000, {32'h40A0_0000, 32'h4000_0000, 32'hBF80_0000, 32'h4040_0000},
             4'h2, 32'h0000_0000, '0, "max one live");
    directed(VEC_FMIN, 32'h0000_0000, {4{32'h8000_0000}}, 4'h1, 32'h8000_0000, '0, "min of zeros");
    directed(VEC_FMAX, 32'h8000_0000, {4{32'h0000_0000}}, 4'h8, 32'h0000_0000, '0, "max of zeros");
    directed(VEC_FMAX, 32'h0000_0000, {4{32'h8000_0000}}, 4'hF, 32'h0000_0000, '0,
             "max keeps plus zero");
    directed(VEC_FMIN, 32'h7F80_0001, {4{32'h3F80_0000}}, 4'h0, 32'h7F80_0001, '0,
             "signaling scalar alone");
    directed(VEC_FMIN, 32'h7FC0_1234, {4{32'h3F80_0000}}, 4'h0, 32'h7FC0_1234, '0,
             "payload scalar alone");
    directed(VEC_FMIN, 32'h7F80_0001, {4{32'h3F80_0000}}, 4'h4, 32'h3F80_0000, Nv,
             "signaling scalar meets live");
    directed(VEC_FMAX, 32'h7FC0_1234, {4{32'hFF80_0001}}, 4'hF, Qnan, Nv, "all NaN canonical");
    directed(VEC_FMAX, 32'h3F80_0000, {32'hFF80_0001, 32'h7FC0_0000, 32'h7FC0_0000, 32'h7FC0_0000},
             4'h7, 32'h3F80_0000, '0, "signaling element masked");
    directed(VEC_FMIN, 32'hFF80_0000, {32'h7FC0_0000, 32'h7FC0_0000, 32'h7FC0_0000, 32'h7F80_0005},
             4'h9, 32'hFF80_0000, Nv, "signaling element live");
  endtask

  // Exact sum then round
  function automatic logic [36:0] ref_add(input logic [31:0] a, input logic [31:0] b,
                                          input logic [2:0] rm);
    logic signed [299:0] xa;
    logic signed [299:0] xb;
    logic signed [299:0] sum;
    logic        [299:0] mag;
    logic        [299:0] rem;
    logic        [299:0] half;
    logic        [299:0] q;
    logic                a_nan;
    logic                b_nan;
    logic                sign;
    logic                up;
    int                  p;
    int                  shift;
    int                  e;
    a_nan = (a[30:23] == 8'hFF) && (a[22:0] != '0);
    b_nan = (b[30:23] == 8'hFF) && (b[22:0] != '0);
    if (a_nan || b_nan)
      return {((a_nan && !a[22]) || (b_nan && !b[22])) ? 5'b10000 : 5'b0, 32'h7FC0_0000};
    if ((a[30:0] == 31'h7F80_0000) && (b[30:0] == 31'h7F80_0000))
      return (a[31] != b[31]) ? {5'b10000, 32'h7FC0_0000} : {5'b0, a};
    if (a[30:0] == 31'h7F80_0000) return {5'b0, a};
    if (b[30:0] == 31'h7F80_0000) return {5'b0, b};
    xa = (a[30:23] == 0) ? 300'(a[22:0]) : (300'({1'b1, a[22:0]}) << (a[30:23] - 1));
    xb = (b[30:23] == 0) ? 300'(b[22:0]) : (300'({1'b1, b[22:0]}) << (b[30:23] - 1));
    if (a[31]) xa = -xa;
    if (b[31]) xb = -xb;
    sum = xa + xb;
    if (sum == 0) return {5'b0, (a[31] == b[31]) ? a[31] : (rm == 3'd2), 31'b0};
    sign = sum < 0;
    mag = sign ? -sum : sum;
    p = 0;
    for (int i = 0; i < 300; i++) if (mag[i]) p = i;
    shift = (p > 23) ? p - 23 : 0;
    q = mag >> shift;
    rem = (shift > 0) ? (mag & ((300'(1) << shift) - 1)) : '0;
    half = (shift > 0) ? (300'(1) << (shift - 1)) : '0;
    case (rm)
      3'd0: up = (rem > half) || ((rem == half) && (rem != 0) && q[0]);
      3'd1: up = 1'b0;
      3'd2: up = (rem != 0) && sign;
      3'd3: up = (rem != 0) && !sign;
      default: up = (rem != 0) && (rem >= half);
    endcase
    q = q + 300'(up);
    e = shift;
    if (q[24]) begin
      q = q >> 1;
      e = e + 1;
    end
    if (!q[23]) return {(rem != 0) ? 5'b00011 : 5'b0, sign, 8'h00, q[22:0]};
    if (e + 1 >= 255) begin
      if ((rm == 3'd1) || ((rm == 3'd2) && !sign) || ((rm == 3'd3) && sign))
        return {5'b00101, sign, 31'h7F7F_FFFF};
      return {5'b00101, sign, 31'h7F80_0000};
    end
    return {(rem != 0) ? 5'b00001 : 5'b0, sign, 8'(e + 1), q[22:0]};
  endfunction

  logic [4:0] sum_seen;
  initial sum_seen = '0;
  always @(negedge clk) if (rst_n && core_en) sum_seen = sum_seen | fflags;

  // Sum operand values
  function automatic logic [31:0] pick_sum();
    logic [31:0] x;
    x = $urandom;
    case ($urandom_range(
        31
    ))
      0: x[30:0] = '0;
      1: x[30:0] = 31'h7F80_0000;
      2: x = 32'h7FC0_0000;
      3: x = {x[31], 8'hFF, 1'b0, x[21:1], 1'b1};
      4, 5: x[30:23] = 8'h00;
      6, 7: x[30:23] = 8'(250 + $urandom_range(4));
      8: x = ($urandom_range(1) != 0) ? 32'h4B80_0000 : 32'hCB80_0000;
      9: x = 32'h3F80_0000;
      default: x[30:23] = 8'(120 + $urandom_range(14));
    endcase
    return x;
  endfunction

  logic [31:0] vals[$];

  // Element order sum
  task automatic run_sum(input vec_fop_e o, input logic [31:0] seed, input logic [31:0] live,
                         input logic [2:0] r, input int gaps, input logic stall, input string tag);
    logic [31:0] acc;
    logic [ 4:0] want_flags;
    logic [36:0] step_out;
    logic        seen;
    logic [ 4:0] got_flags;
    acc            = seed;
    want_flags     = '0;
    seen           = 1'b0;
    sum_seen       = '0;
    vs1_data       = pick_vec();
    vs1_data[31:0] = seed;
    for (int k = 0; k < vals.size(); k++) begin
      if (live[k]) begin
        step_out   = ref_add(acc, vals[k], r);
        acc        = step_out[31:0];
        want_flags = want_flags | step_out[36:32];
        seen       = 1'b1;
      end
      op             = o;
      rm             = r;
      vs2_data       = pick_vec();
      vs2_data[31:0] = vals[k];
      elem_active    = pick_mask();
      elem_active[0] = live[k];
      first          = (k == 0);
      step           = 1'b1;
      @(posedge clk);
      #1;
      scramble();
      if (stall && ($urandom_range(3) == 0)) begin
        core_en = 1'b0;
        repeat ($urandom_range(3, 1)) @(posedge clk);
        #1 core_en = 1'b1;
      end
      @(negedge clk);
      scramble();
      if (k != vals.size() - 1) begin
        repeat (1 + $urandom_range(
            gaps
        )) begin
          @(posedge clk);
          #1;
          @(negedge clk);
          scramble();
        end
      end
    end
    repeat (AddLat) @(posedge clk);
    #1;
    if (!seen && (o == VEC_FREDUSUM) && (acc[30:23] == 8'hFF) && (acc[22:0] != '0)) begin
      if (is_snan(acc)) want_flags = 5'b10000;
      acc = 32'h7FC0_0000;
    end
    got_flags = sum_seen | fflags;
    checks = checks + 2;
    if ((sum_result !== acc) || (got_flags !== want_flags)) begin
      errors = errors + 1;
      if (errors < 12)
        $display(
            "FAIL %0s %0s rm %0d got=%h/%b want=%h/%b at %0t",
            tag,
            o.name(),
            r,
            sum_result,
            got_flags,
            acc,
            want_flags,
            $time
        );
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
    repeat (AddLat + 1) begin
      @(negedge clk);
      scramble();
      op = VEC_FREDUSUM;
      @(posedge clk);
      #1;
      check_quiet(tag);
    end
    @(negedge clk);
  endtask

  task automatic check_sums();
    logic     [31:0] live;
    vec_fop_e        o;
    int              n;
    vals = '{32'h4B80_0000, 32'h3F80_0000, 32'h3F80_0000, 32'hCB80_0000};
    for (int r = 0; r < 5; r++) begin
      run_sum(VEC_FREDOSUM, 32'h0, '1, 3'(r), 0, 1'b0, "ordered rounding");
      run_sum(VEC_FREDUSUM, 32'h0, '1, 3'(r), 0, 1'b0, "unordered rounding");
    end
    vals = '{32'h3F80_0000, 32'h7F80_0001};
    run_sum(VEC_FREDOSUM, 32'h7F80_0001, '0, 3'd0, 0, 1'b0, "ordered empty signaling");
    run_sum(VEC_FREDUSUM, 32'h7F80_0001, '0, 3'd0, 0, 1'b0, "unordered empty signaling");
    run_sum(VEC_FREDOSUM, 32'h7FC0_1234, '0, 3'd0, 0, 1'b0, "ordered empty payload");
    run_sum(VEC_FREDUSUM, 32'hFFC0_1234, '0, 3'd0, 0, 1'b0, "unordered empty payload");
    run_sum(VEC_FREDUSUM, 32'h8000_0000, '0, 3'd0, 0, 1'b0, "unordered empty zero");
    vals = '{32'h7F7F_FFFF, 32'h7F7F_FFFF};
    for (int r = 0; r < 5; r++) run_sum(VEC_FREDOSUM, 32'h0, '1, 3'(r), 0, 1'b0, "overflow");
    vals = '{32'h3F80_0000, 32'hBF80_0000};
    for (int r = 0; r < 5; r++) run_sum(VEC_FREDUSUM, 32'h0, '1, 3'(r), 0, 1'b0, "exact zero");
    for (int i = 0; i < 2500; i++) begin
      n = 1 << $urandom_range(5);
      if ($urandom_range(1) != 0) n = $urandom_range(n, 1);
      vals.delete();
      for (int k = 0; k < n; k++) vals.push_back(pick_sum());
      case ($urandom_range(
          3
      ))
        0: live = '1;
        1: live = '0;
        default: live = $urandom;
      endcase
      if ($urandom_range(1) != 0) o = VEC_FREDUSUM;
      else o = VEC_FREDOSUM;
      run_sum(o, pick_sum(), live, 3'($urandom_range(4)), 2, ($urandom_range(3) == 0), "random");
    end
  endtask

  task automatic verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    $dumpfile("vec_fp_reduce_tb.vcd");
    $dumpvars(0, vec_fp_reduce_tb);

    do_reset();
    check_directed();
    check_random();
    check_sums();
    verdict();
  end

endmodule

`default_nettype wire
