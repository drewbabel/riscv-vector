`default_nettype none

module vec_config_tb ();
  import opcode_pkg::OpcodeOpV, opcode_pkg::OpcodeOpImm, opcode_pkg::Funct3Opcfg;

  localparam int Xlen = arch_pkg::XLEN;
  localparam int Vlen = arch_pkg::VLEN;
  localparam int Elen = arch_pkg::ELEN;
  localparam int VlW = $clog2(Vlen + 1);
  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int MinChecks = 45000;

  localparam logic [Xlen-1:0] Poison = {1'b1, {Xlen - 1{1'b0}}};
  localparam logic [Xlen-1:0] Reserved = {2'b01, {Xlen - 2{1'b0}}};
  localparam logic [Xlen-1:0] AllOnes = '1;

  localparam logic [1:0] TopVsetivli = 2'b11;
  localparam logic [1:0] TopVsetvl = 2'b10;
  localparam logic [6:0] Funct7Vsetvl = 7'b1000000;

  localparam logic [2:0] Sew8 = 3'd0;
  localparam logic [2:0] Sew32 = 3'd2;
  localparam logic [2:0] VsewMax = 3'($clog2(Elen / 8));
  localparam logic [2:0] Lmul1 = 3'b000;
  localparam logic [2:0] Lmul2 = 3'b001;
  localparam logic [2:0] Lmul4 = 3'b010;
  localparam logic [2:0] Lmul8 = 3'b011;
  localparam logic [2:0] LmulReserved = 3'b100;
  localparam logic [2:0] LmulF8 = 3'b101;
  localparam logic [2:0] LmulF4 = 3'b110;
  localparam logic [2:0] LmulF2 = 3'b111;
  localparam logic [5:0] E8m1 = {Sew8, Lmul1};
  localparam logic [5:0] E8m8 = {Sew8, Lmul8};
  localparam logic [5:0] E32m1 = {Sew32, Lmul1};
  localparam int SweepW = 9;

  localparam int FormVsetvli = 0;
  localparam int FormVsetivli = 1;
  localparam int FormVsetvl = 2;

  int              checks = 0;
  int              errors = 0;
  int              max_errors = 0;

  logic [Xlen-1:0] instr;
  logic [Xlen-1:0] rs1_data;
  logic [Xlen-1:0] rs2_data;
  logic [ VlW-1:0] vl_q;
  logic [Xlen-1:0] vtype_q;
  logic            is_vset;
  logic [ VlW-1:0] vl_next;
  logic [Xlen-1:0] vtype_next;

  typedef struct packed {
    logic            is_vset;
    logic [VlW-1:0]  vl;
    logic [Xlen-1:0] vtype;
  } answer_t;

  vec_config #(
      .XLEN(Xlen),
      .VLEN(Vlen),
      .ELEN(Elen)
  ) dut (
      .instr     (instr),
      .rs1_data  (rs1_data),
      .rs2_data  (rs2_data),
      .vl_q      (vl_q),
      .vtype_q   (vtype_q),
      .is_vset   (is_vset),
      .vl_next   (vl_next),
      .vtype_next(vtype_next)
  );

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    instr    = '0;
    rs1_data = '0;
    rs2_data = '0;
    vl_q     = '0;
    vtype_q  = '0;
  endtask  // Automatic

  task automatic check_config(input string name);
    answer_t exp;
    #1;
    exp = model(instr, rs1_data, rs2_data, vl_q, vtype_q);
    check({name, " is_vset"}, Xlen'(is_vset), Xlen'(exp.is_vset));
    check({name, " vl_next"}, Xlen'(vl_next), Xlen'(exp.vl));
    check({name, " vtype_next"}, vtype_next, exp.vtype);
  endtask  // Automatic

  task automatic set_state(input int vlq, input logic [Xlen-1:0] vtq);
    vl_q    = VlW'(vlq);
    vtype_q = vtq;
  endtask  // Automatic

  task automatic do_vsetvli(input logic [10:0] vt, input logic [AWIDTH-1:0] rs1,
                            input logic [AWIDTH-1:0] rd, input logic [Xlen-1:0] a,
                            input string name);
    rs1_data = a;
    instr    = {1'b0, vt, rs1, Funct3Opcfg, rd, OpcodeOpV};
    check_config(name);
  endtask  // Automatic

  task automatic do_vsetivli(input logic [9:0] vt, input logic [AWIDTH-1:0] ui,
                             input logic [AWIDTH-1:0] rd, input string name);
    instr = {TopVsetivli, vt, ui, Funct3Opcfg, rd, OpcodeOpV};
    check_config(name);
  endtask  // Automatic

  task automatic do_vsetvl(input logic [Xlen-1:0] vt, input logic [AWIDTH-1:0] rs1,
                           input logic [AWIDTH-1:0] rd, input logic [Xlen-1:0] a,
                           input string name);
    rs1_data = a;
    rs2_data = vt;
    instr    = {Funct7Vsetvl, AWIDTH'(2), rs1, Funct3Opcfg, rd, OpcodeOpV};
    check_config(name);
  endtask  // Automatic

  task automatic do_form(input int form, input logic [SweepW-1:0] vt, input logic [AWIDTH-1:0] rs1,
                         input logic [AWIDTH-1:0] rd, input logic [Xlen-1:0] a, input string name);
    case (form)
      FormVsetvli:  do_vsetvli(11'(vt), rs1, rd, a, name);
      FormVsetivli: do_vsetivli(10'(vt), a[AWIDTH-1:0], rd, name);
      default:      do_vsetvl(Xlen'(vt), rs1, rd, a, name);
    endcase
  endtask  // Automatic

  task automatic sweep_vtype(input int form, input int rs1, input int rd, input int avl_cases,
                             input string tag);
    int unsigned vm;
    int unsigned targets[7];
    for (int v = 0; v < (1 << SweepW); v++) begin
      vm = vlmax_of(Xlen'(v));
      targets[0] = 0;
      targets[1] = 1;
      targets[2] = (vm > 0) ? vm - 1 : 0;
      targets[3] = vm;
      targets[4] = vm + 1;
      targets[5] = 2 * vm;
      targets[6] = AllOnes;
      for (int t = 0; t < avl_cases; t++) begin
        do_form(form, SweepW'(v), AWIDTH'(rs1), AWIDTH'(rd), Xlen'(targets[t]), $sformatf(
                "%s vtype %0d avl %0d", tag, v, t));
      end
    end
  endtask  // Automatic

  task automatic test_non_vector();
    instr = Xlen'(OpcodeOpImm);
    check_config("non vector instruction");
  endtask  // Automatic

  task automatic sweep_reserved_forms();
    for (int hi = 1; hi < (1 << ($bits(Funct7Vsetvl) - $bits(TopVsetvl))); hi++) begin
      instr = {TopVsetvl, 5'(hi), AWIDTH'(0), AWIDTH'(1), Funct3Opcfg, AWIDTH'(1), OpcodeOpV};
      check_config($sformatf("reserved form %0d", hi));
    end
  endtask  // Automatic

  task automatic sweep_bad_funct3();
    for (int f = 0; f < (1 << $bits(Funct3Opcfg)); f++) begin
      if (3'(f) != Funct3Opcfg) begin
        rs1_data = Xlen'(2);
        instr    = {1'b0, 11'(E32m1), AWIDTH'(1), 3'(f), AWIDTH'(1), OpcodeOpV};
        check_config($sformatf("vsetvli shape funct3 %0d", f));
      end
    end
  endtask  // Automatic

  task automatic sweep_bad_opcode();
    for (int o = 0; o < (1 << $bits(OpcodeOpV)); o++) begin
      if (7'(o) != OpcodeOpV) begin
        rs1_data = Xlen'(2);
        instr    = {1'b0, 11'(E32m1), AWIDTH'(1), Funct3Opcfg, AWIDTH'(1), 7'(o)};
        check_config($sformatf("vsetvli shape opcode %0d", o));
      end
    end
  endtask  // Automatic

  task automatic sweep_upper_vtype();
    for (int u = 0; u < 8; u++) begin
      do_vsetvli({3'(u), 2'b0, E32m1}, AWIDTH'(1), AWIDTH'(1), Xlen'(4), $sformatf(
                 "vsetvli upper vtype %0d", u));
    end
    do_vsetvl(Reserved | Xlen'(E32m1), AWIDTH'(1), AWIDTH'(1), Xlen'(4),
              "vsetvl high reserved bit");
    do_vsetvl(Poison | Xlen'(E32m1), AWIDTH'(1), AWIDTH'(1), Xlen'(4), "vsetvl poisoned argument");
    do_vsetvl(Poison, AWIDTH'(1), AWIDTH'(1), Xlen'(4), "vsetvl poison bit alone");
  endtask  // Automatic

  task automatic test_named_rd();
    do_vsetvli(11'(E32m1), AWIDTH'(0), AWIDTH'(1), Xlen'(9), "rs1 x0 rd named");
    do_vsetvl(Xlen'(E32m1), AWIDTH'(0), AWIDTH'(1), Xlen'(9), "vsetvl rs1 x0 rd named");
  endtask  // Automatic

  task automatic test_named_vlmax();
    do_vsetvli(11'(E8m8), AWIDTH'(0), AWIDTH'(1), Xlen'(9), "rs1 x0 rd named takes vlmax");
    do_vsetivli(10'(E32m1), AWIDTH'(0), AWIDTH'(0), "vsetivli zero fields");
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
    $dumpfile("vec_config_tb.vcd");
    $dumpvars(0, vec_config_tb);

    do_reset();
    set_state(7, Xlen'(E32m1));
    test_non_vector();
    sweep_reserved_forms();
    sweep_bad_funct3();
    sweep_bad_opcode();
    sweep_upper_vtype();

    set_state(4, Xlen'(E32m1));
    sweep_vtype(FormVsetvli, 1, 1, 7, "vsetvli");
    sweep_vtype(FormVsetivli, 1, 1, 7, "vsetivli");
    sweep_vtype(FormVsetvl, 1, 1, 7, "vsetvl");

    set_state(3, Xlen'(E8m1));
    sweep_vtype(FormVsetvli, 0, 0, 1, "keepvl from e8m1");
    sweep_vtype(FormVsetvl, 0, 0, 1, "keepvl vsetvl from e8m1");

    set_state(3, Xlen'(E32m1));
    sweep_vtype(FormVsetvli, 0, 0, 1, "keepvl from e32m1");
    sweep_vtype(FormVsetvl, 0, 0, 1, "keepvl vsetvl from e32m1");

    set_state(3, Poison);
    sweep_vtype(FormVsetvli, 0, 0, 1, "keepvl from poison");
    sweep_vtype(FormVsetvl, 0, 0, 1, "keepvl vsetvl from poison");

    set_state(16, Xlen'(E8m1));
    test_named_rd();
    sweep_vtype(FormVsetvli, 0, 1, 1, "vsetvli rs1 x0 rd named");
    sweep_vtype(FormVsetvl, 0, 1, 1, "vsetvl rs1 x0 rd named");

    set_state(2, Xlen'(E8m1));
    test_named_vlmax();

    do_verdict();
  end

  function automatic int sew_of(input logic [2:0] vsew);
    return 8 << vsew;
  endfunction

  function automatic int lmul_num(input logic [2:0] vlmul);
    case (vlmul)
      Lmul2:   return 2;
      Lmul4:   return 4;
      Lmul8:   return 8;
      default: return 1;
    endcase
  endfunction

  function automatic int lmul_den(input logic [2:0] vlmul);
    case (vlmul)
      LmulF8:  return 8;
      LmulF4:  return 4;
      LmulF2:  return 2;
      default: return 1;
    endcase
  endfunction

  function automatic int vlmax_of(input logic [Xlen-1:0] vtype);
    return (lmul_num(vtype[2:0]) * Vlen) / (lmul_den(vtype[2:0]) * sew_of(vtype[5:3]));
  endfunction

  function automatic logic ratio_bad(input logic [Xlen-1:0] vtype);
    return (sew_of(vtype[5:3]) * lmul_den(vtype[2:0])) / lmul_num(vtype[2:0]) > Elen;
  endfunction

  function automatic answer_t model(input logic [Xlen-1:0] i, input logic [Xlen-1:0] r1,
                                    input logic [Xlen-1:0] r2, input logic [VlW-1:0] vlq,
                                    input logic [Xlen-1:0] vtq);
    answer_t            a;
    logic    [Xlen-1:0] vt;
    logic    [Xlen-1:0] avl;
    logic               keep;
    logic               bad;

    a.is_vset = 1'b0;
    a.vl      = vlq;
    a.vtype   = vtq;
    vt        = '0;
    avl       = '0;
    keep      = 1'b0;

    if (i[6:0] != OpcodeOpV || i[14:12] != Funct3Opcfg) return a;

    if (i[31] == 1'b0) vt = {{Xlen - 11{1'b0}}, i[30:20]};
    else if (i[31:30] == TopVsetivli) vt = {{Xlen - 10{1'b0}}, i[29:20]};
    else if (i[31:25] == Funct7Vsetvl) vt = r2;
    else return a;

    if (i[31:30] == TopVsetivli) begin
      avl = {{Xlen - 5{1'b0}}, i[19:15]};
    end else if (i[19:15] != 5'b0) begin
      avl = r1;
    end else if (i[11:7] != 5'b0) begin
      avl = AllOnes;
    end else begin
      avl  = {{Xlen - VlW{1'b0}}, vlq};
      keep = 1'b1;
    end

    a.is_vset = 1'b1;

    bad = (vt[5:3] > VsewMax) || (vt[2:0] == LmulReserved) || ratio_bad(vt) ||
        (vt[Xlen-2:8] != '0) || vt[Xlen-1];
    if (keep) bad = bad || vtq[Xlen-1] || (vlmax_of(vt) != vlmax_of(vtq));

    if (bad) begin
      a.vl    = '0;
      a.vtype = Poison;
    end else begin
      a.vl    = (avl < vlmax_of(vt)) ? avl[VlW-1:0] : VlW'(vlmax_of(vt));
      a.vtype = {{Xlen - 8{1'b0}}, vt[7:0]};
    end
    return a;
  endfunction

endmodule

`default_nettype wire
