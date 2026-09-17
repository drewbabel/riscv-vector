`default_nettype none

module vec_alu_tb
  import vec_pkg::*;
();

  localparam int DLEN = 128;
  localparam int MaxElems = DLEN / 8;

  int checks = 0;
  int errors = 0;

  vec_op_e op;
  vec_src_e src;
  logic [2:0] vsew;
  logic vm;
  logic [MaxElems-1:0] mask_bits;
  logic [DLEN-1:0] vs2_data;
  logic [DLEN-1:0] vs1_data;
  logic [31:0] xdata;
  logic [4:0] simm;
  logic [DLEN-1:0] result;

  vec_alu #(
      .DLEN(DLEN)
  ) dut (
      .op(op),
      .src(src),
      .vsew(vsew),
      .vm(vm),
      .mask_bits(mask_bits),
      .vs2_data(vs2_data),
      .vs1_data(vs1_data),
      .xdata(xdata),
      .simm(simm),
      .result(result)
  );

  // Width helpers
  function automatic logic [31:0] mask_of(input int w);
    mask_of = (32'h1 << w) - 32'h1;
  endfunction

  function automatic logic [31:0] sext(input logic [31:0] v, input int w);
    sext = v[w-1] ? (v | ~mask_of(w)) : (v & mask_of(w));
  endfunction

  function automatic int width_of(input logic [2:0] sew);
    width_of = 8 << sew;
  endfunction

  // Reference model
  function automatic logic [31:0] ref_lane(input vec_op_e o, input int w, input logic [31:0] ra,
                                           input logic [31:0] rb, input logic mbit,
                                           input logic vmi);
    logic [31:0] m;
    logic [31:0] a;
    logic [31:0] b;
    logic [31:0] sa;
    logic [31:0] sb;
    logic [31:0] sr;
    int sh;
    begin
      m  = mask_of(w);
      a  = ra & m;
      b  = rb & m;
      sa = sext(a, w);
      sb = sext(b, w);
      sh = b & (w - 1);
      sr = $signed(sa) >>> sh;
      case (o)
        VEC_ADD:   ref_lane = (a + b) & m;
        VEC_SUB:   ref_lane = (a - b) & m;
        VEC_RSUB:  ref_lane = (b - a) & m;
        VEC_AND:   ref_lane = (a & b) & m;
        VEC_OR:    ref_lane = (a | b) & m;
        VEC_XOR:   ref_lane = (a ^ b) & m;
        VEC_SLL:   ref_lane = (a << sh) & m;
        VEC_SRL:   ref_lane = (a >> sh) & m;
        VEC_SRA:   ref_lane = sr & m;
        VEC_MINU:  ref_lane = (a < b) ? a : b;
        VEC_MIN:   ref_lane = ($signed(sa) < $signed(sb)) ? a : b;
        VEC_MAXU:  ref_lane = (a > b) ? a : b;
        VEC_MAX:   ref_lane = ($signed(sa) > $signed(sb)) ? a : b;
        VEC_ADC:   ref_lane = (a + b + {31'd0, mbit}) & m;
        VEC_SBC:   ref_lane = (a - b - {31'd0, mbit}) & m;
        VEC_MERGE: ref_lane = (vmi || mbit) ? b : a;
        default:   ref_lane = 32'd0;
      endcase
    end
  endfunction

  function automatic logic [31:0] elem_of(input logic [DLEN-1:0] v, input int w, input int e);
    elem_of = 32'(v >> (e * w)) & mask_of(w);
  endfunction

  function automatic logic [31:0] ref_second(input int w, input int e);
    logic [31:0] raw;
    begin
      case (src)
        VEC_SRC_VV: raw = 32'(vs1_data >> (e * w));
        VEC_SRC_VI: raw = {{27{simm[4]}}, simm};
        default:    raw = xdata;
      endcase
      ref_second = raw & mask_of(w);
    end
  endfunction

  task automatic init_signals();
    op        = VEC_ADD;
    src       = VEC_SRC_VV;
    vsew      = 3'd2;
    vm        = 1'b1;
    mask_bits = '0;
    vs2_data  = '0;
    vs1_data  = '0;
    xdata     = '0;
    simm      = '0;
    #1;
  endtask

  // The one primitive
  task automatic drive(input vec_op_e o, input vec_src_e s, input logic [2:0] sew, input logic m,
                       input logic [MaxElems-1:0] mb, input logic [DLEN-1:0] d2,
                       input logic [DLEN-1:0] d1, input logic [31:0] xd, input logic [4:0] im);
    op        = o;
    src       = s;
    vsew      = sew;
    vm        = m;
    mask_bits = mb;
    vs2_data  = d2;
    vs1_data  = d1;
    xdata     = xd;
    simm      = im;
    #1;
  endtask

  task automatic check_elems();
    int w;
    int n;
    logic [31:0] got;
    logic [31:0] want;
    begin
      w = width_of(vsew);
      n = DLEN / w;
      for (int e = 0; e < n; e++) begin
        got = elem_of(result, w, e);
        want = ref_lane(op, w, elem_of(vs2_data, w, e), ref_second(w, e), mask_bits[e], vm);
        checks = checks + 1;
        if (got !== want) begin
          errors = errors + 1;
          if (errors < 20)
            $display(
                "FAIL op=%0d sew=%0d src=%0d elem=%0d got=%h want=%h", op, vsew, src, e, got, want
            );
        end
      end
    end
  endtask

  task automatic run_case(input vec_op_e o, input vec_src_e s, input logic [2:0] sew, input logic m,
                          input logic [MaxElems-1:0] mb, input logic [DLEN-1:0] d2,
                          input logic [DLEN-1:0] d1, input logic [31:0] xd, input logic [4:0] im);
    drive(o, s, sew, m, mb, d2, d1, xd, im);
    check_elems();
  endtask

  // Full sweep
  task automatic sweep(input int rounds);
    vec_op_e o;
    vec_src_e s;
    logic [DLEN-1:0] d2;
    logic [DLEN-1:0] d1;
    begin
      for (int r = 0; r < rounds; r++) begin
        for (int oi = 0; oi < 16; oi++) begin
          case (oi)
            0: o = VEC_ADD;
            1: o = VEC_SUB;
            2: o = VEC_RSUB;
            3: o = VEC_AND;
            4: o = VEC_OR;
            5: o = VEC_XOR;
            6: o = VEC_SLL;
            7: o = VEC_SRL;
            8: o = VEC_SRA;
            9: o = VEC_MINU;
            10: o = VEC_MIN;
            11: o = VEC_MAXU;
            12: o = VEC_MAX;
            13: o = VEC_ADC;
            14: o = VEC_SBC;
            default: o = VEC_MERGE;
          endcase
          for (int sw = 0; sw < 3; sw++) begin
            for (int si = 0; si < 3; si++) begin
              case (si)
                0: s = VEC_SRC_VV;
                1: s = VEC_SRC_VX;
                default: s = VEC_SRC_VI;
              endcase
              d2 = {$urandom, $urandom, $urandom, $urandom};
              d1 = {$urandom, $urandom, $urandom, $urandom};
              run_case(o, s, 3'(sw), 1'b0, MaxElems'($urandom), d2, d1, $urandom, 5'($urandom));
              run_case(o, s, 3'(sw), 1'b1, MaxElems'($urandom), d2, d1, $urandom, 5'($urandom));
            end
          end
        end
      end
    end
  endtask

  // Shift boundaries
  task automatic shift_edges();
    for (int sw = 0; sw < 3; sw++) begin
      for (int sh = 0; sh < 32; sh++) begin
        run_case(VEC_SLL, VEC_SRC_VX, 3'(sw), 1'b1, '0, {4{32'h8001_7FFE}}, '0, 32'(sh), 5'd0);
        run_case(VEC_SRL, VEC_SRC_VX, 3'(sw), 1'b1, '0, {4{32'h8001_7FFE}}, '0, 32'(sh), 5'd0);
        run_case(VEC_SRA, VEC_SRC_VX, 3'(sw), 1'b1, '0, {4{32'h8001_7FFE}}, '0, 32'(sh), 5'd0);
      end
    end
  endtask

  // Sign boundaries
  task automatic sign_edges();
    logic [DLEN-1:0] lo;
    logic [DLEN-1:0] hi;
    begin
      lo = {4{32'h8000_0000}};
      hi = {4{32'h7FFF_FFFF}};
      for (int sw = 0; sw < 3; sw++) begin
        run_case(VEC_MIN, VEC_SRC_VV, 3'(sw), 1'b1, '0, lo, hi, '0, 5'd0);
        run_case(VEC_MAX, VEC_SRC_VV, 3'(sw), 1'b1, '0, lo, hi, '0, 5'd0);
        run_case(VEC_MINU, VEC_SRC_VV, 3'(sw), 1'b1, '0, lo, hi, '0, 5'd0);
        run_case(VEC_MAXU, VEC_SRC_VV, 3'(sw), 1'b1, '0, lo, hi, '0, 5'd0);
        run_case(VEC_MIN, VEC_SRC_VV, 3'(sw), 1'b1, '0, hi, lo, '0, 5'd0);
        run_case(VEC_MAX, VEC_SRC_VV, 3'(sw), 1'b1, '0, hi, lo, '0, 5'd0);
        run_case(VEC_ADD, VEC_SRC_VV, 3'(sw), 1'b1, '0, hi, hi, '0, 5'd0);
        run_case(VEC_SUB, VEC_SRC_VV, 3'(sw), 1'b1, '0, lo, hi, '0, 5'd0);
      end
    end
  endtask

  // Carry and borrow
  task automatic carry_edges();
    for (int sw = 0; sw < 3; sw++) begin
      run_case(VEC_ADC, VEC_SRC_VV, 3'(sw), 1'b0, '1, {4{32'hFFFF_FFFF}}, '0, '0, 5'd0);
      run_case(VEC_ADC, VEC_SRC_VV, 3'(sw), 1'b0, '0, {4{32'hFFFF_FFFF}}, '0, '0, 5'd0);
      run_case(VEC_SBC, VEC_SRC_VV, 3'(sw), 1'b0, '1, '0, '0, '0, 5'd0);
      run_case(VEC_SBC, VEC_SRC_VV, 3'(sw), 1'b0, '0, '0, '0, '0, 5'd0);
    end
  endtask

  // Merge takes data
  task automatic merge_cases();
    logic [DLEN-1:0] d2;
    logic [DLEN-1:0] d1;
    begin
      d2 = {4{32'hAAAA_AAAA}};
      d1 = {4{32'h5555_5555}};
      for (int sw = 0; sw < 3; sw++) begin
        run_case(VEC_MERGE, VEC_SRC_VV, 3'(sw), 1'b0, '0, d2, d1, '0, 5'd0);
        run_case(VEC_MERGE, VEC_SRC_VV, 3'(sw), 1'b0, '1, d2, d1, '0, 5'd0);
        run_case(VEC_MERGE, VEC_SRC_VV, 3'(sw), 1'b1, '0, d2, d1, '0, 5'd0);
        run_case(VEC_MERGE, VEC_SRC_VX, 3'(sw), 1'b0, MaxElems'(16'hA5A5), d2, d1, 32'h1234_5678,
                 5'd0);
      end
    end
  endtask

  // Immediate sign extension
  task automatic imm_cases();
    for (int sw = 0; sw < 3; sw++) begin
      for (int im = 0; im < 32; im++) begin
        run_case(VEC_ADD, VEC_SRC_VI, 3'(sw), 1'b1, '0, {4{32'h0F0F_0F0F}}, '0, '0, 5'(im));
        run_case(VEC_RSUB, VEC_SRC_VI, 3'(sw), 1'b1, '0, {4{32'h0F0F_0F0F}}, '0, '0, 5'(im));
        run_case(VEC_AND, VEC_SRC_VI, 3'(sw), 1'b1, '0, {4{32'hFFFF_FFFF}}, '0, '0, 5'(im));
      end
    end
  endtask

  task automatic verdict();
    $display("vec_alu: %0d checks, %0d errors", checks, errors);
    if (errors != 0) $fatal(1, "vec_alu FAILED");
    $finish;
  endtask

  initial begin
    // Quiet start
    init_signals();

    // Full sweep
    sweep(12);

    // Shift boundaries
    shift_edges();

    // Sign boundaries
    sign_edges();

    // Carry and borrow
    carry_edges();

    // Merge takes data
    merge_cases();

    // Immediate sign extension
    imm_cases();

    verdict();
  end

endmodule

`default_nettype wire
