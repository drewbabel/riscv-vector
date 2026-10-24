`default_nettype none

module vec_fp_cvt_lane_tb
  import vec_pkg::*;
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNv, fp_pkg::FlagNx;
();

  localparam int Latency = VecFpLatency;
  localparam int MinChecks = 160_000;
  localparam int ShowErrors = 20;
  localparam string TfDir = "build/testfloat/";

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int stall_pct = 0;
  int en_cycle = 0;
  int seed = 11;
  string first_fail = "";

  logic clk;
  logic rst_n = 1'b0;
  logic core_en = 1'b1;
  logic valid = 1'b0;
  vec_fop_e op = VEC_FCVT_X_F;
  vec_eew_e eew = VEC_EEW_SAME;
  logic [2:0] vsew = 3'd2;
  logic [2:0] rm = RmRne;
  logic [31:0] a = '0;
  logic [31:0] result;
  logic [4:0] fflags;
  logic result_valid;

  logic [31:0] q_res[$];
  logic [4:0] q_flags[$];
  int q_issue[$];
  logic [45:0] q_info[$];
  string q_src[$];

  logic [2:0] modes[5] = '{RmRne, RmRtz, RmRdn, RmRup, RmRmm};
  string rms[5] = '{"rne", "rtz", "rdn", "rup", "rmm"};

  initial clk = 1'b0;
  always #5 clk = ~clk;

  vec_fp_cvt_lane dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .valid(valid),
      .op(op),
      .eew(eew),
      .vsew(vsew),
      .rm(rm),
      .a(a),
      .result(result),
      .fflags(fflags),
      .result_valid(result_valid)
  );

  task automatic fail(input string msg);
    errors++;
    if (errors == 1) first_fail = msg;
    if (errors <= ShowErrors) $display("FAIL %s", msg);
    if (errors == max_errors)
      $fatal(1, "TB STOPPED: %0d mismatches, first: %s", errors, first_fail);
  endtask  // Automatic

  task automatic tick();
    logic was_en;
    logic [31:0] prev_res;
    logic [4:0] prev_flags;
    logic prev_vld;
    logic [31:0] er;
    logic [4:0] ef;
    logic [45:0] info;
    string src;
    int issue;
    vec_fop_e fo;
    vec_eew_e fe;
    was_en = core_en;
    prev_res = result;
    prev_flags = fflags;
    prev_vld = result_valid;
    @(posedge clk);
    #1;
    if (!rst_n) begin
      checks++;
      if (result_valid !== 1'b0) fail("result_valid high in reset");
    end else if (!was_en) begin
      checks++;
      if (result !== prev_res || fflags !== prev_flags || result_valid !== prev_vld)
        fail($sformatf("outputs moved while core_en low at %0t", $time));
    end else begin
      en_cycle++;
      if (result_valid === 1'b1) begin
        if (q_res.size() == 0) begin
          fail($sformatf("result_valid with nothing in flight at %0t", $time));
        end else begin
          er = q_res.pop_front();
          ef = q_flags.pop_front();
          issue = q_issue.pop_front();
          info = q_info.pop_front();
          src = q_src.pop_front();
          fo = vec_fop_e'(info[45:40]);
          fe = vec_eew_e'(info[39:38]);
          checks++;
          if (result !== er || fflags !== ef || (en_cycle - issue) != Latency)
            fail($sformatf(
                 "%s %s %s sew=%0d rm=%0d a=%h exp %h/%b got %h/%b after %0d cycles",
                 src,
                 fo.name(),
                 fe.name(),
                 8 << info[37:35],
                 info[34:32],
                 info[31:0],
                 er,
                 ef,
                 result,
                 fflags,
                 en_cycle - issue
                 ));
        end
      end else if (result_valid !== 1'b0) begin
        fail($sformatf("result_valid unknown at %0t", $time));
      end else if (q_issue.size() != 0 && (en_cycle - q_issue[0]) >= Latency) begin
        fail($sformatf("%s result missing at %0t", q_src[0], $time));
        void'(q_res.pop_front());
        void'(q_flags.pop_front());
        void'(q_issue.pop_front());
        void'(q_info.pop_front());
        void'(q_src.pop_front());
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
        valid = 1'($urandom_range(1));
        op = vec_fop_e'(6'(32'(VEC_FCVT_XU_F) + $urandom_range(5)));
        eew = vec_eew_e'(2'($urandom_range(3)));
        a = $urandom;
      end
      tick();
    end
  endtask  // Automatic

  task automatic send(input string src, input vec_fop_e o, input vec_eew_e e,
                      input logic [2:0] mode, input logic [31:0] x, input logic [31:0] er,
                      input logic [4:0] ef);
    stalls();
    core_en = 1'b1;
    valid = 1'b1;
    op = o;
    eew = e;
    vsew = (e == VEC_EEW_SAME) ? 3'd2 : 3'd1;
    rm = mode;
    a = x;
    q_res.push_back(er);
    q_flags.push_back(ef);
    q_issue.push_back(en_cycle);
    q_info.push_back({o, e, vsew, mode, x});
    q_src.push_back(src);
    tick();
    valid = 1'b0;
  endtask  // Automatic

  task automatic drain();
    core_en = 1'b1;
    valid   = 1'b0;
    repeat (Latency + 2) tick();
    if (q_res.size() != 0) fail($sformatf("%0d results never arrived", q_res.size()));
  endtask  // Automatic

  function automatic logic [31:0] clip16(input logic [31:0] x, input logic uns);
    logic is_nan;
    logic neg;
    is_nan = (x[30:23] == 8'hFF) && (x[22:0] != '0);
    neg = x[31] && !is_nan;
    if (uns) clip16 = neg ? 32'h0000_0000 : 32'h0000_FFFF;
    else clip16 = neg ? 32'h0000_8000 : 32'h0000_7FFF;
  endfunction

  task automatic ref_f2i16(input logic [31:0] x, input logic uns, input logic [31:0] res32,
                           input logic [4:0] flags32, output logic [31:0] res16,
                           output logic [4:0] flags16);
    int   sv;
    logic fits;
    sv = int'(res32);
    if (uns) fits = (res32 <= 32'h0000_FFFF);
    else fits = (sv >= -32768) && (sv <= 32767);
    if (!flags32[4] && fits) begin
      res16   = {16'h0000, res32[15:0]};
      flags16 = flags32;
    end else begin
      res16   = clip16(x, uns);
      flags16 = FlagNv;
    end
  endtask  // Automatic

  function automatic logic [31:0] i2f16(input logic [15:0] v, input logic uns);
    logic sign;
    logic [16:0] mag;
    int lead;
    sign = !uns && v[15];
    mag  = sign ? 17'(-{1'b1, v}) : {1'b0, v};
    if (mag == 17'd0) begin
      i2f16 = '0;
    end else begin
      lead = 0;
      for (int i = 0; i < 17; i++) if (mag[i]) lead = i;
      i2f16 = {sign, 8'(127 + lead), 23'(40'(mag) << (23 - lead))};
    end
  endfunction

  function automatic vec_fop_e to_int_op(input logic uns, input logic rtz);
    if (rtz && uns) to_int_op = VEC_FCVT_RTZ_XU_F;
    else if (rtz) to_int_op = VEC_FCVT_RTZ_X_F;
    else if (uns) to_int_op = VEC_FCVT_XU_F;
    else to_int_op = VEC_FCVT_X_F;
  endfunction

  // Float to integer
  task automatic run_to_int(input logic uns, input int m);
    int fd;
    int line;
    logic [31:0] x;
    logic [31:0] r;
    logic [4:0] f;
    logic [31:0] r16;
    logic [4:0] f16;
    logic [2:0] mode;
    string path;
    string src;
    path = {TfDir, uns ? "f32_to_ui32_" : "f32_to_i32_", rms[m], ".txt"};
    fd   = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    line = 0;
    while ($fscanf(
        fd, "%h %h %h\n", x, r, f
    ) == 3) begin
      line++;
      src = $sformatf("%s:%0d", path, line);
      ref_f2i16(x, uns, r, f, r16, f16);
      if (modes[m] == RmRtz) begin
        mode = 3'($urandom_range(4));
        send(src, to_int_op(uns, 1'b1), VEC_EEW_SAME, mode, x, r, f);
        send(src, to_int_op(uns, 1'b1), VEC_EEW_NARROW, mode, x, r16, f16);
      end
      send(src, to_int_op(uns, 1'b0), VEC_EEW_SAME, modes[m], x, r, f);
      send(src, to_int_op(uns, 1'b0), VEC_EEW_NARROW, modes[m], x, r16, f16);
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, line + 1);
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, line);
  endtask  // Automatic

  // Integer to float
  task automatic run_to_float(input logic uns, input int m);
    int fd;
    int line;
    logic [31:0] x;
    logic [31:0] r;
    logic [4:0] f;
    logic [31:0] x16;
    vec_fop_e o;
    string path;
    string src;
    path = {TfDir, uns ? "ui32_to_f32_" : "i32_to_f32_", rms[m], ".txt"};
    if (uns) o = VEC_FCVT_F_XU;
    else o = VEC_FCVT_F_X;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    line = 0;
    while ($fscanf(
        fd, "%h %h %h\n", x, r, f
    ) == 3) begin
      line++;
      src = $sformatf("%s:%0d", path, line);
      send(src, o, VEC_EEW_SAME, modes[m], x, r, f);
      x16 = {16'($urandom), x[15:0]};
      send(src, o, VEC_EEW_WIDEN, modes[m], x16, i2f16(x[15:0], uns), '0);
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, line + 1);
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, line);
  endtask  // Automatic

  // Every short integer
  task automatic sweep_widen();
    logic [31:0] x;
    for (int i = 0; i < 65536; i++) begin
      x = {16'($urandom), 16'(i)};
      send("widen sweep", VEC_FCVT_F_X, VEC_EEW_WIDEN, 3'(i % 5), x, i2f16(16'(i), 1'b0), '0);
      send("widen sweep", VEC_FCVT_F_XU, VEC_EEW_WIDEN, 3'(i % 5), x, i2f16(16'(i), 1'b1), '0);
    end
  endtask  // Automatic

  // Sixteen bit edges
  task automatic run_directed();
    send("i16 max tie", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 32'h46FF_FF00, 32'h7FFF, FlagNv);
    send("i16 max rtz", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRtz, 32'h46FF_FF00, 32'h7FFF, FlagNx);
    send("i16 rtz form", VEC_FCVT_RTZ_X_F, VEC_EEW_NARROW, RmRup, 32'h46FF_FF00, 32'h7FFF, FlagNx);
    send("i16 min tie", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 32'hC700_0080, 32'h8000, FlagNx);
    send("i16 min rdn", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRdn, 32'hC700_0080, 32'h8000, FlagNv);
    send("i16 min exact", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 32'hC700_0000, 32'h8000, '0);
    send("u16 max tie", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, 32'h477F_FF80, 32'hFFFF, FlagNv);
    send("u16 max rtz", VEC_FCVT_RTZ_XU_F, VEC_EEW_NARROW, RmRne, 32'h477F_FF80, 32'hFFFF, FlagNx);
    send("u16 neg half", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, 32'hBF00_0000, 32'h0000, FlagNx);
    send("u16 neg one", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, 32'hBF80_0000, 32'h0000, FlagNv);
    send("i16 qnan", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 32'h7FC0_0000, 32'h7FFF, FlagNv);
    send("i16 neg nan", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 32'hFFC0_0000, 32'h7FFF, FlagNv);
    send("u16 snan", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, 32'h7F80_0001, 32'hFFFF, FlagNv);
    send("i16 +inf", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 32'h7F80_0000, 32'h7FFF, FlagNv);
    send("i16 -inf", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 32'hFF80_0000, 32'h8000, FlagNv);
    send("u16 -inf", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, 32'hFF80_0000, 32'h0000, FlagNv);
    send("i16 big", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 32'h4F80_0000, 32'h7FFF, FlagNv);
    send("i16 neg zero", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 32'h8000_0000, 32'h0000, '0);
    send("i16 tiny up", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRup, 32'h0000_0001, 32'h0001, FlagNx);
    send("i16 tiny dn", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRdn, 32'h8000_0001, 32'hFFFF, FlagNx);
    send("widen i16 min", VEC_FCVT_F_X, VEC_EEW_WIDEN, RmRne, 32'hABCD_8000, 32'hC700_0000, '0);
    send("widen u16 max", VEC_FCVT_F_XU, VEC_EEW_WIDEN, RmRne, 32'h1234_FFFF, 32'h477F_FF00, '0);
    send("widen i16 -1", VEC_FCVT_F_X, VEC_EEW_WIDEN, RmRdn, 32'h0000_FFFF, 32'hBF80_0000, '0);
    send("widen zero", VEC_FCVT_F_X, VEC_EEW_WIDEN, RmRdn, 32'hFFFF_0000, 32'h0000_0000, '0);
    send("i32 rtz form", VEC_FCVT_RTZ_X_F, VEC_EEW_SAME, RmRup, 32'hBFC0_0000, 32'hFFFF_FFFF,
         FlagNx);
    send("u32 rtz form", VEC_FCVT_RTZ_XU_F, VEC_EEW_SAME, RmRup, 32'h3FC0_0000, 32'h0000_0001,
         FlagNx);
    send("f32 from u32", VEC_FCVT_F_XU, VEC_EEW_SAME, RmRne, 32'hFFFF_FFFF, 32'h4F80_0000, FlagNx);
    send("f32 from i32", VEC_FCVT_F_X, VEC_EEW_SAME, RmRne, 32'hFFFF_FFFF, 32'hBF80_0000, '0);
  endtask  // Automatic

  task automatic run_reset_flight();
    send("reset flight", VEC_FCVT_F_X, VEC_EEW_SAME, RmRne, 32'h0000_0001, 32'h3F80_0000, '0);
    rst_n = 1'b0;
    q_res.delete();
    q_flags.delete();
    q_issue.delete();
    q_info.delete();
    q_src.delete();
    repeat (Latency + 1) tick();
    rst_n = 1'b1;
    drain();
  endtask  // Automatic

  task automatic do_verdict();
    drain();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors != 0)
      $fatal(1, "FAIL: %0d mismatches, %0d checks, first: %s", errors, checks, first_fail);
    $display("PASS: %0d checks", checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    void'($urandom(seed));
    $dumpfile("vec_fp_cvt_lane_tb.vcd");
    $dumpvars(0, vec_fp_cvt_lane_tb);

    repeat (2) tick();
    rst_n = 1'b1;
    tick();

    run_directed();
    drain();

    stall_pct = 25;
    run_directed();
    sweep_widen();
    stall_pct = 10;

    for (int m = 0; m < 5; m++) begin
      run_to_int(1'b0, m);
      run_to_int(1'b1, m);
      run_to_float(1'b0, m);
      run_to_float(1'b1, m);
    end

    run_reset_flight();
    do_verdict();
  end

endmodule

`default_nettype wire
