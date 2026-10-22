`default_nettype none

module vec_fp_reduce_tb ();
  import vec_pkg::*;

  localparam int DLEN = arch_pkg::VLEN;
  localparam int Elems = DLEN / 32;
  localparam int MinChecks = 50000;
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
    verdict();
  end

endmodule

`default_nettype wire
