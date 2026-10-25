`default_nettype none

module vec_mask_tb
  import vec_pkg::*;
();

  localparam int DLEN = arch_pkg::VLEN;
  localparam int ELEN = arch_pkg::ELEN;
  localparam int XLEN = arch_pkg::XLEN;
  localparam int MaxElems = DLEN / 8;
  localparam int VlW = $clog2(DLEN + 1);
  localparam int Words = DLEN / 32;
  localparam int Widths = $clog2(ELEN / 8) + 1;
  localparam int MinChecks = 49000;

  int                      checks = 0;
  int                      errors = 0;
  int                      max_errors = 0;

  vec_op_e                 op;
  vec_src_e                src;
  logic     [         2:0] vsew;
  logic                    vm;
  logic     [    DLEN-1:0] vs2_data;
  logic     [    DLEN-1:0] vs1_data;
  logic     [    DLEN-1:0] v0_bits;
  logic     [MaxElems-1:0] mask_bits;
  logic     [    XLEN-1:0] xdata;
  logic     [         4:0] simm;
  logic     [     VlW-1:0] elem_base;
  logic     [     VlW-1:0] vl;

  logic     [    DLEN-1:0] result;
  logic     [    XLEN-1:0] xresult;

  vec_mask #(
      .DLEN(DLEN),
      .ELEN(ELEN),
      .XLEN(XLEN)
  ) dut (
      .op       (op),
      .src      (src),
      .vsew     (vsew),
      .vm       (vm),
      .vs2_data (vs2_data),
      .vs1_data (vs1_data),
      .v0_bits  (v0_bits),
      .mask_bits(mask_bits),
      .xdata    (xdata),
      .simm     (simm),
      .elem_base(elem_base),
      .vl       (vl),
      .result   (result),
      .xresult  (xresult)
  );

  task automatic check(input string name, input logic [DLEN-1:0] got, input logic [DLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  // Inputs at rest
  task automatic do_reset();
    op        = VEC_MSEQ;
    src       = VEC_SRC_VV;
    vsew      = 3'd0;
    vm        = 1'b1;
    vs2_data  = '0;
    vs1_data  = '0;
    v0_bits   = '0;
    mask_bits = '0;
    xdata     = '0;
    simm      = '0;
    elem_base = '0;
    vl        = '0;
  endtask  // Automatic

  // Random register data
  function automatic logic [DLEN-1:0] rand_data();
    rand_data = '0;
    for (int i = 0; i < Words; i++) rand_data = (rand_data << 32) | DLEN'($urandom);
  endfunction

  task automatic run_cmp(input vec_op_e o, input vec_src_e s, input logic [2:0] sew,
                         input string tag);
    int bits;
    int n;
    logic [MaxElems-1:0] want;
    logic signed [ELEN:0] b;
    begin
      op   = o;
      src  = s;
      vsew = sew;
      bits = 8 << sew;
      n    = DLEN / bits;
      #1;
      want = '0;
      for (int e = 0; e < n; e++) begin
        if (s == VEC_SRC_VV) b = pick(vs1_data, bits, e, ref_signed(o));
        else if (s == VEC_SRC_VI)
          b = pick_scalar({{(ELEN - 5) {simm[4]}}, simm}, bits, ref_signed(o));
        else b = pick_scalar(ELEN'(xdata), bits, ref_signed(o));
        want[e] = ref_cmp(o, pick(vs2_data, bits, e, ref_signed(o)), b);
      end
      for (int e = 0; e < n; e++) check(tag, DLEN'(result[e]), DLEN'(want[e]));
    end
  endtask  // Automatic

  // Every compare form
  task automatic check_compares();
    vec_op_e list[8];
    begin
      list = '{VEC_MSEQ, VEC_MSNE, VEC_MSLTU, VEC_MSLT, VEC_MSLEU, VEC_MSLE, VEC_MSGTU, VEC_MSGT};
      for (int r = 0; r < 60; r++) begin
        vs2_data = rand_data();
        vs1_data = rand_data();
        xdata    = XLEN'($urandom);
        simm     = 5'($urandom);
        if (r % 4 == 0) vs1_data = vs2_data;
        for (int i = 0; i < $size(list); i++) begin
          for (int sew = 0; sew < Widths; sew++) begin
            run_cmp(list[i], VEC_SRC_VV, 3'(sew), "cmp vv");
            run_cmp(list[i], VEC_SRC_VX, 3'(sew), "cmp vx");
            run_cmp(list[i], VEC_SRC_VI, 3'(sew), "cmp vi");
          end
        end
      end
    end
  endtask  // Automatic

  // Edges and extremes
  task automatic check_compare_edges();
    begin
      vs2_data = DLEN'(64'h80000000_7fffffff);
      vs1_data = DLEN'(64'h7fffffff_80000000);
      run_cmp(VEC_MSLT, VEC_SRC_VV, 3'd2, "cmp signed edge");
      run_cmp(VEC_MSLTU, VEC_SRC_VV, 3'd2, "cmp unsigned edge");
      run_cmp(VEC_MSLE, VEC_SRC_VV, 3'd2, "cmp signed le edge");
      vs2_data = '1;
      vs1_data = '0;
      run_cmp(VEC_MSGT, VEC_SRC_VV, 3'd0, "cmp byte gt");
      run_cmp(VEC_MSGTU, VEC_SRC_VV, 3'd0, "cmp byte gtu");
      xdata = '1;
      run_cmp(VEC_MSEQ, VEC_SRC_VX, 3'd1, "cmp half eq");
      simm = '1;
      run_cmp(VEC_MSLE, VEC_SRC_VI, 3'd0, "cmp byte imm");
      run_cmp(VEC_MSLEU, VEC_SRC_VI, 3'd1, "cmp half immu");
    end
  endtask  // Automatic

  // Carry borrow out
  task automatic run_carry(input vec_op_e o, input vec_src_e s, input logic [2:0] sew,
                           input string tag);
    int bits;
    int n;
    longint a;
    longint b;
    longint c;
    logic [MaxElems-1:0] want;
    begin
      op   = o;
      src  = s;
      vsew = sew;
      bits = 8 << sew;
      n    = DLEN / bits;
      #1;
      want = '0;
      for (int e = 0; e < n; e++) begin
        a = longint'(pick(vs2_data, bits, e, 1'b0));
        if (s == VEC_SRC_VV) b = longint'(pick(vs1_data, bits, e, 1'b0));
        else if (s == VEC_SRC_VI)
          b = longint'(pick_scalar({{(ELEN - 5) {simm[4]}}, simm}, bits, 1'b0));
        else b = longint'(pick_scalar(ELEN'(xdata), bits, 1'b0));
        c = (!vm && mask_bits[e]) ? 1 : 0;
        if (o == VEC_MADC) want[e] = (a + b + c) >= (longint'(1) << bits);
        else want[e] = a < (b + c);
      end
      for (int e = 0; e < n; e++) check(tag, DLEN'(result[e]), DLEN'(want[e]));
    end
  endtask  // Automatic

  // Every carry form
  task automatic check_carry();
    begin
      for (int r = 0; r < 60; r++) begin
        vs2_data  = rand_data();
        vs1_data  = rand_data();
        mask_bits = MaxElems'(rand_data());
        xdata     = XLEN'($urandom);
        simm      = 5'($urandom);
        vm        = 1'(r % 2);
        if (r % 4 == 0) vs1_data = vs2_data;
        if (r % 5 == 0) vs1_data = ~vs2_data;
        for (int sew = 0; sew < Widths; sew++) begin
          run_carry(VEC_MADC, VEC_SRC_VV, 3'(sew), "madc vv");
          run_carry(VEC_MADC, VEC_SRC_VX, 3'(sew), "madc vx");
          run_carry(VEC_MADC, VEC_SRC_VI, 3'(sew), "madc vi");
          run_carry(VEC_MSBC, VEC_SRC_VV, 3'(sew), "msbc vv");
          run_carry(VEC_MSBC, VEC_SRC_VX, 3'(sew), "msbc vx");
        end
      end
      vm = 1'b1;
    end
  endtask  // Automatic

  // Every logic form
  task automatic check_logic();
    vec_op_e list[8];
    logic [DLEN-1:0] want;
    begin
      list = '{VEC_MAND, VEC_MNAND, VEC_MANDN, VEC_MOR, VEC_MNOR, VEC_MORN, VEC_MXOR, VEC_MXNOR};
      for (int r = 0; r < 40; r++) begin
        vs2_data = rand_data();
        vs1_data = rand_data();
        for (int i = 0; i < $size(list); i++) begin
          op = list[i];
          #1;
          for (int b = 0; b < DLEN; b++) want[b] = ref_logic(list[i], vs2_data[b], vs1_data[b]);
          check("mask logic", result, want);
        end
      end
    end
  endtask  // Automatic

  // Before during after
  task automatic check_set();
    int f;
    logic [DLEN-1:0] want;
    begin
      for (int r = 0; r < 60; r++) begin
        vs2_data = rand_data();
        v0_bits  = rand_data();
        vm       = 1'($urandom);
        vl       = VlW'($urandom_range(DLEN));
        if (r % 5 == 0) vs2_data = '0;
        for (int k = 0; k < 3; k++) begin
          op = (k == 0) ? VEC_MSBF : ((k == 1) ? VEC_MSIF : VEC_MSOF);
          #1;
          f    = ref_first();
          want = '0;
          for (int i = 0; i < DLEN; i++) begin
            if (op == VEC_MSBF) want[i] = (f < 0) ? 1'b1 : (i < f);
            else if (op == VEC_MSIF) want[i] = (f < 0) ? 1'b1 : (i <= f);
            else want[i] = (f >= 0) && (i == f);
          end
          check("mask set", result, want);
        end
      end
    end
  endtask  // Automatic

  // Counted and indexed
  task automatic check_index();
    int bits;
    int n;
    int count;
    logic [ELEN-1:0] val;
    logic [DLEN-1:0] want;
    begin
      for (int r = 0; r < 40; r++) begin
        vs2_data = rand_data();
        v0_bits  = rand_data();
        vm       = 1'($urandom);
        vl       = VlW'($urandom_range(DLEN));
        for (int sew = 0; sew < Widths; sew++) begin
          bits      = 8 << sew;
          n         = DLEN / bits;
          elem_base = VlW'(n * $urandom_range(3));
          for (int k = 0; k < 2; k++) begin
            op   = (k == 0) ? VEC_IOTA : VEC_ID;
            vsew = 3'(sew);
            #1;
            want = '0;
            for (int e = 0; e < n; e++) begin
              if (int'(elem_base) + e < DLEN) begin
                count = 0;
                for (int j = 0; j < int'(elem_base) + e; j++) begin
                  if (ref_active(j) && vs2_data[j]) count = count + 1;
                end
                val = (op == VEC_ID) ? ELEN'(int'(elem_base) + e) : ELEN'(count);
                for (int b = 0; b < bits; b++) begin
                  want[e*bits+b] = val[b];
                end
              end
            end
            check("mask index", result, want);
          end
        end
      end
    end
  endtask  // Automatic

  // Scalar summaries
  task automatic check_scalar();
    int count;
    int f;
    begin
      for (int r = 0; r < 60; r++) begin
        vs2_data = rand_data();
        v0_bits  = rand_data();
        vm       = 1'($urandom);
        vl       = VlW'($urandom_range(DLEN));
        if (r % 7 == 0) vs2_data = '0;
        op = VEC_CPOP;
        #1;
        count = 0;
        for (int i = 0; i < DLEN; i++) if (ref_active(i) && vs2_data[i]) count = count + 1;
        check("cpop", DLEN'(xresult), DLEN'(XLEN'(count)));
        op = VEC_FIRST;
        #1;
        f = ref_first();
        check("first", DLEN'(xresult), DLEN'((f < 0) ? {XLEN{1'b1}} : XLEN'(f)));
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
    $dumpfile("vec_mask_tb.vcd");
    $dumpvars(0, vec_mask_tb);
    do_reset();
    check_compares();
    check_compare_edges();
    check_carry();
    check_logic();
    check_set();
    check_index();
    check_scalar();
    do_verdict();
  end

  // One element out
  function automatic logic signed [ELEN:0] pick(input logic [DLEN-1:0] data, input int bits,
                                                input int idx, input logic sgn);
    logic [ELEN-1:0] raw;
    int              i;
    begin
      raw = '0;
      for (i = 0; i < bits; i++) raw[i] = data[idx*bits+i];
      if (sgn && raw[bits-1]) begin
        for (i = bits; i < ELEN; i++) raw[i] = 1'b1;
      end
      pick = sgn ? {raw[ELEN-1], raw} : {1'b0, raw};
    end
  endfunction

  // Trimmed scalar
  function automatic logic signed [ELEN:0] pick_scalar(input logic [ELEN-1:0] val, input int bits,
                                                       input logic sgn);
    logic [ELEN-1:0] raw;
    int              i;
    begin
      raw = '0;
      for (i = 0; i < bits; i++) raw[i] = val[i];
      if (sgn && raw[bits-1]) begin
        for (i = bits; i < ELEN; i++) raw[i] = 1'b1;
      end
      pick_scalar = sgn ? {raw[ELEN-1], raw} : {1'b0, raw};
    end
  endfunction

  function automatic logic ref_signed(input vec_op_e o);
    ref_signed = (o == VEC_MSLT) || (o == VEC_MSLE) || (o == VEC_MSGT);
  endfunction

  // Compare by subtraction
  function automatic logic ref_cmp(input vec_op_e o, input logic signed [ELEN:0] a,
                                   input logic signed [ELEN:0] b);
    logic signed [ELEN+1:0] diff;
    begin
      diff = (ELEN + 2)'(a) - (ELEN + 2)'(b);
      case (o)
        VEC_MSEQ:            ref_cmp = (diff == 0);
        VEC_MSNE:            ref_cmp = (diff != 0);
        VEC_MSLTU, VEC_MSLT: ref_cmp = (diff < 0);
        VEC_MSLEU, VEC_MSLE: ref_cmp = (diff <= 0);
        VEC_MSGTU, VEC_MSGT: ref_cmp = (diff > 0);
        default:             ref_cmp = 1'b0;
      endcase
    end
  endfunction

  // Bitwise truth table
  function automatic logic ref_logic(input vec_op_e o, input logic a, input logic b);
    case (o)
      VEC_MAND:  ref_logic = a & b;
      VEC_MNAND: ref_logic = ~(a & b);
      VEC_MANDN: ref_logic = a & ~b;
      VEC_MOR:   ref_logic = a | b;
      VEC_MNOR:  ref_logic = ~(a | b);
      VEC_MORN:  ref_logic = a | ~b;
      VEC_MXOR:  ref_logic = a ^ b;
      VEC_MXNOR: ref_logic = ~(a ^ b);
      default:   ref_logic = 1'b0;
    endcase
  endfunction

  // Live and enabled
  function automatic logic ref_active(input int i);
    ref_active = (i < int'(vl)) && (vm || v0_bits[i]);
  endfunction

  // First enabled hit
  function automatic int ref_first();
    int i;
    begin
      ref_first = -1;
      for (i = DLEN - 1; i >= 0; i--) begin
        if (ref_active(i) && vs2_data[i]) ref_first = i;
      end
    end
  endfunction

endmodule

`default_nettype wire
