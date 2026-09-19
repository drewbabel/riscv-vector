`default_nettype none

module vec_sequencer_tb ();
  import vec_pkg::*;

  localparam int AWIDTH = 5;
  localparam int VLEN = 128;
  localparam int MaxElems = VLEN / 8;

  int                  checks = 0;
  int                  errors = 0;

  logic                clk = 1'b0;
  logic                rst_n;
  logic                core_en;
  logic                start;
  logic [         4:0] vs1;
  logic [         4:0] vs2;
  logic [         4:0] vd;
  logic                reads_vd;
  logic [         7:0] vl;
  logic [         2:0] vsew;
  logic [         2:0] vlmul;
  logic                vm;
  logic [MaxElems-1:0] mask_bits;
  vec_rel_e            d_rel;
  vec_rel_e            s1_rel;
  vec_rel_e            s2_rel;
  logic                mul_rate;
  logic                single_write;
  logic                mask_dest;
  logic                mask_whole;
  logic                mask_src;
  logic [  AWIDTH-1:0] raddr1;
  logic [  AWIDTH-1:0] raddr2;
  logic [  AWIDTH-1:0] raddr3;
  logic [  AWIDTH-1:0] waddr;
  logic [    VLEN-1:0] wstrb;
  logic                wen;
  logic [         6:0] s1_off;
  logic [         6:0] s2_off;
  logic [         6:0] d_off;
  logic [         7:0] elem_base;
  logic [         4:0] elem_count;
  logic [MaxElems-1:0] elem_active;
  logic                last;
  logic                busy;
  logic                done;

  always #5 clk = ~clk;

  vec_sequencer #(
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) dut (
      .clk         (clk),
      .rst_n       (rst_n),
      .core_en     (core_en),
      .start       (start),
      .vs1         (vs1),
      .vs2         (vs2),
      .vd          (vd),
      .reads_vd    (reads_vd),
      .vl          (vl),
      .vsew        (vsew),
      .vlmul       (vlmul),
      .vm          (vm),
      .mask_bits   (mask_bits),
      .d_rel       (d_rel),
      .s1_rel      (s1_rel),
      .s2_rel      (s2_rel),
      .mul_rate    (mul_rate),
      .single_write(single_write),
      .mask_dest(mask_dest),
      .mask_whole(mask_whole),
      .mask_src(mask_src),
      .raddr1      (raddr1),
      .raddr2      (raddr2),
      .raddr3      (raddr3),
      .waddr       (waddr),
      .wstrb       (wstrb),
      .wen         (wen),
      .s1_off      (s1_off),
      .s2_off      (s2_off),
      .d_off       (d_off),
      .elem_base   (elem_base),
      .elem_count  (elem_count),
      .elem_active (elem_active),
      .last        (last),
      .busy        (busy),
      .done        (done)
  );

  // Reference model
  function automatic int ref_regs(input logic [2:0] lmul);
    if (lmul[2]) return 1;
    return 1 << lmul[1:0];
  endfunction

  function automatic int ref_width(input vec_rel_e rel, input logic [2:0] sew);
    int base;
    base = 8 << sew;
    case (rel)
      VEC_REL_WIDE:    return base * 2;
      VEC_REL_HALF:    return base / 2;
      VEC_REL_QUARTER: return base / 4;
      default:         return base;
    endcase
  endfunction

  function automatic int ref_count(input logic [2:0] sew, input logic mr, input logic sw);
    int widest, n;
    widest = ref_width(s2_rel, sew);
    if (!sw) begin
      if (ref_width(d_rel, sew) > widest) widest = ref_width(d_rel, sew);
      if (ref_width(s1_rel, sew) > widest) widest = ref_width(s1_rel, sew);
    end
    n = VLEN / widest;
    if (mr && (n > 4)) n = 4;
    return n;
  endfunction

  function automatic int ref_total(input logic [2:0] sew, input logic [2:0] lmul);
    return ref_regs(lmul) * (VLEN / (8 << sew));
  endfunction

  // Element placement
  function automatic int ref_reg_of(input int idx, input int width);
    return (idx * width) / VLEN;
  endfunction

  function automatic int ref_bit_of(input int idx, input int width);
    return (idx * width) % VLEN;
  endfunction

  function automatic logic [VLEN-1:0] ref_strb(input int eb, input logic [2:0] sew,
                                               input logic [7:0] len, input logic use_all,
                                               input logic [MaxElems-1:0] msk, input logic sw,
                                               input logic is_last);
    logic [VLEN-1:0] out;
    int dw, n;
    out = '0;
    dw  = ref_width(d_rel, sew);
    n   = ref_count(sew, mul_rate, sw);
    if (sw) begin
      if (is_last) for (int b = 0; b < dw; b++) out[b] = 1'b1;
      return out;
    end
    for (int e = 0; e < n; e++) begin
      if (((eb + e) < int'(len)) && (use_all || msk[e])) begin
        for (int b = 0; b < dw; b++) out[ref_bit_of(eb+e, dw)+b] = 1'b1;
      end
    end
    return out;
  endfunction

  task automatic init_signals();
    rst_n        = 1'b0;
    core_en      = 1'b1;
    start        = 1'b0;
    vs1          = 5'd0;
    vs2          = 5'd0;
    vd           = 5'd0;
    reads_vd     = 1'b0;
    vl           = 8'd0;
    vsew         = 3'd0;
    vlmul        = 3'd0;
    vm           = 1'b1;
    mask_bits    = '1;
    d_rel        = VEC_REL_SAME;
    s1_rel       = VEC_REL_SAME;
    s2_rel       = VEC_REL_SAME;
    mul_rate     = 1'b0;
    single_write = 1'b0;
    mask_dest = 1'b0;
    mask_whole = 1'b0;
    mask_src = 1'b0;
  endtask

  task automatic do_reset();
    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  task automatic fail(input string what);
    errors++;
    if (errors < 12) $display("FAIL %s at %0t", what, $time);
  endtask

  // One phase
  task automatic check_tick(input int eb, input logic [4:0] a1, input logic [4:0] a2,
                            input logic [4:0] dst, input logic rd_vd, input logic [2:0] sew,
                            input logic [7:0] len, input logic use_all,
                            input logic [MaxElems-1:0] msk, input logic sw, input logic is_last);
    logic [VLEN-1:0] exp_strb;
    int dw, w1, w2, n, roff_d, roff_1, roff_2;
    dw       = ref_width(d_rel, sew);
    w1       = ref_width(s1_rel, sew);
    w2       = ref_width(s2_rel, sew);
    n        = ref_count(sew, mul_rate, sw);
    roff_d   = sw ? 0 : ref_reg_of(eb, dw);
    roff_1   = sw ? 0 : ref_reg_of(eb, w1);
    roff_2   = ref_reg_of(eb, w2);
    exp_strb = ref_strb(eb, sew, len, use_all, msk, sw, is_last);
    checks++;
    if (raddr1 !== a1 + 5'(roff_1)) fail("raddr1");
    else if (raddr2 !== a2 + 5'(roff_2)) fail("raddr2");
    else if (raddr3 !== (rd_vd ? dst + 5'(roff_d) : 5'd0)) fail("raddr3");
    else if (waddr !== dst + 5'(roff_d)) fail("waddr");
    else if (wstrb !== exp_strb) fail("wstrb");
    else if (elem_base !== 8'(eb)) fail("elem_base");
    else if (elem_count !== 5'(n)) fail("elem_count");
    else if (s1_off !== 7'(sw ? 0 : ref_bit_of(eb, w1))) fail("s1_off");
    else if (s2_off !== 7'(ref_bit_of(eb, w2))) fail("s2_off");
    else if (d_off !== 7'(sw ? 0 : ref_bit_of(eb, dw))) fail("d_off");
    else if (last !== is_last) fail("last");
    else if (wen !== (exp_strb != '0)) fail("wen");
  endtask

  task automatic run_case(input logic [4:0] a1, input logic [4:0] a2, input logic [4:0] dst,
                          input logic rd_vd, input logic [7:0] len, input logic [2:0] sew,
                          input logic [2:0] lmul, input logic use_all,
                          input logic [MaxElems-1:0] msk);
    int n, total, eb;

    vs1       = a1;
    vs2       = a2;
    vd        = dst;
    reads_vd  = rd_vd;
    vl        = len;
    vsew      = sew;
    vlmul     = lmul;
    vm        = use_all;
    mask_bits = msk;

    start     = 1'b1;
    @(posedge clk);
    @(negedge clk);
    start = 1'b0;

    if (len == 8'd0) begin
      checks++;
      if (busy !== 1'b0) fail("busy at zero length");
      checks++;
      if (done !== 1'b1) fail("done at zero length");
      @(negedge clk);
      return;
    end

    n     = ref_count(sew, mul_rate, single_write);
    total = ref_total(sew, lmul);
    eb    = 0;
    while (eb < total) begin
      checks++;
      if (busy !== 1'b1) fail("busy during walk");
      check_tick(eb, a1, a2, dst, rd_vd, sew, len, use_all, msk, single_write, (eb + n) >= total);
      eb = eb + n;
      @(negedge clk);
    end

    checks++;
    if (busy !== 1'b0) fail("busy after walk");
    checks++;
    if (done !== 1'b1) fail("done after walk");
    @(negedge clk);
    checks++;
    if (done !== 1'b0) fail("done stuck high");
  endtask

  // Shapes under test
  task automatic set_shape(input vec_rel_e d, input vec_rel_e s1, input vec_rel_e s2,
                           input logic mr, input logic sw);
    d_rel        = d;
    s1_rel       = s1;
    s2_rel       = s2;
    mul_rate     = mr;
    single_write = sw;
  endtask

  task automatic check_clock_enable();
    set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_SAME, 1'b0, 1'b0);
    vs1      = 5'd1;
    vs2      = 5'd2;
    vd       = 5'd4;
    reads_vd = 1'b0;
    vl       = 8'd16;
    vsew     = 3'd2;
    vlmul    = 3'd2;
    vm       = 1'b1;
    mask_bits = '1;
    start    = 1'b1;
    @(posedge clk);
    @(negedge clk);
    start   = 1'b0;
    core_en = 1'b0;
    repeat (3) begin
      checks++;
      if (elem_base !== 8'd0) fail("elem_base moved with core_en low");
      @(negedge clk);
    end
    core_en = 1'b1;
    @(negedge clk);
    checks++;
    if (elem_base !== 8'd4) fail("elem_base stuck after core_en");
    while (busy) @(negedge clk);
    @(negedge clk);
  endtask

  task automatic sweep();
    for (int sew = 0; sew < 3; sew++) begin
      for (int lm = 0; lm < 4; lm++) begin
        for (int t = 0; t < 3; t++) begin
          int vmax;
          vmax = (VLEN / (8 << sew)) * (1 << lm);
          set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_SAME, 1'b0, 1'b0);
          run_case(5'd1, 5'd8, 5'd16, 1'b0, 8'(t == 0 ? vmax : (t == 1 ? vmax / 2 : 1)), 3'(sew),
                   3'(lm), 1'b1, '1);
          set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_SAME, 1'b1, 1'b0);
          run_case(5'd1, 5'd8, 5'd16, 1'b0, 8'(t == 0 ? vmax : (t == 1 ? vmax / 2 : 1)), 3'(sew),
                   3'(lm), 1'b1, '1);
          if (sew < 2) begin
            set_shape(VEC_REL_WIDE, VEC_REL_SAME, VEC_REL_SAME, 1'b0, 1'b0);
            run_case(5'd2, 5'd8, 5'd16, 1'b1, 8'(t == 0 ? vmax : (t == 1 ? vmax / 2 : 1)),
                     3'(sew), 3'(lm), 1'b1, '1);
            set_shape(VEC_REL_WIDE, VEC_REL_SAME, VEC_REL_WIDE, 1'b0, 1'b0);
            run_case(5'd2, 5'd8, 5'd16, 1'b0, 8'(t == 0 ? vmax : (t == 1 ? vmax / 2 : 1)),
                     3'(sew), 3'(lm), 1'b1, '1);
            set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_WIDE, 1'b0, 1'b0);
            run_case(5'd2, 5'd8, 5'd16, 1'b0, 8'(t == 0 ? vmax : (t == 1 ? vmax / 2 : 1)),
                     3'(sew), 3'(lm), 1'b1, '1);
          end
          if (sew > 0) begin
            set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_HALF, 1'b0, 1'b0);
            run_case(5'd2, 5'd8, 5'd16, 1'b0, 8'(t == 0 ? vmax : (t == 1 ? vmax / 2 : 1)),
                     3'(sew), 3'(lm), 1'b1, '1);
          end
          set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_SAME, 1'b0, 1'b1);
          run_case(5'd1, 5'd8, 5'd16, 1'b0, 8'(t == 0 ? vmax : (t == 1 ? vmax / 2 : 1)), 3'(sew),
                   3'(lm), 1'b1, '1);
        end
      end
    end
  endtask

  task automatic verdict();
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask

  initial begin
    $dumpfile("vec_sequencer_tb.vcd");
    $dumpvars(0, vec_sequencer_tb);

    init_signals();
    do_reset();

    // Single register
    set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_SAME, 1'b0, 1'b0);
    run_case(5'd1, 5'd8, 5'd16, 1'b0, 8'd4, 3'd2, 3'd0, 1'b1, '1);

    // Four registers ganged
    run_case(5'd16, 5'd24, 5'd8, 1'b0, 8'd16, 3'd2, 3'd2, 1'b1, '1);

    // Tail cut
    run_case(5'd16, 5'd24, 5'd8, 1'b0, 8'd10, 3'd2, 3'd2, 1'b1, '1);

    // Zero length
    run_case(5'd1, 5'd2, 5'd3, 1'b0, 8'd0, 3'd2, 3'd0, 1'b1, '1);

    // Accumulator read
    run_case(5'd1, 5'd8, 5'd16, 1'b1, 8'd8, 3'd1, 3'd1, 1'b1, '1);

    // Mask holes
    run_case(5'd1, 5'd8, 5'd16, 1'b0, 8'd4, 3'd2, 3'd0, 1'b0, 16'b0000_0000_0000_1010);

    // Fractional grouping
    run_case(5'd1, 5'd8, 5'd16, 1'b0, 8'd2, 3'd2, 3'd7, 1'b1, '1);

    // Byte elements
    run_case(5'd2, 5'd4, 5'd6, 1'b0, 8'd16, 3'd0, 3'd0, 1'b1, '1);

    // Byte multiply rate
    set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_SAME, 1'b1, 1'b0);
    run_case(5'd2, 5'd4, 5'd6, 1'b0, 8'd16, 3'd0, 3'd0, 1'b1, '1);

    // Widening walk
    set_shape(VEC_REL_WIDE, VEC_REL_SAME, VEC_REL_SAME, 1'b0, 1'b0);
    run_case(5'd2, 5'd4, 5'd8, 1'b0, 8'd8, 3'd1, 3'd0, 1'b1, '1);

    // Narrowing walk
    set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_WIDE, 1'b0, 1'b0);
    run_case(5'd2, 5'd4, 5'd8, 1'b0, 8'd8, 3'd1, 3'd0, 1'b1, '1);

    // Reduction write
    set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_SAME, 1'b0, 1'b1);
    run_case(5'd2, 5'd4, 5'd8, 1'b0, 8'd8, 3'd1, 3'd1, 1'b1, '1);

    check_clock_enable();

    // Exhaustive sweep
    sweep();

    verdict();
  end

endmodule

`default_nettype wire
