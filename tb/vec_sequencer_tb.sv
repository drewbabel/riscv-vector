`default_nettype none

module vec_sequencer_tb ();
  import vec_pkg::*;

  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int VLEN = arch_pkg::VLEN;
  localparam int ELEN = arch_pkg::ELEN;
  localparam int MulLanes = arch_pkg::MulLanes;
  localparam int MaxElems = VLEN / 8;
  localparam int Widths = $clog2(ELEN / 8) + 1;
  localparam int VlW = $clog2(VLEN + 1);
  localparam int OffW = $clog2(VLEN);
  localparam int CntW = $clog2(MaxElems + 1);
  localparam int IdleTimeout = 2 * VLEN;
  localparam int MinChecks = 41000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int reg_dones = 0;

  logic clk = 1'b0;
  logic rst_n;
  logic core_en;
  logic start;
  logic [AWIDTH-1:0] vs1;
  logic [AWIDTH-1:0] vs2;
  logic [AWIDTH-1:0] vd;
  logic reads_vd;
  logic [VlW-1:0] vl;
  logic [2:0] vsew;
  logic [2:0] vlmul;
  logic vm;
  logic [MaxElems-1:0] mask_bits;
  vec_rel_e d_rel;
  vec_rel_e s1_rel;
  vec_rel_e s2_rel;
  logic mul_rate;
  logic single_write;
  logic mask_dest;
  logic mask_whole;
  logic mask_src;
  logic serial;
  logic [AWIDTH-1:0] raddr1;
  logic [AWIDTH-1:0] raddr2;
  logic [AWIDTH-1:0] raddr3;
  logic [AWIDTH-1:0] waddr;
  logic [VLEN-1:0] wstrb;
  logic wen;
  logic [OffW-1:0] s1_off;
  logic [OffW-1:0] s2_off;
  logic [OffW-1:0] d_off;
  logic [VlW-1:0] elem_base;
  logic [CntW-1:0] elem_count;
  logic [MaxElems-1:0] elem_active;
  logic last;
  logic reg_done;
  logic busy;
  logic done;

  always #5 clk = ~clk;

  vec_sequencer #(
      .AWIDTH   (AWIDTH),
      .VLEN     (VLEN),
      .ELEN     (ELEN),
      .MUL_LANES(MulLanes)
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
      .v0_bits     ({VLEN{1'b1}}),
      .d_rel       (d_rel),
      .s1_rel      (s1_rel),
      .s2_rel      (s2_rel),
      .mul_rate    (mul_rate),
      .single_write(single_write),
      .mask_dest   (mask_dest),
      .mask_whole  (mask_whole),
      .mask_src    (mask_src),
      .serial      (serial),
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
      .reg_done    (reg_done),
      .busy        (busy),
      .done        (done)
  );

  task automatic check(input string name, input logic [VLEN-1:0] got, input logic [VLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    rst_n        = 1'b0;
    core_en      = 1'b1;
    start        = 1'b0;
    vs1          = '0;
    vs2          = '0;
    vd           = '0;
    reads_vd     = 1'b0;
    vl           = '0;
    vsew         = 3'd0;
    vlmul        = 3'd0;
    vm           = 1'b1;
    mask_bits    = '1;
    d_rel        = VEC_REL_SAME;
    s1_rel       = VEC_REL_SAME;
    s2_rel       = VEC_REL_SAME;
    mul_rate     = 1'b0;
    single_write = 1'b0;
    mask_dest    = 1'b0;
    mask_whole   = 1'b0;
    mask_src     = 1'b0;
    serial       = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  // Shapes under test
  task automatic set_shape(input vec_rel_e d, input vec_rel_e s1, input vec_rel_e s2,
                           input logic mr, input logic sw, input logic ser);
    d_rel        = d;
    s1_rel       = s1;
    s2_rel       = s2;
    mul_rate     = mr;
    single_write = sw;
    serial       = ser;
  endtask  // Automatic

  task automatic set_plain();
    set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_SAME, 1'b0, 1'b0, 1'b0);
  endtask  // Automatic

  task automatic launch(input logic [AWIDTH-1:0] a1, input logic [AWIDTH-1:0] a2,
                        input logic [AWIDTH-1:0] dst, input logic rd_vd, input logic [VlW-1:0] len,
                        input logic [2:0] sew, input logic [2:0] lmul, input logic use_all,
                        input logic [MaxElems-1:0] msk);
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
  endtask  // Automatic

  // One phase
  task automatic check_tick(input int eb, input logic [AWIDTH-1:0] a1, input logic [AWIDTH-1:0] a2,
                            input logic [AWIDTH-1:0] dst, input logic rd_vd, input logic [2:0] sew,
                            input logic [VlW-1:0] len, input logic use_all,
                            input logic [MaxElems-1:0] msk, input logic sw, input logic is_last);
    logic [VLEN-1:0] exp_strb;
    logic exp_done;
    logic [AWIDTH-1:0] exp_r1, exp_r2, exp_r3, exp_w;
    logic [OffW-1:0] exp_s1, exp_s2, exp_d;
    logic [ VlW-1:0] exp_eb;
    logic [CntW-1:0] exp_n;
    int dw, w1, w2, n, roff_d, roff_1, roff_2;
    dw       = ref_width(d_rel, sew);
    w1       = ref_width(s1_rel, sew);
    w2       = ref_width(s2_rel, sew);
    n        = ref_count(sew, mul_rate, sw);
    roff_d   = sw ? 0 : ref_reg_of(eb, dw);
    roff_1   = sw ? 0 : ref_reg_of(eb, w1);
    roff_2   = ref_reg_of(eb, w2);
    exp_strb = ref_strb(eb, sew, len, use_all, msk, sw, is_last);
    exp_done = is_last || (!sw && (ref_reg_of(eb + n, dw) != roff_d));
    exp_r1   = a1 + AWIDTH'(roff_1);
    exp_r2   = a2 + AWIDTH'(roff_2);
    exp_r3   = rd_vd ? dst + AWIDTH'(roff_d) : '0;
    exp_w    = dst + AWIDTH'(roff_d);
    exp_eb   = VlW'(eb);
    exp_n    = CntW'(n);
    exp_s1   = OffW'(sw ? 0 : ref_bit_of(eb, w1));
    exp_s2   = OffW'(ref_bit_of(eb, w2));
    exp_d    = OffW'(sw ? 0 : ref_bit_of(eb, dw));
    check("raddr1", VLEN'(raddr1), VLEN'(exp_r1));
    check("raddr2", VLEN'(raddr2), VLEN'(exp_r2));
    check("raddr3", VLEN'(raddr3), VLEN'(exp_r3));
    check("waddr", VLEN'(waddr), VLEN'(exp_w));
    check("wstrb", wstrb, exp_strb);
    check("elem_base", VLEN'(elem_base), VLEN'(exp_eb));
    check("elem_count", VLEN'(elem_count), VLEN'(exp_n));
    check("s1_off", VLEN'(s1_off), VLEN'(exp_s1));
    check("s2_off", VLEN'(s2_off), VLEN'(exp_s2));
    check("d_off", VLEN'(d_off), VLEN'(exp_d));
    check("last", VLEN'(last), VLEN'(is_last));
    check("reg_done", VLEN'(reg_done), VLEN'(exp_done));
    check("wen", VLEN'(wen), VLEN'(exp_strb != '0));
  endtask  // Automatic

  task automatic run_case(input logic [AWIDTH-1:0] a1, input logic [AWIDTH-1:0] a2,
                          input logic [AWIDTH-1:0] dst, input logic rd_vd,
                          input logic [VlW-1:0] len, input logic [2:0] sew, input logic [2:0] lmul,
                          input logic use_all, input logic [MaxElems-1:0] msk);
    int n, total, eb;
    launch(a1, a2, dst, rd_vd, len, sew, lmul, use_all, msk);

    if (len == '0) begin
      check("busy at zero length", VLEN'(busy), '0);
      check("done at zero length", VLEN'(done), VLEN'(1'b1));
      @(negedge clk);
      return;
    end

    n     = ref_count(sew, mul_rate, single_write);
    total = ref_total(sew, lmul);
    eb    = 0;
    while (eb < total) begin
      check("busy during walk", VLEN'(busy), VLEN'(1'b1));
      check_tick(eb, a1, a2, dst, rd_vd, sew, len, use_all, msk, single_write, (eb + n) >= total);
      eb = eb + n;
      @(negedge clk);
    end

    check("busy after walk", VLEN'(busy), '0);
    check("done after walk", VLEN'(done), VLEN'(1'b1));
    @(negedge clk);
    check("done stuck high", VLEN'(done), '0);
  endtask  // Automatic

  task automatic run_regs(input int a1, input int a2, input int dst, input logic rd_vd,
                          input int len, input logic [2:0] sew, input logic [2:0] lmul,
                          input logic use_all, input logic [MaxElems-1:0] msk);
    run_case(AWIDTH'(a1), AWIDTH'(a2), AWIDTH'(dst), rd_vd, VlW'(len), sew, lmul, use_all, msk);
  endtask  // Automatic

  // Single register
  task automatic test_single_register();
    set_plain();
    run_regs(1, 8, 16, 1'b0, 4, 3'd2, 3'd0, 1'b1, '1);
  endtask  // Automatic

  // Four registers ganged
  task automatic test_four_registers();
    set_plain();
    run_regs(16, 24, 8, 1'b0, 16, 3'd2, 3'd2, 1'b1, '1);
  endtask  // Automatic

  // Tail cut
  task automatic test_tail_cut();
    set_plain();
    run_regs(16, 24, 8, 1'b0, 10, 3'd2, 3'd2, 1'b1, '1);
  endtask  // Automatic

  // Zero length
  task automatic test_zero_length();
    set_plain();
    run_regs(1, 2, 3, 1'b0, 0, 3'd2, 3'd0, 1'b1, '1);
  endtask  // Automatic

  // Accumulator read
  task automatic test_accumulator();
    set_plain();
    run_regs(1, 8, 16, 1'b1, 8, 3'd1, 3'd1, 1'b1, '1);
  endtask  // Automatic

  // Mask holes
  task automatic test_mask_holes();
    set_plain();
    run_regs(1, 8, 16, 1'b0, 4, 3'd2, 3'd0, 1'b0, MaxElems'('b1010));
  endtask  // Automatic

  // Fractional grouping
  task automatic test_fractional();
    set_plain();
    run_regs(1, 8, 16, 1'b0, 2, 3'd2, 3'd7, 1'b1, '1);
  endtask  // Automatic

  // Byte elements
  task automatic test_bytes();
    set_plain();
    run_regs(2, 4, 6, 1'b0, 16, 3'd0, 3'd0, 1'b1, '1);
  endtask  // Automatic

  // Byte multiply rate
  task automatic test_byte_mul_rate();
    set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_SAME, 1'b1, 1'b0, 1'b0);
    run_regs(2, 4, 6, 1'b0, 16, 3'd0, 3'd0, 1'b1, '1);
  endtask  // Automatic

  // Widening walk
  task automatic test_widening();
    set_shape(VEC_REL_WIDE, VEC_REL_SAME, VEC_REL_SAME, 1'b0, 1'b0, 1'b0);
    run_regs(2, 4, 8, 1'b0, 8, 3'd1, 3'd0, 1'b1, '1);
  endtask  // Automatic

  // Narrowing walk
  task automatic test_narrowing();
    set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_WIDE, 1'b0, 1'b0, 1'b0);
    run_regs(2, 4, 8, 1'b0, 8, 3'd1, 3'd0, 1'b1, '1);
  endtask  // Automatic

  // Reduction write
  task automatic test_reduction();
    set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_SAME, 1'b0, 1'b1, 1'b0);
    run_regs(2, 4, 8, 1'b0, 8, 3'd1, 3'd1, 1'b1, '1);
  endtask  // Automatic

  // One element steps
  task automatic test_serial();
    set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_SAME, 1'b0, 1'b1, 1'b1);
    run_regs(2, 4, 8, 1'b0, 16, 3'd2, 3'd2, 1'b1, '1);
    run_regs(2, 8, 8, 1'b0, 5, 3'd2, 3'd1, 1'b0, MaxElems'('b0101));
    set_plain();
  endtask  // Automatic

  task automatic wait_idle();
    int guard;
    guard = 0;
    while (busy && guard < IdleTimeout) begin
      @(negedge clk);
      guard++;
    end
    check("went idle", VLEN'(busy), '0);
  endtask  // Automatic

  task automatic test_clock_enable();
    set_plain();
    launch(AWIDTH'(1), AWIDTH'(2), AWIDTH'(4), 1'b0, VlW'(16), 3'd2, 3'd2, 1'b1, '1);
    core_en = 1'b0;
    repeat (3) begin
      check("elem_base moved with core_en low", VLEN'(elem_base), '0);
      @(negedge clk);
    end
    core_en = 1'b1;
    @(negedge clk);
    check("elem_base stuck after core_en", VLEN'(elem_base), VLEN'(VLEN / 32));
    wait_idle();
    @(negedge clk);
  endtask  // Automatic

  task automatic sweep();
    for (int sew = 0; sew < Widths; sew++) begin
      for (int lm = 0; lm < 4; lm++) begin
        for (int t = 0; t < 3; t++) begin
          int vmax;
          int len;
          vmax = (VLEN / (8 << sew)) * (1 << lm);
          case (t)
            0: len = vmax;
            1: len = vmax / 2;
            default: len = 1;
          endcase
          set_plain();
          run_regs(1, 8, 16, 1'b0, len, 3'(sew), 3'(lm), 1'b1, '1);
          set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_SAME, 1'b1, 1'b0, 1'b0);
          run_regs(1, 8, 16, 1'b0, len, 3'(sew), 3'(lm), 1'b1, '1);
          if (sew < Widths - 1) begin
            set_shape(VEC_REL_WIDE, VEC_REL_SAME, VEC_REL_SAME, 1'b0, 1'b0, 1'b0);
            run_regs(2, 8, 16, 1'b1, len, 3'(sew), 3'(lm), 1'b1, '1);
            set_shape(VEC_REL_WIDE, VEC_REL_SAME, VEC_REL_WIDE, 1'b0, 1'b0, 1'b0);
            run_regs(2, 8, 16, 1'b0, len, 3'(sew), 3'(lm), 1'b1, '1);
            set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_WIDE, 1'b0, 1'b0, 1'b0);
            run_regs(2, 8, 16, 1'b0, len, 3'(sew), 3'(lm), 1'b1, '1);
          end
          if (sew > 0) begin
            set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_HALF, 1'b0, 1'b0, 1'b0);
            run_regs(2, 8, 16, 1'b0, len, 3'(sew), 3'(lm), 1'b1, '1);
          end
          set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_SAME, 1'b0, 1'b1, 1'b0);
          run_regs(1, 8, 16, 1'b0, len, 3'(sew), 3'(lm), 1'b1, '1);
          set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_SAME, 1'b0, 1'b1, 1'b1);
          run_regs(1, 8, 16, 1'b0, len, 3'(sew), 3'(lm), 1'($urandom), MaxElems'($urandom));
          set_plain();
        end
      end
    end
  endtask  // Automatic

  // Destination group size
  task automatic run_counted(input logic rd_vd, input logic [VlW-1:0] len, input logic [2:0] sew,
                             input logic [2:0] lmul);
    int dregs;
    dregs = (ref_total(sew, lmul) * ref_width(d_rel, sew)) / VLEN;
    if (dregs < 1) dregs = 1;
    reg_dones = 0;
    run_regs(4, 8, 16, rd_vd, int'(len), sew, lmul, 1'b1, '1);
    check("registers finished", VLEN'(reg_dones), VLEN'(dregs));
  endtask  // Automatic

  // Wide and narrow
  task automatic test_group_shapes();
    for (int i = 0; i < 5; i++) begin
      for (int sew = 0; sew < Widths - 1; sew++) begin
        logic [2:0] lm;
        int vmax;
        lm = 3'(i + 6);
        if ((lm == 3'd6) && (sew > 0)) continue;
        vmax = ref_total(3'(sew), lm);
        for (int t = 0; t < 2; t++) begin
          logic [VlW-1:0] len;
          len = VlW'(t == 0 ? vmax : 1);
          set_shape(VEC_REL_WIDE, VEC_REL_SAME, VEC_REL_SAME, 1'b0, 1'b0, 1'b0);
          run_counted(1'b1, len, 3'(sew), lm);
          set_shape(VEC_REL_WIDE, VEC_REL_SAME, VEC_REL_WIDE, 1'b0, 1'b0, 1'b0);
          run_counted(1'b0, len, 3'(sew), lm);
          set_shape(VEC_REL_WIDE, VEC_REL_SAME, VEC_REL_SAME, 1'b1, 1'b0, 1'b0);
          run_counted(1'b1, len, 3'(sew), lm);
          set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_WIDE, 1'b0, 1'b0, 1'b0);
          run_counted(1'b0, len, 3'(sew), lm);
          set_shape(VEC_REL_SAME, VEC_REL_SAME, VEC_REL_WIDE, 1'b1, 1'b0, 1'b0);
          run_counted(1'b0, len, 3'(sew), lm);
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
    $dumpfile("vec_sequencer_tb.vcd");
    $dumpvars(0, vec_sequencer_tb);

    do_reset();

    test_single_register();
    test_four_registers();
    test_tail_cut();
    test_zero_length();
    test_accumulator();
    test_mask_holes();
    test_fractional();
    test_bytes();
    test_byte_mul_rate();
    test_widening();
    test_narrowing();
    test_reduction();
    test_serial();
    test_clock_enable();
    sweep();

    test_group_shapes();

    do_verdict();
  end

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
    if (mr && (n > MulLanes)) n = MulLanes;
    if (serial) n = 1;
    return n;
  endfunction

  function automatic int ref_total(input logic [2:0] sew, input logic [2:0] lmul);
    if (lmul[2]) return (VLEN / (8 << sew)) >> (4 - lmul[1:0]);
    return ref_regs(lmul) * (VLEN / (8 << sew));
  endfunction

  // Element placement
  function automatic int ref_reg_of(input int idx, input int width);
    return (idx * width) / VLEN;
  endfunction

  function automatic int ref_bit_of(input int idx, input int width);
    return (idx * width) % VLEN;
  endfunction

  function automatic logic [VLEN-1:0] ref_strb(
      input int eb, input logic [2:0] sew, input logic [VlW-1:0] len, input logic use_all,
      input logic [MaxElems-1:0] msk, input logic sw, input logic is_last);
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

  always @(posedge clk) if (core_en && reg_done) reg_dones++;

endmodule

`default_nettype wire
