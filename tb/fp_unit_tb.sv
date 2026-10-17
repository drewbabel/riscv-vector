`default_nettype none

module fp_unit_tb
  import fp_pkg::*;
();

  localparam int Xlen = arch_pkg::XLEN;
  localparam int NRegs = arch_pkg::NumRegs;
  localparam int ShowErrors = 20;
  localparam int RandOps = 1200;
  localparam int MinChecks = 30000;
  localparam int MinStalls = 500;
  localparam int Timeout = 100000;
  localparam logic [31:0] Qnan = 32'h7FC0_0000;
  localparam logic [31:0] SignBit = 32'h8000_0000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int busy_stalls = 0;
  int port_stalls = 0;
  int cycle = 0;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic core_en = 1'b1;

  logic start = 1'b0;
  logic xstart = 1'b0;
  logic xack = 1'b0;
  fp_unit_e unit = FP_NONE;
  logic sub = 1'b0;
  logic neg_prod = 1'b0;
  logic neg_add = 1'b0;
  logic to_int = 1'b0;
  logic is_unsigned = 1'b0;
  logic sqrt = 1'b0;
  logic [4:0] funct5 = '0;
  logic [2:0] funct3 = '0;
  logic [2:0] rm = '0;
  logic [4:0] rd = '0;
  logic [31:0] a = '0;
  logic [31:0] b = '0;
  logic [31:0] c = '0;
  logic [Xlen-1:0] xa = '0;

  logic ready;
  logic idle;
  logic [NRegs-1:0] reg_busy;
  logic wb_valid;
  logic [4:0] wb_rd;
  logic [31:0] wb_data;
  logic [4:0] wb_flags;
  logic xvalid;
  logic [Xlen-1:0] xresult;
  logic [4:0] xflags;

  logic [31:0] shadow[NRegs];
  logic exp_pend[NRegs];
  logic [31:0] exp_data[NRegs];
  logic [4:0] exp_flags[NRegs];
  int exp_issue[NRegs];
  int exp_lat[NRegs];
  logic [4:0] flags_model;
  logic [4:0] flags_dut;

  always #5 clk = ~clk;

  fp_unit dut (
      .clk        (clk),
      .rst_n      (rst_n),
      .core_en    (core_en),
      .start      (start),
      .xstart     (xstart),
      .xack       (xack),
      .unit       (unit),
      .sub        (sub),
      .neg_prod   (neg_prod),
      .neg_add    (neg_add),
      .to_int     (to_int),
      .is_unsigned(is_unsigned),
      .sqrt       (sqrt),
      .funct5     (funct5),
      .funct3     (funct3),
      .rm         (rm),
      .rd         (rd),
      .a          (a),
      .b          (b),
      .c          (c),
      .xa         (xa),
      .ready      (ready),
      .idle       (idle),
      .reg_busy   (reg_busy),
      .wb_valid   (wb_valid),
      .wb_rd      (wb_rd),
      .wb_data    (wb_data),
      .wb_flags   (wb_flags),
      .xvalid     (xvalid),
      .xresult    (xresult),
      .xflags     (xflags)
  );

  task automatic fail(input string msg);
    errors++;
    if (errors <= ShowErrors) $display("FAIL cycle %0d: %s", cycle, msg);
    if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
  endtask  // Automatic

  task automatic check(input string name, input logic [31:0] got, input logic [31:0] exp);
    checks++;
    if (got !== exp) fail($sformatf("%s got %h exp %h", name, got, exp));
  endtask  // Automatic

  function automatic logic [NRegs-1:0] pend_mask();
    logic [NRegs-1:0] m;
    for (int r = 0; r < NRegs; r++) m[r] = exp_pend[r];
    return m;
  endfunction

  task automatic idle_inputs();
    start  = 1'b0;
    xstart = 1'b0;
    xack   = 1'b0;
    unit   = fp_unit_e'($urandom_range(0, 10));
    rm     = 3'($urandom);
    rd     = 5'($urandom);
    a      = $urandom;
    b      = $urandom;
    c      = $urandom;
    xa     = $urandom;
  endtask  // Automatic

  task automatic tick();
    @(posedge clk);
    cycle++;
    #1;
    idle_inputs();
    @(negedge clk);
    if (wb_valid) begin
      if (!exp_pend[wb_rd]) begin
        fail($sformatf("write to f%0d with nothing pending", wb_rd));
      end else begin
        check($sformatf("f%0d data", wb_rd), wb_data, exp_data[wb_rd]);
        check($sformatf("f%0d flags", wb_rd), 32'(wb_flags), 32'(exp_flags[wb_rd]));
        if (exp_lat[wb_rd] != 0)
          check($sformatf("f%0d latency", wb_rd), cycle - exp_issue[wb_rd], exp_lat[wb_rd]);
        exp_pend[wb_rd] = 1'b0;
        shadow[wb_rd]   = wb_data;
        flags_dut       = flags_dut | wb_flags;
        flags_model     = flags_model | exp_flags[wb_rd];
      end
    end
    check("reg_busy", 32'(reg_busy), 32'(pend_mask() & ~(wb_valid ? (32'd1 << wb_rd) : 32'd0)));
    check("idle", 32'(idle), 32'((pend_mask() | (wb_valid ? (32'd1 << wb_rd) : 32'd0)) == '0));
    check("flags_accrued", 32'(flags_dut), 32'(flags_model));
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    rst_n = 1'b0;
    idle_inputs();
    for (int r = 0; r < NRegs; r++) begin
      shadow[r]   = '0;
      exp_pend[r] = 1'b0;
    end
    flags_model = '0;
    flags_dut   = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  function automatic int lat_of(input fp_unit_e u);
    case (u)
      FP_ADD:      return FpAddLatency;
      FP_MUL:      return FpMulLatency;
      FP_FMA:      return FpFmaLatency;
      FP_DIV_SQRT: return 0;
      default:     return 1;
    endcase
  endfunction

  task automatic fop(input fp_unit_e u, input logic [4:0] f5, input logic [2:0] f3,
                     input logic [2:0] mode, input logic [4:0] dst, input logic [4:0] s1,
                     input logic [4:0] s2, input logic [4:0] s3, input logic [Xlen-1:0] xin,
                     input logic [31:0] exp_res, input logic [4:0] exp_fl);
    logic [NRegs-1:0] need;
    need = (32'd1 << dst) | (32'd1 << s1) | (32'd1 << s2) | (32'd1 << s3);
    forever begin
      if ((reg_busy & need) != '0) begin
        busy_stalls++;
        tick();
        continue;
      end
      unit        = u;
      funct5      = f5;
      funct3      = f3;
      sub         = (u == FP_ADD) && (f5 == Funct5Fsub);
      neg_prod    = (u == FP_FMA) && f5[1];
      neg_add     = (u == FP_FMA) && f5[0];
      to_int      = 1'b0;
      is_unsigned = (u == FP_CVT) && f3[0];
      sqrt        = (u == FP_DIV_SQRT) && (f5 == Funct5Fsqrt);
      rm          = mode;
      rd          = dst;
      a           = shadow[s1];
      b           = shadow[s2];
      c           = shadow[s3];
      xa          = xin;
      #1;
      if (ready) break;
      port_stalls++;
      tick();
    end
    start          = 1'b1;
    exp_pend[dst]  = 1'b1;
    exp_data[dst]  = exp_res;
    exp_flags[dst] = exp_fl;
    exp_issue[dst] = cycle;
    exp_lat[dst]   = lat_of(u);
    tick();
  endtask  // Automatic

  task automatic load(input logic [4:0] dst, input logic [31:0] val);
    fop(FP_MV_W_X, Funct5FmvWX, 3'd0, 3'($urandom), dst, dst, dst, dst, val, val, '0);
  endtask  // Automatic

  task automatic xop(input fp_unit_e u, input logic [4:0] f5, input logic [2:0] f3, input logic ti,
                     input logic uns, input logic [2:0] mode, input logic [4:0] s1,
                     input logic [4:0] s2, input logic [31:0] exp_res, input logic [4:0] exp_fl,
                     input logic retire);
    logic [NRegs-1:0] need;
    need = (32'd1 << s1) | (32'd1 << s2);
    while ((reg_busy & need) != '0) begin
      busy_stalls++;
      tick();
    end
    unit        = u;
    funct5      = f5;
    funct3      = f3;
    to_int      = ti;
    is_unsigned = uns;
    rm          = mode;
    a           = shadow[s1];
    b           = shadow[s2];
    xstart      = 1'b1;
    #1;
    check("xvalid_before", 32'(xvalid), 32'd0);
    tick();
    check("xvalid", 32'(xvalid), 32'd1);
    check("xresult", xresult, exp_res);
    check("xflags", 32'(xflags), 32'(exp_fl));
    if (retire) flags_model = flags_model | exp_fl;
    if (retire) flags_dut = flags_dut | xflags;
    xack = 1'b1;
    tick();
    check("xvalid_after", 32'(xvalid), 32'd0);
  endtask  // Automatic

  task automatic drain();
    int n;
    n = 0;
    while (pend_mask() != '0 && n < 200) begin
      tick();
      n++;
    end
    check("drained", 32'(pend_mask()), 32'd0);
  endtask  // Automatic

  function automatic logic is_nan(input logic [31:0] x);
    return (x[30:23] == 8'hFF) && (x[22:0] != 0);
  endfunction

  function automatic logic is_snan(input logic [31:0] x);
    return is_nan(x) && !x[22];
  endfunction

  function automatic logic [31:0] fclass_of(input logic [31:0] x);
    logic sign;
    logic [7:0] e;
    logic [22:0] f;
    sign = x[31];
    e = x[30:23];
    f = x[22:0];
    if (e == 8'hFF && f == 0) return sign ? 32'd1 : 32'd128;
    if (e == 8'hFF) return f[22] ? 32'd512 : 32'd256;
    if (e == 0 && f == 0) return sign ? 32'd8 : 32'd16;
    if (e == 0) return sign ? 32'd4 : 32'd32;
    return sign ? 32'd2 : 32'd64;
  endfunction

  function automatic logic lt_total(input logic [31:0] x, input logic [31:0] y);
    if (x[31] != y[31]) return x[31];
    if (x[31]) return x[30:0] > y[30:0];
    return x[30:0] < y[30:0];
  endfunction

  task automatic minmax_model(input logic is_max, input logic [31:0] x, input logic [31:0] y,
                              output logic [31:0] res, output logic [4:0] fl);
    fl = (is_snan(x) || is_snan(y)) ? FlagNv : '0;
    if (is_nan(x) && is_nan(y)) res = Qnan;
    else if (is_nan(x)) res = y;
    else if (is_nan(y)) res = x;
    else if (is_max) res = lt_total(x, y) ? y : x;
    else res = lt_total(x, y) ? x : y;
  endtask  // Automatic

  function automatic logic [31:0] sgnj_model(input logic [2:0] f3, input logic [31:0] x,
                                             input logic [31:0] y);
    case (f3)
      Funct3Fsgnj:  return {y[31], x[30:0]};
      Funct3Fsgnjn: return {!y[31], x[30:0]};
      default:      return {x[31] ^ y[31], x[30:0]};
    endcase
  endfunction

  task automatic test_directed();
    load(5'd1, 32'h3F80_0000);
    load(5'd2, 32'h4040_0000);
    load(5'd3, 32'hBFC0_0000);
    load(5'd4, 32'h3EAA_AAAB);

    fop(FP_ADD, Funct5Fadd, RmRne, RmRne, 5'd10, 5'd1, 5'd2, 5'd0, '0, 32'h4080_0000, '0);
    fop(FP_ADD, Funct5Fsub, RmRne, RmRne, 5'd11, 5'd1, 5'd2, 5'd0, '0, 32'hC000_0000, '0);
    fop(FP_MUL, Funct5Fmul, RmRne, RmRne, 5'd12, 5'd2, 5'd3, 5'd0, '0, 32'hC090_0000, '0);
    fop(FP_FMA, 5'd0, RmRne, RmRne, 5'd13, 5'd1, 5'd2, 5'd3, '0, 32'h3FC0_0000, '0);
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, 5'd14, 5'd1, 5'd2, 5'd0, '0, 32'h3EAA_AAAB, FlagNx);
    fop(FP_DIV_SQRT, Funct5Fsqrt, RmRne, RmRne, 5'd15, 5'd2, 5'd0, 5'd0, '0, 32'h3FDD_B3D7, FlagNx);
    fop(FP_MISC, Funct5Fsgnj, Funct3Fsgnjn, 3'd0, 5'd16, 5'd2, 5'd3, 5'd0, '0, 32'h4040_0000, '0);
    fop(FP_MISC, Funct5Fminmax, Funct3Fmin, 3'd0, 5'd17, 5'd1, 5'd3, 5'd0, '0, 32'hBFC0_0000, '0);
    fop(FP_CVT, Funct5FcvtSW, 3'd0, RmRne, 5'd18, 5'd0, 5'd0, 5'd0, 32'hFFFF_FFF9, 32'hC0E0_0000,
        '0);
    fop(FP_CVT, Funct5FcvtSW, 3'd1, RmRne, 5'd19, 5'd0, 5'd0, 5'd0, 32'hFFFF_FFF9, 32'h4F80_0000,
        FlagNx);
    drain();

    xop(FP_MISC, Funct5Fcmp, Funct3Flt, 1'b0, 1'b0, 3'd0, 5'd1, 5'd2, 32'd1, '0, 1'b1);
    xop(FP_MISC, Funct5FmvXW, Funct3Fclass, 1'b0, 1'b0, 3'd0, 5'd3, 5'd0, 32'd2, '0, 1'b1);
    xop(FP_MV_X_W, Funct5FmvXW, Funct3Fmv, 1'b0, 1'b0, 3'd0, 5'd4, 5'd0, 32'h3EAA_AAAB, '0, 1'b1);
    xop(FP_CVT, Funct5FcvtWS, 3'd0, 1'b1, 1'b0, RmRtz, 5'd3, 5'd0, 32'hFFFF_FFFF, FlagNx, 1'b1);
    xop(FP_CVT, Funct5FcvtWS, 3'd0, 1'b1, 1'b1, RmRne, 5'd3, 5'd0, 32'd0, FlagNv, 1'b1);
  endtask  // Automatic

  task automatic test_dependent();
    int t0;
    load(5'd1, 32'h3F80_0000);
    load(5'd2, 32'h4000_0000);
    t0 = busy_stalls;
    fop(FP_MUL, Funct5Fmul, RmRne, RmRne, 5'd5, 5'd2, 5'd2, 5'd0, '0, 32'h4080_0000, '0);
    fop(FP_ADD, Funct5Fadd, RmRne, RmRne, 5'd6, 5'd5, 5'd1, 5'd0, '0, 32'h40A0_0000, '0);
    check("dependent_add_stalled", 32'(busy_stalls - t0 >= FpMulLatency - 1), 32'd1);
    fop(FP_FMA, 5'd0, RmRne, RmRne, 5'd5, 5'd6, 5'd6, 5'd5, '0, 32'h41E8_0000, '0);
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, 5'd7, 5'd5, 5'd2, 5'd0, '0, 32'h4168_0000, '0);
    fop(FP_ADD, Funct5Fadd, RmRne, RmRne, 5'd7, 5'd7, 5'd7, 5'd0, '0, 32'h41E8_0000, '0);
    drain();
    xop(FP_MV_X_W, Funct5FmvXW, Funct3Fmv, 1'b0, 1'b0, 3'd0, 5'd7, 5'd0, 32'h41E8_0000, '0, 1'b1);
  endtask  // Automatic

  task automatic test_booking();
    load(5'd1, 32'h3F80_0000);
    load(5'd2, 32'h4000_0000);
    drain();
    unit = FP_MUL;
    rd = 5'd8;
    a = shadow[1];
    b = shadow[2];
    rm = RmRne;
    #1;
    check("mul_ready_idle", 32'(ready), 32'd1);
    start        = 1'b1;
    exp_pend[8]  = 1'b1;
    exp_data[8]  = 32'h4000_0000;
    exp_flags[8] = '0;
    exp_issue[8] = cycle;
    exp_lat[8]   = FpMulLatency;
    tick();
    unit = FP_ADD;
    #1;
    check("add_behind_mul_clash", 32'(ready), (FpAddLatency == FpMulLatency - 1) ? 32'd0 : 32'd1);
    unit = FP_MUL;
    #1;
    check("mul_behind_mul_free", 32'(ready), 32'd1);
    unit = FP_DIV_SQRT;
    #1;
    check("div_free_beside_mul", 32'(ready), 32'd1);
    drain();

    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, 5'd9, 5'd1, 5'd2, 5'd0, '0, 32'h3F00_0000, '0);
    unit = FP_DIV_SQRT;
    #1;
    check("div_busy_not_ready", 32'(ready), 32'd0);
    for (int i = 0; i < 6; i++) begin
      fop(FP_ADD, Funct5Fadd, RmRne, RmRne, 5'(10 + i), 5'd1, 5'd1, 5'd0, '0, 32'h4000_0000, '0);
      check("div_still_pending", 32'(exp_pend[9]), 32'd1);
    end
    drain();
  endtask  // Automatic

  task automatic test_rm_at_start();
    load(5'd1, 32'h4B80_0001);
    load(5'd2, 32'h3F80_0000);
    load(5'd3, 32'hBF80_0000);
    fop(FP_ADD, Funct5Fadd, RmRup, RmRup, 5'd4, 5'd1, 5'd2, 5'd0, '0, 32'h4B80_0002, FlagNx);
    fop(FP_ADD, Funct5Fadd, RmRne, RmRne, 5'd5, 5'd1, 5'd2, 5'd0, '0, 32'h4B80_0002, FlagNx);
    fop(FP_ADD, Funct5Fadd, RmRtz, RmRtz, 5'd6, 5'd1, 5'd2, 5'd0, '0, 32'h4B80_0001, FlagNx);
    fop(FP_ADD, Funct5Fadd, RmRdn, RmRdn, 5'd7, 5'd1, 5'd3, 5'd0, '0, 32'h4B80_0000, FlagNx);
    fop(FP_MUL, Funct5Fmul, RmRtz, RmRtz, 5'd8, 5'd1, 5'd2, 5'd0, '0, 32'h4B80_0001, '0);
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRup, RmRup, 5'd9, 5'd2, 5'd1, 5'd0, '0, 32'h337F_FFFF, FlagNx);
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRtz, RmRtz, 5'd10, 5'd2, 5'd1, 5'd0, '0, 32'h337F_FFFE, FlagNx);
    drain();
  endtask  // Automatic

  task automatic test_cancel();
    logic [4:0] prior;
    load(5'd1, 32'h3F80_0000);
    load(5'd2, 32'h0000_0000);
    drain();
    prior = flags_dut;
    unit = FP_DIV_SQRT;
    funct5 = Funct5Fdiv;
    rd = 5'd20;
    a = shadow[1];
    b = shadow[2];
    #1;
    check("cancel_ready", 32'(ready), 32'd1);
    tick();
    unit = FP_ADD;
    rd = 5'd21;
    a = 32'h7F80_0001;
    #1;
    tick();
    repeat (40) tick();
    check("cancel_no_flags", 32'(flags_dut), 32'(prior));
    check("cancel_idle", 32'(idle), 32'd1);
    xop(FP_MISC, Funct5Fcmp, Funct3Flt, 1'b0, 1'b0, 3'd0, 5'd1, 5'd1, 32'd0, '0, 1'b0);
    load(5'd3, 32'h7F80_0001);
    xop(FP_MISC, Funct5Fcmp, Funct3Feq, 1'b0, 1'b0, 3'd0, 5'd3, 5'd1, 32'd0, FlagNv, 1'b0);
    check("cancelled_xop_no_flags", 32'(flags_dut), 32'(prior));
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, 5'd20, 5'd1, 5'd2, 5'd0, '0, 32'h7F80_0000, FlagDz);
    drain();
    check("retired_div_flags", 32'(flags_dut), 32'(prior | FlagDz));
  endtask  // Automatic

  task automatic test_stall_core_en();
    load(5'd1, 32'h3F80_0000);
    load(5'd2, 32'h4000_0000);
    fop(FP_MUL, Funct5Fmul, RmRne, RmRne, 5'd3, 5'd2, 5'd2, 5'd0, '0, 32'h4080_0000, '0);
    exp_lat[3] = 0;
    @(posedge clk);
    #1;
    core_en = 1'b0;
    repeat (5) @(posedge clk);
    #1;
    core_en = 1'b1;
    drain();
    xop(FP_MV_X_W, Funct5FmvXW, Funct3Fmv, 1'b0, 1'b0, 3'd0, 5'd3, 5'd0, 32'h4080_0000, '0, 1'b1);
  endtask  // Automatic

  task automatic test_div_done_cycle();
    int lat;
    int t9;
    load(5'd1, 32'h3F80_0000);
    load(5'd2, 32'h4040_0000);
    drain();
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, 5'd9, 5'd1, 5'd2, 5'd0, '0, 32'h3EAA_AAAB, FlagNx);
    t9 = exp_issue[9];
    while (exp_pend[9]) tick();
    lat = cycle - t9;

    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, 5'd9, 5'd1, 5'd2, 5'd0, '0, 32'h3EAA_AAAB, FlagNx);
    t9 = exp_issue[9];
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, 5'd10, 5'd2, 5'd1, 5'd0, '0, 32'h4040_0000, '0);
    check("div_starts_in_done_cycle", exp_issue[10] - t9, lat);
    drain();

    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, 5'd9, 5'd1, 5'd2, 5'd0, '0, 32'h3EAA_AAAB, FlagNx);
    t9 = exp_issue[9];
    while (cycle < t9 + lat - 1) tick();
    load(5'd11, 32'h4000_0000);
    check("mv_writes_in_done_cycle", exp_issue[11] - t9, lat - 1);
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, 5'd10, 5'd2, 5'd1, 5'd0, '0, 32'h4040_0000, '0);
    check("div_waits_for_pended_write", exp_issue[10] - t9, lat + 1);
    drain();
  endtask  // Automatic

  int fd[13];
  string rms[5] = '{"rne", "rtz", "rdn", "rup", "rmm"};
  logic [2:0] rmv[5] = '{RmRne, RmRtz, RmRdn, RmRup, RmRmm};

  task automatic open_files(input int k);
    string names[13];
    string skip;
    names[0]  = {"f32_add_", rms[k]};
    names[1]  = {"f32_sub_", rms[k]};
    names[2]  = {"f32_mul_", rms[k]};
    names[3]  = {"f32_mulAdd_", rms[k]};
    names[4]  = {"f32_div_", rms[k]};
    names[5]  = {"f32_sqrt_", rms[k]};
    names[6]  = {"i32_to_f32_", rms[k]};
    names[7]  = {"ui32_to_f32_", rms[k]};
    names[8]  = {"f32_to_i32_", rms[k]};
    names[9]  = {"f32_to_ui32_", rms[k]};
    names[10] = "f32_eq";
    names[11] = "f32_lt";
    names[12] = "f32_le";
    for (int i = 0; i < 13; i++) begin
      fd[i] = $fopen({"build/testfloat/", names[i], ".txt"}, "r");
      if (fd[i] == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", names[i]);
      for (int s = $urandom_range(0, 300); s > 0; s--) void'($fgets(skip, fd[i]));
    end
  endtask  // Automatic

  task automatic close_files();
    for (int i = 0; i < 13; i++) $fclose(fd[i]);
  endtask  // Automatic

  task automatic refill(input int k);
    int ch;
    ch = $fgetc(fd[k]);
    if (ch == -1) void'($rewind(fd[k]));
    else void'($ungetc(ch, fd[k]));
  endtask  // Automatic

  function automatic logic [4:0] pick_reg();
    return 5'($urandom_range(0, NRegs - 1));
  endfunction

  task automatic rand_op(input logic [2:0] mode);
    int kind;
    logic [31:0] va, vb, vc, vr;
    logic [31:0] vflag;
    logic [4:0] s1, s2, s3, dst;
    logic [31:0] res;
    logic [4:0] fl;
    logic [2:0] f3;
    int n;
    kind = $urandom_range(0, 15);
    s1   = pick_reg();
    do s2 = pick_reg(); while (s2 == s1);
    do s3 = pick_reg(); while (s3 == s1 || s3 == s2);
    dst = pick_reg();
    if (kind <= 13) refill((kind == 13) ? 3 : kind);
    case (kind)
      0, 1, 2, 4: begin
        n = $fscanf(fd[kind], "%h %h %h %h\n", va, vb, vr, vflag);
        if (n != 4) $fatal(1, "TB BAD LINE: file %0d", kind);
        load(s1, va);
        load(s2, vb);
        case (kind)
          0: fop(FP_ADD, Funct5Fadd, mode, mode, dst, s1, s2, 5'd0, '0, vr, 5'(vflag));
          1: fop(FP_ADD, Funct5Fsub, mode, mode, dst, s1, s2, 5'd0, '0, vr, 5'(vflag));
          2: fop(FP_MUL, Funct5Fmul, mode, mode, dst, s1, s2, 5'd0, '0, vr, 5'(vflag));
          default: fop(FP_DIV_SQRT, Funct5Fdiv, mode, mode, dst, s1, s2, 5'd0, '0, vr, 5'(vflag));
        endcase
      end
      3, 13: begin
        logic [1:0] form;
        n = $fscanf(fd[3], "%h %h %h %h %h\n", va, vb, vc, vr, vflag);
        if (n != 5) $fatal(1, "TB BAD LINE: file 3");
        form = 2'($urandom);
        load(s1, form[1] ? va ^ SignBit : va);
        load(s2, vb);
        load(s3, form[0] ? vc ^ SignBit : vc);
        fop(FP_FMA, {3'b000, form}, mode, mode, dst, s1, s2, s3, '0, vr, 5'(vflag));
      end
      5: begin
        n = $fscanf(fd[5], "%h %h %h\n", va, vr, vflag);
        if (n != 3) $fatal(1, "TB BAD LINE: file 5");
        load(s1, va);
        fop(FP_DIV_SQRT, Funct5Fsqrt, mode, mode, dst, s1, s1, 5'd0, '0, vr, 5'(vflag));
      end
      6, 7: begin
        n = $fscanf(fd[kind], "%h %h %h\n", va, vr, vflag);
        if (n != 3) $fatal(1, "TB BAD LINE: file %0d", kind);
        fop(FP_CVT, Funct5FcvtSW, (kind == 7) ? 3'd1 : 3'd0, mode, dst, dst, dst, dst, va, vr,
            5'(vflag));
      end
      8, 9: begin
        n = $fscanf(fd[kind], "%h %h %h\n", va, vr, vflag);
        if (n != 3) $fatal(1, "TB BAD LINE: file %0d", kind);
        load(s1, va);
        xop(FP_CVT, Funct5FcvtWS, 3'd0, 1'b1, kind == 9, mode, s1, s1, vr, 5'(vflag), 1'b1);
      end
      10, 11, 12: begin
        n = $fscanf(fd[kind], "%h %h %h %h\n", va, vb, vr, vflag);
        if (n != 4) $fatal(1, "TB BAD LINE: file %0d", kind);
        load(s1, va);
        load(s2, vb);
        f3 = (kind == 10) ? Funct3Feq : (kind == 11) ? Funct3Flt : Funct3Fle;
        xop(FP_MISC, Funct5Fcmp, f3, 1'b0, 1'b0, 3'd0, s1, s2, vr, 5'(vflag), 1'b1);
      end
      default: begin
        va = $urandom_range(0, 3) == 0 ? (32'h7F80_0000 | 32'($urandom_range(1, 8))) : $urandom;
        vb = $urandom_range(0, 3) == 0 ? {1'($urandom), 31'h0} : $urandom;
        load(s1, va);
        load(s2, vb);
        n = $urandom_range(0, 3);
        case (n)
          0: begin
            f3  = 3'($urandom_range(0, 2));
            res = sgnj_model(f3, va, vb);
            fop(FP_MISC, Funct5Fsgnj, f3, 3'($urandom), dst, s1, s2, 5'd0, '0, res, '0);
          end
          1: begin
            f3 = 3'($urandom_range(0, 1));
            minmax_model(f3[0], va, vb, res, fl);
            fop(FP_MISC, Funct5Fminmax, f3, 3'($urandom), dst, s1, s2, 5'd0, '0, res, fl);
          end
          2: begin
            res = fclass_of(va);
            xop(FP_MISC, Funct5FmvXW, Funct3Fclass, 1'b0, 1'b0, 3'd0, s1, s1, res, '0, 1'b1);
          end
          default: xop(FP_MV_X_W, Funct5FmvXW, Funct3Fmv, 1'b0, 1'b0, 3'd0, s2, s2, vb, '0, 1'b1);
        endcase
      end
    endcase
  endtask  // Automatic

  task automatic test_random();
    for (int k = 0; k < 5; k++) begin
      open_files(k);
      for (int i = 0; i < RandOps; i++) rand_op(rmv[k]);
      close_files();
      drain();
    end
  endtask  // Automatic

  task automatic verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (busy_stalls < MinStalls)
      $fatal(1, "TB UNDER-RAN: %0d busy-bit stalls, expected at least %0d", busy_stalls, MinStalls);
    if (errors != 0) $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $display("PASS: %0d checks, %0d busy-bit stalls, %0d write-port stalls, %0d mismatches",
             checks, busy_stalls, port_stalls, errors);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    repeat (Timeout) @(posedge clk);
    $fatal(1, "FAIL: timeout, %0d mismatches, %0d checks", errors, checks);
  end

  initial begin
    $dumpfile("fp_unit_tb.vcd");
    $dumpvars(0, fp_unit_tb);
    do_reset();
    test_directed();
    test_dependent();
    test_booking();
    test_rm_at_start();
    test_cancel();
    test_stall_core_en();
    test_div_done_cycle();
    test_random();
    drain();
    verdict();
  end

endmodule

`default_nettype wire
