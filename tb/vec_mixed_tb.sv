`default_nettype none

module vec_mixed_tb ();
  import vec_pkg::*;

  localparam int DLEN = 128;

  int              checks = 0;
  int              errors = 0;

  vec_op_e         op;
  vec_src_e        src;
  vec_eew_e        eew;
  logic     [ 2:0] vsew;
  logic [DLEN-1:0] vs2_data;
  logic [DLEN-1:0] vs1_data;
  logic     [31:0] xdata;
  logic     [ 4:0] simm;
  logic [DLEN-1:0] result;

  vec_mixed #(
      .DLEN(DLEN)
  ) dut (
      .op      (op),
      .src     (src),
      .eew     (eew),
      .vsew    (vsew),
      .vs2_data(vs2_data),
      .vs1_data(vs1_data),
      .xdata   (xdata),
      .simm    (simm),
      .result  (result)
  );

  // Reference model
  function automatic int sew_bits();
    return 8 << vsew;
  endfunction

  function automatic logic is_narrow();
    return (op == VEC_NSRL) || (op == VEC_NSRA);
  endfunction

  function automatic logic is_ext();
    return (op == VEC_ZEXT2) || (op == VEC_ZEXT4) || (op == VEC_SEXT2) || (op == VEC_SEXT4);
  endfunction

  function automatic int dest_bits();
    if (is_narrow() || is_ext()) return sew_bits();
    return sew_bits() * 2;
  endfunction

  function automatic int src2_bits();
    if (is_narrow()) return sew_bits() * 2;
    if (op == VEC_ZEXT4 || op == VEC_SEXT4) return sew_bits() / 4;
    if (is_ext()) return sew_bits() / 2;
    if (eew == VEC_EEW_WIDEN_W) return sew_bits() * 2;
    return sew_bits();
  endfunction

  function automatic int lanes();
    int widest;
    widest = dest_bits();
    if (src2_bits() > widest) widest = src2_bits();
    return DLEN / widest;
  endfunction

  function automatic logic [63:0] slice(input logic [DLEN-1:0] data, input int width,
                                        input int idx);
    logic [63:0] out;
    out = 64'd0;
    for (int b = 0; b < width; b++) out[b] = data[idx*width+b];
    return out;
  endfunction

  function automatic logic [63:0] extend(input logic [63:0] raw, input int width,
                                         input logic do_sign);
    logic [63:0] out;
    out = raw;
    for (int b = width; b < 64; b++) out[b] = do_sign ? raw[width-1] : 1'b0;
    return out;
  endfunction

  function automatic logic [63:0] ref_elem(input int e);
    logic [63:0] a;
    logic [63:0] b;
    logic [63:0] w;
    int sh;
    logic sgn;
    sgn = (op == VEC_WADD) || (op == VEC_WSUB);
    case (op)
      VEC_NSRL, VEC_NSRA: begin
        w = slice(vs2_data, sew_bits() * 2, e);
        case (src)
          VEC_SRC_VV: sh = int'(slice(vs1_data, sew_bits(), e));
          VEC_SRC_VI: sh = int'(simm);
          default:    sh = int'(xdata[5:0]);
        endcase
        sh = sh % (sew_bits() * 2);
        if (op == VEC_NSRA) begin
          w = extend(w, sew_bits() * 2, 1'b1);
          return $signed(w) >>> sh;
        end
        return w >> sh;
      end
      VEC_ZEXT2, VEC_ZEXT4, VEC_SEXT2, VEC_SEXT4: begin
        a = slice(vs2_data, src2_bits(), e);
        return extend(a, src2_bits(), (op == VEC_SEXT2) || (op == VEC_SEXT4));
      end
      default: begin
        if (eew == VEC_EEW_WIDEN_W) a = slice(vs2_data, dest_bits(), e);
        else a = extend(slice(vs2_data, sew_bits(), e), sew_bits(), sgn);
        if (src == VEC_SRC_VV) b = slice(vs1_data, sew_bits(), e);
        else b = slice({96'd0, xdata}, sew_bits(), 0);
        b = extend(b, sew_bits(), sgn);
        if ((op == VEC_WSUBU) || (op == VEC_WSUB)) return a - b;
        return a + b;
      end
    endcase
  endfunction

  task automatic check_lanes(input string tag);
    logic [63:0] want;
    logic [63:0] got;
    #1;
    for (int e = 0; e < lanes(); e++) begin
      want = ref_elem(e) & ((64'd1 << dest_bits()) - 64'd1);
      got  = slice(result, dest_bits(), e);
      checks = checks + 1;
      if (got !== want) begin
        errors = errors + 1;
        if (errors < 12)
          $display("FAIL %0s lane %0d got=%h want=%h sew=%0d", tag, e, got, want, sew_bits());
      end
    end
  endtask

  task automatic drive(input vec_op_e o, input vec_src_e s, input vec_eew_e w,
                       input logic [2:0] sew);
    op       = o;
    src      = s;
    eew      = w;
    vsew     = sew;
    vs2_data = {$urandom, $urandom, $urandom, $urandom};
    vs1_data = {$urandom, $urandom, $urandom, $urandom};
    xdata    = $urandom;
    simm     = 5'($urandom);
  endtask

  // Widening forms
  task automatic check_widen();
    for (int sew = 0; sew < 2; sew++) begin
      for (int f = 0; f < 2; f++) begin
        for (int t = 0; t < 8; t++) begin
          drive(VEC_WADDU, f == 0 ? VEC_SRC_VV : VEC_SRC_VX, VEC_EEW_WIDEN, 3'(sew));
          check_lanes("waddu");
          drive(VEC_WADD, f == 0 ? VEC_SRC_VV : VEC_SRC_VX, VEC_EEW_WIDEN, 3'(sew));
          check_lanes("wadd");
          drive(VEC_WSUBU, f == 0 ? VEC_SRC_VV : VEC_SRC_VX, VEC_EEW_WIDEN, 3'(sew));
          check_lanes("wsubu");
          drive(VEC_WSUB, f == 0 ? VEC_SRC_VV : VEC_SRC_VX, VEC_EEW_WIDEN, 3'(sew));
          check_lanes("wsub");
          drive(VEC_WADDU, f == 0 ? VEC_SRC_VV : VEC_SRC_VX, VEC_EEW_WIDEN_W, 3'(sew));
          check_lanes("waddu wv");
          drive(VEC_WSUB, f == 0 ? VEC_SRC_VV : VEC_SRC_VX, VEC_EEW_WIDEN_W, 3'(sew));
          check_lanes("wsub wv");
        end
      end
    end
  endtask

  // Narrowing shifts
  task automatic check_narrow();
    for (int sew = 0; sew < 2; sew++) begin
      for (int f = 0; f < 3; f++) begin
        for (int t = 0; t < 8; t++) begin
          drive(VEC_NSRL, vec_src_e'(f), VEC_EEW_NARROW, 3'(sew));
          check_lanes("nsrl");
          drive(VEC_NSRA, vec_src_e'(f), VEC_EEW_NARROW, 3'(sew));
          check_lanes("nsra");
        end
      end
    end
  endtask

  // Extension forms
  task automatic check_ext();
    for (int t = 0; t < 8; t++) begin
      drive(VEC_ZEXT2, VEC_SRC_VV, VEC_EEW_SAME, 3'd1);
      check_lanes("zext2 half");
      drive(VEC_SEXT2, VEC_SRC_VV, VEC_EEW_SAME, 3'd1);
      check_lanes("sext2 half");
      drive(VEC_ZEXT2, VEC_SRC_VV, VEC_EEW_SAME, 3'd2);
      check_lanes("zext2 word");
      drive(VEC_SEXT2, VEC_SRC_VV, VEC_EEW_SAME, 3'd2);
      check_lanes("sext2 word");
      drive(VEC_ZEXT4, VEC_SRC_VV, VEC_EEW_SAME, 3'd2);
      check_lanes("zext4");
      drive(VEC_SEXT4, VEC_SRC_VV, VEC_EEW_SAME, 3'd2);
      check_lanes("sext4");
    end
  endtask

  // Known values
  task automatic check_directed();
    op       = VEC_WADD;
    src      = VEC_SRC_VV;
    eew      = VEC_EEW_WIDEN;
    vsew     = 3'd0;
    vs2_data = 128'h0000_0000_0000_0000_0000_0000_0000_80ff;
    vs1_data = 128'h0000_0000_0000_0000_0000_0000_0000_0102;
    check_lanes("directed wadd");

    op       = VEC_NSRA;
    src      = VEC_SRC_VI;
    eew      = VEC_EEW_NARROW;
    vsew     = 3'd0;
    vs2_data = 128'h0000_0000_0000_0000_0000_0000_ff00_8000;
    simm     = 5'd4;
    check_lanes("directed nsra");
  endtask

  task automatic verdict();
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask

  initial begin
    $dumpfile("vec_mixed_tb.vcd");
    $dumpvars(0, vec_mixed_tb);

    op       = VEC_WADD;
    src      = VEC_SRC_VV;
    eew      = VEC_EEW_WIDEN;
    vsew     = 3'd0;
    vs2_data = '0;
    vs1_data = '0;
    xdata    = '0;
    simm     = '0;

    check_directed();
    check_widen();
    check_narrow();
    check_ext();

    verdict();
  end

endmodule

`default_nettype wire
