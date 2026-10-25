`default_nettype none

module fp_unit_tb
  import fp_pkg::*;
();

  localparam int Xlen = arch_pkg::XLEN;
  localparam int NRegs = arch_pkg::NumRegs;
  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int DataW = (FLEN > Xlen) ? FLEN : Xlen;
  localparam int FlagW = fp_pkg::FlagW;
  localparam int RmW = fp_pkg::RmW;
  localparam int F5W = $bits(Funct5Fadd);
  localparam int F3W = $bits(Funct3Fsgnj);
  localparam int RandOps = 1200;
  localparam int MinChecks = 150000;
  localparam int MinStalls = 500;
  localparam int Timeout = 100000;
  localparam logic [FLEN-1:0] Qnan = {1'b0, {ExpW{1'b1}}, 1'b1, {(FracW - 1) {1'b0}}};
  localparam logic [FLEN-1:0] PosInf = {1'b0, {ExpW{1'b1}}, {FracW{1'b0}}};
  localparam logic [FLEN-1:0] SignBit = {1'b1, {(FLEN - 1) {1'b0}}};

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int busy_stalls = 0;
  int port_stalls = 0;
  int cycle = 0;

  logic clk = 1'b0;
  logic rst_n;
  logic core_en;

  logic start;
  logic xstart;
  logic xack;
  fp_unit_e unit;
  logic sub;
  logic neg_prod;
  logic neg_add;
  logic to_int;
  logic is_unsigned;
  logic sqrt;
  logic [F5W-1:0] funct5;
  logic [F3W-1:0] funct3;
  logic [RmW-1:0] rm;
  logic [AWIDTH-1:0] rd;
  logic [FLEN-1:0] a;
  logic [FLEN-1:0] b;
  logic [FLEN-1:0] c;
  logic [Xlen-1:0] xa;

  logic ready;
  logic idle;
  logic [NRegs-1:0] reg_busy;
  logic wb_valid;
  logic [AWIDTH-1:0] wb_rd;
  logic [FLEN-1:0] wb_data;
  logic [FlagW-1:0] wb_flags;
  logic xvalid;
  logic [Xlen-1:0] xresult;
  logic [FlagW-1:0] xflags;

  logic [FLEN-1:0] shadow[NRegs];
  logic exp_pend[NRegs];
  logic [FLEN-1:0] exp_data[NRegs];
  logic [FlagW-1:0] exp_flags[NRegs];
  int exp_issue[NRegs];
  int exp_lat[NRegs];
  logic [FlagW-1:0] flags_model;
  logic [FlagW-1:0] flags_dut;

  int fd[13];
  string rms[5] = '{"rne", "rtz", "rdn", "rup", "rmm"};
  logic [RmW-1:0] rmv[5] = '{RmRne, RmRtz, RmRdn, RmRup, RmRmm};

  initial void'($value$plusargs("max_errors=%d", max_errors));

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

  task automatic check(input string name, input logic [DataW-1:0] got, input logic [DataW-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  function automatic string at(input string name);
    at = $sformatf("cycle %0d %s", cycle, name);
  endfunction

  task automatic do_reset();
    rst_n = 1'b0;
    core_en = 1'b1;
    sub = 1'b0;
    neg_prod = 1'b0;
    neg_add = 1'b0;
    to_int = 1'b0;
    is_unsigned = 1'b0;
    sqrt = 1'b0;
    funct5 = '0;
    funct3 = '0;
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

  function automatic logic [NRegs-1:0] pend_mask();
    logic [NRegs-1:0] m;
    for (int r = 0; r < NRegs; r++) m[r] = exp_pend[r];
    return m;
  endfunction

  task automatic idle_inputs();
    start  = 1'b0;
    xstart = 1'b0;
    xack   = 1'b0;
    unit   = fp_unit_e'($urandom_range(int'(FP_MV_W_X)));
    rm     = RmW'($urandom);
    rd     = AWIDTH'($urandom);
    a      = FLEN'($urandom);
    b      = FLEN'($urandom);
    c      = FLEN'($urandom);
    xa     = Xlen'($urandom);
  endtask  // Automatic

  task automatic tick();
    logic [NRegs-1:0] wb_bit;
    @(posedge clk);
    cycle++;
    #1;
    idle_inputs();
    @(negedge clk);
    wb_bit = wb_valid ? (NRegs'(1) << wb_rd) : '0;
    if (wb_valid) begin
      check(at($sformatf("write to f%0d pending", wb_rd)), DataW'(exp_pend[wb_rd]), DataW'(1'b1));
      if (exp_pend[wb_rd]) begin
        check(at($sformatf("f%0d data", wb_rd)), DataW'(wb_data), DataW'(exp_data[wb_rd]));
        check(at($sformatf("f%0d flags", wb_rd)), DataW'(wb_flags), DataW'(exp_flags[wb_rd]));
        if (exp_lat[wb_rd] != 0)
          check(at($sformatf("f%0d latency", wb_rd)), DataW'(cycle - exp_issue[wb_rd]),
                DataW'(exp_lat[wb_rd]));
        exp_pend[wb_rd] = 1'b0;
        shadow[wb_rd]   = wb_data;
        flags_dut       = flags_dut | wb_flags;
        flags_model     = flags_model | exp_flags[wb_rd];
      end
    end
    check(at("reg_busy"), DataW'(reg_busy), DataW'(pend_mask() & ~wb_bit));
    check(at("idle"), DataW'(idle), DataW'((pend_mask() | wb_bit) == '0));
    check(at("flags_accrued"), DataW'(flags_dut), DataW'(flags_model));
  endtask  // Automatic

  task automatic fop(input fp_unit_e u, input logic [F5W-1:0] f5, input logic [F3W-1:0] f3,
                     input logic [RmW-1:0] mode, input logic [AWIDTH-1:0] dst,
                     input logic [AWIDTH-1:0] s1, input logic [AWIDTH-1:0] s2,
                     input logic [AWIDTH-1:0] s3, input logic [Xlen-1:0] xin,
                     input logic [FLEN-1:0] exp_res, input logic [FlagW-1:0] exp_fl);
    logic [NRegs-1:0] need;
    need = (NRegs'(1) << dst) | (NRegs'(1) << s1) | (NRegs'(1) << s2) | (NRegs'(1) << s3);
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

  task automatic load(input logic [AWIDTH-1:0] dst, input logic [FLEN-1:0] val);
    fop(FP_MV_W_X, Funct5FmvWX, Funct3Fmv, RmW'($urandom), dst, dst, dst, dst, Xlen'(val), val, '0);
  endtask  // Automatic

  task automatic xop(input fp_unit_e u, input logic [F5W-1:0] f5, input logic [F3W-1:0] f3,
                     input logic ti, input logic uns, input logic [RmW-1:0] mode,
                     input logic [AWIDTH-1:0] s1, input logic [AWIDTH-1:0] s2,
                     input logic [Xlen-1:0] exp_res, input logic [FlagW-1:0] exp_fl,
                     input logic retire);
    logic [NRegs-1:0] need;
    need = (NRegs'(1) << s1) | (NRegs'(1) << s2);
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
    check(at("xvalid_before"), DataW'(xvalid), DataW'(1'b0));
    tick();
    check(at("xvalid"), DataW'(xvalid), DataW'(1'b1));
    check(at("xresult"), DataW'(xresult), DataW'(exp_res));
    check(at("xflags"), DataW'(xflags), DataW'(exp_fl));
    if (retire) flags_model = flags_model | exp_fl;
    if (retire) flags_dut = flags_dut | xflags;
    xack = 1'b1;
    tick();
    check(at("xvalid_after"), DataW'(xvalid), DataW'(1'b0));
  endtask  // Automatic

  task automatic drain();
    int n;
    n = 0;
    while (pend_mask() != '0 && n < 200) begin
      tick();
      n++;
    end
    check(at("drained"), DataW'(pend_mask()), '0);
  endtask  // Automatic

  task automatic test_directed();
    load(AWIDTH'(1), 32'h3F80_0000);
    load(AWIDTH'(2), 32'h4040_0000);
    load(AWIDTH'(3), 32'hBFC0_0000);
    load(AWIDTH'(4), 32'h3EAA_AAAB);

    fop(FP_ADD, Funct5Fadd, RmRne, RmRne, AWIDTH'(10), AWIDTH'(1), AWIDTH'(2), AWIDTH'(0), '0,
        32'h4080_0000, '0);
    fop(FP_ADD, Funct5Fsub, RmRne, RmRne, AWIDTH'(11), AWIDTH'(1), AWIDTH'(2), AWIDTH'(0), '0,
        32'hC000_0000, '0);
    fop(FP_MUL, Funct5Fmul, RmRne, RmRne, AWIDTH'(12), AWIDTH'(2), AWIDTH'(3), AWIDTH'(0), '0,
        32'hC090_0000, '0);
    fop(FP_FMA, F5W'(0), RmRne, RmRne, AWIDTH'(13), AWIDTH'(1), AWIDTH'(2), AWIDTH'(3), '0,
        32'h3FC0_0000, '0);
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, AWIDTH'(14), AWIDTH'(1), AWIDTH'(2), AWIDTH'(0), '0,
        32'h3EAA_AAAB, FlagNx);
    fop(FP_DIV_SQRT, Funct5Fsqrt, RmRne, RmRne, AWIDTH'(15), AWIDTH'(2), AWIDTH'(0), AWIDTH'(0), '0,
        32'h3FDD_B3D7, FlagNx);
    fop(FP_MISC, Funct5Fsgnj, Funct3Fsgnjn, RmRne, AWIDTH'(16), AWIDTH'(2), AWIDTH'(3), AWIDTH'(0),
        '0, 32'h4040_0000, '0);
    fop(FP_MISC, Funct5Fminmax, Funct3Fmin, RmRne, AWIDTH'(17), AWIDTH'(1), AWIDTH'(3), AWIDTH'(0),
        '0, 32'hBFC0_0000, '0);
    fop(FP_CVT, Funct5FcvtSW, F3W'(0), RmRne, AWIDTH'(18), AWIDTH'(0), AWIDTH'(0), AWIDTH'(0),
        32'hFFFF_FFF9, 32'hC0E0_0000, '0);
    fop(FP_CVT, Funct5FcvtSW, F3W'(1), RmRne, AWIDTH'(19), AWIDTH'(0), AWIDTH'(0), AWIDTH'(0),
        32'hFFFF_FFF9, 32'h4F80_0000, FlagNx);
    drain();

    xop(FP_MISC, Funct5Fcmp, Funct3Flt, 1'b0, 1'b0, RmRne, AWIDTH'(1), AWIDTH'(2), Xlen'(1), '0,
        1'b1);
    xop(FP_MISC, Funct5FmvXW, Funct3Fclass, 1'b0, 1'b0, RmRne, AWIDTH'(3), AWIDTH'(0), Xlen'(2), '0,
        1'b1);
    xop(FP_MV_X_W, Funct5FmvXW, Funct3Fmv, 1'b0, 1'b0, RmRne, AWIDTH'(4), AWIDTH'(0), 32'h3EAA_AAAB,
        '0, 1'b1);
    xop(FP_CVT, Funct5FcvtWS, F3W'(0), 1'b1, 1'b0, RmRtz, AWIDTH'(3), AWIDTH'(0), 32'hFFFF_FFFF,
        FlagNx, 1'b1);
    xop(FP_CVT, Funct5FcvtWS, F3W'(0), 1'b1, 1'b1, RmRne, AWIDTH'(3), AWIDTH'(0), Xlen'(0), FlagNv,
        1'b1);
  endtask  // Automatic

  task automatic test_dependent();
    int t0;
    load(AWIDTH'(1), 32'h3F80_0000);
    load(AWIDTH'(2), 32'h4000_0000);
    t0 = busy_stalls;
    fop(FP_MUL, Funct5Fmul, RmRne, RmRne, AWIDTH'(5), AWIDTH'(2), AWIDTH'(2), AWIDTH'(0), '0,
        32'h4080_0000, '0);
    fop(FP_ADD, Funct5Fadd, RmRne, RmRne, AWIDTH'(6), AWIDTH'(5), AWIDTH'(1), AWIDTH'(0), '0,
        32'h40A0_0000, '0);
    check(at("dependent_add_stalled"), DataW'(busy_stalls - t0 >= FpMulLatency - 1), DataW'(1'b1));
    fop(FP_FMA, F5W'(0), RmRne, RmRne, AWIDTH'(5), AWIDTH'(6), AWIDTH'(6), AWIDTH'(5), '0,
        32'h41E8_0000, '0);
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, AWIDTH'(7), AWIDTH'(5), AWIDTH'(2), AWIDTH'(0), '0,
        32'h4168_0000, '0);
    fop(FP_ADD, Funct5Fadd, RmRne, RmRne, AWIDTH'(7), AWIDTH'(7), AWIDTH'(7), AWIDTH'(0), '0,
        32'h41E8_0000, '0);
    drain();
    xop(FP_MV_X_W, Funct5FmvXW, Funct3Fmv, 1'b0, 1'b0, RmRne, AWIDTH'(7), AWIDTH'(0), 32'h41E8_0000,
        '0, 1'b1);
  endtask  // Automatic

  task automatic test_booking();
    load(AWIDTH'(1), 32'h3F80_0000);
    load(AWIDTH'(2), 32'h4000_0000);
    drain();
    unit = FP_MUL;
    rd = AWIDTH'(8);
    a = shadow[1];
    b = shadow[2];
    rm = RmRne;
    #1;
    check(at("mul_ready_idle"), DataW'(ready), DataW'(1'b1));
    start        = 1'b1;
    exp_pend[8]  = 1'b1;
    exp_data[8]  = 32'h4000_0000;
    exp_flags[8] = '0;
    exp_issue[8] = cycle;
    exp_lat[8]   = FpMulLatency;
    tick();
    unit = FP_ADD;
    #1;
    check(at("add_behind_mul_clash"), DataW'(ready), DataW'(FpAddLatency != FpMulLatency - 1));
    unit = FP_MUL;
    #1;
    check(at("mul_behind_mul_free"), DataW'(ready), DataW'(1'b1));
    unit = FP_DIV_SQRT;
    #1;
    check(at("div_free_beside_mul"), DataW'(ready), DataW'(1'b1));
    drain();

    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, AWIDTH'(9), AWIDTH'(1), AWIDTH'(2), AWIDTH'(0), '0,
        32'h3F00_0000, '0);
    unit = FP_DIV_SQRT;
    #1;
    check(at("div_busy_not_ready"), DataW'(ready), DataW'(1'b0));
    for (int i = 0; i < 6; i++) begin
      fop(FP_ADD, Funct5Fadd, RmRne, RmRne, AWIDTH'(10 + i), AWIDTH'(1), AWIDTH'(1), AWIDTH'(0), '0,
          32'h4000_0000, '0);
      check(at("div_still_pending"), DataW'(exp_pend[9]), DataW'(1'b1));
    end
    drain();
  endtask  // Automatic

  task automatic test_rm_at_start();
    load(AWIDTH'(1), 32'h4B80_0001);
    load(AWIDTH'(2), 32'h3F80_0000);
    load(AWIDTH'(3), 32'hBF80_0000);
    fop(FP_ADD, Funct5Fadd, RmRup, RmRup, AWIDTH'(4), AWIDTH'(1), AWIDTH'(2), AWIDTH'(0), '0,
        32'h4B80_0002, FlagNx);
    fop(FP_ADD, Funct5Fadd, RmRne, RmRne, AWIDTH'(5), AWIDTH'(1), AWIDTH'(2), AWIDTH'(0), '0,
        32'h4B80_0002, FlagNx);
    fop(FP_ADD, Funct5Fadd, RmRtz, RmRtz, AWIDTH'(6), AWIDTH'(1), AWIDTH'(2), AWIDTH'(0), '0,
        32'h4B80_0001, FlagNx);
    fop(FP_ADD, Funct5Fadd, RmRdn, RmRdn, AWIDTH'(7), AWIDTH'(1), AWIDTH'(3), AWIDTH'(0), '0,
        32'h4B80_0000, FlagNx);
    fop(FP_MUL, Funct5Fmul, RmRtz, RmRtz, AWIDTH'(8), AWIDTH'(1), AWIDTH'(2), AWIDTH'(0), '0,
        32'h4B80_0001, '0);
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRup, RmRup, AWIDTH'(9), AWIDTH'(2), AWIDTH'(1), AWIDTH'(0), '0,
        32'h337F_FFFF, FlagNx);
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRtz, RmRtz, AWIDTH'(10), AWIDTH'(2), AWIDTH'(1), AWIDTH'(0), '0,
        32'h337F_FFFE, FlagNx);
    drain();
  endtask  // Automatic

  task automatic test_cancel();
    logic [FlagW-1:0] prior;
    load(AWIDTH'(1), 32'h3F80_0000);
    load(AWIDTH'(2), 32'h0000_0000);
    drain();
    prior = flags_dut;
    unit = FP_DIV_SQRT;
    funct5 = Funct5Fdiv;
    rd = AWIDTH'(20);
    a = shadow[1];
    b = shadow[2];
    #1;
    check(at("cancel_ready"), DataW'(ready), DataW'(1'b1));
    tick();
    unit = FP_ADD;
    rd = AWIDTH'(21);
    a = 32'h7F80_0001;
    #1;
    tick();
    repeat (40) tick();
    check(at("cancel_no_flags"), DataW'(flags_dut), DataW'(prior));
    check(at("cancel_idle"), DataW'(idle), DataW'(1'b1));
    xop(FP_MISC, Funct5Fcmp, Funct3Flt, 1'b0, 1'b0, RmRne, AWIDTH'(1), AWIDTH'(1), Xlen'(0), '0,
        1'b0);
    load(AWIDTH'(3), 32'h7F80_0001);
    xop(FP_MISC, Funct5Fcmp, Funct3Feq, 1'b0, 1'b0, RmRne, AWIDTH'(3), AWIDTH'(1), Xlen'(0), FlagNv,
        1'b0);
    check(at("cancelled_xop_no_flags"), DataW'(flags_dut), DataW'(prior));
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, AWIDTH'(20), AWIDTH'(1), AWIDTH'(2), AWIDTH'(0), '0,
        PosInf, FlagDz);
    drain();
    check(at("retired_div_flags"), DataW'(flags_dut), DataW'(prior | FlagDz));
  endtask  // Automatic

  task automatic test_stall_core_en();
    load(AWIDTH'(1), 32'h3F80_0000);
    load(AWIDTH'(2), 32'h4000_0000);
    fop(FP_MUL, Funct5Fmul, RmRne, RmRne, AWIDTH'(3), AWIDTH'(2), AWIDTH'(2), AWIDTH'(0), '0,
        32'h4080_0000, '0);
    exp_lat[3] = 0;
    @(negedge clk);
    core_en = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk);
    core_en = 1'b1;
    drain();
    xop(FP_MV_X_W, Funct5FmvXW, Funct3Fmv, 1'b0, 1'b0, RmRne, AWIDTH'(3), AWIDTH'(0), 32'h4080_0000,
        '0, 1'b1);
  endtask  // Automatic

  task automatic test_div_done_cycle();
    int lat;
    int t9;
    load(AWIDTH'(1), 32'h3F80_0000);
    load(AWIDTH'(2), 32'h4040_0000);
    drain();
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, AWIDTH'(9), AWIDTH'(1), AWIDTH'(2), AWIDTH'(0), '0,
        32'h3EAA_AAAB, FlagNx);
    t9 = exp_issue[9];
    while (exp_pend[9]) tick();
    lat = cycle - t9;

    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, AWIDTH'(9), AWIDTH'(1), AWIDTH'(2), AWIDTH'(0), '0,
        32'h3EAA_AAAB, FlagNx);
    t9 = exp_issue[9];
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, AWIDTH'(10), AWIDTH'(2), AWIDTH'(1), AWIDTH'(0), '0,
        32'h4040_0000, '0);
    check(at("div_starts_in_done_cycle"), DataW'(exp_issue[10] - t9), DataW'(lat));
    drain();

    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, AWIDTH'(9), AWIDTH'(1), AWIDTH'(2), AWIDTH'(0), '0,
        32'h3EAA_AAAB, FlagNx);
    t9 = exp_issue[9];
    while (cycle < t9 + lat - 1) tick();
    load(AWIDTH'(11), 32'h4000_0000);
    check(at("mv_writes_in_done_cycle"), DataW'(exp_issue[11] - t9), DataW'(lat - 1));
    fop(FP_DIV_SQRT, Funct5Fdiv, RmRne, RmRne, AWIDTH'(10), AWIDTH'(2), AWIDTH'(1), AWIDTH'(0), '0,
        32'h4040_0000, '0);
    check(at("div_waits_for_pended_write"), DataW'(exp_issue[10] - t9), DataW'(lat + 1));
    drain();
  endtask  // Automatic

  task automatic open_files(input int k);
    string names[$size(fd)];
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
    for (int i = 0; i < $size(fd); i++) begin
      fd[i] = $fopen({"build/testfloat/", names[i], ".txt"}, "r");
      if (fd[i] == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", names[i]);
      for (int s = $urandom_range(300); s > 0; s--) void'($fgets(skip, fd[i]));
    end
  endtask  // Automatic

  task automatic close_files();
    for (int i = 0; i < $size(fd); i++) $fclose(fd[i]);
  endtask  // Automatic

  task automatic refill(input int k);
    int ch;
    ch = $fgetc(fd[k]);
    if (ch == -1) void'($rewind(fd[k]));
    else void'($ungetc(ch, fd[k]));
  endtask  // Automatic

  function automatic logic [AWIDTH-1:0] pick_reg();
    return AWIDTH'($urandom_range(NRegs - 1));
  endfunction

  task automatic rand_op(input logic [RmW-1:0] mode);
    int kind;
    logic [FLEN-1:0] va, vb, vc, vr;
    logic [DataW-1:0] vflag;
    logic [AWIDTH-1:0] s1, s2, s3, dst;
    logic [FLEN-1:0] res;
    logic [FlagW-1:0] fl;
    logic [F3W-1:0] f3;
    int n;
    kind = $urandom_range(15);
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
          0: fop(FP_ADD, Funct5Fadd, mode, mode, dst, s1, s2, AWIDTH'(0), '0, vr, FlagW'(vflag));
          1: fop(FP_ADD, Funct5Fsub, mode, mode, dst, s1, s2, AWIDTH'(0), '0, vr, FlagW'(vflag));
          2: fop(FP_MUL, Funct5Fmul, mode, mode, dst, s1, s2, AWIDTH'(0), '0, vr, FlagW'(vflag));
          default:
          fop(FP_DIV_SQRT, Funct5Fdiv, mode, mode, dst, s1, s2, AWIDTH'(0), '0, vr, FlagW'(vflag));
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
        fop(FP_FMA, F5W'(form), mode, mode, dst, s1, s2, s3, '0, vr, FlagW'(vflag));
      end
      5: begin
        n = $fscanf(fd[5], "%h %h %h\n", va, vr, vflag);
        if (n != 3) $fatal(1, "TB BAD LINE: file 5");
        load(s1, va);
        fop(FP_DIV_SQRT, Funct5Fsqrt, mode, mode, dst, s1, s1, AWIDTH'(0), '0, vr, FlagW'(vflag));
      end
      6, 7: begin
        n = $fscanf(fd[kind], "%h %h %h\n", va, vr, vflag);
        if (n != 3) $fatal(1, "TB BAD LINE: file %0d", kind);
        fop(FP_CVT, Funct5FcvtSW, F3W'(kind == 7), mode, dst, dst, dst, dst, Xlen'(va), vr,
            FlagW'(vflag));
      end
      8, 9: begin
        n = $fscanf(fd[kind], "%h %h %h\n", va, vr, vflag);
        if (n != 3) $fatal(1, "TB BAD LINE: file %0d", kind);
        load(s1, va);
        xop(FP_CVT, Funct5FcvtWS, F3W'(0), 1'b1, kind == 9, mode, s1, s1, Xlen'(vr), FlagW'(vflag),
            1'b1);
      end
      10, 11, 12: begin
        n = $fscanf(fd[kind], "%h %h %h %h\n", va, vb, vr, vflag);
        if (n != 4) $fatal(1, "TB BAD LINE: file %0d", kind);
        load(s1, va);
        load(s2, vb);
        case (kind)
          10: f3 = Funct3Feq;
          11: f3 = Funct3Flt;
          default: f3 = Funct3Fle;
        endcase
        xop(FP_MISC, Funct5Fcmp, f3, 1'b0, 1'b0, RmRne, s1, s2, Xlen'(vr), FlagW'(vflag), 1'b1);
      end
      default: begin
        va = ($urandom_range(3) == 0) ? (PosInf | FLEN'($urandom_range(1, 8))) : FLEN'($urandom);
        vb = ($urandom_range(3) == 0) ? {1'($urandom), (FLEN - 1)'(0)} : FLEN'($urandom);
        load(s1, va);
        load(s2, vb);
        n = $urandom_range(3);
        case (n)
          0: begin
            f3  = F3W'($urandom_range(2));
            res = sgnj_model(f3, va, vb);
            fop(FP_MISC, Funct5Fsgnj, f3, RmW'($urandom), dst, s1, s2, AWIDTH'(0), '0, res, '0);
          end
          1: begin
            f3 = F3W'(1'($urandom));
            minmax_model(f3[0], va, vb, res, fl);
            fop(FP_MISC, Funct5Fminmax, f3, RmW'($urandom), dst, s1, s2, AWIDTH'(0), '0, res, fl);
          end
          2: begin
            res = fclass_of(va);
            xop(FP_MISC, Funct5FmvXW, Funct3Fclass, 1'b0, 1'b0, RmRne, s1, s1, Xlen'(res), '0,
                1'b1);
          end
          default:
          xop(FP_MV_X_W, Funct5FmvXW, Funct3Fmv, 1'b0, 1'b0, RmRne, s2, s2, Xlen'(vb), '0, 1'b1);
        endcase
      end
    endcase
  endtask  // Automatic

  task automatic test_random();
    for (int k = 0; k < $size(rmv); k++) begin
      open_files(k);
      for (int i = 0; i < RandOps; i++) rand_op(rmv[k]);
      close_files();
      drain();
    end
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (busy_stalls < MinStalls)
      $fatal(1, "TB UNDER-RAN: %0d busy-bit stalls, expected at least %0d", busy_stalls, MinStalls);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  task automatic watchdog();
    repeat (Timeout) @(posedge clk);
    $fatal(1, "FAIL: timeout, %0d mismatches, %0d checks", errors, checks);
  endtask  // Automatic

  initial watchdog();

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
    do_verdict();
  end

  function automatic int lat_of(input fp_unit_e u);
    case (u)
      FP_ADD:      return FpAddLatency;
      FP_MUL:      return FpMulLatency;
      FP_FMA:      return FpFmaLatency;
      FP_DIV_SQRT: return 0;
      default:     return 1;
    endcase
  endfunction

  function automatic logic is_nan(input logic [FLEN-1:0] x);
    return (x[FLEN-2:FracW] == '1) && (x[FracW-1:0] != '0);
  endfunction

  function automatic logic is_snan(input logic [FLEN-1:0] x);
    return is_nan(x) && !x[FracW-1];
  endfunction

  function automatic logic [FLEN-1:0] fclass_of(input logic [FLEN-1:0] x);
    logic sign;
    logic [ExpW-1:0] e;
    logic [FracW-1:0] f;
    sign = x[FLEN-1];
    e = x[FLEN-2:FracW];
    f = x[FracW-1:0];
    if (e == '1 && f == '0) return FLEN'(1) << (sign ? 0 : 7);
    if (e == '1) return FLEN'(1) << (f[FracW-1] ? 9 : 8);
    if (e == '0 && f == '0) return FLEN'(1) << (sign ? 3 : 4);
    if (e == '0) return FLEN'(1) << (sign ? 2 : 5);
    return FLEN'(1) << (sign ? 1 : 6);
  endfunction

  function automatic logic lt_total(input logic [FLEN-1:0] x, input logic [FLEN-1:0] y);
    if (x[FLEN-1] != y[FLEN-1]) return x[FLEN-1];
    if (x[FLEN-1]) return x[FLEN-2:0] > y[FLEN-2:0];
    return x[FLEN-2:0] < y[FLEN-2:0];
  endfunction

  task automatic minmax_model(input logic is_max, input logic [FLEN-1:0] x,
                              input logic [FLEN-1:0] y, output logic [FLEN-1:0] res,
                              output logic [FlagW-1:0] fl);
    fl = (is_snan(x) || is_snan(y)) ? FlagNv : '0;
    if (is_nan(x) && is_nan(y)) res = Qnan;
    else if (is_nan(x)) res = y;
    else if (is_nan(y)) res = x;
    else if (is_max) res = lt_total(x, y) ? y : x;
    else res = lt_total(x, y) ? x : y;
  endtask  // Automatic

  function automatic logic [FLEN-1:0] sgnj_model(input logic [F3W-1:0] f3, input logic [FLEN-1:0] x,
                                                 input logic [FLEN-1:0] y);
    case (f3)
      Funct3Fsgnj:  return {y[FLEN-1], x[FLEN-2:0]};
      Funct3Fsgnjn: return {!y[FLEN-1], x[FLEN-2:0]};
      default:      return {x[FLEN-1] ^ y[FLEN-1], x[FLEN-2:0]};
    endcase
  endfunction

endmodule

`default_nettype wire
