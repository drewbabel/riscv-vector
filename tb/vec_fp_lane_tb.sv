`default_nettype none

module vec_fp_lane_tb
  import vec_pkg::*;
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNv;
();

  localparam int Latency = VecFpLatency;
  localparam int MinChecks = 1_900_000;
  localparam int ShowErrors = 20;
  localparam int NumSpecial = 22;
  localparam int RandPerOp = 4000;
  localparam logic [31:0] Qnan = 32'h7FC0_0000;
  localparam logic [31:0] One = 32'h3F80_0000;
  localparam logic [31:0] Two = 32'h4000_0000;
  localparam logic [31:0] Three = 32'h4040_0000;


  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int stall_pct = 0;
  int en_cycle = 0;
  int seed = 7;
  string first_fail = "";

  logic clk;
  logic rst_n = 1'b0;
  logic core_en = 1'b1;
  logic valid = 1'b0;
  vec_fop_e op = VEC_FADD;
  logic [2:0] rm = RmRne;
  logic [31:0] a = '0;
  logic [31:0] b = '0;
  logic [31:0] c = '0;
  logic [31:0] result;
  logic [4:0] fflags;
  logic result_valid;

  logic [31:0] q_res[$];
  logic [4:0] q_flags[$];
  int q_issue[$];
  logic [104:0] q_info[$];
  string q_src[$];

  initial clk = 1'b0;
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

  function automatic logic [31:0] special(input int i);
    case (i)
      0: special = 32'h0000_0000;
      1: special = 32'h8000_0000;
      2: special = 32'h7F80_0000;
      3: special = 32'hFF80_0000;
      4: special = 32'h7FC0_0000;
      5: special = 32'hFFC0_0000;
      6: special = 32'h7F80_0001;
      7: special = 32'hFF80_0001;
      8: special = 32'h7FA0_0000;
      9: special = 32'h7FFF_FFFF;
      10: special = 32'hFFFF_FFFF;
      11: special = 32'h0000_0001;
      12: special = 32'h8000_0001;
      13: special = 32'h007F_FFFF;
      14: special = 32'h807F_FFFF;
      15: special = 32'h0080_0000;
      16: special = 32'h8080_0000;
      17: special = 32'h7F7F_FFFF;
      18: special = 32'hFF7F_FFFF;
      19: special = 32'h3F80_0000;
      20: special = 32'hBF80_0000;
      default: special = 32'h4000_0000;
    endcase
  endfunction

  function automatic logic is_nan(input logic [30:0] m);
    is_nan = (m[30:23] == 8'hFF) && (m[22:0] != '0);
  endfunction

  function automatic logic is_snan(input logic [30:0] m);
    is_snan = is_nan(m) && !m[22];
  endfunction

  function automatic logic is_zero(input logic [30:0] m);
    is_zero = (m == '0);
  endfunction

  function automatic logic ref_lt(input logic [31:0] x, input logic [31:0] y);
    if (is_nan(x[30:0]) || is_nan(y[30:0])) ref_lt = 1'b0;
    else if (is_zero(x[30:0]) && is_zero(y[30:0])) ref_lt = 1'b0;
    else if (x[31] != y[31]) ref_lt = x[31];
    else if (x[31]) ref_lt = x[30:0] > y[30:0];
    else ref_lt = x[30:0] < y[30:0];
  endfunction

  function automatic logic ref_eq(input logic [31:0] x, input logic [31:0] y);
    if (is_nan(x[30:0]) || is_nan(y[30:0])) ref_eq = 1'b0;
    else ref_eq = (x == y) || (is_zero(x[30:0]) && is_zero(y[30:0]));
  endfunction

  function automatic logic [31:0] ref_min(input logic [31:0] x, input logic [31:0] y);
    if (is_nan(x[30:0]) && is_nan(y[30:0])) ref_min = Qnan;
    else if (is_nan(x[30:0])) ref_min = y;
    else if (is_nan(y[30:0])) ref_min = x;
    else if (is_zero(x[30:0]) && is_zero(y[30:0])) ref_min = x[31] ? x : y;
    else ref_min = ref_lt(x, y) ? x : y;
  endfunction

  function automatic logic [31:0] ref_max(input logic [31:0] x, input logic [31:0] y);
    if (is_nan(x[30:0]) && is_nan(y[30:0])) ref_max = Qnan;
    else if (is_nan(x[30:0])) ref_max = y;
    else if (is_nan(y[30:0])) ref_max = x;
    else if (is_zero(x[30:0]) && is_zero(y[30:0])) ref_max = x[31] ? y : x;
    else ref_max = ref_lt(x, y) ? y : x;
  endfunction

  function automatic logic [9:0] ref_class(input logic [31:0] x);
    logic x_sub;
    logic x_norm;
    logic x_inf;
    logic x_zero;
    x_sub = (x[30:23] == '0) && (x[22:0] != '0);
    x_norm = (x[30:23] != '0) && (x[30:23] != 8'hFF);
    x_inf = (x[30:23] == 8'hFF) && (x[22:0] == '0);
    x_zero = is_zero(x[30:0]);
    ref_class = {
      is_nan(x[30:0]) && x[22],
      is_snan(x[30:0]),
      !x[31] && x_inf,
      !x[31] && x_norm,
      !x[31] && x_sub,
      !x[31] && x_zero,
      x[31] && x_zero,
      x[31] && x_sub,
      x[31] && x_norm,
      x[31] && x_inf
    };
  endfunction

  task automatic ref_misc(input vec_fop_e o, input logic [31:0] x, input logic [31:0] y,
                          output logic [31:0] r, output logic [4:0] f);
    logic any_nan;
    logic any_snan;
    any_nan = is_nan(x[30:0]) || is_nan(y[30:0]);
    any_snan = is_snan(x[30:0]) || is_snan(y[30:0]);
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
      VEC_FSGNJ: r = {y[31], x[30:0]};
      VEC_FSGNJN: r = {~y[31], x[30:0]};
      VEC_FSGNJX: r = {x[31] ^ y[31], x[30:0]};
      VEC_MFEQ: begin
        r = 32'(ref_eq(x, y));
        f = any_snan ? FlagNv : '0;
      end
      VEC_MFNE: begin
        r = 32'(!ref_eq(x, y));
        f = any_snan ? FlagNv : '0;
      end
      VEC_MFLT: begin
        r = 32'(ref_lt(x, y));
        f = any_nan ? FlagNv : '0;
      end
      VEC_MFLE: begin
        r = 32'(ref_lt(x, y) || ref_eq(x, y));
        f = any_nan ? FlagNv : '0;
      end
      VEC_MFGT: begin
        r = 32'(ref_lt(y, x));
        f = any_nan ? FlagNv : '0;
      end
      VEC_MFGE: begin
        r = 32'(ref_lt(y, x) || ref_eq(x, y));
        f = any_nan ? FlagNv : '0;
      end
      VEC_FCLASS: r = 32'(ref_class(x));
      VEC_FMV: r = x;
      default: $fatal(1, "TB BAD REFERENCE OP: %s", o.name());
    endcase
  endtask  // Automatic

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
    logic [104:0] info;
    string src;
    int issue;
    vec_fop_e fo;
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
          fo = vec_fop_e'(info[104:99]);
          checks++;
          if (result !== er || fflags !== ef || (en_cycle - issue) != Latency)
            fail($sformatf(
                 "%s %s rm=%0d a=%h b=%h c=%h exp %h/%b got %h/%b after %0d cycles",
                 src,
                 fo.name(),
                 info[98:96],
                 info[95:64],
                 info[63:32],
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
        op = vec_fop_e'(6'($urandom_range(32'(VEC_FMV))));
        a = $urandom;
        b = $urandom;
        c = $urandom;
      end
      tick();
    end
  endtask  // Automatic

  task automatic send(input string src, input vec_fop_e o, input logic [2:0] mode,
                      input logic [31:0] x, input logic [31:0] y, input logic [31:0] z,
                      input logic [31:0] er, input logic [4:0] ef);
    stalls();
    core_en = 1'b1;
    valid = 1'b1;
    op = o;
    rm = mode;
    a = x;
    b = y;
    c = z;
    q_res.push_back(er);
    q_flags.push_back(ef);
    q_issue.push_back(en_cycle);
    q_info.push_back({o, mode, x, y, z});
    q_src.push_back(src);
    tick();
    valid = 1'b0;
  endtask  // Automatic

  task automatic send_misc(input string src, input vec_fop_e o, input logic [31:0] x,
                           input logic [31:0] y);
    logic [31:0] r;
    logic [ 4:0] f;
    ref_misc(o, x, y, r, f);
    send(src, o, 3'($urandom_range(4)), x, y, $urandom, r, f);
  endtask  // Automatic

  task automatic drain();
    core_en = 1'b1;
    valid   = 1'b0;
    repeat (Latency + 2) tick();
    if (q_res.size() != 0) fail($sformatf("%0d results never arrived", q_res.size()));
  endtask  // Automatic

  function automatic logic [31:0] neg(input logic [31:0] x);
    neg = {~x[31], x[30:0]};
  endfunction

  task automatic run_binary(input string path, input vec_fop_e o, input logic [2:0] mode);
    int fd;
    int line;
    logic [31:0] x;
    logic [31:0] y;
    logic [31:0] er;
    logic [4:0] ef;
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
        if (o == VEC_FSUB && line[0]) send(src, VEC_FRSUB, mode, y, x, $urandom, er, ef);
        else send(src, o, mode, x, y, $urandom, er, ef);
      end
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, line + 1);
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, line);
  endtask  // Automatic

  task automatic run_fma(input string path, input logic [2:0] mode);
    int fd;
    int line;
    logic [31:0] x;
    logic [31:0] y;
    logic [31:0] z;
    logic [31:0] er;
    logic [4:0] ef;
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
    logic [31:0] x;
    logic [31:0] y;
    logic r;
    logic [4:0] ef;
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
        send(src, o, 3'($urandom_range(4)), x, y, $urandom, 32'(r), ef);
        if (o_swap == VEC_MFNE) send(src, o_swap, RmRne, x, y, $urandom, 32'(!r), ef);
        else send(src, o_swap, RmRne, y, x, $urandom, 32'(r), ef);
      end
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, line + 1);
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, line);
  endtask  // Automatic

  function automatic logic [31:0] pick();
    logic [31:0] x;
    x = $urandom;
    case ($urandom_range(
        3
    ))
      0: x = special($urandom_range(NumSpecial - 1));
      1: x[30:23] = ($urandom_range(1) != 0) ? 8'hFF : 8'h00;
      2: x[30:23] = 8'(126 + $urandom_range(3));
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
    logic [31:0] x;
    logic [31:0] y;
    for (int k = 0; k < 13; k++) begin
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

  task automatic run_directed();
    send("min signed zero", VEC_FMIN, RmRne, 32'h0000_0000, 32'h8000_0000, 0, 32'h8000_0000, 0);
    send("min signed zero", VEC_FMIN, RmRne, 32'h8000_0000, 32'h0000_0000, 0, 32'h8000_0000, 0);
    send("max signed zero", VEC_FMAX, RmRne, 32'h8000_0000, 32'h0000_0000, 0, 32'h0000_0000, 0);
    send("max signed zero", VEC_FMAX, RmRne, 32'h0000_0000, 32'h8000_0000, 0, 32'h0000_0000, 0);
    send("min qnan", VEC_FMIN, RmRne, 32'h7FC0_0000, One, 0, One, 0);
    send("min snan", VEC_FMIN, RmRne, One, 32'h7F80_0001, 0, One, FlagNv);
    send("max qnan", VEC_FMAX, RmRne, 32'hFFC0_0000, 32'hBF80_0000, 0, 32'hBF80_0000, 0);
    send("max two nan", VEC_FMAX, RmRne, 32'hFFC0_0001, 32'h7FA0_0000, 0, Qnan, FlagNv);
    send("min two qnan", VEC_FMIN, RmRne, 32'h7FC0_0001, 32'hFFC0_0000, 0, Qnan, 0);
    send("min inf", VEC_FMIN, RmRne, 32'hFF80_0000, 32'hFF7F_FFFF, 0, 32'hFF80_0000, 0);
    send("max inf", VEC_FMAX, RmRne, 32'h7F80_0000, 32'h7F7F_FFFF, 0, 32'h7F80_0000, 0);
    send("eq qnan", VEC_MFEQ, RmRne, 32'h7FC0_0000, 32'h7FC0_0000, 0, 0, 0);
    send("eq snan", VEC_MFEQ, RmRne, 32'h7F80_0001, One, 0, 0, FlagNv);
    send("eq zeros", VEC_MFEQ, RmRne, 32'h8000_0000, 32'h0000_0000, 0, 1, 0);
    send("ne qnan", VEC_MFNE, RmRne, 32'h7FC0_0000, One, 0, 1, 0);
    send("ne snan", VEC_MFNE, RmRne, One, 32'hFF80_0001, 0, 1, FlagNv);
    send("ne zeros", VEC_MFNE, RmRne, 32'h0000_0000, 32'h8000_0000, 0, 0, 0);
    send("lt qnan", VEC_MFLT, RmRne, 32'h7FC0_0000, One, 0, 0, FlagNv);
    send("lt zeros", VEC_MFLT, RmRne, 32'h8000_0000, 32'h0000_0000, 0, 0, 0);
    send("lt inf", VEC_MFLT, RmRne, 32'hFF80_0000, 32'hFF7F_FFFF, 0, 1, 0);
    send("le zeros", VEC_MFLE, RmRne, 32'h0000_0000, 32'h8000_0000, 0, 1, 0);
    send("le qnan", VEC_MFLE, RmRne, One, 32'hFFC0_0000, 0, 0, FlagNv);
    send("gt order", VEC_MFGT, RmRne, Two, One, 0, 1, 0);
    send("gt order", VEC_MFGT, RmRne, One, Two, 0, 0, 0);
    send("gt qnan", VEC_MFGT, RmRne, One, 32'h7FC0_0000, 0, 0, FlagNv);
    send("gt inf", VEC_MFGT, RmRne, 32'h7F80_0000, 32'h7F7F_FFFF, 0, 1, 0);
    send("ge zeros", VEC_MFGE, RmRne, 32'h8000_0000, 32'h0000_0000, 0, 1, 0);
    send("ge order", VEC_MFGE, RmRne, 32'hBF80_0000, One, 0, 0, 0);
    send("ge snan", VEC_MFGE, RmRne, 32'h7F80_0001, 32'h7F80_0001, 0, 0, FlagNv);
    send("class -inf", VEC_FCLASS, RmRne, 32'hFF80_0000, 0, 0, 32'h001, 0);
    send("class -norm", VEC_FCLASS, RmRne, 32'hBF80_0000, 0, 0, 32'h002, 0);
    send("class -sub", VEC_FCLASS, RmRne, 32'h8000_0001, 0, 0, 32'h004, 0);
    send("class -0", VEC_FCLASS, RmRne, 32'h8000_0000, 0, 0, 32'h008, 0);
    send("class +0", VEC_FCLASS, RmRne, 32'h0000_0000, 0, 0, 32'h010, 0);
    send("class +sub", VEC_FCLASS, RmRne, 32'h007F_FFFF, 0, 0, 32'h020, 0);
    send("class +norm", VEC_FCLASS, RmRne, 32'h7F7F_FFFF, 0, 0, 32'h040, 0);
    send("class +inf", VEC_FCLASS, RmRne, 32'h7F80_0000, 0, 0, 32'h080, 0);
    send("class snan", VEC_FCLASS, RmRne, 32'hFFBF_FFFF, 0, 0, 32'h100, 0);
    send("class qnan", VEC_FCLASS, RmRne, 32'h7FC0_0000, 0, 0, 32'h200, 0);
    send("sgnj nan", VEC_FSGNJ, RmRne, 32'h7F80_0001, 32'h8000_0000, 0, 32'hFF80_0001, 0);
    send("sgnjn zero", VEC_FSGNJN, RmRne, 32'h0000_0000, 32'h0000_0000, 0, 32'h8000_0000, 0);
    send("sgnjx inf", VEC_FSGNJX, RmRne, 32'hFF80_0000, 32'hBF80_0000, 0, 32'h7F80_0000, 0);
    send("move snan", VEC_FMV, RmRne, 32'h7F80_0001, One, 0, 32'h7F80_0001, 0);
    send("move neg zero", VEC_FMV, RmRdn, 32'h8000_0000, 0, 0, 32'h8000_0000, 0);
    send("rsub order", VEC_FRSUB, RmRne, One, Two, 0, One, 0);
    send("add inf clash", VEC_FADD, RmRne, 32'h7F80_0000, 32'hFF80_0000, 0, Qnan, FlagNv);
    send("sub zero rdn", VEC_FSUB, RmRdn, 32'h0000_0000, 32'h0000_0000, 0, 32'h8000_0000, 0);
    send("mul inf zero", VEC_FMUL, RmRne, 32'h7F80_0000, 32'h8000_0000, 0, Qnan, FlagNv);
    send("macc order", VEC_FMACC, RmRne, Two, Three, One, 32'h40E0_0000, 0);
    send("madd order", VEC_FMADD, RmRne, One, Two, Three, 32'h40E0_0000, 0);
    send("nmacc order", VEC_FNMACC, RmRne, Two, Three, One, 32'hC0E0_0000, 0);
    send("nmadd order", VEC_FNMADD, RmRne, One, Two, Three, 32'hC0E0_0000, 0);
    send("msac order", VEC_FMSAC, RmRne, Two, Three, One, 32'h40A0_0000, 0);
    send("msub order", VEC_FMSUB, RmRne, One, Two, Three, 32'h40A0_0000, 0);
    send("nmsac order", VEC_FNMSAC, RmRne, Two, Three, One, 32'hC0A0_0000, 0);
    send("nmsub order", VEC_FNMSUB, RmRne, One, Two, Three, 32'hC0A0_0000, 0);
    send("macc inf zero qnan", VEC_FMACC, RmRne, 32'h7F80_0000, 32'h0000_0000, 32'h7FC0_0000, Qnan,
         FlagNv);
  endtask  // Automatic

  task automatic run_reset_flight();
    send("reset flight", VEC_FADD, RmRne, 32'h3F80_0000, 32'h3F80_0000, 0, 32'h4000_0000, 0);
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
    $dumpfile("vec_fp_lane_tb.vcd");
    $dumpvars(0, vec_fp_lane_tb);

    repeat (2) tick();
    rst_n = 1'b1;
    tick();

    run_directed();
    drain();

    stall_pct = 25;
    run_misc_ops();
    run_directed();
    stall_pct = 10;

    run_binary("build/testfloat/f32_add_rne.txt", VEC_FADD, RmRne);
    run_binary("build/testfloat/f32_add_rtz.txt", VEC_FADD, RmRtz);
    run_binary("build/testfloat/f32_add_rdn.txt", VEC_FADD, RmRdn);
    run_binary("build/testfloat/f32_add_rup.txt", VEC_FADD, RmRup);
    run_binary("build/testfloat/f32_add_rmm.txt", VEC_FADD, RmRmm);
    run_binary("build/testfloat/f32_sub_rne.txt", VEC_FSUB, RmRne);
    run_binary("build/testfloat/f32_sub_rtz.txt", VEC_FSUB, RmRtz);
    run_binary("build/testfloat/f32_sub_rdn.txt", VEC_FSUB, RmRdn);
    run_binary("build/testfloat/f32_sub_rup.txt", VEC_FSUB, RmRup);
    run_binary("build/testfloat/f32_sub_rmm.txt", VEC_FSUB, RmRmm);
    run_binary("build/testfloat/f32_mul_rne.txt", VEC_FMUL, RmRne);
    run_binary("build/testfloat/f32_mul_rtz.txt", VEC_FMUL, RmRtz);
    run_binary("build/testfloat/f32_mul_rdn.txt", VEC_FMUL, RmRdn);
    run_binary("build/testfloat/f32_mul_rup.txt", VEC_FMUL, RmRup);
    run_binary("build/testfloat/f32_mul_rmm.txt", VEC_FMUL, RmRmm);
    run_fma("build/testfloat/f32_mulAdd_rne.txt", RmRne);
    run_fma("build/testfloat/f32_mulAdd_rtz.txt", RmRtz);
    run_fma("build/testfloat/f32_mulAdd_rdn.txt", RmRdn);
    run_fma("build/testfloat/f32_mulAdd_rup.txt", RmRup);
    run_fma("build/testfloat/f32_mulAdd_rmm.txt", RmRmm);
    run_cmp("build/testfloat/f32_eq.txt", VEC_MFEQ, VEC_MFNE);
    run_cmp("build/testfloat/f32_lt.txt", VEC_MFLT, VEC_MFGT);
    run_cmp("build/testfloat/f32_le.txt", VEC_MFLE, VEC_MFGE);

    run_reset_flight();
    do_verdict();
  end

endmodule

`default_nettype wire
