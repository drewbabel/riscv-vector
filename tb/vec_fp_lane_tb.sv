`default_nettype none

module vec_fp_lane_tb
  import vec_pkg::*;
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNv, fp_pkg::FlagDz, fp_pkg::FlagOf, fp_pkg::FlagNx;
  import fp_pkg::ExpW, fp_pkg::FracW, fp_pkg::Bias;
();

  localparam int FLEN = fp_pkg::FLEN;
  localparam int FlagW = $bits(fp_pkg::FlagNv);
  localparam int RmW = $bits(fp_pkg::RmRne);
  localparam int Latency = VecFpLatency;
  localparam int MinChecks = 6_400_000;
  localparam int NumSpecial = 22;
  localparam int NumMisc = 13;
  localparam int RandPerOp = 4000;
  localparam int MiscStallPct = 25;
  localparam int FileStallPct = 10;
  localparam string TfDir = "build/testfloat/";
  localparam logic [FLEN-1:0] SignBit = {1'b1, {(FLEN - 1) {1'b0}}};
  localparam logic [FLEN-1:0] Inf = {1'b0, {ExpW{1'b1}}, {FracW{1'b0}}};
  localparam logic [FLEN-1:0] QuietBit = FLEN'(1) << (FracW - 1);
  localparam logic [FLEN-1:0] Qnan = Inf | QuietBit;
  localparam logic [FLEN-1:0] QnanPayload = Qnan | FLEN'(1);
  localparam logic [FLEN-1:0] SNan = Inf | FLEN'(1);
  localparam logic [FLEN-1:0] SNanMid = Inf | (QuietBit >> 1);
  localparam logic [FLEN-1:0] AllOnes = '1;
  localparam logic [FLEN-1:0] PosAllOnes = ~SignBit;
  localparam logic [FLEN-1:0] MinSub = FLEN'(1);
  localparam logic [FLEN-1:0] MaxSub = (FLEN'(1) << FracW) - 1;
  localparam logic [FLEN-1:0] MinNorm = FLEN'(1) << FracW;
  localparam logic [FLEN-1:0] MaxNorm = Inf - 1;
  localparam logic [FLEN-1:0] One = FLEN'(Bias) << FracW;
  localparam logic [FLEN-1:0] Two = FLEN'(Bias + 1) << FracW;
  localparam logic [FLEN-1:0] Three = Two | QuietBit;
  localparam logic [FLEN-1:0] Four = FLEN'(Bias + 2) << FracW;
  localparam logic [FLEN-1:0] Five = Four | (QuietBit >> 1);
  localparam logic [FLEN-1:0] Seven = Four | QuietBit | (QuietBit >> 1);
  localparam logic [FLEN-1:0] NegInf = SignBit | Inf;
  localparam logic [FLEN-1:0] NegQnan = SignBit | Qnan;
  localparam logic [FLEN-1:0] NegSNan = SignBit | SNan;
  localparam logic [FLEN-1:0] NegSNanMax = AllOnes ^ QuietBit;
  localparam logic [FLEN-1:0] NegMinSub = SignBit | MinSub;
  localparam logic [FLEN-1:0] NegMaxSub = SignBit | MaxSub;
  localparam logic [FLEN-1:0] NegMinNorm = SignBit | MinNorm;
  localparam logic [FLEN-1:0] NegMaxNorm = SignBit | MaxNorm;
  localparam logic [FLEN-1:0] NegOne = SignBit | One;
  localparam logic [FLEN-1:0] NegFive = SignBit | Five;
  localparam logic [FLEN-1:0] NegSeven = SignBit | Seven;

  typedef struct packed {
    vec_fop_e op;
    logic [RmW-1:0] rm;
    logic [FLEN-1:0] a;
    logic [FLEN-1:0] b;
    logic [FLEN-1:0] c;
  } op_info_t;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int stall_pct = 0;
  int en_cycle = 0;
  int seed = 7;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic core_en;
  logic valid;
  vec_fop_e op;
  logic [RmW-1:0] rm;
  logic [FLEN-1:0] a;
  logic [FLEN-1:0] b;
  logic [FLEN-1:0] c;
  logic [FLEN-1:0] result;
  logic [FlagW-1:0] fflags;
  logic result_valid;

  logic [FLEN-1:0] q_res[$];
  logic [FlagW-1:0] q_flags[$];
  int q_issue[$];
  logic [$bits(op_info_t)-1:0] q_info[$];
  string q_src[$];

  always #5 clk = ~clk;

  vec_fp_lane dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .valid(valid),
      .op(op),
      .rm(rm),
      .a(a),
      .b(b),
      .c(c),
      .result(result),
      .fflags(fflags),
      .result_valid(result_valid)
  );

  task automatic check(input string name, input logic [FLEN-1:0] got, input logic [FLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset(input int cycles);
    rst_n = 1'b0;
    core_en = 1'b1;
    valid = 1'b0;
    op = VEC_FADD;
    rm = RmRne;
    a = '0;
    b = '0;
    c = '0;
    q_res.delete();
    q_flags.delete();
    q_issue.delete();
    q_info.delete();
    q_src.delete();
    repeat (cycles) tick();
    rst_n = 1'b1;
    tick();
  endtask  // Automatic

  task automatic seed_random();
    void'($urandom(seed));
  endtask  // Automatic

  task automatic tick();
    logic was_en;
    logic [FLEN-1:0] prev_res;
    logic [FlagW-1:0] prev_flags;
    logic prev_vld;
    was_en = core_en;
    prev_res = result;
    prev_flags = fflags;
    prev_vld = result_valid;
    @(posedge clk);
    @(negedge clk);
    if (!rst_n) begin
      check("result_valid in reset", FLEN'(result_valid), '0);
    end else if (!was_en) begin
      check("result held with core_en low", result, prev_res);
      check("fflags held with core_en low", FLEN'(fflags), FLEN'(prev_flags));
      check("result_valid held with core_en low", FLEN'(result_valid), FLEN'(prev_vld));
    end else begin
      en_cycle++;
      check_retire();
    end
  endtask  // Automatic

  task automatic check_retire();
    logic exp_valid;
    logic [FLEN-1:0] er;
    logic [FlagW-1:0] ef;
    op_info_t info;
    vec_fop_e fo;
    string name;
    exp_valid = q_issue.size() != 0 && (en_cycle - q_issue[0]) >= Latency;
    check($sformatf("result_valid at %0t", $time), FLEN'(result_valid), FLEN'(exp_valid));
    if (exp_valid) begin
      er = q_res.pop_front();
      ef = q_flags.pop_front();
      void'(q_issue.pop_front());
      info = op_info_t'(q_info.pop_front());
      fo = info.op;
      name = $sformatf(
          "%s %s rm=%0d a=%h b=%h c=%h",
          q_src.pop_front(),
          fo.name(),
          info.rm,
          info.a,
          info.b,
          info.c
      );
      if (result_valid === 1'b1) begin
        check({name, " result"}, result, er);
        check({name, " fflags"}, FLEN'(fflags), FLEN'(ef));
      end
    end
  endtask  // Automatic

  task automatic stalls();
    while ($urandom_range(
        99
    ) < stall_pct) begin
      core_en = $urandom_range(3) != 0;
      valid   = 1'b0;
      if (!core_en) begin
        valid = 1'($urandom);
        op = vec_fop_e'($urandom_range(int'(VEC_FMV)));
        a = FLEN'($urandom);
        b = FLEN'($urandom);
        c = FLEN'($urandom);
      end
      tick();
    end
  endtask  // Automatic

  task automatic send(input string src, input vec_fop_e o, input logic [RmW-1:0] mode,
                      input logic [FLEN-1:0] x, input logic [FLEN-1:0] y, input logic [FLEN-1:0] z,
                      input logic [FLEN-1:0] er, input logic [FlagW-1:0] ef);
    op_info_t info;
    stalls();
    core_en = 1'b1;
    valid = 1'b1;
    op = o;
    rm = mode;
    a = x;
    b = y;
    c = z;
    info.op = o;
    info.rm = mode;
    info.a = x;
    info.b = y;
    info.c = z;
    q_res.push_back(er);
    q_flags.push_back(ef);
    q_issue.push_back(en_cycle);
    q_info.push_back(info);
    q_src.push_back(src);
    tick();
    valid = 1'b0;
  endtask  // Automatic

  task automatic send_misc(input string src, input vec_fop_e o, input logic [FLEN-1:0] x,
                           input logic [FLEN-1:0] y);
    logic [ FLEN-1:0] r;
    logic [FlagW-1:0] f;
    ref_misc(o, x, y, r, f);
    send(src, o, RmW'($urandom_range(RmRmm)), x, y, FLEN'($urandom), r, f);
  endtask  // Automatic

  task automatic drain();
    core_en = 1'b1;
    valid   = 1'b0;
    repeat (Latency + 2) tick();
    check("results never arrived", FLEN'(q_res.size()), '0);
  endtask  // Automatic

  task automatic run_binary(input string path, input vec_fop_e o, input logic [RmW-1:0] mode);
    int fd;
    int line;
    logic [FLEN-1:0] x;
    logic [FLEN-1:0] y;
    logic [FLEN-1:0] er;
    logic [FlagW-1:0] ef;
    string src;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    line = 0;
    while ($fscanf(
        fd, "%h %h %h %h\n", x, y, er, ef
    ) == 4) begin
      line++;
      begin
        src = $sformatf("%s:%0d", path, line);
        if (o == VEC_FSUB && line[0]) send(src, VEC_FRSUB, mode, y, x, FLEN'($urandom), er, ef);
        else send(src, o, mode, x, y, FLEN'($urandom), er, ef);
      end
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, line + 1);
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, line);
  endtask  // Automatic

  task automatic run_fma(input string path, input logic [RmW-1:0] mode);
    int fd;
    int line;
    logic [FLEN-1:0] x;
    logic [FLEN-1:0] y;
    logic [FLEN-1:0] z;
    logic [FLEN-1:0] er;
    logic [FlagW-1:0] ef;
    string src;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    line = 0;
    while ($fscanf(
        fd, "%h %h %h %h %h\n", x, y, z, er, ef
    ) == 5) begin
      line++;
      begin
        src = $sformatf("%s:%0d", path, line);
        case (line % 8)
          0: send(src, VEC_FMACC, mode, x, y, z, er, ef);
          1: send(src, VEC_FNMACC, mode, neg(x), y, neg(z), er, ef);
          2: send(src, VEC_FMSAC, mode, x, y, neg(z), er, ef);
          3: send(src, VEC_FNMSAC, mode, neg(x), y, z, er, ef);
          4: send(src, VEC_FMADD, mode, z, x, y, er, ef);
          5: send(src, VEC_FNMADD, mode, neg(z), neg(x), y, er, ef);
          6: send(src, VEC_FMSUB, mode, neg(z), x, y, er, ef);
          default: send(src, VEC_FNMSUB, mode, z, neg(x), y, er, ef);
        endcase
      end
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, line + 1);
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, line);
  endtask  // Automatic

  task automatic run_cmp(input string path, input vec_fop_e o, input vec_fop_e o_swap);
    int fd;
    int line;
    logic [FLEN-1:0] x;
    logic [FLEN-1:0] y;
    logic r;
    logic [FlagW-1:0] ef;
    string src;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    line = 0;
    while ($fscanf(
        fd, "%h %h %h %h\n", x, y, r, ef
    ) == 4) begin
      line++;
      begin
        src = $sformatf("%s:%0d", path, line);
        send(src, o, RmW'($urandom_range(RmRmm)), x, y, FLEN'($urandom), FLEN'(r), ef);
        if (o_swap == VEC_MFNE) send(src, o_swap, RmRne, x, y, FLEN'($urandom), FLEN'(!r), ef);
        else send(src, o_swap, RmRne, y, x, FLEN'($urandom), FLEN'(r), ef);
      end
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, line + 1);
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, line);
  endtask  // Automatic

  task automatic run_modes(input string name, input vec_fop_e o);
    run_binary($sformatf("%sf%0d_%s_rne.txt", TfDir, FLEN, name), o, RmRne);
    run_binary($sformatf("%sf%0d_%s_rtz.txt", TfDir, FLEN, name), o, RmRtz);
    run_binary($sformatf("%sf%0d_%s_rdn.txt", TfDir, FLEN, name), o, RmRdn);
    run_binary($sformatf("%sf%0d_%s_rup.txt", TfDir, FLEN, name), o, RmRup);
    run_binary($sformatf("%sf%0d_%s_rmm.txt", TfDir, FLEN, name), o, RmRmm);
  endtask  // Automatic

  task automatic run_fma_modes();
    run_fma($sformatf("%sf%0d_mulAdd_rne.txt", TfDir, FLEN), RmRne);
    run_fma($sformatf("%sf%0d_mulAdd_rtz.txt", TfDir, FLEN), RmRtz);
    run_fma($sformatf("%sf%0d_mulAdd_rdn.txt", TfDir, FLEN), RmRdn);
    run_fma($sformatf("%sf%0d_mulAdd_rup.txt", TfDir, FLEN), RmRup);
    run_fma($sformatf("%sf%0d_mulAdd_rmm.txt", TfDir, FLEN), RmRmm);
  endtask  // Automatic

  task automatic run_testfloat(input int pct);
    stall_pct = pct;
    run_modes("add", VEC_FADD);
    run_modes("sub", VEC_FSUB);
    run_modes("mul", VEC_FMUL);
    run_fma_modes();
    run_cmp($sformatf("%sf%0d_eq.txt", TfDir, FLEN), VEC_MFEQ, VEC_MFNE);
    run_cmp($sformatf("%sf%0d_lt.txt", TfDir, FLEN), VEC_MFLT, VEC_MFGT);
    run_cmp($sformatf("%sf%0d_le.txt", TfDir, FLEN), VEC_MFLE, VEC_MFGE);
  endtask  // Automatic

  function automatic logic [FLEN-1:0] pick();
    logic [FLEN-1:0] x;
    x = FLEN'($urandom);
    case ($urandom_range(
        3
    ))
      0: x = special($urandom_range(NumSpecial - 1));
      1: x[FracW+:ExpW] = 1'($urandom) ? '1 : '0;
      2: x[FracW+:ExpW] = ExpW'(Bias - 1 + $urandom_range(3));
      default: ;
    endcase
    pick = x;
  endfunction

  function automatic vec_fop_e misc_op(input int k);
    case (k)
      0: misc_op = VEC_FMIN;
      1: misc_op = VEC_FMAX;
      2: misc_op = VEC_FSGNJ;
      3: misc_op = VEC_FSGNJN;
      4: misc_op = VEC_FSGNJX;
      5: misc_op = VEC_MFEQ;
      6: misc_op = VEC_MFNE;
      7: misc_op = VEC_MFLT;
      8: misc_op = VEC_MFLE;
      9: misc_op = VEC_MFGT;
      10: misc_op = VEC_MFGE;
      11: misc_op = VEC_FCLASS;
      default: misc_op = VEC_FMV;
    endcase
  endfunction

  task automatic run_misc_ops();
    logic [FLEN-1:0] x;
    logic [FLEN-1:0] y;
    for (int k = 0; k < NumMisc; k++) begin
      for (int i = 0; i < NumSpecial; i++)
      for (int j = 0; j < NumSpecial; j++) begin
        send_misc("special", misc_op(k), special(i), special(j));
      end
      for (int n = 0; n < RandPerOp; n++) begin
        x = pick();
        y = pick();
        case ($urandom_range(
            7
        ))
          0: y = x;
          1: y = neg(x);
          default: ;
        endcase
        send_misc("random", misc_op(k), x, y);
      end
    end
  endtask  // Automatic

  function automatic logic [FLEN-1:0] special(input int i);
    case (i)
      0: special = '0;
      1: special = SignBit;
      2: special = Inf;
      3: special = NegInf;
      4: special = Qnan;
      5: special = NegQnan;
      6: special = SNan;
      7: special = NegSNan;
      8: special = SNanMid;
      9: special = PosAllOnes;
      10: special = AllOnes;
      11: special = MinSub;
      12: special = NegMinSub;
      13: special = MaxSub;
      14: special = NegMaxSub;
      15: special = MinNorm;
      16: special = NegMinNorm;
      17: special = MaxNorm;
      18: special = NegMaxNorm;
      19: special = One;
      20: special = NegOne;
      default: special = Two;
    endcase
  endfunction

  // Single precision spec vectors
  task automatic run_f32_est();
    send("rec7 spec sub", VEC_FREC7, RmRne, 'h0071_8ABC, 0, 0, 'h7E90_0000, 0);
    send("rec7 spec big", VEC_FREC7, RmRne, 'h7F76_5432, 0, 0, 'h0021_4000, 0);
    send("rsqrt7 spec sub", VEC_FRSQRT7, RmRne, 'h0071_8ABC, 0, 0, 'h5F08_0000, 0);
    send("rsqrt7 spec big", VEC_FRSQRT7, RmRne, 'h7F76_5432, 0, 0, 'h1F82_0000, 0);
  endtask  // Automatic

  task automatic run_directed();
    send("min signed zero", VEC_FMIN, RmRne, 0, SignBit, 0, SignBit, 0);
    send("min signed zero", VEC_FMIN, RmRne, SignBit, 0, 0, SignBit, 0);
    send("max signed zero", VEC_FMAX, RmRne, SignBit, 0, 0, 0, 0);
    send("max signed zero", VEC_FMAX, RmRne, 0, SignBit, 0, 0, 0);
    send("min qnan", VEC_FMIN, RmRne, Qnan, One, 0, One, 0);
    send("min snan", VEC_FMIN, RmRne, One, SNan, 0, One, FlagNv);
    send("max qnan", VEC_FMAX, RmRne, NegQnan, NegOne, 0, NegOne, 0);
    send("max two nan", VEC_FMAX, RmRne, SignBit | QnanPayload, SNanMid, 0, Qnan, FlagNv);
    send("min two qnan", VEC_FMIN, RmRne, QnanPayload, NegQnan, 0, Qnan, 0);
    send("min inf", VEC_FMIN, RmRne, NegInf, NegMaxNorm, 0, NegInf, 0);
    send("max inf", VEC_FMAX, RmRne, Inf, MaxNorm, 0, Inf, 0);
    send("eq qnan", VEC_MFEQ, RmRne, Qnan, Qnan, 0, 0, 0);
    send("eq snan", VEC_MFEQ, RmRne, SNan, One, 0, 0, FlagNv);
    send("eq zeros", VEC_MFEQ, RmRne, SignBit, 0, 0, 1, 0);
    send("ne qnan", VEC_MFNE, RmRne, Qnan, One, 0, 1, 0);
    send("ne snan", VEC_MFNE, RmRne, One, NegSNan, 0, 1, FlagNv);
    send("ne zeros", VEC_MFNE, RmRne, 0, SignBit, 0, 0, 0);
    send("lt qnan", VEC_MFLT, RmRne, Qnan, One, 0, 0, FlagNv);
    send("lt zeros", VEC_MFLT, RmRne, SignBit, 0, 0, 0, 0);
    send("lt inf", VEC_MFLT, RmRne, NegInf, NegMaxNorm, 0, 1, 0);
    send("le zeros", VEC_MFLE, RmRne, 0, SignBit, 0, 1, 0);
    send("le qnan", VEC_MFLE, RmRne, One, NegQnan, 0, 0, FlagNv);
    send("gt order", VEC_MFGT, RmRne, Two, One, 0, 1, 0);
    send("gt order", VEC_MFGT, RmRne, One, Two, 0, 0, 0);
    send("gt qnan", VEC_MFGT, RmRne, One, Qnan, 0, 0, FlagNv);
    send("gt inf", VEC_MFGT, RmRne, Inf, MaxNorm, 0, 1, 0);
    send("ge zeros", VEC_MFGE, RmRne, SignBit, 0, 0, 1, 0);
    send("ge order", VEC_MFGE, RmRne, NegOne, One, 0, 0, 0);
    send("ge snan", VEC_MFGE, RmRne, SNan, SNan, 0, 0, FlagNv);
    send("class -inf", VEC_FCLASS, RmRne, NegInf, 0, 0, 'h001, 0);
    send("class -norm", VEC_FCLASS, RmRne, NegOne, 0, 0, 'h002, 0);
    send("class -sub", VEC_FCLASS, RmRne, NegMinSub, 0, 0, 'h004, 0);
    send("class -0", VEC_FCLASS, RmRne, SignBit, 0, 0, 'h008, 0);
    send("class +0", VEC_FCLASS, RmRne, 0, 0, 0, 'h010, 0);
    send("class +sub", VEC_FCLASS, RmRne, MaxSub, 0, 0, 'h020, 0);
    send("class +norm", VEC_FCLASS, RmRne, MaxNorm, 0, 0, 'h040, 0);
    send("class +inf", VEC_FCLASS, RmRne, Inf, 0, 0, 'h080, 0);
    send("class snan", VEC_FCLASS, RmRne, NegSNanMax, 0, 0, 'h100, 0);
    send("class qnan", VEC_FCLASS, RmRne, Qnan, 0, 0, 'h200, 0);
    if (FLEN == 32) run_f32_est();
    send("rec7 overflow", VEC_FREC7, RmRne, MinSub, 0, 0, Inf, FlagOf | FlagNx);
    send("rec7 overflow", VEC_FREC7, RmRne, NegMinSub, 0, 0, NegInf, FlagOf | FlagNx);
    send("rec7 overflow", VEC_FREC7, RmRtz, MinSub, 0, 0, MaxNorm, FlagOf | FlagNx);
    send("rec7 overflow", VEC_FREC7, RmRtz, NegMinSub, 0, 0, NegMaxNorm, FlagOf | FlagNx);
    send("rec7 overflow", VEC_FREC7, RmRdn, MinSub, 0, 0, MaxNorm, FlagOf | FlagNx);
    send("rec7 overflow", VEC_FREC7, RmRdn, NegMinSub, 0, 0, NegInf, FlagOf | FlagNx);
    send("rec7 overflow", VEC_FREC7, RmRup, MinSub, 0, 0, Inf, FlagOf | FlagNx);
    send("rec7 overflow", VEC_FREC7, RmRup, NegMinSub, 0, 0, NegMaxNorm, FlagOf | FlagNx);
    send("rec7 overflow", VEC_FREC7, RmRmm, MinSub, 0, 0, Inf, FlagOf | FlagNx);
    send("rec7 overflow", VEC_FREC7, RmRmm, NegMinSub, 0, 0, NegInf, FlagOf | FlagNx);
    send("rec7 +0", VEC_FREC7, RmRne, 0, 0, 0, Inf, FlagDz);
    send("rec7 -0", VEC_FREC7, RmRne, SignBit, 0, 0, NegInf, FlagDz);
    send("rec7 +inf", VEC_FREC7, RmRne, Inf, 0, 0, 0, 0);
    send("rec7 -inf", VEC_FREC7, RmRne, NegInf, 0, 0, SignBit, 0);
    send("rec7 snan", VEC_FREC7, RmRne, SNan, 0, 0, Qnan, FlagNv);
    send("rec7 qnan", VEC_FREC7, RmRne, NegQnan, 0, 0, Qnan, 0);
    send("rsqrt7 -norm", VEC_FRSQRT7, RmRne, NegOne, 0, 0, Qnan, FlagNv);
    send("rsqrt7 -sub", VEC_FRSQRT7, RmRne, NegMinSub, 0, 0, Qnan, FlagNv);
    send("rsqrt7 +0", VEC_FRSQRT7, RmRne, 0, 0, 0, Inf, FlagDz);
    send("rsqrt7 -0", VEC_FRSQRT7, RmRne, SignBit, 0, 0, NegInf, FlagDz);
    send("rsqrt7 +inf", VEC_FRSQRT7, RmRne, Inf, 0, 0, 0, 0);
    send("rsqrt7 -inf", VEC_FRSQRT7, RmRne, NegInf, 0, 0, Qnan, FlagNv);
    send("rsqrt7 snan", VEC_FRSQRT7, RmRne, NegSNan, 0, 0, Qnan, FlagNv);
    send("rsqrt7 qnan", VEC_FRSQRT7, RmRne, QnanPayload, 0, 0, Qnan, 0);
    send("sgnj nan", VEC_FSGNJ, RmRne, SNan, SignBit, 0, NegSNan, 0);
    send("sgnjn zero", VEC_FSGNJN, RmRne, 0, 0, 0, SignBit, 0);
    send("sgnjx inf", VEC_FSGNJX, RmRne, NegInf, NegOne, 0, Inf, 0);
    send("move snan", VEC_FMV, RmRne, SNan, One, 0, SNan, 0);
    send("move neg zero", VEC_FMV, RmRdn, SignBit, 0, 0, SignBit, 0);
    send("rsub order", VEC_FRSUB, RmRne, One, Two, 0, One, 0);
    send("add inf clash", VEC_FADD, RmRne, Inf, NegInf, 0, Qnan, FlagNv);
    send("sub zero rdn", VEC_FSUB, RmRdn, 0, 0, 0, SignBit, 0);
    send("mul inf zero", VEC_FMUL, RmRne, Inf, SignBit, 0, Qnan, FlagNv);
    send("macc order", VEC_FMACC, RmRne, Two, Three, One, Seven, 0);
    send("madd order", VEC_FMADD, RmRne, One, Two, Three, Seven, 0);
    send("nmacc order", VEC_FNMACC, RmRne, Two, Three, One, NegSeven, 0);
    send("nmadd order", VEC_FNMADD, RmRne, One, Two, Three, NegSeven, 0);
    send("msac order", VEC_FMSAC, RmRne, Two, Three, One, Five, 0);
    send("msub order", VEC_FMSUB, RmRne, One, Two, Three, Five, 0);
    send("nmsac order", VEC_FNMSAC, RmRne, Two, Three, One, NegFive, 0);
    send("nmsub order", VEC_FNMSUB, RmRne, One, Two, Three, NegFive, 0);
    send("macc inf zero qnan", VEC_FMACC, RmRne, Inf, 0, Qnan, Qnan, FlagNv);
  endtask  // Automatic

  task automatic run_stalled(input int pct);
    stall_pct = pct;
    run_misc_ops();
    run_directed();
  endtask  // Automatic

  task automatic run_reset_flight();
    send("reset flight", VEC_FADD, RmRne, One, One, 0, Two, 0);
    do_reset(Latency + 1);
    drain();
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
    $dumpfile("vec_fp_lane_tb.vcd");
    $dumpvars(0, vec_fp_lane_tb);
    seed_random();
    do_reset(2);

    run_directed();
    drain();
    run_stalled(MiscStallPct);
    run_testfloat(FileStallPct);
    run_reset_flight();

    drain();
    do_verdict();
  end

  function automatic logic is_nan(input logic [FLEN-2:0] m);
    is_nan = (m[FracW+:ExpW] == '1) && (m[FracW-1:0] != '0);
  endfunction

  function automatic logic is_snan(input logic [FLEN-2:0] m);
    is_snan = is_nan(m) && !m[FracW-1];
  endfunction

  function automatic logic is_zero(input logic [FLEN-2:0] m);
    is_zero = (m == '0);
  endfunction

  function automatic logic [FLEN-1:0] neg(input logic [FLEN-1:0] x);
    neg = {~x[FLEN-1], x[FLEN-2:0]};
  endfunction

  function automatic logic ref_lt(input logic [FLEN-1:0] x, input logic [FLEN-1:0] y);
    if (is_nan(x[FLEN-2:0]) || is_nan(y[FLEN-2:0])) ref_lt = 1'b0;
    else if (is_zero(x[FLEN-2:0]) && is_zero(y[FLEN-2:0])) ref_lt = 1'b0;
    else if (x[FLEN-1] != y[FLEN-1]) ref_lt = x[FLEN-1];
    else if (x[FLEN-1]) ref_lt = x[FLEN-2:0] > y[FLEN-2:0];
    else ref_lt = x[FLEN-2:0] < y[FLEN-2:0];
  endfunction

  function automatic logic ref_eq(input logic [FLEN-1:0] x, input logic [FLEN-1:0] y);
    if (is_nan(x[FLEN-2:0]) || is_nan(y[FLEN-2:0])) ref_eq = 1'b0;
    else ref_eq = (x == y) || (is_zero(x[FLEN-2:0]) && is_zero(y[FLEN-2:0]));
  endfunction

  function automatic logic [FLEN-1:0] ref_min(input logic [FLEN-1:0] x, input logic [FLEN-1:0] y);
    if (is_nan(x[FLEN-2:0]) && is_nan(y[FLEN-2:0])) ref_min = Qnan;
    else if (is_nan(x[FLEN-2:0])) ref_min = y;
    else if (is_nan(y[FLEN-2:0])) ref_min = x;
    else if (is_zero(x[FLEN-2:0]) && is_zero(y[FLEN-2:0])) ref_min = x[FLEN-1] ? x : y;
    else ref_min = ref_lt(x, y) ? x : y;
  endfunction

  function automatic logic [FLEN-1:0] ref_max(input logic [FLEN-1:0] x, input logic [FLEN-1:0] y);
    if (is_nan(x[FLEN-2:0]) && is_nan(y[FLEN-2:0])) ref_max = Qnan;
    else if (is_nan(x[FLEN-2:0])) ref_max = y;
    else if (is_nan(y[FLEN-2:0])) ref_max = x;
    else if (is_zero(x[FLEN-2:0]) && is_zero(y[FLEN-2:0])) ref_max = x[FLEN-1] ? y : x;
    else ref_max = ref_lt(x, y) ? y : x;
  endfunction

  function automatic logic [FLEN-1:0] ref_class(input logic [FLEN-1:0] x);
    logic x_sub;
    logic x_norm;
    logic x_inf;
    logic x_zero;
    logic s;
    s = x[FLEN-1];
    x_sub = (x[FracW+:ExpW] == '0) && (x[FracW-1:0] != '0);
    x_norm = (x[FracW+:ExpW] != '0) && (x[FracW+:ExpW] != '1);
    x_inf = (x[FracW+:ExpW] == '1) && (x[FracW-1:0] == '0);
    x_zero = is_zero(x[FLEN-2:0]);
    ref_class = FLEN'({
      is_nan(x[FLEN-2:0]) && x[FracW-1],
      is_snan(x[FLEN-2:0]),
      !s && x_inf,
      !s && x_norm,
      !s && x_sub,
      !s && x_zero,
      s && x_zero,
      s && x_sub,
      s && x_norm,
      s && x_inf
    });
  endfunction

  task automatic ref_misc(input vec_fop_e o, input logic [FLEN-1:0] x, input logic [FLEN-1:0] y,
                          output logic [FLEN-1:0] r, output logic [FlagW-1:0] f);
    logic any_nan;
    logic any_snan;
    any_nan = is_nan(x[FLEN-2:0]) || is_nan(y[FLEN-2:0]);
    any_snan = is_snan(x[FLEN-2:0]) || is_snan(y[FLEN-2:0]);
    r = '0;
    f = '0;
    case (o)
      VEC_FMIN: begin
        r = ref_min(x, y);
        f = any_snan ? FlagNv : '0;
      end
      VEC_FMAX: begin
        r = ref_max(x, y);
        f = any_snan ? FlagNv : '0;
      end
      VEC_FSGNJ: r = {y[FLEN-1], x[FLEN-2:0]};
      VEC_FSGNJN: r = {~y[FLEN-1], x[FLEN-2:0]};
      VEC_FSGNJX: r = {x[FLEN-1] ^ y[FLEN-1], x[FLEN-2:0]};
      VEC_MFEQ: begin
        r = FLEN'(ref_eq(x, y));
        f = any_snan ? FlagNv : '0;
      end
      VEC_MFNE: begin
        r = FLEN'(!ref_eq(x, y));
        f = any_snan ? FlagNv : '0;
      end
      VEC_MFLT: begin
        r = FLEN'(ref_lt(x, y));
        f = any_nan ? FlagNv : '0;
      end
      VEC_MFLE: begin
        r = FLEN'(ref_lt(x, y) || ref_eq(x, y));
        f = any_nan ? FlagNv : '0;
      end
      VEC_MFGT: begin
        r = FLEN'(ref_lt(y, x));
        f = any_nan ? FlagNv : '0;
      end
      VEC_MFGE: begin
        r = FLEN'(ref_lt(y, x) || ref_eq(x, y));
        f = any_nan ? FlagNv : '0;
      end
      VEC_FCLASS: r = ref_class(x);
      VEC_FMV: r = x;
      default: $fatal(1, "TB BAD REFERENCE OP: %s", o.name());
    endcase
  endtask  // Automatic

endmodule

`default_nettype wire
