`default_nettype none

module vec_mask_tb
  import vec_pkg::*;
();

  localparam int DLEN = 128;
  localparam int MaxElems = DLEN / 8;

  int                  checks = 0;
  int                  errors = 0;

  vec_op_e             op;
  vec_src_e            src;
  logic     [     2:0] vsew;
  logic                vm;
  logic     [DLEN-1:0] vs2_data;
  logic     [DLEN-1:0] vs1_data;
  logic     [DLEN-1:0] v0_bits;
  logic     [    31:0] xdata;
  logic     [     4:0] simm;
  logic     [     7:0] elem_base;
  logic     [     7:0] vl;

  logic     [DLEN-1:0] result;
  logic     [    31:0] xresult;

  vec_mask #(
      .DLEN(DLEN)
  ) dut (
      .op       (op),
      .src      (src),
      .vsew     (vsew),
      .vm       (vm),
      .vs2_data (vs2_data),
      .vs1_data (vs1_data),
      .v0_bits  (v0_bits),
      .xdata    (xdata),
      .simm     (simm),
      .elem_base(elem_base),
      .vl       (vl),
      .result   (result),
      .xresult  (xresult)
  );

  task automatic note(input string tag, input logic [DLEN-1:0] got, input logic [DLEN-1:0] want);
    checks = checks + 1;
    if (got !== want) begin
      errors = errors + 1;
      if (errors < 15) $display("FAIL %0s got=%h want=%h", tag, got, want);
    end
  endtask

  // Inputs at rest
  task automatic init_signals();
    op        = VEC_MSEQ;
    src       = VEC_SRC_VV;
    vsew      = 3'd0;
    vm        = 1'b1;
    vs2_data  = '0;
    vs1_data  = '0;
    v0_bits   = '0;
    xdata     = '0;
    simm      = '0;
    elem_base = 8'd0;
    vl        = 8'd0;
  endtask

  // One element out
  function automatic logic signed [32:0] pick(input logic [DLEN-1:0] data, input int bits,
                                              input int idx, input logic sgn);
    logic [31:0] raw;
    int          i;
    begin
      raw = 32'd0;
      for (i = 0; i < bits; i++) raw[i] = data[idx*bits+i];
      if (sgn && raw[bits-1]) begin
        for (i = bits; i < 32; i++) raw[i] = 1'b1;
      end
      pick = sgn ? {raw[31], raw} : {1'b0, raw};
    end
  endfunction

  // A trimmed scalar
  function automatic logic signed [32:0] pick_scalar(input logic [31:0] val, input int bits,
                                                     input logic sgn);
    logic [31:0] raw;
    int          i;
    begin
      raw = 32'd0;
      for (i = 0; i < bits; i++) raw[i] = val[i];
      if (sgn && raw[bits-1]) begin
        for (i = bits; i < 32; i++) raw[i] = 1'b1;
      end
      pick_scalar = sgn ? {raw[31], raw} : {1'b0, raw};
    end
  endfunction

  function automatic logic ref_signed(input vec_op_e o);
    ref_signed = (o == VEC_MSLT) || (o == VEC_MSLE) || (o == VEC_MSGT);
  endfunction

  // Compare by subtraction
  function automatic logic ref_cmp(input vec_op_e o, input logic signed [32:0] a,
                                   input logic signed [32:0] b);
    logic signed [33:0] diff;
    begin
      diff = 34'(a) - 34'(b);
      case (o)
        VEC_MSEQ:            ref_cmp = (diff == 34'sd0);
        VEC_MSNE:            ref_cmp = (diff != 34'sd0);
        VEC_MSLTU, VEC_MSLT: ref_cmp = (diff < 34'sd0);
        VEC_MSLEU, VEC_MSLE: ref_cmp = (diff <= 34'sd0);
        VEC_MSGTU, VEC_MSGT: ref_cmp = (diff > 34'sd0);
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

  task automatic run_cmp(input vec_op_e o, input vec_src_e s, input logic [2:0] sew,
                         input string tag);
    int bits;
    int n;
    logic [MaxElems-1:0] want;
    logic signed [32:0] b;
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
        else if (s == VEC_SRC_VI) b = pick_scalar({{27{simm[4]}}, simm}, bits, ref_signed(o));
        else b = pick_scalar(xdata, bits, ref_signed(o));
        want[e] = ref_cmp(o, pick(vs2_data, bits, e, ref_signed(o)), b);
      end
      for (int e = 0; e < n; e++) note(tag, DLEN'(result[e]), DLEN'(want[e]));
    end
  endtask

  // Every compare form
  task automatic check_compares();
    vec_op_e list[8];
    begin
      list = '{VEC_MSEQ, VEC_MSNE, VEC_MSLTU, VEC_MSLT, VEC_MSLEU, VEC_MSLE, VEC_MSGTU, VEC_MSGT};
      for (int r = 0; r < 60; r++) begin
        vs2_data = {$urandom, $urandom, $urandom, $urandom};
        vs1_data = {$urandom, $urandom, $urandom, $urandom};
        xdata    = $urandom;
        simm     = 5'($urandom);
        if (r % 4 == 0) vs1_data = vs2_data;
        for (int i = 0; i < 8; i++) begin
          for (int sew = 0; sew < 3; sew++) begin
            run_cmp(list[i], VEC_SRC_VV, 3'(sew), "cmp vv");
            run_cmp(list[i], VEC_SRC_VX, 3'(sew), "cmp vx");
            run_cmp(list[i], VEC_SRC_VI, 3'(sew), "cmp vi");
          end
        end
      end
    end
  endtask

  // Edges and extremes
  task automatic check_compare_edges();
    begin
      vs2_data = 128'h00000000_00000000_80000000_7fffffff;
      vs1_data = 128'h00000000_00000000_7fffffff_80000000;
      run_cmp(VEC_MSLT, VEC_SRC_VV, 3'd2, "cmp signed edge");
      run_cmp(VEC_MSLTU, VEC_SRC_VV, 3'd2, "cmp unsigned edge");
      run_cmp(VEC_MSLE, VEC_SRC_VV, 3'd2, "cmp signed le edge");
      vs2_data = 128'hffffffff_ffffffff_ffffffff_ffffffff;
      vs1_data = '0;
      run_cmp(VEC_MSGT, VEC_SRC_VV, 3'd0, "cmp byte gt");
      run_cmp(VEC_MSGTU, VEC_SRC_VV, 3'd0, "cmp byte gtu");
      xdata = 32'hffff_ffff;
      run_cmp(VEC_MSEQ, VEC_SRC_VX, 3'd1, "cmp half eq");
      simm = 5'b11111;
      run_cmp(VEC_MSLE, VEC_SRC_VI, 3'd0, "cmp byte imm");
      run_cmp(VEC_MSLEU, VEC_SRC_VI, 3'd1, "cmp half immu");
    end
  endtask

  // Every logic form
  task automatic check_logic();
    vec_op_e list[8];
    logic [DLEN-1:0] want;
    begin
      list = '{VEC_MAND, VEC_MNAND, VEC_MANDN, VEC_MOR, VEC_MNOR, VEC_MORN, VEC_MXOR, VEC_MXNOR};
      for (int r = 0; r < 40; r++) begin
        vs2_data = {$urandom, $urandom, $urandom, $urandom};
        vs1_data = {$urandom, $urandom, $urandom, $urandom};
        for (int i = 0; i < 8; i++) begin
          op = list[i];
          #1;
          for (int b = 0; b < DLEN; b++) want[b] = ref_logic(list[i], vs2_data[b], vs1_data[b]);
          note("mask logic", result, want);
        end
      end
    end
  endtask

  // Before during after
  task automatic check_set();
    int f;
    logic [DLEN-1:0] want;
    begin
      for (int r = 0; r < 60; r++) begin
        vs2_data = {$urandom, $urandom, $urandom, $urandom};
        v0_bits  = {$urandom, $urandom, $urandom, $urandom};
        vm       = 1'($urandom);
        vl       = 8'($urandom % (DLEN + 1));
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
          note("mask set", result, want);
        end
      end
    end
  endtask

  // Counted and indexed
  task automatic check_index();
    int bits;
    int n;
    int count;
    logic [31:0] val;
    logic [DLEN-1:0] want;
    begin
      for (int r = 0; r < 40; r++) begin
        vs2_data = {$urandom, $urandom, $urandom, $urandom};
        v0_bits  = {$urandom, $urandom, $urandom, $urandom};
        vm       = 1'($urandom);
        vl       = 8'($urandom % (DLEN + 1));
        for (int sew = 0; sew < 3; sew++) begin
          bits      = 8 << sew;
          n         = DLEN / bits;
          elem_base = 8'(n * ($urandom % 4));
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
                val = (op == VEC_ID) ? 32'(int'(elem_base) + e) : 32'(count);
                for (int b = 0; b < bits; b++) begin
                  want[e*bits+b] = val[b];
                end
              end
            end
            note("mask index", result, want);
          end
        end
      end
    end
  endtask

  // Scalar summaries
  task automatic check_scalar();
    int count;
    int f;
    begin
      for (int r = 0; r < 60; r++) begin
        vs2_data = {$urandom, $urandom, $urandom, $urandom};
        v0_bits  = {$urandom, $urandom, $urandom, $urandom};
        vm       = 1'($urandom);
        vl       = 8'($urandom % (DLEN + 1));
        if (r % 7 == 0) vs2_data = '0;
        op = VEC_CPOP;
        #1;
        count = 0;
        for (int i = 0; i < DLEN; i++) if (ref_active(i) && vs2_data[i]) count = count + 1;
        note("cpop", DLEN'(xresult), DLEN'(32'(count)));
        op = VEC_FIRST;
        #1;
        f = ref_first();
        note("first", DLEN'(xresult), DLEN'((f < 0) ? 32'hFFFF_FFFF : 32'(f)));
      end
    end
  endtask

  task automatic verdict();
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask

  initial begin
    $dumpfile("vec_mask_tb.vcd");
    $dumpvars(0, vec_mask_tb);
    init_signals();
    check_compares();
    check_compare_edges();
    check_logic();
    check_set();
    check_index();
    check_scalar();
    verdict();
  end

endmodule

`default_nettype wire
