`default_nettype none

module vec_config_tb ();

  localparam int Xlen = 32;
  localparam int Vlen = 128;
  localparam int Elen = 32;

  localparam logic [6:0] OpcodeOpV = 7'b1010111;
  localparam logic [2:0] Funct3Opcfg = 3'b111;
  localparam logic [31:0] Poison = 32'h8000_0000;
  localparam logic [31:0] AllOnes = 32'hFFFF_FFFF;

  localparam int FormVsetvli = 0;
  localparam int FormVsetivli = 1;
  localparam int FormVsetvl = 2;

  int          checks = 0;
  int          errors = 0;

  logic [31:0] instr;
  logic [31:0] rs1_data;
  logic [31:0] rs2_data;
  logic [ 7:0] vl_q;
  logic [31:0] vtype_q;
  logic        is_vset;
  logic [ 7:0] vl_d;
  logic [31:0] vtype_d;

  typedef struct packed {
    logic        is_vset;
    logic [7:0]  vl;
    logic [31:0] vtype;
  } answer_t;

  vec_config #(
      .XLEN(Xlen),
      .VLEN(Vlen)
  ) dut (
      .instr   (instr),
      .rs1_data(rs1_data),
      .rs2_data(rs2_data),
      .vl_q    (vl_q),
      .vtype_q (vtype_q),
      .is_vset (is_vset),
      .vl_d    (vl_d),
      .vtype_d (vtype_d)
  );

  function automatic int sew_of(input logic [2:0] vsew);
    return 8 << vsew;
  endfunction

  function automatic int lmul_num(input logic [2:0] vlmul);
    case (vlmul)
      3'b001:  return 2;
      3'b010:  return 4;
      3'b011:  return 8;
      default: return 1;
    endcase
  endfunction

  function automatic int lmul_den(input logic [2:0] vlmul);
    case (vlmul)
      3'b101:  return 8;
      3'b110:  return 4;
      3'b111:  return 2;
      default: return 1;
    endcase
  endfunction

  function automatic int vlmax_of(input logic [31:0] vtype);
    return (lmul_num(vtype[2:0]) * Vlen) / (lmul_den(vtype[2:0]) * sew_of(vtype[5:3]));
  endfunction

  function automatic logic ratio_bad(input logic [31:0] vtype);
    return (sew_of(vtype[5:3]) * lmul_den(vtype[2:0])) / lmul_num(vtype[2:0]) > Elen;
  endfunction

  function automatic answer_t model(input logic [31:0] i, input logic [31:0] r1,
                                    input logic [31:0] r2, input logic [7:0] vlq,
                                    input logic [31:0] vtq);
    answer_t        a;
    logic    [31:0] vt;
    logic    [31:0] avl;
    logic           keep;
    logic           bad;

    a.is_vset = 1'b0;
    a.vl      = vlq;
    a.vtype   = vtq;
    vt        = '0;
    avl       = '0;
    keep      = 1'b0;

    if (i[6:0] != OpcodeOpV || i[14:12] != Funct3Opcfg) return a;

    if (i[31] == 1'b0) vt = {21'b0, i[30:20]};
    else if (i[31:30] == 2'b11) vt = {22'b0, i[29:20]};
    else if (i[31:25] == 7'b1000000) vt = r2;
    else return a;

    if (i[31:30] == 2'b11) begin
      avl = {27'b0, i[19:15]};
    end else if (i[19:15] != 5'b0) begin
      avl = r1;
    end else if (i[11:7] != 5'b0) begin
      avl = AllOnes;
    end else begin
      avl  = {24'b0, vlq};
      keep = 1'b1;
    end

    a.is_vset = 1'b1;

    bad = (vt[5:3] > 3'b010) || (vt[2:0] == 3'b100) || ratio_bad(vt) || (vt[30:8] != '0) || vt[31];
    if (keep) bad = bad || vtq[31] || (vlmax_of(vt) != vlmax_of(vtq));

    if (bad) begin
      a.vl    = 8'b0;
      a.vtype = Poison;
    end else begin
      a.vl    = (avl < vlmax_of(vt)) ? avl[7:0] : 8'(vlmax_of(vt));
      a.vtype = {24'b0, vt[7:0]};
    end
    return a;
  endfunction

  task automatic check(input string name);
    answer_t exp;
    #1;
    exp = model(instr, rs1_data, rs2_data, vl_q, vtype_q);
    checks += 3;
    if (is_vset !== exp.is_vset) begin
      errors++;
      $error("%s is_vset: got %b, exp %b", name, is_vset, exp.is_vset);
    end
    if (vl_d !== exp.vl) begin
      errors++;
      $error("%s vl_d: got %0d, exp %0d", name, vl_d, exp.vl);
    end
    if (vtype_d !== exp.vtype) begin
      errors++;
      $error("%s vtype_d: got %h, exp %h", name, vtype_d, exp.vtype);
    end
  endtask

  task automatic set_state(input logic [7:0] vlq, input logic [31:0] vtq);
    vl_q    = vlq;
    vtype_q = vtq;
  endtask

  task automatic do_vsetvli(input logic [10:0] vt, input logic [4:0] rs1, input logic [4:0] rd,
                            input logic [31:0] a, input string name);
    rs1_data = a;
    instr    = {1'b0, vt, rs1, Funct3Opcfg, rd, OpcodeOpV};
    check(name);
  endtask

  task automatic do_vsetivli(input logic [9:0] vt, input logic [4:0] ui, input logic [4:0] rd,
                             input string name);
    instr = {2'b11, vt, ui, Funct3Opcfg, rd, OpcodeOpV};
    check(name);
  endtask

  task automatic do_vsetvl(input logic [31:0] vt, input logic [4:0] rs1, input logic [4:0] rd,
                           input logic [31:0] a, input string name);
    rs1_data = a;
    rs2_data = vt;
    instr    = {7'b1000000, 5'd2, rs1, Funct3Opcfg, rd, OpcodeOpV};
    check(name);
  endtask

  task automatic do_form(input int form, input logic [8:0] vt, input logic [4:0] rs1,
                         input logic [4:0] rd, input logic [31:0] a, input string name);
    case (form)
      FormVsetvli:  do_vsetvli({2'b0, vt}, rs1, rd, a, name);
      FormVsetivli: do_vsetivli({1'b0, vt}, a[4:0], rd, name);
      default:      do_vsetvl({23'b0, vt}, rs1, rd, a, name);
    endcase
  endtask

  task automatic sweep_vtype(input int form, input logic [4:0] rs1, input logic [4:0] rd,
                             input int avl_cases, input string tag);
    int unsigned vm;
    int unsigned targets[7];
    for (int v = 0; v < 512; v++) begin
      vm = vlmax_of({23'b0, 9'(v)});
      targets[0] = 0;
      targets[1] = 1;
      targets[2] = (vm > 0) ? vm - 1 : 0;
      targets[3] = vm;
      targets[4] = vm + 1;
      targets[5] = 2 * vm;
      targets[6] = AllOnes;
      for (int t = 0; t < avl_cases; t++) begin
        do_form(form, 9'(v), rs1, rd, 32'(targets[t]), $sformatf("%s vtype %0d avl %0d", tag, v, t
                ));
      end
    end
  endtask

  task automatic sweep_reserved_forms();
    for (int hi = 1; hi < 32; hi++) begin
      instr = {2'b10, 5'(hi), 5'd0, 5'd1, Funct3Opcfg, 5'd1, OpcodeOpV};
      check($sformatf("reserved form %0d", hi));
    end
  endtask

  task automatic sweep_bad_funct3();
    for (int f = 0; f < 8; f++) begin
      if (f != 7) begin
        rs1_data = 32'd2;
        instr    = {1'b0, 11'b000_0_0_010_000, 5'd1, 3'(f), 5'd1, OpcodeOpV};
        check($sformatf("vsetvli shape funct3 %0d", f));
      end
    end
  endtask

  task automatic sweep_bad_opcode();
    for (int o = 0; o < 128; o++) begin
      if (o != 87) begin
        rs1_data = 32'd2;
        instr    = {1'b0, 11'b000_0_0_010_000, 5'd1, Funct3Opcfg, 5'd1, 7'(o)};
        check($sformatf("vsetvli shape opcode %0d", o));
      end
    end
  endtask

  task automatic sweep_upper_vtype();
    for (int u = 0; u < 8; u++) begin
      do_vsetvli({3'(u), 8'b0_0_010_000}, 5'd1, 5'd1, 32'd4, $sformatf("vsetvli upper vtype %0d", u
                 ));
    end
    do_vsetvl(32'h4000_0010, 5'd1, 5'd1, 32'd4, "vsetvl high reserved bit");
    do_vsetvl(32'h8000_0010, 5'd1, 5'd1, 32'd4, "vsetvl poisoned argument");
    do_vsetvl(Poison, 5'd1, 5'd1, 32'd4, "vsetvl poison bit alone");
  endtask

  task automatic verdict();
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask

  initial begin
    $dumpfile("vec_config_tb.vcd");
    $dumpvars(0, vec_config_tb);

    rs1_data = '0;
    rs2_data = '0;
    set_state(8'd7, 32'h0000_0010);

    instr = 32'h0000_0013;
    check("non vector instruction");

    sweep_reserved_forms();
    sweep_bad_funct3();
    sweep_bad_opcode();
    sweep_upper_vtype();

    set_state(8'd4, 32'h0000_0010);
    sweep_vtype(FormVsetvli, 5'd1, 5'd1, 7, "vsetvli");
    sweep_vtype(FormVsetivli, 5'd1, 5'd1, 7, "vsetivli");
    sweep_vtype(FormVsetvl, 5'd1, 5'd1, 7, "vsetvl");

    set_state(8'd3, 32'h0000_0000);
    sweep_vtype(FormVsetvli, 5'd0, 5'd0, 1, "keepvl from e8m1");
    sweep_vtype(FormVsetvl, 5'd0, 5'd0, 1, "keepvl vsetvl from e8m1");

    set_state(8'd3, 32'h0000_0010);
    sweep_vtype(FormVsetvli, 5'd0, 5'd0, 1, "keepvl from e32m1");
    sweep_vtype(FormVsetvl, 5'd0, 5'd0, 1, "keepvl vsetvl from e32m1");

    set_state(8'd3, Poison);
    sweep_vtype(FormVsetvli, 5'd0, 5'd0, 1, "keepvl from poison");
    sweep_vtype(FormVsetvl, 5'd0, 5'd0, 1, "keepvl vsetvl from poison");

    set_state(8'd16, 32'h0000_0000);
    do_vsetvli(11'b000_0_0_010_000, 5'd0, 5'd1, 32'd9, "rs1 x0 rd named");
    do_vsetvl(32'h0000_0010, 5'd0, 5'd1, 32'd9, "vsetvl rs1 x0 rd named");

    set_state(8'd2, 32'h0000_0000);
    do_vsetvli(11'b000_0_0_000_011, 5'd0, 5'd1, 32'd9, "rs1 x0 rd named takes vlmax");
    do_vsetivli(10'b00_0_0_010_000, 5'd0, 5'd0, "vsetivli zero fields");

    verdict();
  end

endmodule

`default_nettype wire
