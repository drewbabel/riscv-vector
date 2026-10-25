`default_nettype none

module vec_alu_tb
  import vec_pkg::*;
();

  localparam int DLEN = arch_pkg::VLEN;
  localparam int ELEN = arch_pkg::ELEN;
  localparam int XLEN = arch_pkg::XLEN;
  localparam int MaxElems = DLEN / 8;
  localparam int Words = DLEN / ELEN;
  localparam int Sews = $clog2(ELEN / 8) + 1;
  localparam int VsewW = 3;
  localparam int SimmW = arch_pkg::RegAddrW;
  localparam int SweepRounds = 12;
  localparam int MinChecks = 2500 * MaxElems;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  vec_op_e op;
  vec_src_e src;
  logic [VsewW-1:0] vsew;
  logic vm;
  logic [MaxElems-1:0] mask_bits;
  logic [DLEN-1:0] vs2_data;
  logic [DLEN-1:0] vs1_data;
  logic [XLEN-1:0] xdata;
  logic [SimmW-1:0] simm;
  logic [DLEN-1:0] result;

  vec_op_e alu_ops[17] = '{
      VEC_ADD,
      VEC_SUB,
      VEC_RSUB,
      VEC_AND,
      VEC_OR,
      VEC_XOR,
      VEC_SLL,
      VEC_SRL,
      VEC_SRA,
      VEC_MINU,
      VEC_MIN,
      VEC_MAXU,
      VEC_MAX,
      VEC_ADC,
      VEC_SBC,
      VEC_MERGE,
      VEC_MVNRR
  };
  vec_src_e alu_srcs[3] = '{VEC_SRC_VV, VEC_SRC_VX, VEC_SRC_VI};

  vec_alu #(
      .DLEN(DLEN),
      .XLEN(XLEN)
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

  initial void'($value$plusargs("max_errors=%d", max_errors));

  task automatic check(input string name, input logic [ELEN-1:0] got, input logic [ELEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    op        = VEC_ADD;
    src       = VEC_SRC_VV;
    vsew      = '0;
    vm        = 1'b1;
    mask_bits = '0;
    vs2_data  = '0;
    vs1_data  = '0;
    xdata     = '0;
    simm      = '0;
    #1;
  endtask  // Automatic

  // Random register data
  function automatic logic [DLEN-1:0] rand_data();
    rand_data = '0;
    for (int i = 0; i < Words; i++) rand_data = (rand_data << ELEN) | DLEN'(ELEN'($urandom));
  endfunction

  // The one primitive
  task automatic drive(input vec_op_e o, input vec_src_e s, input logic [VsewW-1:0] sew,
                       input logic m, input logic [MaxElems-1:0] mb, input logic [DLEN-1:0] d2,
                       input logic [DLEN-1:0] d1, input logic [XLEN-1:0] xd,
                       input logic [SimmW-1:0] im);
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
  endtask  // Automatic

  task automatic check_elems();
    int w;
    w = width_of(vsew);
    for (int e = 0; e < DLEN / w; e++) begin
      check($sformatf("op=%0d sew=%0d src=%0d elem=%0d", op, vsew, src, e), elem_of(result, w, e),
            ref_lane(op, w, elem_of(vs2_data, w, e), ref_second(w, e), mask_bits[e], vm));
    end
  endtask  // Automatic

  task automatic run_case(input vec_op_e o, input vec_src_e s, input logic [VsewW-1:0] sew,
                          input logic m, input logic [MaxElems-1:0] mb, input logic [DLEN-1:0] d2,
                          input logic [DLEN-1:0] d1, input logic [XLEN-1:0] xd,
                          input logic [SimmW-1:0] im);
    drive(o, s, sew, m, mb, d2, d1, xd, im);
    check_elems();
  endtask  // Automatic

  // Full sweep
  task automatic sweep(input int rounds);
    logic [DLEN-1:0] d2;
    logic [DLEN-1:0] d1;
    for (int r = 0; r < rounds; r++) begin
      for (int oi = 0; oi < $size(alu_ops); oi++) begin
        for (int sw = 0; sw < Sews; sw++) begin
          for (int si = 0; si < $size(alu_srcs); si++) begin
            d2 = rand_data();
            d1 = rand_data();
            run_case(alu_ops[oi], alu_srcs[si], VsewW'(sw), 1'b0, MaxElems'($urandom), d2, d1,
                     XLEN'($urandom), SimmW'($urandom));
            run_case(alu_ops[oi], alu_srcs[si], VsewW'(sw), 1'b1, MaxElems'($urandom), d2, d1,
                     XLEN'($urandom), SimmW'($urandom));
          end
        end
      end
    end
  endtask  // Automatic

  // Shift boundaries
  task automatic shift_edges();
    logic [DLEN-1:0] d2;
    d2 = {Words{ELEN'('h8001_7FFE)}};
    for (int sw = 0; sw < Sews; sw++) begin
      for (int sh = 0; sh < ELEN; sh++) begin
        run_case(VEC_SLL, VEC_SRC_VX, VsewW'(sw), 1'b1, '0, d2, '0, XLEN'(sh), '0);
        run_case(VEC_SRL, VEC_SRC_VX, VsewW'(sw), 1'b1, '0, d2, '0, XLEN'(sh), '0);
        run_case(VEC_SRA, VEC_SRC_VX, VsewW'(sw), 1'b1, '0, d2, '0, XLEN'(sh), '0);
      end
    end
  endtask  // Automatic

  // Sign boundaries
  task automatic sign_edges();
    logic [DLEN-1:0] lo;
    logic [DLEN-1:0] hi;
    lo = {Words{ELEN'('h8000_0000)}};
    hi = {Words{ELEN'('h7FFF_FFFF)}};
    for (int sw = 0; sw < Sews; sw++) begin
      run_case(VEC_MIN, VEC_SRC_VV, VsewW'(sw), 1'b1, '0, lo, hi, '0, '0);
      run_case(VEC_MAX, VEC_SRC_VV, VsewW'(sw), 1'b1, '0, lo, hi, '0, '0);
      run_case(VEC_MINU, VEC_SRC_VV, VsewW'(sw), 1'b1, '0, lo, hi, '0, '0);
      run_case(VEC_MAXU, VEC_SRC_VV, VsewW'(sw), 1'b1, '0, lo, hi, '0, '0);
      run_case(VEC_MIN, VEC_SRC_VV, VsewW'(sw), 1'b1, '0, hi, lo, '0, '0);
      run_case(VEC_MAX, VEC_SRC_VV, VsewW'(sw), 1'b1, '0, hi, lo, '0, '0);
      run_case(VEC_ADD, VEC_SRC_VV, VsewW'(sw), 1'b1, '0, hi, hi, '0, '0);
      run_case(VEC_SUB, VEC_SRC_VV, VsewW'(sw), 1'b1, '0, lo, hi, '0, '0);
    end
  endtask  // Automatic

  // Carry and borrow
  task automatic carry_edges();
    for (int sw = 0; sw < Sews; sw++) begin
      run_case(VEC_ADC, VEC_SRC_VV, VsewW'(sw), 1'b0, '1, '1, '0, '0, '0);
      run_case(VEC_ADC, VEC_SRC_VV, VsewW'(sw), 1'b0, '0, '1, '0, '0, '0);
      run_case(VEC_SBC, VEC_SRC_VV, VsewW'(sw), 1'b0, '1, '0, '0, '0, '0);
      run_case(VEC_SBC, VEC_SRC_VV, VsewW'(sw), 1'b0, '0, '0, '0, '0, '0);
    end
  endtask  // Automatic

  // Merge takes data
  task automatic merge_cases();
    logic [DLEN-1:0] d2;
    logic [DLEN-1:0] d1;
    d2 = {Words{ELEN'('hAAAA_AAAA)}};
    d1 = {Words{ELEN'('h5555_5555)}};
    for (int sw = 0; sw < Sews; sw++) begin
      run_case(VEC_MERGE, VEC_SRC_VV, VsewW'(sw), 1'b0, '0, d2, d1, '0, '0);
      run_case(VEC_MERGE, VEC_SRC_VV, VsewW'(sw), 1'b0, '1, d2, d1, '0, '0);
      run_case(VEC_MERGE, VEC_SRC_VV, VsewW'(sw), 1'b1, '0, d2, d1, '0, '0);
      run_case(VEC_MERGE, VEC_SRC_VX, VsewW'(sw), 1'b0, MaxElems'('hA5A5), d2, d1,
               XLEN'('h1234_5678), '0);
    end
  endtask  // Automatic

  // Immediate sign extension
  task automatic imm_cases();
    for (int sw = 0; sw < Sews; sw++) begin
      for (int im = 0; im < 2 ** SimmW; im++) begin
        run_case(VEC_ADD, VEC_SRC_VI, VsewW'(sw), 1'b1, '0, {Words{ELEN'('h0F0F_0F0F)}}, '0, '0,
                 SimmW'(im));
        run_case(VEC_RSUB, VEC_SRC_VI, VsewW'(sw), 1'b1, '0, {Words{ELEN'('h0F0F_0F0F)}}, '0, '0,
                 SimmW'(im));
        run_case(VEC_AND, VEC_SRC_VI, VsewW'(sw), 1'b1, '0, '1, '0, '0, SimmW'(im));
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

  initial begin
    $dumpfile("vec_alu_tb.vcd");
    $dumpvars(0, vec_alu_tb);
    do_reset();
    sweep(SweepRounds);
    shift_edges();
    sign_edges();
    carry_edges();
    merge_cases();
    imm_cases();
    do_verdict();
  end

  // Width helpers
  function automatic logic [ELEN-1:0] mask_of(input int w);
    mask_of = (ELEN'(1'b1) << w) - ELEN'(1'b1);
  endfunction

  function automatic logic [ELEN-1:0] sext(input logic [ELEN-1:0] v, input int w);
    sext = v[w-1] ? (v | ~mask_of(w)) : (v & mask_of(w));
  endfunction

  function automatic int width_of(input logic [VsewW-1:0] sew);
    width_of = 8 << sew;
  endfunction

  function automatic logic [ELEN-1:0] elem_of(input logic [DLEN-1:0] v, input int w, input int e);
    elem_of = ELEN'(v >> (e * w)) & mask_of(w);
  endfunction

  // Reference model
  function automatic logic [ELEN-1:0] ref_lane(input vec_op_e o, input int w,
                                               input logic [ELEN-1:0] ra, input logic [ELEN-1:0] rb,
                                               input logic mbit, input logic vmi);
    logic [ELEN-1:0] m;
    logic [ELEN-1:0] a;
    logic [ELEN-1:0] b;
    logic [ELEN-1:0] sa;
    logic [ELEN-1:0] sb;
    logic [ELEN-1:0] sr;
    int sh;
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
      VEC_ADC:   ref_lane = (a + b + ELEN'(mbit)) & m;
      VEC_SBC:   ref_lane = (a - b - ELEN'(mbit)) & m;
      VEC_MERGE: ref_lane = (vmi || mbit) ? b : a;
      VEC_MVNRR: ref_lane = a;
      default:   ref_lane = '0;
    endcase
  endfunction

  function automatic logic [ELEN-1:0] ref_second(input int w, input int e);
    logic [ELEN-1:0] raw;
    case (src)
      VEC_SRC_VV: raw = ELEN'(vs1_data >> (e * w));
      VEC_SRC_VI: raw = {{(ELEN - SimmW) {simm[SimmW-1]}}, simm};
      default:    raw = ELEN'(xdata);
    endcase
    ref_second = raw & mask_of(w);
  endfunction

endmodule

`default_nettype wire
