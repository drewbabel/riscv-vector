`default_nettype none

module vec_reduce_tb ();
  import vec_pkg::*;

  localparam int DLEN = 128;
  localparam int MaxElems = DLEN / 8;

  int                  checks = 0;
  int                  errors = 0;

  logic                clk = 1'b0;
  logic                rst_n;
  logic                core_en;
  vec_op_e             op;
  logic [         2:0] vsew;
  logic                widen;
  logic                first;
  logic                step;
  logic [    DLEN-1:0] vs2_data;
  logic [    DLEN-1:0] vs1_data;
  logic [MaxElems-1:0] elem_active;
  logic [    DLEN-1:0] result;

  always #5 clk = ~clk;

  vec_reduce #(
      .DLEN(DLEN)
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

  // Reference model
  logic [31:0] model;

  function automatic int sew_bits();
    return 8 << vsew;
  endfunction

  function automatic int acc_bits();
    return widen ? sew_bits() * 2 : sew_bits();
  endfunction

  function automatic logic signed_op();
    return (op == VEC_REDMIN) || (op == VEC_REDMAX) || (op == VEC_WREDSUM);
  endfunction

  function automatic logic [31:0] elem_of(input logic [DLEN-1:0] data, input int width,
                                          input int idx);
    logic [31:0] out;
    out = 32'd0;
    for (int b = 0; b < width; b++) out[b] = data[idx*width+b];
    for (int b = width; b < 32; b++) out[b] = signed_op() ? out[width-1] : 1'b0;
    return out;
  endfunction

  function automatic logic [31:0] fold(input logic [31:0] x, input logic [31:0] y);
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
    logic [31:0] acc;
    acc = is_first ? elem_of(vs1_data, acc_bits(), 0) : model;
    for (int e = 0; e < MaxElems; e++) begin
      if (elem_active[e] && (e < (DLEN / sew_bits()))) acc = fold(acc, elem_of(vs2_data,
                                                                               sew_bits(), e));
    end
    model = acc;
  endtask

  task automatic check_result(input string tag);
    logic [31:0] want;
    logic [31:0] got;
    want   = model & (32'hFFFF_FFFF >> (32 - acc_bits()));
    got    = result[31:0] & (32'hFFFF_FFFF >> (32 - acc_bits()));
    checks = checks + 1;
    if (got !== want) begin
      errors = errors + 1;
      if (errors < 12) $display("FAIL %0s got=%h want=%h at %0t", tag, got, want, $time);
    end
  endtask

  task automatic do_reset();
    rst_n       = 1'b0;
    core_en     = 1'b1;
    first       = 1'b0;
    step        = 1'b0;
    op          = VEC_REDSUM;
    vsew        = 3'd2;
    widen       = 1'b0;
    vs2_data    = '0;
    vs1_data    = '0;
    elem_active = '0;
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
  endtask

  // Walk one group
  task automatic run_fold(input vec_op_e o, input logic [2:0] sew, input logic wide,
                          input int phases, input logic [MaxElems-1:0] act, input string tag);
    op       = o;
    vsew     = sew;
    widen    = wide;
    vs1_data = {$urandom, $urandom, $urandom, $urandom};
    for (int p = 0; p < phases; p++) begin
      vs2_data    = {$urandom, $urandom, $urandom, $urandom};
      elem_active = act;
      first       = (p == 0);
      step        = 1'b1;
      #1;
      ref_phase(p == 0);
      check_result(tag);
      @(posedge clk);
      @(negedge clk);
    end
    step  = 1'b0;
    first = 1'b0;
  endtask

  task automatic check_ops();
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
    for (int i = 0; i < 10; i++) begin
      for (int sew = 0; sew < 3; sew++) begin
        logic wide;
        wide = (i >= 8);
        if (!(wide && (sew == 2))) begin
          run_fold(list[i], 3'(sew), wide, 4, '1, "all live");
          run_fold(list[i], 3'(sew), wide, 2, 16'h00ff, "half live");
          run_fold(list[i], 3'(sew), wide, 1, 16'h0001, "one live");
          run_fold(list[i], 3'(sew), wide, 3, 16'h0000, "none live");
        end
      end
    end
  endtask

  // Seed only
  task automatic check_seed();
    op          = VEC_REDSUM;
    vsew        = 3'd2;
    widen       = 1'b0;
    vs1_data    = 128'h0000_0000_0000_0000_0000_0000_0000_0007;
    vs2_data    = 128'h0000_0004_0000_0003_0000_0002_0000_0001;
    elem_active = '1;
    first       = 1'b1;
    step        = 1'b1;
    #1;
    checks = checks + 1;
    if (result[31:0] !== 32'd17) begin
      errors = errors + 1;
      $display("FAIL directed sum got=%0d want=17", result[31:0]);
    end
    @(posedge clk);
    @(negedge clk);
    step  = 1'b0;
    first = 1'b0;
  endtask

  task automatic verdict();
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask

  initial begin
    $dumpfile("vec_reduce_tb.vcd");
    $dumpvars(0, vec_reduce_tb);

    do_reset();
    check_seed();
    check_ops();
    verdict();
  end

endmodule

`default_nettype wire
