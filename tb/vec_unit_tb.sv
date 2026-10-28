`default_nettype none

module vec_unit_tb
  import vec_pkg::*;
  import csr_pkg::VxrmAddr;
  import csr_pkg::VxsatAddr;
  import csr_pkg::VcsrAddr;
();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int VLEN = arch_pkg::VLEN;
  localparam int ELEN = arch_pkg::ELEN;
  localparam int VlW = $clog2(VLEN + 1);
  localparam int VlMax = (1 << VlW) - 1;
  localparam int Depth = 2 ** AWIDTH;
  localparam int Bytes = 256;
  localparam int LineB = VLEN / 8;
  localparam int Timeout = 2000000;
  localparam int IdleWait = 1000;
  localparam int ShowErrors = 12;
  localparam int MinChecks = 200000;
  localparam int MinRefChecks = 81000;
  localparam int StallPct = 30;
  localparam int GroupRegs = 8;
  localparam logic [2:0] NfGroup = 3'(GroupRegs - 1);
  localparam int CsrAddrW = $bits(VxrmAddr);
  localparam int RmW = fp_pkg::RmW;
  localparam logic [RmW-1:0] RmBad = fp_pkg::RmRmm + RmW'(1);
  localparam string TfDir = "build/testfloat/";
  localparam int RefLines = 2000;
  localparam int FpExpW = fp_pkg::ExpW;
  localparam int FpFracW = fp_pkg::FracW;
  localparam int FpSigW = fp_pkg::SigW;
  localparam int FLEN = fp_pkg::FLEN;
  localparam int FpBias = fp_pkg::Bias;
  localparam int FlagW = fp_pkg::FlagW;
  localparam int FpElems = VLEN / FLEN;
  localparam int FpEMin = 1 - FpBias;
  localparam int FpLsbMin = FpEMin - FpFracW;
  localparam int FpExpMax = (1 << FpExpW) - 1;
  localparam int RefW = 2 * (FpBias + 1) - 2 * FpLsbMin + 2;
  localparam int DivShift = 2 * FpSigW + 2;
  localparam int SqrtShift = FpSigW + 2;
  localparam int SqrtW = FpSigW + 2 + 2 * SqrtShift;
  localparam int FillW = FpFracW - 7;
  localparam logic [FLEN-1:0] CanonNan = {1'b0, {FpExpW{1'b1}}, 1'b1, {(FpFracW - 1) {1'b0}}};
  localparam logic [FLEN-2:0] InfMag = {{FpExpW{1'b1}}, {FpFracW{1'b0}}};
  localparam logic [FLEN-2:0] MaxMag = {{(FpExpW - 1) {1'b1}}, 1'b0, {FpFracW{1'b1}}};
  localparam logic [FLEN-1:0] FpOne = {2'b00, {(FpExpW - 1) {1'b1}}, {FpFracW{1'b0}}};
  localparam logic [FLEN-1:0] FpBig = {1'b0, FpExpW'(FpBias + FpSigW), {FpFracW{1'b0}}};
  localparam logic [FLEN-1:0] NegZero = {1'b1, {(FLEN - 1) {1'b0}}};
  localparam logic [FLEN-1:0] SnanPos = {1'b0, {FpExpW{1'b1}}, {(FpFracW - 1) {1'b0}}, 1'b1};
  localparam logic [FLEN-1:0] SnanNeg = {1'b1, {FpExpW{1'b1}}, 2'b01, {(FpFracW - 2) {1'b0}}};
  localparam logic [FLEN-1:0] QnanNeg = {1'b1, {FpExpW{1'b1}}, 1'b1, (FpFracW - 1)'('h1234)};

  typedef logic [FlagW+FLEN-1:0] fres_t;

  int                  checks = 0;
  int                  errors = 0;
  int                  ref_checks = 0;
  int                  max_errors = 0;

  logic                clk = 1'b0;
  logic                rst_n;
  logic                core_en;
  logic [        31:0] instr;
  logic                instr_valid;
  logic                cancel;
  logic [    XLEN-1:0] xdata;
  logic [    XLEN-1:0] xstride;
  logic [    XLEN-1:0] fdata;
  logic [     RmW-1:0] frm;
  logic [   FlagW-1:0] fflags;
  logic                vstart_set;
  logic [   FlagW-1:0] flags_seen = '0;
  logic                vill;
  logic [     VlW-1:0] vl;
  logic [         2:0] vsew;
  logic [         2:0] vlmul;
  logic [         1:0] vxrm;
  logic                vxsat;
  logic                csr_we;
  logic [CsrAddrW-1:0] csr_waddr;
  logic [    XLEN-1:0] csr_wdata;
  logic                csr_wait;
  logic                is_vector;
  logic                vec_hold;
  logic                vec_idle;
  logic                load_pending;
  logic                store_pending;
  logic                mem_misaligned;
  logic [    XLEN-1:0] mem_bad_addr;
  logic                xreg_valid;
  logic [    XLEN-1:0] xreg_result;
  int                  ready_pct = 100;
  int                  stall_pct = 0;

  logic [    VLEN-1:0] shadow          [Depth];
  logic [    VLEN-1:0] mem_rdata;
  logic                mem_ready;
  logic                mem_req;
  logic [    XLEN-1:0] mem_addr;
  logic [    VLEN-1:0] mem_wdata;
  logic [   LineB-1:0] mem_wstrb;
  logic [    XLEN-1:0] line_base;
  logic [         7:0] mem             [Bytes];
  logic [         7:0] gmem            [Bytes];
  logic                img_mode = 1'b0;
  logic [    VLEN-1:0] img             [Depth];
  logic [    VLEN-1:0] dump            [Depth];

  always #5 clk = ~clk;


  logic dec_valid;
  vec_op_e dec_op;
  vec_src_e dec_src;
  vec_eew_e dec_eew;
  logic dec_vm;
  logic [AWIDTH-1:0] dec_vs1;
  logic [AWIDTH-1:0] dec_vs2;
  logic [AWIDTH-1:0] dec_vd;
  logic [AWIDTH-1:0] dec_simm;
  logic dec_reads_vd;
  logic dec_reads_xreg;
  logic dec_writes_xreg;
  logic dec_writes_mask;
  vec_fop_e dec_fop;
  logic dec_reads_freg;
  logic dec_writes_freg;
  logic [1:0] dec_mem_width;
  logic dec_mem_whole;
  logic [2:0] dec_mem_nf;
  logic dec_mem_mask;
  logic dec_mem_strided;
  vec_dec_t dec;

  vec_decode u_decode (
      .instr(instr),
      .valid(dec_valid),
      .op(dec_op),
      .src(dec_src),
      .eew(dec_eew),
      .vm(dec_vm),
      .vs1(dec_vs1),
      .vs2(dec_vs2),
      .vd(dec_vd),
      .simm(dec_simm),
      .reads_vd(dec_reads_vd),
      .reads_xreg(dec_reads_xreg),
      .writes_xreg(dec_writes_xreg),
      .writes_mask(dec_writes_mask),
      .fop(dec_fop),
      .reads_freg(dec_reads_freg),
      .writes_freg(dec_writes_freg),
      .mem_width(dec_mem_width),
      .mem_whole(dec_mem_whole),
      .mem_nf(dec_mem_nf),
      .mem_mask(dec_mem_mask),
      .mem_strided(dec_mem_strided)
  );

  always_comb begin
    dec.valid = dec_valid;
    dec.op = dec_op;
    dec.src = dec_src;
    dec.eew = dec_eew;
    dec.vm = dec_vm;
    dec.vs1 = dec_vs1;
    dec.vs2 = dec_vs2;
    dec.vd = dec_vd;
    dec.simm = dec_simm;
    dec.reads_vd = dec_reads_vd;
    dec.reads_xreg = dec_reads_xreg;
    dec.writes_xreg = dec_writes_xreg;
    dec.writes_mask = dec_writes_mask;
    dec.fop = dec_fop;
    dec.reads_freg = dec_reads_freg;
    dec.writes_freg = dec_writes_freg;
    dec.mem_width = dec_mem_width;
    dec.mem_whole = dec_mem_whole;
    dec.mem_nf = dec_mem_nf;
    dec.mem_mask = dec_mem_mask;
    dec.mem_strided = dec_mem_strided;
  end

  vec_unit #(
      .XLEN  (XLEN),
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN),
      .ELEN  (ELEN)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .dec(dec),
      .instr_valid(instr_valid),
      .cancel(cancel),
      .ex_advance(!vec_hold),
      .xdata(xdata),
      .xstride(xstride),
      .fdata(fdata),
      .vill(vill),
      .vl(vl),
      .vsew(vsew),
      .vlmul(vlmul),
      .csr_we(csr_we),
      .csr_waddr(csr_waddr),
      .csr_wdata(csr_wdata),
      .csr_wait(csr_wait),
      .vxrm(vxrm),
      .vxsat(vxsat),
      .frm(frm),
      .fflags(fflags),
      .vstart_set(vstart_set),
      .mem_rdata(mem_rdata),
      .mem_ready(mem_ready),
      .mem_req(mem_req),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
      .mem_wstrb(mem_wstrb),
      .mem_misaligned(mem_misaligned),
      .mem_bad_addr(mem_bad_addr),
      .xreg_valid(xreg_valid),
      .xreg_result(xreg_result),
      .is_vector(is_vector),
      .vec_hold(vec_hold),
      .vec_idle(vec_idle),
      .load_pending(load_pending),
      .store_pending(store_pending)
  );

  task automatic check(input string name, input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      if (errors <= ShowErrors)
        $display("FAIL %s: got %h, expected %h at %0t", name, got, exp, $time);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic check_vreg(input string name, input logic [VLEN-1:0] got,
                            input logic [VLEN-1:0] exp);
    for (int w = 0; w < VLEN / XLEN; w++)
      check($sformatf("%0s word %0d", name, w), got[w*XLEN+:XLEN], exp[w*XLEN+:XLEN]);
  endtask  // Automatic

  task automatic check_ref(input string name, input fres_t got, input fres_t exp);
    ref_checks++;
    if (got !== exp) $fatal(1, "TB REFERENCE MISMATCH %s: got %h, expected %h", name, got, exp);
  endtask  // Automatic

  task automatic do_reset();
    rst_n       = 1'b0;
    core_en     = 1'b1;
    instr       = '0;
    instr_valid = 1'b0;
    cancel      = 1'b0;
    xdata       = '0;
    xstride     = '0;
    fdata       = '0;
    frm         = fp_pkg::RmRne;
    vstart_set  = 1'b0;
    vill        = 1'b0;
    mem_ready   = 1'b1;
    for (int b = 0; b < Bytes; b++) begin
      mem[b]  = 8'($urandom);
      gmem[b] = mem[b];
    end
    vl        = VlW'(FpElems);
    vsew      = 3'd2;
    vlmul     = 3'd0;
    csr_we    = 1'b0;
    csr_waddr = '0;
    csr_wdata = '0;
    csr_wait  = 1'b0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
  endtask  // Automatic

  task automatic watchdog();
    repeat (Timeout) @(posedge clk);
    $fatal(1, "TB TIMEOUT: %0d errors, %0d checks", errors, checks);
  endtask  // Automatic

  // Clock enable gaps
  task automatic gap();
    while ($urandom_range(
        99
    ) < stall_pct) begin
      core_en = 1'b0;
      @(negedge clk);
    end
    core_en = 1'b1;
  endtask  // Automatic

  // Present one instruction
  task automatic issue(input logic [31:0] word);
    @(negedge clk);
    gap();
    instr       = word;
    instr_valid = 1'b1;
    do @(posedge clk); while (vec_hold);
    @(negedge clk);
    instr_valid = 1'b0;
  endtask  // Automatic

  task automatic wait_idle(output logic idle);
    int guard;
    guard = 0;
    while (!vec_idle && (guard < IdleWait)) begin
      gap();
      @(negedge clk);
      guard++;
    end
    idle = vec_idle;
  endtask  // Automatic

  task automatic drain();
    logic idle;
    wait_idle(idle);
    check("unit goes idle", XLEN'(idle), XLEN'(1));
    @(negedge clk);
  endtask  // Automatic

  // Whole register image
  task automatic image_ops(input logic store, input logic [AWIDTH-1:0] r, input int count,
                           input logic [2:0] nf);
    logic [XLEN-1:0] save_x;
    logic idle;
    int save_pct;
    save_x    = xdata;
    save_pct  = ready_pct;
    ready_pct = 100;
    img_mode  = 1'b1;
    for (int k = 0; k < count; k++) begin
      xdata = XLEN'(int'(r) + k * (int'(nf) + 1)) * XLEN'(LineB);
      issue(enc_mem(store, 2'd0, 1'b1, 1'b0, 1'b1, AWIDTH'(int'(r) + k * (int'(nf) + 1))
            ) | {nf, 29'd0});
    end
    wait_idle(idle);
    if (!idle) $fatal(1, "TB IMAGE STALLED at v%0d", r);
    @(negedge clk);
    img_mode  = 1'b0;
    xdata     = save_x;
    ready_pct = save_pct;
  endtask  // Automatic

  task automatic seed_reg(input logic [AWIDTH-1:0] r, input logic [VLEN-1:0] data);
    img[r]    = data;
    shadow[r] = data;
    image_ops(1'b0, r, 1, 3'd0);
  endtask  // Automatic

  function automatic logic [VLEN-1:0] rand_vec();
    for (int w = VLEN / XLEN - 1; w >= 0; w--) rand_vec[w*XLEN+:XLEN] = XLEN'($urandom);
  endfunction

  task automatic seed_image();
    image_ops(1'b0, '0, Depth / GroupRegs, NfGroup);
  endtask  // Automatic

  task automatic seed_all();
    for (int r = 0; r < Depth; r++) begin
      img[r]    = rand_vec();
      shadow[r] = img[r];
    end
    seed_image();
  endtask  // Automatic

  task automatic check_regs(input string tag);
    for (int r = 0; r < Depth; r++) dump[r] = 'x;
    image_ops(1'b1, '0, Depth / GroupRegs, NfGroup);
    for (int r = 0; r < Depth; r++) check_vreg($sformatf("%0s v%0d", tag, r), dump[r], shadow[r]);
  endtask  // Automatic

  task automatic check_mem(input string tag);
    for (int k = 0; k < Bytes; k++)
      check($sformatf("%0s byte %0d", tag, k), XLEN'(mem[k]), XLEN'(gmem[k]));
  endtask  // Automatic

  // Write one register
  task automatic csr_poke(input logic [CsrAddrW-1:0] addr, input logic [XLEN-1:0] val);
    @(negedge clk);
    csr_we    = 1'b1;
    csr_waddr = addr;
    csr_wdata = val;
    @(negedge clk);
    csr_we = 1'b0;
  endtask  // Automatic


  // Element access
  function automatic logic [VLEN-1:0] wmask(input int w);
    wmask = (VLEN'(1) << w) - VLEN'(1);
  endfunction

  function automatic logic [ELEN-1:0] get_elem(input logic [VLEN-1:0] v, input int w, input int e);
    get_elem = ELEN'((v >> (e * w)) & wmask(w));
  endfunction

  function automatic logic [VLEN-1:0] set_elem(input logic [VLEN-1:0] v, input int w, input int e,
                                               input logic [ELEN-1:0] val);
    set_elem = (v & ~(wmask(w) << (e * w))) | ((VLEN'(val) & wmask(w)) << (e * w));
  endfunction

  function automatic logic [ELEN-1:0] sext(input logic [ELEN-1:0] v, input int w);
    sext = v[w-1] ?
        (v | ~(ELEN'((ELEN'(1) << w) - ELEN'(1)))) : (v & ELEN'((ELEN'(1) << w) - ELEN'(1)));
  endfunction

  // Element rule
  function automatic logic [ELEN-1:0] ref_op(input vec_op_e o, input int w,
                                             input logic [ELEN-1:0] ra, input logic [ELEN-1:0] rb,
                                             input logic cin, input logic vmb);
    logic [ELEN-1:0] m;
    logic [ELEN-1:0] a;
    logic [ELEN-1:0] b;
    logic [ELEN-1:0] sa;
    logic [ELEN-1:0] sb;
    logic [ELEN-1:0] sr;
    int sh;
    begin
      m  = ELEN'((ELEN'(1) << w) - ELEN'(1));
      a  = ra & m;
      b  = rb & m;
      sa = sext(a, w);
      sb = sext(b, w);
      sh = b & (w - 1);
      sr = $signed(sa) >>> sh;
      case (o)
        VEC_ADD:   ref_op = (a + b) & m;
        VEC_SUB:   ref_op = (a - b) & m;
        VEC_RSUB:  ref_op = (b - a) & m;
        VEC_AND:   ref_op = (a & b) & m;
        VEC_OR:    ref_op = (a | b) & m;
        VEC_XOR:   ref_op = (a ^ b) & m;
        VEC_SLL:   ref_op = (a << sh) & m;
        VEC_SRL:   ref_op = (a >> sh) & m;
        VEC_SRA:   ref_op = sr & m;
        VEC_MINU:  ref_op = (a < b) ? a : b;
        VEC_MIN:   ref_op = ($signed(sa) < $signed(sb)) ? a : b;
        VEC_MAXU:  ref_op = (a > b) ? a : b;
        VEC_MAX:   ref_op = ($signed(sa) > $signed(sb)) ? a : b;
        VEC_ADC:   ref_op = (a + b + ELEN'(cin)) & m;
        VEC_SBC:   ref_op = (a - b - ELEN'(cin)) & m;
        VEC_MERGE: ref_op = (vmb || cin) ? b : a;
        default:   ref_op = '0;
      endcase
    end
  endfunction

  // Encode one instruction
  function automatic logic [31:0] enc(input logic [5:0] f6, input logic vmb,
                                      input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] s1,
                                      input logic [2:0] f3, input logic [AWIDTH-1:0] d);
    enc = {f6, vmb, s2, s1, f3, d, opcode_pkg::OpcodeOpV};
  endfunction

  function automatic logic [5:0] funct6_of(input vec_op_e o);
    case (o)
      VEC_ADD:   funct6_of = 6'b000000;
      VEC_SUB:   funct6_of = 6'b000010;
      VEC_RSUB:  funct6_of = 6'b000011;
      VEC_MINU:  funct6_of = 6'b000100;
      VEC_MIN:   funct6_of = 6'b000101;
      VEC_MAXU:  funct6_of = 6'b000110;
      VEC_MAX:   funct6_of = 6'b000111;
      VEC_AND:   funct6_of = 6'b001001;
      VEC_OR:    funct6_of = 6'b001010;
      VEC_XOR:   funct6_of = 6'b001011;
      VEC_ADC:   funct6_of = 6'b010000;
      VEC_SBC:   funct6_of = 6'b010010;
      VEC_MERGE: funct6_of = 6'b010111;
      VEC_SLL:   funct6_of = 6'b100101;
      VEC_SRL:   funct6_of = 6'b101000;
      default:   funct6_of = 6'b101001;
    endcase
  endfunction

  // Model one instruction
  task automatic ref_apply(input vec_op_e o, input int form, input logic [AWIDTH-1:0] s1,
                           input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d, input logic vmb,
                           input logic [XLEN-1:0] xd, input logic [AWIDTH-1:0] im, input int w,
                           input int regs, input int len);
    int per_reg;
    int idx;
    logic [ELEN-1:0] ea;
    logic [ELEN-1:0] eb;
    logic cin;
    logic uses_v0;
    begin
      per_reg = VLEN / w;
      for (int r = 0; r < regs; r++) begin
        for (int e = 0; e < per_reg; e++) begin
          idx = r * per_reg + e;
          cin = shadow[0][idx];
          uses_v0 = (o == VEC_ADC) || (o == VEC_SBC) || (o == VEC_MERGE);
          if ((idx < len) && (vmb || cin || uses_v0)) begin
            ea = get_elem(shadow[(XLEN'(s2)+r)%Depth], w, e);
            case (form)
              0: eb = get_elem(shadow[(XLEN'(s1)+r)%Depth], w, e);
              1: eb = xd & ELEN'((ELEN'(1) << w) - ELEN'(1));
              default: eb = ELEN'($signed(im)) & ELEN'((ELEN'(1) << w) - ELEN'(1));
            endcase
            shadow[(XLEN'(d)+r)%Depth] =
                set_elem(shadow[(XLEN'(d)+r)%Depth], w, e, ref_op(o, w, ea, eb, cin, vmb));
          end
        end
      end
    end
  endtask  // Automatic

  // Run one operation
  task automatic run_one(input vec_op_e o, input int form, input logic [AWIDTH-1:0] s1,
                         input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d, input logic vmb,
                         input logic [XLEN-1:0] xd, input logic [AWIDTH-1:0] im,
                         input logic [2:0] sew, input logic [2:0] lmul, input logic [VlW-1:0] len);
    logic [2:0] f3;
    logic [AWIDTH-1:0] f2;
    int regs;
    begin
      vsew  = sew;
      vlmul = lmul;
      vl    = len;
      regs  = lmul[2] ? 1 : (1 << lmul[1:0]);
      case (form)
        0: f3 = 3'b000;
        1: f3 = 3'b100;
        default: f3 = 3'b011;
      endcase
      case (form)
        0: f2 = s1;
        1: f2 = AWIDTH'(1);
        default: f2 = im;
      endcase
      xdata = xd;
      ref_apply(o, form, s1, s2, d, vmb, xd, im, 8 << sew, regs, int'(len));
      issue(enc(funct6_of(o), vmb, s2, f2, f3, d));
      drain();
      check_regs("run_one");
    end
  endtask  // Automatic

  // Snapshot survives reconfigure
  task automatic check_snapshot();
    begin
      seed_all();
      vsew  = 3'd0;
      vlmul = 3'd3;
      vl    = VlW'(70);
      ref_apply(VEC_ADD, 0, AWIDTH'(8), AWIDTH'(16), AWIDTH'(24), 1'b1, '0, AWIDTH'(0), 8, 8, 70);
      issue(enc(6'b000000, 1'b1, AWIDTH'(16), AWIDTH'(8), 3'b000, AWIDTH'(24)));
      vsew  = 3'd2;
      vlmul = 3'd0;
      vl    = VlW'(1);
      drain();
      check_regs("snapshot");
    end
  endtask  // Automatic

  // Non vector ignored
  task automatic check_not_vector();
    begin
      seed_all();
      vsew  = 3'd2;
      vlmul = 3'd0;
      vl    = VlW'(4);
      issue({12'd1, AWIDTH'(0), 3'b000, AWIDTH'(1), opcode_pkg::OpcodeOpImm});
      drain();
      check_regs("addi");
      issue(enc(6'b110000, 1'b1, AWIDTH'(4), AWIDTH'(3), 3'b001, AWIDTH'(5)));
      drain();
      check_regs("float widening add");
      issue(enc(6'b001100, 1'b1, AWIDTH'(4), AWIDTH'(3), 3'b000, AWIDTH'(5)));
      drain();
      check_regs("gather");
      issue(enc(6'b111000, 1'b1, AWIDTH'(4), AWIDTH'(3), 3'b010, AWIDTH'(6)));
      drain();
      check_regs("widening multiply");
    end
  endtask  // Automatic

  // Tail stays untouched
  task automatic check_tail();
    begin
      seed_all();
      run_one(VEC_ADD, 0, AWIDTH'(6), AWIDTH'(7), AWIDTH'(8), 1'b1, '0, AWIDTH'(0), 3'd2, 3'd0,
              VlW'(2));
      run_one(VEC_XOR, 0, AWIDTH'(9), AWIDTH'(10), AWIDTH'(11), 1'b1, '0, AWIDTH'(0), 3'd1, 3'd0,
              VlW'(3));
      run_one(VEC_OR, 0, AWIDTH'(12), AWIDTH'(13), AWIDTH'(14), 1'b1, '0, AWIDTH'(0), 3'd0, 3'd0,
              VlW'(5));
    end
  endtask  // Automatic

  // Mask gates writes
  task automatic check_masked();
    begin
      seed_all();
      run_one(VEC_ADD, 0, AWIDTH'(2), AWIDTH'(3), AWIDTH'(4), 1'b0, '0, AWIDTH'(0), 3'd2, 3'd0,
              VlW'(4));
      run_one(VEC_SUB, 0, AWIDTH'(5), AWIDTH'(6), AWIDTH'(7), 1'b0, '0, AWIDTH'(0), 3'd1, 3'd0,
              VlW'(8));
      run_one(VEC_MERGE, 0, AWIDTH'(8), AWIDTH'(9), AWIDTH'(10), 1'b0, '0, AWIDTH'(0), 3'd0, 3'd0,
              VlW'(16));
    end
  endtask  // Automatic

  // Groups walk registers
  task automatic check_groups();
    begin
      seed_all();
      run_one(VEC_ADD, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, '0, AWIDTH'(0), 3'd2, 3'd1,
              VlW'(8));
      run_one(VEC_AND, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(16), 1'b1, '0, AWIDTH'(0), 3'd2, 3'd2,
              VlW'(16));
      run_one(VEC_XOR, 0, AWIDTH'(8), AWIDTH'(16), AWIDTH'(24), 1'b1, '0, AWIDTH'(0), 3'd1, 3'd1,
              VlW'(16));
    end
  endtask  // Automatic

  // Scalar and immediate
  task automatic check_forms();
    begin
      seed_all();
      run_one(VEC_ADD, 1, AWIDTH'(0), AWIDTH'(3), AWIDTH'(5), 1'b1, XLEN'('hDEAD_BEEF), AWIDTH'(0),
              3'd2, 3'd0, VlW'(4));
      run_one(VEC_RSUB, 1, AWIDTH'(0), AWIDTH'(6), AWIDTH'(7), 1'b1, XLEN'('h1234_5678), AWIDTH'(0),
              3'd1, 3'd0, VlW'(8));
      run_one(VEC_ADD, 2, AWIDTH'(0), AWIDTH'(9), AWIDTH'(11), 1'b1, '0, AWIDTH'(19), 3'd0, 3'd0,
              VlW'(16));
      run_one(VEC_SLL, 2, AWIDTH'(0), AWIDTH'(12), AWIDTH'(13), 1'b1, '0, AWIDTH'(3), 3'd2, 3'd0,
              VlW'(4));
    end
  endtask  // Automatic

  // Zero length
  task automatic check_zero_length();
    begin
      seed_all();
      run_one(VEC_ADD, 0, AWIDTH'(1), AWIDTH'(2), AWIDTH'(3), 1'b1, '0, AWIDTH'(0), 3'd2, 3'd0,
              VlW'(0));
    end
  endtask  // Automatic

  // Random traffic
  task automatic soak(input int n);
    vec_op_e o;
    int form;
    logic [2:0] sew;
    logic [2:0] lmul;
    logic [VlW-1:0] len;
    logic vmb;
    begin
      seed_all();
      for (int i = 0; i < n; i++) begin
        case ($urandom_range(
            12
        ))
          0: o = VEC_ADD;
          1: o = VEC_SUB;
          2: o = VEC_AND;
          3: o = VEC_OR;
          4: o = VEC_XOR;
          5: o = VEC_SLL;
          6: o = VEC_SRL;
          7: o = VEC_SRA;
          8: o = VEC_MINU;
          9: o = VEC_MIN;
          10: o = VEC_MAXU;
          11: o = VEC_MAX;
          default: o = VEC_MERGE;
        endcase
        form = int'(1'($urandom));
        sew  = 3'($urandom_range(2));
        lmul = 3'($urandom_range(2));
        len  = VlW'($urandom_range((VLEN >> sew) * (1 << lmul)));
        vmb  = 1'($urandom);
        if (o == VEC_MERGE) vmb = 1'b0;
        run_one(o, form, AWIDTH'(4), AWIDTH'(8), AWIDTH'(16), vmb, XLEN'($urandom),
                AWIDTH'($urandom), sew, lmul, len);
      end
    end
  endtask  // Automatic

  // Memory encode
  function automatic logic [31:0] enc_mem(input logic store, input logic [1:0] w, input logic whole,
                                          input logic strided, input logic vmb,
                                          input logic [AWIDTH-1:0] d);
    logic [2:0] f3;
    f3 = (w == 2'd2) ? 3'b110 : ((w == 2'd1) ? 3'b101 : 3'b000);
    enc_mem = {
      3'b000,
      1'b0,
      strided ? 2'b10 : 2'b00,
      vmb,
      whole ? 5'b01000 : (strided ? AWIDTH'(12) : AWIDTH'(0)),
      AWIDTH'(10),
      f3,
      d,
      store ? opcode_pkg::OpcodeStoreFp : opcode_pkg::OpcodeLoadFp
    };
  endfunction

  // Memory reference
  task automatic ref_mem(input logic store, input int w, input logic vmb,
                         input logic [AWIDTH-1:0] d, input logic [XLEN-1:0] b,
                         input logic [XLEN-1:0] st, input int len);
    int bytes;
    int per_reg;
    int r;
    logic [XLEN-1:0] a;
    logic [ELEN-1:0] e;
    begin
      bytes   = 1 << w;
      per_reg = LineB >> w;
      for (int i = 0; i < len; i++) begin
        a = b + XLEN'(i) * st;
        r = (int'(d) + i / per_reg) % Depth;
        if (!(vmb || shadow[0][i])) continue;
        if (!store) begin
          e = XLEN'('h0);
          for (int k = 0; k < bytes; k++) e[k*8+:8] = gmem[(a+XLEN'(k))%Bytes];
          shadow[r] = set_elem(shadow[r], bytes * 8, i % per_reg, e);
        end else begin
          e = get_elem(shadow[r], bytes * 8, i % per_reg);
          for (int k = 0; k < bytes; k++) gmem[(a+XLEN'(k))%Bytes] = e[k*8+:8];
        end
      end
    end
  endtask  // Automatic

  // Run one move
  task automatic run_mem(input logic store, input logic [1:0] w, input logic whole,
                         input logic strided, input logic vmb, input logic [AWIDTH-1:0] d,
                         input logic [XLEN-1:0] b, input logic [XLEN-1:0] st, input logic [2:0] sew,
                         input logic [2:0] lmul, input logic [VlW-1:0] len);
    int count;
    begin
      vsew    = sew;
      vlmul   = lmul;
      vl      = len;
      xdata   = b;
      xstride = st;
      count   = whole ? (VLEN >> (3 + w)) : int'(len);
      ref_mem(store, int'(w), vmb || whole, d, b, strided ? st : (XLEN'(1) << w), count);
      issue(enc_mem(store, w, whole, strided, vmb || whole, d));
      drain();
      check_regs("run_mem");
      check_mem("run_mem");
    end
  endtask  // Automatic

  // Legality and alignment
  task automatic check_mem_rules();
    begin
      vsew  = 3'd0;
      vlmul = 3'd0;
      vl    = VlW'(4);
      vill  = 1'b1;
      instr = enc_mem(1'b0, 2'd0, 1'b0, 1'b0, 1'b1, AWIDTH'(3));
      @(negedge clk);
      check("element load under vill", XLEN'(is_vector), XLEN'(0));
      instr = enc_mem(1'b0, 2'd1, 1'b1, 1'b0, 1'b1, AWIDTH'(3));
      @(negedge clk);
      check("whole load under vill", XLEN'(is_vector), XLEN'(1));
      vill  = 1'b0;
      vlmul = 3'd3;
      instr = enc_mem(1'b1, 2'd1, 1'b0, 1'b0, 1'b1, AWIDTH'(3));
      @(negedge clk);
      check("group too wide", XLEN'(is_vector), XLEN'(0));
      vsew  = 3'd2;
      vlmul = 3'b101;
      instr = enc_mem(1'b0, 2'd0, 1'b0, 1'b0, 1'b1, AWIDTH'(3));
      @(negedge clk);
      check("group too narrow", XLEN'(is_vector), XLEN'(0));
      vsew  = 3'd1;
      vlmul = 3'd0;
      xdata = XLEN'('h0000_0101);
      instr = enc_mem(1'b0, 2'd1, 1'b0, 1'b0, 1'b1, AWIDTH'(3));
      @(negedge clk);
      check("half base misaligned", XLEN'(mem_misaligned), XLEN'(1));
      check("half base address", mem_bad_addr, XLEN'('h0000_0101));
      xdata   = XLEN'('h0000_0100);
      xstride = XLEN'(3);
      instr   = enc_mem(1'b1, 2'd1, 1'b0, 1'b1, 1'b1, AWIDTH'(3));
      @(negedge clk);
      check("half stride misaligned", XLEN'(mem_misaligned), XLEN'(1));
      check("half stride address", mem_bad_addr, XLEN'('h0000_0103));
      vl = VlW'(1);
      @(negedge clk);
      check("one element stride", XLEN'(mem_misaligned), XLEN'(0));
      vl = VlW'(0);
      xdata = XLEN'('h0000_0103);
      @(negedge clk);
      check("empty base", XLEN'(mem_misaligned), XLEN'(0));
      vl = VlW'(4);
      instr = enc_mem(1'b1, 2'd0, 1'b0, 1'b1, 1'b1, AWIDTH'(3));
      @(negedge clk);
      check("byte never misaligned", XLEN'(mem_misaligned), XLEN'(0));
      vsew  = 3'd2;
      xdata = XLEN'('h0000_0102);
      instr = enc_mem(1'b0, 2'd2, 1'b1, 1'b0, 1'b1, AWIDTH'(3));
      @(negedge clk);
      check("whole word misaligned", XLEN'(mem_misaligned), XLEN'(1));
      xdata   = '0;
      xstride = '0;
    end
  endtask  // Automatic

  // Rounding and saturation
  task automatic check_fixed_point();
    begin
      csr_poke(VxrmAddr, XLEN'(2));
      check("vxrm takes a write", XLEN'(vxrm), XLEN'(2));
      check("vxsat untouched", XLEN'(vxsat), XLEN'(0));
      csr_poke(VxsatAddr, XLEN'(1));
      check("vxsat takes a write", XLEN'(vxsat), XLEN'(1));
      check("vxrm untouched", XLEN'(vxrm), XLEN'(2));
      csr_poke(VcsrAddr, XLEN'(3));
      check("vcsr sets the mode", XLEN'(vxrm), XLEN'(1));
      check("vcsr sets the flag", XLEN'(vxsat), XLEN'(1));
      csr_poke(VcsrAddr, XLEN'(0));
      check("vcsr clears both", XLEN'({vxrm, vxsat}), XLEN'(0));

      vsew  = 3'd0;
      vlmul = 3'd3;
      vl    = VlW'(128);
      issue(enc(6'b000000, 1'b1, AWIDTH'(16), AWIDTH'(8), 3'b000, AWIDTH'(24)));
      @(negedge clk);
      csr_wait = 1'b1;
      @(negedge clk);
      check("the access waits", XLEN'(vec_hold), XLEN'(1));
      drain();
      @(negedge clk);
      check("the access lands", XLEN'(vec_hold), XLEN'(0));
      csr_wait = 1'b0;
      vlmul = 3'd0;
      seed_all();
    end
  endtask  // Automatic

  // Reserved register numbers
  task automatic check_group_rules();
    begin
      vill  = 1'b0;
      vsew  = 3'd0;
      vl    = VlW'(8);
      vlmul = 3'd2;
      instr = enc(6'b000000, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(1));
      @(negedge clk);
      check("base off the multiple", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b000000, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(4));
      @(negedge clk);
      check("base on the multiple", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b000000, 1'b1, AWIDTH'(6), AWIDTH'(4), 3'b010, AWIDTH'(1));
      @(negedge clk);
      check("reduction source off", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b000000, 1'b1, AWIDTH'(4), AWIDTH'(4), 3'b010, AWIDTH'(1));
      @(negedge clk);
      check("reduction source on", XLEN'(is_vector), XLEN'(1));
      vlmul = 3'd0;
      instr = enc(6'b110000, 1'b1, AWIDTH'(2), AWIDTH'(1), 3'b010, AWIDTH'(2));
      @(negedge clk);
      check("wide over the low half", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b110000, 1'b1, AWIDTH'(3), AWIDTH'(1), 3'b010, AWIDTH'(2));
      @(negedge clk);
      check("wide over the high half", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b110000, 1'b1, AWIDTH'(6), AWIDTH'(1), 3'b010, AWIDTH'(2));
      @(negedge clk);
      check("wide clear of the source", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b101100, 1'b1, AWIDTH'(2), AWIDTH'(1), 3'b000, AWIDTH'(3));
      @(negedge clk);
      check("narrow over the high half", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b101100, 1'b1, AWIDTH'(2), AWIDTH'(1), 3'b000, AWIDTH'(2));
      @(negedge clk);
      check("narrow over the low half", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b110001, 1'b1, AWIDTH'(2), AWIDTH'(1), 3'b000, AWIDTH'(2));
      @(negedge clk);
      check("reduction over its source", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b000000, 1'b0, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(0));
      @(negedge clk);
      check("masked onto the mask", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b000000, 1'b0, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(1));
      @(negedge clk);
      check("masked clear of the mask", XLEN'(is_vector), XLEN'(1));
      vlmul = 3'd3;
      instr = enc(6'b110000, 1'b1, AWIDTH'(8), AWIDTH'(16), 3'b010, AWIDTH'(0));
      @(negedge clk);
      check("multiplier past eight", XLEN'(is_vector), XLEN'(0));
      vlmul = 3'd1;
      instr = enc(6'b011000, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(9));
      @(negedge clk);
      check("compare over vs2 high", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b011000, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(8));
      @(negedge clk);
      check("compare over vs2 low", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b011000, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(5));
      @(negedge clk);
      check("compare over vs1 high", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b011000, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(4));
      @(negedge clk);
      check("compare over vs1 low", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b011000, 1'b1, AWIDTH'(8), AWIDTH'(3), 3'b011, AWIDTH'(9));
      @(negedge clk);
      check("immediate over vs2 high", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b011000, 1'b1, AWIDTH'(8), AWIDTH'(5), 3'b100, AWIDTH'(5));
      @(negedge clk);
      check("scalar ignores vs1 field", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b010001, 1'b0, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(9));
      @(negedge clk);
      check("carry over vs2 high", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010011, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(8));
      @(negedge clk);
      check("borrow over vs2 low", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b010001, 1'b0, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(0));
      @(negedge clk);
      check("carry onto the mask", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b011001, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b010, AWIDTH'(9));
      @(negedge clk);
      check("mask logic over source", XLEN'(is_vector), XLEN'(1));
      vlmul = 3'b111;
      instr = enc(6'b011000, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(8));
      @(negedge clk);
      check("fractional compare over vs2", XLEN'(is_vector), XLEN'(1));
      vlmul = 3'd0;
      instr = enc(6'b010000, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(1));
      @(negedge clk);
      check("unmasked vadc vv", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010000, 1'b1, AWIDTH'(8), AWIDTH'(5), 3'b011, AWIDTH'(1));
      @(negedge clk);
      check("unmasked vadc vi", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010010, 1'b1, AWIDTH'(8), AWIDTH'(5), 3'b100, AWIDTH'(1));
      @(negedge clk);
      check("unmasked vsbc vx", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010000, 1'b0, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(1));
      @(negedge clk);
      check("masked vadc vv", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b010010, 1'b0, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(1));
      @(negedge clk);
      check("masked vsbc vv", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b010001, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(1));
      @(negedge clk);
      check("unmasked vmadc vv", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b010111, 1'b1, AWIDTH'(0), AWIDTH'(4), 3'b000, AWIDTH'(1));
      @(negedge clk);
      check("unmasked merge is a move", XLEN'(is_vector), XLEN'(1));
      vlmul = 3'd0;
      instr = '0;
    end
  endtask  // Automatic

  // Trap drops instruction
  task automatic check_mem_cancel();
    begin
      vsew   = 3'd0;
      vlmul  = 3'd0;
      vl     = VlW'(16);
      xdata  = XLEN'(16);
      cancel = 1'b1;
      issue(enc_mem(1'b1, 2'd0, 1'b0, 1'b0, 1'b1, AWIDTH'(5)));
      cancel = 1'b0;
      drain();
      check_regs("cancel");
      check_mem("cancel");
    end
  endtask  // Automatic

  // Pending until drained
  task automatic check_mem_pending();
    begin
      ready_pct = 20;
      vsew = 3'd0;
      vlmul = 3'd0;
      vl = VlW'(16);
      xdata = XLEN'(40);
      ref_mem(1'b1, 0, 1'b1, AWIDTH'(6), XLEN'(40), XLEN'(1), 16);
      issue(enc_mem(1'b1, 2'd0, 1'b0, 1'b0, 1'b1, AWIDTH'(6)));
      check("store pending", XLEN'(store_pending), XLEN'(1));
      check("no load pending", XLEN'(load_pending), XLEN'(0));
      xdata = XLEN'(80);
      ref_mem(1'b0, 0, 1'b1, AWIDTH'(7), XLEN'(80), XLEN'(1), 16);
      issue(enc_mem(1'b0, 2'd0, 1'b0, 1'b0, 1'b1, AWIDTH'(7)));
      check("load pending", XLEN'(load_pending), XLEN'(1));
      drain();
      check("store cleared", XLEN'(store_pending), XLEN'(0));
      check("load cleared", XLEN'(load_pending), XLEN'(0));
      check_regs("pending");
      check_mem("pending");
      ready_pct = 100;
    end
  endtask  // Automatic

  // Directed moves
  task automatic check_moves();
    begin
      seed_all();
      run_mem(1'b0, 2'd0, 1'b0, 1'b0, 1'b1, AWIDTH'(3), XLEN'(8), '0, 3'd0, 3'd0, VlW'(5));
      run_mem(1'b0, 2'd1, 1'b0, 1'b0, 1'b1, AWIDTH'(4), XLEN'(20), '0, 3'd1, 3'd0, VlW'(8));
      run_mem(1'b1, 2'd2, 1'b0, 1'b0, 1'b1, AWIDTH'(5), XLEN'(64), '0, 3'd2, 3'd0, VlW'(4));
      run_mem(1'b1, 2'd1, 1'b0, 1'b1, 1'b1, AWIDTH'(6), XLEN'(100), -XLEN'(6), 3'd1, 3'd0, VlW'(7));
      run_mem(1'b0, 2'd0, 1'b0, 1'b1, 1'b0, AWIDTH'(8), XLEN'(7), XLEN'(3), 3'd0, 3'd0, VlW'(9));
      run_mem(1'b1, 2'd0, 1'b0, 1'b0, 1'b0, AWIDTH'(9), XLEN'(140), '0, 3'd0, 3'd0, VlW'(16));
      run_mem(1'b0, 2'd0, 1'b1, 1'b0, 1'b1, AWIDTH'(10), XLEN'(33), '0, 3'd2, 3'd0, VlW'(1));
      run_mem(1'b1, 2'd0, 1'b1, 1'b0, 1'b1, AWIDTH'(11), XLEN'(200), '0, 3'd1, 3'd0, VlW'(0));
      run_mem(1'b0, 2'd2, 1'b1, 1'b0, 1'b1, AWIDTH'(12), XLEN'(16), '0, 3'd0, 3'd0, VlW'(3));
      run_mem(1'b0, 2'd1, 1'b0, 1'b0, 1'b1, AWIDTH'(14), XLEN'(40), '0, 3'd0, 3'd0, VlW'(12));
      run_mem(1'b1, 2'd0, 1'b0, 1'b0, 1'b1, AWIDTH'(16), XLEN'(0), '0, 3'd0, 3'd3, VlW'(100));
      run_mem(1'b0, 2'd0, 1'b0, 1'b0, 1'b1, AWIDTH'(24), XLEN'(0), '0, 3'd0, 3'd0, VlW'(0));
    end
  endtask  // Automatic

  // Random moves
  task automatic soak_mem(input int n);
    logic store;
    logic [1:0] w;
    logic whole;
    logic strided;
    logic vmb;
    logic [2:0] sew;
    logic [2:0] lmul;
    logic [AWIDTH-1:0] d;
    logic [VlW-1:0] len;
    int emul;
    int nregs;
    int vlmax;
    begin
      stall_pct = StallPct;
      seed_all();
      for (int i = 0; i < n; i++) begin
        store   = 1'($urandom);
        w       = 2'($urandom_range(2));
        whole   = (($urandom_range(3)) == 0) && (store == 1'b0 || w == 2'd0);
        strided = !whole && 1'($urandom);
        vmb     = whole || 1'($urandom);
        emul    = 9;
        while (emul > 3 || emul < -3) begin
          sew  = 3'($urandom_range(2));
          lmul = 3'($urandom_range(3));
          emul = whole ? 0 : int'(lmul) + int'(w) - int'(sew);
        end
        vlmax = (VLEN << lmul) >> (3 + sew);
        len = VlW'($urandom_range(vlmax > VlMax ? VlMax : vlmax));
        nregs = (emul <= 0) ? 1 : (1 << emul);
        d = ((!vmb && !store) ? AWIDTH'(23) - AWIDTH'($urandom_range(19)) :
             AWIDTH'($urandom)) & ~AWIDTH'(nregs - 1);
        if (!vmb && !store && (d == AWIDTH'(0))) d = AWIDTH'(nregs);
        ready_pct = ((1'($urandom)) == 0) ? 100 : 40;
        run_mem(store, w, whole, strided, vmb, d, XLEN'($urandom_range(Bytes - 1
                )) & ~((XLEN'(1) << w) - 1), XLEN'($signed(XLEN'($urandom_range(12))) - 6) << w,
                sew, lmul, len);
      end
      ready_pct = 100;
      stall_pct = 0;
    end
  endtask  // Automatic

  // Live state ignored
  task automatic scramble_cfg();
    vill  = 1'($urandom);
    vsew  = 3'($urandom_range(2));
    vlmul = 3'($urandom_range(3));
    vl    = VlW'($urandom_range(16));
  endtask  // Automatic

  // Whole register transfer
  task automatic run_whole(input logic store, input logic [1:0] w, input logic [2:0] nf,
                           input logic [AWIDTH-1:0] d, input logic [XLEN-1:0] b);
    begin
      scramble_cfg();
      xdata = b;
      ref_mem(store, int'(w), 1'b1, d, b, XLEN'(1) << w, (int'(nf) + 1) * (VLEN >> (3 + w)));
      issue(enc_mem(store, w, 1'b1, 1'b0, 1'b1, d) | {nf, 29'd0});
      drain();
      check_regs("run_whole");
      check_mem("run_whole");
      vill = 1'b0;
    end
  endtask  // Automatic

  // Whole register move
  task automatic run_mvnr(input logic [2:0] nf, input logic [AWIDTH-1:0] s2,
                          input logic [AWIDTH-1:0] d);
    logic [VLEN-1:0] src[GroupRegs];
    begin
      scramble_cfg();
      vill = 1'b0;
      for (int r = 0; r <= int'(nf); r++) src[r] = shadow[(XLEN'(s2)+r)%Depth];
      for (int r = 0; r <= int'(nf); r++) shadow[(XLEN'(d)+r)%Depth] = src[r];
      issue(enc(6'b100111, 1'b1, s2, AWIDTH'(nf), 3'b011, d));
      drain();
      check_regs("run_mvnr");
      vill = 1'b0;
    end
  endtask  // Automatic

  // Whole register rules
  task automatic check_whole_rules();
    begin
      vill  = 1'b1;
      vsew  = 3'd2;
      vlmul = 3'd0;
      vl    = VlW'(0);
      instr = enc(6'b100111, 1'b1, AWIDTH'(8), AWIDTH'(3), 3'b011, AWIDTH'(4));
      @(negedge clk);
      check("move under vill", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b100111, 1'b1, AWIDTH'(4), AWIDTH'(3), 3'b011, AWIDTH'(4));
      @(negedge clk);
      check("self move under vill", XLEN'(is_vector), XLEN'(0));
      instr = enc_mem(1'b0, 2'd2, 1'b1, 1'b0, 1'b1, AWIDTH'(8)) | {3'd7, 29'd0};
      @(negedge clk);
      check("eight loads under vill", XLEN'(is_vector), XLEN'(1));
      vill  = 1'b0;
      instr = enc(6'b100111, 1'b1, AWIDTH'(8), AWIDTH'(1), 3'b011, AWIDTH'(3));
      @(negedge clk);
      check("move dest off two", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b100111, 1'b1, AWIDTH'(6), AWIDTH'(3), 3'b011, AWIDTH'(8));
      @(negedge clk);
      check("move source off four", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b100111, 1'b1, AWIDTH'(8), AWIDTH'(7), 3'b011, AWIDTH'(0));
      @(negedge clk);
      check("eight onto v0", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b100111, 1'b1, AWIDTH'(8), AWIDTH'(2), 3'b011, AWIDTH'(0));
      @(negedge clk);
      check("three registers", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b100111, 1'b1, AWIDTH'(20), AWIDTH'(3), 3'b011, AWIDTH'(20));
      @(negedge clk);
      check("copy onto itself", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b100111, 1'b1, AWIDTH'(20), AWIDTH'(3), 3'b011, AWIDTH'(24));
      @(negedge clk);
      check("copy four registers", XLEN'(is_vector), XLEN'(1));
      instr = enc_mem(1'b0, 2'd0, 1'b1, 1'b0, 1'b1, AWIDTH'(5)) | {3'd1, 29'd0};
      @(negedge clk);
      check("load pair off two", XLEN'(is_vector), XLEN'(0));
      instr = enc_mem(1'b1, 2'd0, 1'b1, 1'b0, 1'b1, AWIDTH'(12)) | {3'd3, 29'd0};
      @(negedge clk);
      check("store four on four", XLEN'(is_vector), XLEN'(1));
      instr = enc_mem(1'b1, 2'd0, 1'b1, 1'b0, 1'b1, AWIDTH'(12)) | {3'd7, 29'd0};
      @(negedge clk);
      check("store eight off eight", XLEN'(is_vector), XLEN'(0));
      xdata = XLEN'('h0000_0102);
      instr = enc_mem(1'b0, 2'd2, 1'b1, 1'b0, 1'b1, AWIDTH'(8)) | {3'd1, 29'd0};
      @(negedge clk);
      check("pair word misaligned", XLEN'(mem_misaligned), XLEN'(1));
      xdata = '0;
      vl    = VlW'(4);
      instr = '0;
    end
  endtask  // Automatic

  // Whole register groups
  task automatic check_whole();
    logic [2:0] nf;
    logic [1:0] w;
    logic store;
    begin
      seed_all();
      run_whole(1'b0, 2'd0, 3'd1, AWIDTH'(2), XLEN'(5));
      run_whole(1'b0, 2'd1, 3'd3, AWIDTH'(4), XLEN'(34));
      run_whole(1'b0, 2'd2, 3'd7, AWIDTH'(8), XLEN'(100));
      run_whole(1'b1, 2'd0, 3'd1, AWIDTH'(6), XLEN'(3));
      run_whole(1'b1, 2'd0, 3'd7, AWIDTH'(16), XLEN'(64));
      run_mvnr(3'd0, AWIDTH'(3), AWIDTH'(9));
      run_mvnr(3'd1, AWIDTH'(10), AWIDTH'(12));
      run_mvnr(3'd3, AWIDTH'(16), AWIDTH'(4));
      run_mvnr(3'd7, AWIDTH'(8), AWIDTH'(24));
      run_mvnr(3'd3, AWIDTH'(20), AWIDTH'(20));
      for (int i = 0; i < 60; i++) begin
        case ($urandom_range(
            3
        ))
          0: nf = 3'd0;
          1: nf = 3'd1;
          2: nf = 3'd3;
          default: nf = 3'd7;
        endcase
        store = 1'($urandom);
        w = store ? 2'd0 : 2'($urandom_range(2));
        ready_pct = ((1'($urandom)) == 0) ? 100 : 40;
        if (($urandom_range(2)) == 0)
          run_mvnr(nf, AWIDTH'($urandom) & ~AWIDTH'(nf), AWIDTH'($urandom) & ~AWIDTH'(nf));
        else
          run_whole(store, w, nf, AWIDTH'($urandom) & ~AWIDTH'(nf), XLEN'($urandom_range(Bytes - 1
                    )) & ~((XLEN'(1) << w) - 1));
      end
      ready_pct = 100;
    end
  endtask  // Automatic

  // Group element access
  function automatic logic [ELEN-1:0] grp_get(input logic [AWIDTH-1:0] base, input int w,
                                              input int i);
    int roff;
    int pos;
    roff = (i * w) / VLEN;
    pos  = ((i * w) % VLEN) / w;
    return get_elem(shadow[(XLEN'(base)+roff)%Depth], w, pos);
  endfunction

  task automatic grp_set(input logic [AWIDTH-1:0] base, input int w, input int i,
                         input logic [ELEN-1:0] val);
    int roff;
    int pos;
    roff = (i * w) / VLEN;
    pos = ((i * w) % VLEN) / w;
    shadow[(XLEN'(base)+roff)%Depth] = set_elem(shadow[(XLEN'(base)+roff)%Depth], w, pos, val);
  endtask  // Automatic

  function automatic int group_elems(input int sew, input int regs);
    return regs * (VLEN / sew);
  endfunction

  // Widening model
  task automatic ref_widen(input vec_op_e o, input int form, input logic [AWIDTH-1:0] s1,
                           input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d, input logic vmb,
                           input logic [XLEN-1:0] xd, input int sew, input int regs, input int len,
                           input logic wv);
    int dw;
    logic [ELEN-1:0] a;
    logic [ELEN-1:0] b;
    logic sgn;
    dw  = sew * 2;
    sgn = (o == VEC_WADD) || (o == VEC_WSUB);
    for (int i = 0; i < group_elems(sew, regs); i++) begin
      if ((i < len) && (vmb || shadow[0][i])) begin
        if (wv) a = grp_get(s2, dw, i);
        else a = sgn ? sext(grp_get(s2, sew, i), sew) : grp_get(s2, sew, i);
        b = (form == 0) ? grp_get(s1, sew, i) : (xd & ELEN'((ELEN'(1) << sew) - ELEN'(1)));
        if (sgn) b = sext(b, sew);
        grp_set(d, dw, i, ((o == VEC_WSUBU) || (o == VEC_WSUB)) ? (a - b) : (a + b));
      end
    end
  endtask  // Automatic

  // Narrowing model
  task automatic ref_narrow(input vec_op_e o, input int form, input logic [AWIDTH-1:0] s1,
                            input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d,
                            input logic vmb, input logic [XLEN-1:0] xd, input logic [AWIDTH-1:0] im,
                            input int sew, input int regs, input int len);
    logic [ELEN-1:0] w;
    logic [ELEN-1:0] r;
    int sh;
    for (int i = 0; i < group_elems(sew, regs); i++) begin
      if ((i < len) && (vmb || shadow[0][i])) begin
        w  = grp_get(s2, sew * 2, i);
        sh = (form == 0) ? int'(grp_get(s1, sew, i)) : ((form == 1) ? int'(xd[5:0]) : int'(im));
        sh = sh % (sew * 2);
        r  = (o == VEC_NSRA) ? XLEN'($signed(sext(w, sew * 2)) >>> sh) : (w >> sh);
        grp_set(d, sew, i, r);
      end
    end
  endtask  // Automatic

  // Extension model
  task automatic ref_extend(input vec_op_e o, input logic [AWIDTH-1:0] s2,
                            input logic [AWIDTH-1:0] d, input logic vmb, input int sew,
                            input int regs, input int len, input int factor);
    int sw;
    logic [ELEN-1:0] a;
    logic sgn;
    sw  = sew / factor;
    sgn = (o == VEC_SEXT2) || (o == VEC_SEXT4);
    for (int i = 0; i < group_elems(sew, regs); i++) begin
      if ((i < len) && (vmb || shadow[0][i])) begin
        a = grp_get(s2, sw, i);
        grp_set(d, sew, i, sgn ? sext(a, sw) : a);
      end
    end
  endtask  // Automatic

  // Reduction model
  function automatic logic [ELEN-1:0] ref_fold(input vec_op_e o, input logic [ELEN-1:0] x,
                                               input logic [ELEN-1:0] y);
    case (o)
      VEC_REDSUM, VEC_WREDSUM, VEC_WREDSUMU: return x + y;
      VEC_REDAND: return x & y;
      VEC_REDOR: return x | y;
      VEC_REDXOR: return x ^ y;
      VEC_REDMINU: return (x < y) ? x : y;
      VEC_REDMIN: return ($signed(x) < $signed(y)) ? x : y;
      VEC_REDMAXU: return (x > y) ? x : y;
      VEC_REDMAX: return ($signed(x) > $signed(y)) ? x : y;
      default: return x;
    endcase
  endfunction

  task automatic ref_reduce(input vec_op_e o, input logic [AWIDTH-1:0] s1,
                            input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d,
                            input logic vmb, input int sew, input int regs, input int len,
                            input logic wide);
    int accw;
    logic [ELEN-1:0] acc;
    logic [ELEN-1:0] v;
    logic sgn;
    accw = wide ? sew * 2 : sew;
    sgn  = (o == VEC_REDMIN) || (o == VEC_REDMAX) || (o == VEC_WREDSUM);
    if (len == 0) return;
    acc = grp_get(s1, accw, 0);
    if (sgn) acc = sext(acc, accw);
    for (int i = 0; i < group_elems(sew, regs); i++) begin
      if ((i < len) && (vmb || shadow[0][i])) begin
        v = grp_get(s2, sew, i);
        if (sgn) v = sext(v, sew);
        acc = ref_fold(o, acc, v);
      end
    end
    grp_set(d, accw, 0, acc);
  endtask  // Automatic

  // Mixed width runs
  task automatic run_widen(input vec_op_e o, input int form, input logic [AWIDTH-1:0] s1,
                           input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d, input logic vmb,
                           input logic [XLEN-1:0] xd, input logic [2:0] sew, input logic [2:0] lmul,
                           input logic [VlW-1:0] len, input logic wv);
    logic [5:0] f6;
    int regs;
    regs  = lmul[2] ? 1 : (1 << lmul[1:0]);
    vsew  = sew;
    vlmul = lmul;
    vl    = len;
    xdata = xd;
    case (o)
      VEC_WADDU: f6 = wv ? 6'b110100 : 6'b110000;
      VEC_WADD:  f6 = wv ? 6'b110101 : 6'b110001;
      VEC_WSUBU: f6 = wv ? 6'b110110 : 6'b110010;
      default:   f6 = wv ? 6'b110111 : 6'b110011;
    endcase
    ref_widen(o, form, s1, s2, d, vmb, xd, 8 << sew, regs, int'(len), wv);
    issue(enc(f6, vmb, s2, s1, (form == 0) ? 3'b010 : 3'b110, d));
    drain();
    check_regs("widen");
  endtask  // Automatic

  task automatic run_narrow(input vec_op_e o, input int form, input logic [AWIDTH-1:0] s1,
                            input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d,
                            input logic vmb, input logic [XLEN-1:0] xd, input logic [AWIDTH-1:0] im,
                            input logic [2:0] sew, input logic [2:0] lmul,
                            input logic [VlW-1:0] len);
    logic [5:0] f6;
    logic [2:0] f3;
    logic [AWIDTH-1:0] sf;
    int regs;
    regs  = lmul[2] ? 1 : (1 << lmul[1:0]);
    vsew  = sew;
    vlmul = lmul;
    vl    = len;
    xdata = xd;
    f6    = (o == VEC_NSRA) ? 6'b101101 : 6'b101100;
    case (form)
      0: begin
        f3 = 3'b000;
        sf = s1;
      end
      1: begin
        f3 = 3'b100;
        sf = AWIDTH'(1);
      end
      default: begin
        f3 = 3'b011;
        sf = im;
      end
    endcase
    ref_narrow(o, form, s1, s2, d, vmb, xd, im, 8 << sew, regs, int'(len));
    issue(enc(f6, vmb, s2, sf, f3, d));
    drain();
    check_regs("narrow");
  endtask  // Automatic

  task automatic run_extend(input vec_op_e o, input logic [AWIDTH-1:0] s2,
                            input logic [AWIDTH-1:0] d, input logic vmb, input logic [2:0] sew,
                            input logic [2:0] lmul, input logic [VlW-1:0] len);
    logic [AWIDTH-1:0] sel;
    int regs;
    int factor;
    regs   = lmul[2] ? 1 : (1 << lmul[1:0]);
    vsew   = sew;
    vlmul  = lmul;
    vl     = len;
    factor = ((o == VEC_ZEXT4) || (o == VEC_SEXT4)) ? 4 : 2;
    case (o)
      VEC_ZEXT2: sel = 5'b00110;
      VEC_SEXT2: sel = 5'b00111;
      VEC_ZEXT4: sel = 5'b00100;
      default:   sel = 5'b00101;
    endcase
    ref_extend(o, s2, d, vmb, 8 << sew, regs, int'(len), factor);
    issue(enc(6'b010010, vmb, s2, sel, 3'b010, d));
    drain();
    check_regs("extend");
  endtask  // Automatic

  task automatic run_reduce(input vec_op_e o, input logic [AWIDTH-1:0] s1,
                            input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d,
                            input logic vmb, input logic [2:0] sew, input logic [2:0] lmul,
                            input logic [VlW-1:0] len);
    logic [5:0] f6;
    logic [2:0] f3;
    logic wide;
    int regs;
    regs  = lmul[2] ? 1 : (1 << lmul[1:0]);
    vsew  = sew;
    vlmul = lmul;
    vl    = len;
    wide  = (o == VEC_WREDSUM) || (o == VEC_WREDSUMU);
    f3    = wide ? 3'b000 : 3'b010;
    case (o)
      VEC_REDSUM:   f6 = 6'b000000;
      VEC_REDAND:   f6 = 6'b000001;
      VEC_REDOR:    f6 = 6'b000010;
      VEC_REDXOR:   f6 = 6'b000011;
      VEC_REDMINU:  f6 = 6'b000100;
      VEC_REDMIN:   f6 = 6'b000101;
      VEC_REDMAXU:  f6 = 6'b000110;
      VEC_REDMAX:   f6 = 6'b000111;
      VEC_WREDSUMU: f6 = 6'b110000;
      default:      f6 = 6'b110001;
    endcase
    ref_reduce(o, s1, s2, d, vmb, 8 << sew, regs, int'(len), wide);
    issue(enc(f6, vmb, s2, s1, f3, d));
    drain();
    check_regs("reduce");
  endtask  // Automatic

  // Scalar moves
  task automatic run_move_sx(input logic [AWIDTH-1:0] d, input logic [XLEN-1:0] xd,
                             input logic [2:0] sew, input logic [VlW-1:0] len);
    vsew  = sew;
    vlmul = 3'd0;
    vl    = len;
    xdata = xd;
    if (len != VlW'(0)) grp_set(d, 8 << sew, 0, xd);
    issue(enc(6'b010000, 1'b1, 5'b00000, AWIDTH'(3), 3'b110, d));
    drain();
    check_regs("move sx");
  endtask  // Automatic

  task automatic run_move_xs(input logic [AWIDTH-1:0] s2, input logic [2:0] sew,
                             input logic [VlW-1:0] len);
    logic [ELEN-1:0] want;
    vsew  = sew;
    vlmul = 3'd0;
    vl    = len;
    want  = sext(get_elem(shadow[s2], 8 << sew, 0), 8 << sew);
    issue(enc(6'b010000, 1'b1, s2, 5'b00000, 3'b010, AWIDTH'(7)));
    drain();
    check_regs("move xs");
    check("move xs", XLEN'(xreg_result), XLEN'(want));
  endtask  // Automatic

  task automatic check_widening();
    seed_all();
    run_widen(VEC_WADDU, 0, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, '0, 3'd0, 3'd0, VlW'(16),
              1'b0);
    run_widen(VEC_WADD, 0, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, '0, 3'd0, 3'd0, VlW'(16),
              1'b0);
    run_widen(VEC_WSUBU, 0, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, '0, 3'd1, 3'd0, VlW'(8),
              1'b0);
    run_widen(VEC_WSUB, 0, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, '0, 3'd1, 3'd0, VlW'(8),
              1'b0);
    run_widen(VEC_WADD, 1, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, XLEN'('h0000_00a5), 3'd0,
              3'd0, VlW'(16), 1'b0);
    run_widen(VEC_WADDU, 0, AWIDTH'(2), AWIDTH'(6), AWIDTH'(20), 1'b1, '0, 3'd0, 3'd1, VlW'(32),
              1'b0);
    run_widen(VEC_WSUB, 0, AWIDTH'(2), AWIDTH'(6), AWIDTH'(20), 1'b1, '0, 3'd1, 3'd1, VlW'(16),
              1'b0);
    run_widen(VEC_WADDU, 0, AWIDTH'(1), AWIDTH'(16), AWIDTH'(24), 1'b1, '0, 3'd0, 3'd0, VlW'(16),
              1'b1);
    run_widen(VEC_WSUB, 0, AWIDTH'(1), AWIDTH'(16), AWIDTH'(24), 1'b1, '0, 3'd1, 3'd0, VlW'(8),
              1'b1);
    run_widen(VEC_WADD, 0, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b0, '0, 3'd0, 3'd0, VlW'(16),
              1'b0);
    run_widen(VEC_WADD, 0, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, '0, 3'd0, 3'd0, VlW'(5),
              1'b0);
  endtask  // Automatic

  task automatic check_narrowing();
    seed_all();
    run_narrow(VEC_NSRL, 0, AWIDTH'(1), AWIDTH'(16), AWIDTH'(8), 1'b1, '0, AWIDTH'(0), 3'd0, 3'd0,
               VlW'(16));
    run_narrow(VEC_NSRA, 0, AWIDTH'(1), AWIDTH'(16), AWIDTH'(8), 1'b1, '0, AWIDTH'(0), 3'd0, 3'd0,
               VlW'(16));
    run_narrow(VEC_NSRL, 1, AWIDTH'(1), AWIDTH'(16), AWIDTH'(8), 1'b1, XLEN'(5), AWIDTH'(0), 3'd1,
               3'd0, VlW'(8));
    run_narrow(VEC_NSRA, 2, AWIDTH'(1), AWIDTH'(16), AWIDTH'(8), 1'b1, '0, AWIDTH'(9), 3'd1, 3'd0,
               VlW'(8));
    run_narrow(VEC_NSRL, 0, AWIDTH'(2), AWIDTH'(16), AWIDTH'(8), 1'b1, '0, AWIDTH'(0), 3'd0, 3'd1,
               VlW'(32));
    run_narrow(VEC_NSRA, 0, AWIDTH'(1), AWIDTH'(16), AWIDTH'(8), 1'b0, '0, AWIDTH'(0), 3'd0, 3'd0,
               VlW'(16));
    run_narrow(VEC_NSRL, 0, AWIDTH'(1), AWIDTH'(16), AWIDTH'(8), 1'b1, '0, AWIDTH'(0), 3'd0, 3'd0,
               VlW'(7));
  endtask  // Automatic

  task automatic check_extensions();
    seed_all();
    run_extend(VEC_ZEXT2, AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd1, 3'd0, VlW'(8));
    run_extend(VEC_SEXT2, AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd1, 3'd0, VlW'(8));
    run_extend(VEC_ZEXT2, AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd2, 3'd0, VlW'(4));
    run_extend(VEC_SEXT2, AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd2, 3'd0, VlW'(4));
    run_extend(VEC_ZEXT4, AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd2, 3'd0, VlW'(4));
    run_extend(VEC_SEXT4, AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd2, 3'd0, VlW'(4));
    run_extend(VEC_SEXT2, AWIDTH'(4), AWIDTH'(18), 1'b1, 3'd2, 3'd1, VlW'(8));
    run_extend(VEC_SEXT2, AWIDTH'(4), AWIDTH'(16), 1'b0, 3'd2, 3'd0, VlW'(4));
  endtask  // Automatic

  task automatic check_reductions();
    seed_all();
    seed_reg(AWIDTH'(1), '1);
    seed_reg(AWIDTH'(2), {(VLEN / 8) {8'hA5}});
    run_reduce(VEC_REDSUM, AWIDTH'(2), AWIDTH'(1), AWIDTH'(18), 1'b1, 3'd2, 3'd0, VlW'(4));
    run_reduce(VEC_REDAND, AWIDTH'(2), AWIDTH'(1), AWIDTH'(19), 1'b1, 3'd2, 3'd0, VlW'(4));
    run_reduce(VEC_REDOR, AWIDTH'(2), AWIDTH'(1), AWIDTH'(20), 1'b1, 3'd2, 3'd0, VlW'(4));
    run_reduce(VEC_REDXOR, AWIDTH'(2), AWIDTH'(1), AWIDTH'(21), 1'b1, 3'd2, 3'd0, VlW'(4));
    seed_all();
    run_reduce(VEC_REDSUM, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd2, 3'd0, VlW'(4));
    run_reduce(VEC_REDAND, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd2, 3'd0, VlW'(4));
    run_reduce(VEC_REDOR, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd1, 3'd0, VlW'(8));
    run_reduce(VEC_REDXOR, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd0, 3'd0, VlW'(16));
    run_reduce(VEC_REDMINU, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd2, 3'd0, VlW'(4));
    run_reduce(VEC_REDMIN, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd2, 3'd0, VlW'(4));
    run_reduce(VEC_REDMAXU, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd1, 3'd0, VlW'(8));
    run_reduce(VEC_REDMAX, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd0, 3'd0, VlW'(16));
    run_reduce(VEC_REDSUM, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd2, 3'd2, VlW'(16));
    run_reduce(VEC_REDSUM, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b0, 3'd2, 3'd0, VlW'(4));
    run_reduce(VEC_REDSUM, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd2, 3'd0, VlW'(0));
    run_reduce(VEC_WREDSUMU, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd1, 3'd0, VlW'(8));
    run_reduce(VEC_WREDSUM, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd1, 3'd0, VlW'(8));
    run_reduce(VEC_WREDSUM, AWIDTH'(1), AWIDTH'(4), AWIDTH'(16), 1'b1, 3'd0, 3'd1, VlW'(32));
  endtask  // Automatic

  task automatic check_scalar_moves();
    seed_all();
    run_move_sx(AWIDTH'(9), XLEN'('hdead_beef), 3'd2, VlW'(4));
    run_move_sx(AWIDTH'(9), XLEN'('h0000_00a5), 3'd0, VlW'(4));
    run_move_sx(AWIDTH'(9), XLEN'('hffff_8001), 3'd1, VlW'(8));
    run_move_sx(AWIDTH'(9), XLEN'('h1234_5678), 3'd2, VlW'(0));
    run_move_xs(AWIDTH'(4), 3'd2, VlW'(4));
    run_move_xs(AWIDTH'(4), 3'd1, VlW'(8));
    run_move_xs(AWIDTH'(4), 3'd0, VlW'(16));
    run_move_xs(AWIDTH'(4), 3'd2, VlW'(0));
  endtask  // Automatic

  // Mask bit read
  function automatic logic mbit(input logic [AWIDTH-1:0] r, input int i);
    mbit = shadow[r][i];
  endfunction

  function automatic logic [ELEN-1:0] mask_w(input int w);
    mask_w = (w >= ELEN) ? '1 : ((ELEN'(1) << w) - ELEN'(1));
  endfunction

  function automatic logic [ELEN-1:0] sign_ext(input logic [ELEN-1:0] v, input int w);
    logic [ELEN-1:0] t;
    begin
      t = v & mask_w(w);
      sign_ext = t[w-1] ? (t | ~mask_w(w)) : t;
    end
  endfunction

  // One compare bit
  function automatic logic ref_cmp_bit(input vec_op_e o, input logic [ELEN-1:0] a,
                                       input logic [ELEN-1:0] b, input int w);
    logic signed [ELEN:0] sa;
    logic signed [ELEN:0] sb;
    logic        [ELEN:0] ua;
    logic        [ELEN:0] ub;
    begin
      sa = 33'($signed(sign_ext(a, w)));
      sb = 33'($signed(sign_ext(b, w)));
      ua = {1'b0, a & mask_w(w)};
      ub = {1'b0, b & mask_w(w)};
      case (o)
        VEC_MSEQ:  ref_cmp_bit = (ua == ub);
        VEC_MSNE:  ref_cmp_bit = (ua != ub);
        VEC_MSLTU: ref_cmp_bit = (ua < ub);
        VEC_MSLEU: ref_cmp_bit = (ua <= ub);
        VEC_MSGTU: ref_cmp_bit = (ua > ub);
        VEC_MSLT:  ref_cmp_bit = (sa < sb);
        VEC_MSLE:  ref_cmp_bit = (sa <= sb);
        VEC_MSGT:  ref_cmp_bit = (sa > sb);
        default:   ref_cmp_bit = 1'b0;
      endcase
    end
  endfunction

  function automatic logic [5:0] cmp_funct6(input vec_op_e o);
    case (o)
      VEC_MSEQ:  cmp_funct6 = 6'b011000;
      VEC_MSNE:  cmp_funct6 = 6'b011001;
      VEC_MSLTU: cmp_funct6 = 6'b011010;
      VEC_MSLT:  cmp_funct6 = 6'b011011;
      VEC_MSLEU: cmp_funct6 = 6'b011100;
      VEC_MSLE:  cmp_funct6 = 6'b011101;
      VEC_MSGTU: cmp_funct6 = 6'b011110;
      default:   cmp_funct6 = 6'b011111;
    endcase
  endfunction

  // Run one compare
  task automatic run_cmp(input vec_op_e o, input int form, input logic [AWIDTH-1:0] s1,
                         input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d, input logic vmb,
                         input logic [XLEN-1:0] xd, input logic [AWIDTH-1:0] im,
                         input logic [2:0] sew, input logic [2:0] lmul, input logic [VlW-1:0] len);
    int w;
    logic [ELEN-1:0] b;
    logic [2:0] f3;
    logic [AWIDTH-1:0] f2;
    begin
      vsew  = sew;
      vlmul = lmul;
      vl    = len;
      xdata = xd;
      w     = 8 << sew;
      for (int i = 0; i < int'(len); i++) begin
        if (vmb || mbit(AWIDTH'(0), i)) begin
          if (form == 0) b = grp_get(s1, w, i);
          else if (form == 2) b = ELEN'($signed(im));
          else b = xd;
          shadow[d][i] = ref_cmp_bit(o, grp_get(s2, w, i), b, w);
        end
      end
      case (form)
        0:       f3 = 3'b000;
        1:       f3 = 3'b100;
        default: f3 = 3'b011;
      endcase
      case (form)
        0:       f2 = s1;
        1:       f2 = AWIDTH'(1);
        default: f2 = im;
      endcase
      issue(enc(cmp_funct6(o), vmb, s2, f2, f3, d));
      drain();
      check_regs($sformatf(
                 "cmp op=%0d form=%0d sew=%0d lmul=%0d len=%0d vm=%0b", o, form, sew, lmul, len, vmb
                 ));
    end
  endtask  // Automatic

  // Every compare shape
  task automatic check_compares();
    vec_op_e list[8];
    vec_op_e o;
    int form;
    logic [2:0] sew;
    logic [2:0] lmul;
    logic [VlW-1:0] len;
    logic vmb;
    begin
      list = '{VEC_MSEQ, VEC_MSNE, VEC_MSLTU, VEC_MSLT, VEC_MSLEU, VEC_MSLE, VEC_MSGTU, VEC_MSGT};
      seed_all();
      for (int i = 0; i < 8; i++) begin
        run_cmp(list[i], (i >= 6) ? 1 : 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(20), 1'b1, XLEN'('h5),
                AWIDTH'(5), 3'd0, 3'd0, VlW'(8));
        run_cmp(list[i], ((i == 2) || (i == 3)) ? 1 : 2, AWIDTH'(4), AWIDTH'(8), AWIDTH'(20), 1'b1,
                XLEN'('h5), AWIDTH'(5), 3'd1, 3'd0, VlW'(4));
      end
      for (int i = 0; i < 8; i++) begin
        for (int k = 0; k < 8; k++) begin
          o = list[i];
          if ((o == VEC_MSGTU) || (o == VEC_MSGT)) form = 1 + int'(1'($urandom));
          else if ((o == VEC_MSLTU) || (o == VEC_MSLT)) form = int'(1'($urandom));
          else form = int'($urandom_range(2));
          sew  = 3'($urandom_range(2));
          lmul = 3'($urandom_range(2));
          len  = VlW'($urandom_range((VLEN >> (3 + sew)) << lmul));
          vmb  = 1'($urandom);
          run_cmp(o, form, AWIDTH'(4), AWIDTH'(8), AWIDTH'(20), vmb, XLEN'($urandom),
                  AWIDTH'($urandom), sew, lmul, len);
        end
      end
      run_cmp(VEC_MSEQ, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(20), 1'b1, '0, AWIDTH'(0), 3'd0, 3'd0,
              VlW'(0));
      run_cmp(VEC_MSLT, 0, AWIDTH'(4), AWIDTH'(4), AWIDTH'(20), 1'b1, '0, AWIDTH'(0), 3'd2, 3'd0,
              VlW'(4));
      run_cmp(VEC_MSEQ, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(4), 1'b1, '0, AWIDTH'(0), 3'd0, 3'd0,
              VlW'(16));
    end
  endtask  // Automatic

  // Carry borrow out
  function automatic logic ref_carry_bit(input vec_op_e o, input logic [ELEN-1:0] a,
                                         input logic [ELEN-1:0] b, input logic cin, input int w);
    logic [ELEN-1:0] ma;
    logic [ELEN-1:0] mb;
    longint ua;
    longint ub;
    begin
      ma = a & mask_w(w);
      mb = b & mask_w(w);
      ua = longint'(ma);
      ub = longint'(mb);
      if (o == VEC_MADC) ref_carry_bit = (ua + ub + longint'(cin)) >= (longint'(1) << w);
      else ref_carry_bit = ua < (ub + longint'(cin));
    end
  endfunction

  // One carry compare
  task automatic run_carry(input vec_op_e o, input int form, input logic [AWIDTH-1:0] s1,
                           input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d, input logic vmb,
                           input logic [XLEN-1:0] xd, input logic [AWIDTH-1:0] im,
                           input logic [2:0] sew, input logic [2:0] lmul,
                           input logic [VlW-1:0] len);
    int w;
    logic [ELEN-1:0] b;
    logic [VLEN-1:0] cin;
    logic [2:0] f3;
    logic [AWIDTH-1:0] f2;
    begin
      vsew  = sew;
      vlmul = lmul;
      vl    = len;
      xdata = xd;
      w     = 8 << sew;
      cin   = vmb ? '0 : shadow[0];
      for (int i = 0; i < int'(len); i++) begin
        if (form == 0) b = grp_get(s1, w, i);
        else if (form == 2) b = ELEN'($signed(im));
        else b = xd;
        shadow[d][i] = ref_carry_bit(o, grp_get(s2, w, i), b, cin[i], w);
      end
      case (form)
        0:       f3 = 3'b000;
        1:       f3 = 3'b100;
        default: f3 = 3'b011;
      endcase
      case (form)
        0:       f2 = s1;
        1:       f2 = AWIDTH'(1);
        default: f2 = im;
      endcase
      issue(enc((o == VEC_MADC) ? 6'b010001 : 6'b010011, vmb, s2, f2, f3, d));
      drain();
      check_regs(
          $sformatf(
          "carry op=%0d form=%0d sew=%0d lmul=%0d len=%0d vm=%0b", o, form, sew, lmul, len, vmb));
    end
  endtask  // Automatic

  // Every carry shape
  task automatic check_carry();
    vec_op_e o;
    int form;
    logic [2:0] sew;
    logic [2:0] lmul;
    logic [VlW-1:0] len;
    logic [AWIDTH-1:0] d;
    begin
      seed_all();
      for (int k = 0; k < 2; k++) begin
        o = vec_op_e'((k == 0) ? VEC_MADC : VEC_MSBC);
        for (int f = 0; f < 3; f++) begin
          if ((o == VEC_MSBC) && (f == 2)) continue;
          for (int s = 0; s < 3; s++) begin
            for (int m = 0; m < 2; m++) begin
              run_carry(o, f, AWIDTH'(4), AWIDTH'(8), AWIDTH'(20), 1'(m), XLEN'($urandom),
                        AWIDTH'($urandom), 3'(s), 3'd0, VlW'(VLEN >> (3 + s)));
            end
          end
        end
      end
      for (int k = 0; k < 40; k++) begin
        o    = vec_op_e'((k % 2 == 0) ? VEC_MADC : VEC_MSBC);
        form = (o == VEC_MADC) ? int'($urandom_range(2)) : int'(1'($urandom));
        sew  = 3'($urandom_range(2));
        lmul = 3'($urandom_range(3));
        len  = VlW'($urandom_range((VLEN >> (3 + sew)) << lmul));
        run_carry(o, form, AWIDTH'(8), AWIDTH'(16), AWIDTH'(24), 1'($urandom), XLEN'($urandom),
                  AWIDTH'($urandom), sew, lmul, len);
      end

      // Carry ripples out
      seed_reg(AWIDTH'(0), '1);
      seed_reg(AWIDTH'(4), '1);
      seed_reg(AWIDTH'(8), '0);
      for (int s = 0; s < 3; s++) begin
        run_carry(VEC_MADC, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(20), 1'b0, '0, AWIDTH'(0), 3'(s),
                  3'd0, VlW'(4));
        run_carry(VEC_MADC, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(21), 1'b1, '0, AWIDTH'(0), 3'(s),
                  3'd0, VlW'(4));
        run_carry(VEC_MSBC, 0, AWIDTH'(8), AWIDTH'(8), AWIDTH'(22), 1'b0, '0, AWIDTH'(0), 3'(s),
                  3'd0, VlW'(4));
        run_carry(VEC_MSBC, 0, AWIDTH'(8), AWIDTH'(8), AWIDTH'(23), 1'b1, '0, AWIDTH'(0), 3'(s),
                  3'd0, VlW'(4));
        run_carry(VEC_MADC, 2, AWIDTH'(0), AWIDTH'(4), AWIDTH'(24), 1'b1, '0, AWIDTH'(1), 3'(s),
                  3'd0, VlW'(4));
      end

      // Destination is v0
      seed_all();
      for (int s = 0; s < 3; s++) begin
        d = AWIDTH'(0);
        run_carry(VEC_MADC, 0, AWIDTH'(4), AWIDTH'(8), d, 1'b0, '0, AWIDTH'(0), 3'(s), 3'd1,
                  VlW'((VLEN >> (3 + s)) << 1));
        run_carry(VEC_MSBC, 1, AWIDTH'(4), AWIDTH'(8), d, 1'b0, XLEN'($urandom), AWIDTH'(0), 3'(s),
                  3'd0, VlW'(3));
      end

      // Destination overlaps source
      run_carry(VEC_MADC, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(8), 1'b0, '0, AWIDTH'(0), 3'd2, 3'd1,
                VlW'(8));
      run_carry(VEC_MSBC, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(4), 1'b0, '0, AWIDTH'(0), 3'd0, 3'd0,
                VlW'(16));
      run_carry(VEC_MADC, 1, AWIDTH'(4), AWIDTH'(8), AWIDTH'(20), 1'b0, '0, AWIDTH'(0), 3'd0, 3'd0,
                VlW'(0));
    end
  endtask  // Automatic

  // One logic form
  task automatic run_mlogic(input logic [5:0] f6, input logic [AWIDTH-1:0] s1,
                            input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d,
                            input logic [VlW-1:0] len);
    logic a;
    logic b;
    begin
      vsew  = 3'd0;
      vlmul = 3'd0;
      vl    = len;
      for (int i = 0; i < int'(len); i++) begin
        a = mbit(s2, i);
        b = mbit(s1, i);
        case (f6)
          6'b011001: shadow[d][i] = a & b;
          6'b011101: shadow[d][i] = ~(a & b);
          6'b011000: shadow[d][i] = a & ~b;
          6'b011010: shadow[d][i] = a | b;
          6'b011110: shadow[d][i] = ~(a | b);
          6'b011100: shadow[d][i] = a | ~b;
          6'b011011: shadow[d][i] = a ^ b;
          default:   shadow[d][i] = ~(a ^ b);
        endcase
      end
      issue(enc(f6, 1'b1, s2, s1, 3'b010, d));
      drain();
      check_regs("mask logic");
    end
  endtask  // Automatic

  // Every logic shape
  task automatic check_mask_logic();
    logic [5:0] list[8];
    begin
      list = '{
          6'b011001,
          6'b011101,
          6'b011000,
          6'b011010,
          6'b011110,
          6'b011100,
          6'b011011,
          6'b011111
      };
      seed_all();
      for (int i = 0; i < 8; i++) begin
        run_mlogic(list[i], AWIDTH'(3), AWIDTH'(9), AWIDTH'(21), VlW'(1 + ($urandom_range(VLEN - 1
                   ))));
      end
      run_mlogic(6'b011001, AWIDTH'(3), AWIDTH'(9), AWIDTH'(21), VlW'(0));
      run_mlogic(6'b011010, AWIDTH'(3), AWIDTH'(3), AWIDTH'(3), VlW'(128));
    end
  endtask  // Automatic

  // First set bit
  function automatic int ref_first_bit(input logic [AWIDTH-1:0] s2, input logic vmb,
                                       input logic [VlW-1:0] len);
    begin
      ref_first_bit = -1;
      for (int i = int'(len) - 1; i >= 0; i--) begin
        if ((vmb || mbit(AWIDTH'(0), i)) && mbit(s2, i)) ref_first_bit = i;
      end
    end
  endfunction

  // One set form
  task automatic run_mset(input logic [AWIDTH-1:0] sel, input logic [AWIDTH-1:0] s2,
                          input logic [AWIDTH-1:0] d, input logic vmb, input logic [VlW-1:0] len);
    int   f;
    logic want;
    begin
      vsew  = 3'd0;
      vlmul = 3'd0;
      vl    = len;
      f     = ref_first_bit(s2, vmb, len);
      for (int i = 0; i < int'(len); i++) begin
        if (vmb || mbit(AWIDTH'(0), i)) begin
          case (sel)
            5'b00001: want = (f < 0) ? 1'b1 : (i < f);
            5'b00011: want = (f < 0) ? 1'b1 : (i <= f);
            default:  want = (f >= 0) && (i == f);
          endcase
          shadow[d][i] = want;
        end
      end
      issue(enc(6'b010100, vmb, s2, sel, 3'b010, d));
      drain();
      check_regs("mask set");
    end
  endtask  // Automatic

  // Every set shape
  task automatic check_mask_set();
    begin
      seed_all();
      for (int k = 0; k < 12; k++) begin
        run_mset(5'b00001, AWIDTH'(5), AWIDTH'(22), 1'($urandom), VlW'($urandom_range(VLEN)));
        run_mset(5'b00011, AWIDTH'(5), AWIDTH'(23), 1'($urandom), VlW'($urandom_range(VLEN)));
        run_mset(5'b00010, AWIDTH'(5), AWIDTH'(24), 1'($urandom), VlW'($urandom_range(VLEN)));
      end
      seed_reg(AWIDTH'(5), '0);
      run_mset(5'b00001, AWIDTH'(5), AWIDTH'(22), 1'b1, VlW'(64));
      run_mset(5'b00011, AWIDTH'(5), AWIDTH'(23), 1'b1, VlW'(64));
      run_mset(5'b00010, AWIDTH'(5), AWIDTH'(24), 1'b1, VlW'(64));
    end
  endtask  // Automatic

  // One index form
  task automatic run_index(input logic is_id, input logic [AWIDTH-1:0] s2,
                           input logic [AWIDTH-1:0] d, input logic vmb, input logic [2:0] sew,
                           input logic [2:0] lmul, input logic [VlW-1:0] len);
    int w;
    int count;
    begin
      vsew  = sew;
      vlmul = lmul;
      vl    = len;
      w     = 8 << sew;
      count = 0;
      for (int i = 0; i < int'(len); i++) begin
        if (vmb || mbit(AWIDTH'(0), i)) grp_set(d, w, i, is_id ? XLEN'(i) : XLEN'(count));
        if (!is_id && (vmb || mbit(AWIDTH'(0), i)) && mbit(s2, i)) count = count + 1;
      end
      issue(enc(6'b010100, vmb, is_id ? AWIDTH'(0) : s2, is_id ? 5'b10001 : 5'b10000, 3'b010, d));
      drain();
      check_regs("mask index");
    end
  endtask  // Automatic

  // Every index shape
  task automatic check_mask_index();
    logic [2:0] sew;
    logic [2:0] lmul;
    logic [VlW-1:0] len;
    begin
      seed_all();
      for (int k = 0; k < 10; k++) begin
        sew  = 3'($urandom_range(2));
        lmul = 3'($urandom_range(2));
        len  = VlW'($urandom_range((VLEN >> (3 + sew)) << lmul));
        run_index(1'b0, AWIDTH'(6), AWIDTH'(16), 1'($urandom), sew, lmul, len);
        run_index(1'b1, AWIDTH'(0), AWIDTH'(24), 1'($urandom), sew, lmul, len);
      end
      run_index(1'b0, AWIDTH'(6), AWIDTH'(16), 1'b1, 3'd0, 3'd0, VlW'(0));
      run_index(1'b1, AWIDTH'(0), AWIDTH'(24), 1'b1, 3'd2, 3'd2, VlW'(16));
    end
  endtask  // Automatic

  // Mask unary traps
  task automatic check_mask_unary_rules();
    logic [AWIDTH-1:0] sel[3];
    begin
      sel   = '{5'b00001, 5'b00011, 5'b00010};
      vill  = 1'b0;
      vsew  = 3'd0;
      vlmul = 3'd0;
      vl    = VlW'(4);
      for (int k = 0; k < 3; k++) begin
        instr = enc(6'b010100, 1'b1, AWIDTH'(5), sel[k], 3'b010, AWIDTH'(5));
        @(negedge clk);
        check($sformatf("mask set %0d over source", k), XLEN'(is_vector), XLEN'(0));
        instr = enc(6'b010100, 1'b0, AWIDTH'(5), sel[k], 3'b010, AWIDTH'(0));
        @(negedge clk);
        check($sformatf("masked mask set %0d into v0", k), XLEN'(is_vector), XLEN'(0));
        instr = enc(6'b010100, 1'b1, AWIDTH'(5), sel[k], 3'b010, AWIDTH'(0));
        @(negedge clk);
        check($sformatf("unmasked mask set %0d into v0", k), XLEN'(is_vector), XLEN'(1));
        instr = enc(6'b010100, 1'b0, AWIDTH'(0), sel[k], 3'b010, AWIDTH'(6));
        @(negedge clk);
        check($sformatf("masked mask set %0d from v0", k), XLEN'(is_vector), XLEN'(1));
      end
      vlmul = 3'd2;
      instr = enc(6'b010100, 1'b1, AWIDTH'(8), 5'b10000, 3'b010, AWIDTH'(8));
      @(negedge clk);
      check("viota over group base", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010100, 1'b1, AWIDTH'(11), 5'b10000, 3'b010, AWIDTH'(8));
      @(negedge clk);
      check("viota over group top", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010100, 1'b1, AWIDTH'(12), 5'b10000, 3'b010, AWIDTH'(8));
      @(negedge clk);
      check("viota above group", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b010100, 1'b1, AWIDTH'(7), 5'b10000, 3'b010, AWIDTH'(8));
      @(negedge clk);
      check("viota below group", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b010100, 1'b0, AWIDTH'(4), 5'b10000, 3'b010, AWIDTH'(0));
      @(negedge clk);
      check("masked viota into v0", XLEN'(is_vector), XLEN'(0));
      vlmul = 3'd7;
      instr = enc(6'b010100, 1'b1, AWIDTH'(8), 5'b10000, 3'b010, AWIDTH'(8));
      @(negedge clk);
      check("fractional viota over source", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010100, 1'b1, AWIDTH'(9), 5'b10000, 3'b010, AWIDTH'(8));
      @(negedge clk);
      check("fractional viota apart", XLEN'(is_vector), XLEN'(1));
      vlmul = 3'd0;
      instr = enc(6'b010100, 1'b1, AWIDTH'(0), 5'b10001, 3'b010, AWIDTH'(8));
      @(negedge clk);
      check("vid without source", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b010100, 1'b1, AWIDTH'(3), 5'b10001, 3'b010, AWIDTH'(8));
      @(negedge clk);
      check("vid with source", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010100, 1'b0, AWIDTH'(16), 5'b10001, 3'b010, AWIDTH'(8));
      @(negedge clk);
      check("masked vid with source", XLEN'(is_vector), XLEN'(0));
      instr = '0;
      vlmul = 3'd0;
    end
  endtask  // Automatic

  // One summary form
  task automatic run_msum(input logic is_pop, input logic [AWIDTH-1:0] s2, input logic vmb,
                          input logic [VlW-1:0] len);
    int count;
    logic [ELEN-1:0] want;
    begin
      vsew  = 3'd0;
      vlmul = 3'd0;
      vl    = len;
      count = 0;
      for (int i = 0; i < int'(len); i++) begin
        if ((vmb || mbit(AWIDTH'(0), i)) && mbit(s2, i)) count = count + 1;
      end
      want = is_pop ? XLEN'(count) : ((ref_first_bit(s2, vmb, len) < 0) ? XLEN'('hFFFF_FFFF) :
                                      XLEN'(ref_first_bit(s2, vmb, len)));
      issue(enc(6'b010000, vmb, s2, is_pop ? 5'b10000 : 5'b10001, 3'b010, AWIDTH'(7)));
      drain();
      check("mask summary", XLEN'(xreg_result), XLEN'(want));
      check_regs("mask summary");
    end
  endtask  // Automatic

  // Every summary shape
  task automatic check_mask_scalar();
    begin
      seed_all();
      for (int k = 0; k < 14; k++) begin
        run_msum(1'b1, AWIDTH'(7), 1'($urandom), VlW'($urandom_range(VLEN)));
        run_msum(1'b0, AWIDTH'(7), 1'($urandom), VlW'($urandom_range(VLEN)));
      end
      seed_reg(AWIDTH'(7), '0);
      run_msum(1'b1, AWIDTH'(7), 1'b1, VlW'(128));
      run_msum(1'b0, AWIDTH'(7), 1'b1, VlW'(128));
    end
  endtask  // Automatic

  // Rounding increment model
  function automatic longint ref_round(input longint v, input int d, input logic [1:0] mode);
    if (d == 0) return 0;
    case (mode)
      2'd0: return longint'(v[d-1]);
      2'd1: begin
        return longint'(v[d-1] && (((d > 1) && ((v & ((64'sd1 <<< (d - 1)) - 1)) != 0)) || v[d]));
      end
      2'd2: return 0;
      default: return longint'(!v[d] && ((v & ((64'sd1 <<< d) - 1)) != 0));
    endcase
  endfunction

  // Lane element model
  function automatic logic [ELEN:0] ref_lane(input vec_op_e o, input int w,
                                             input logic [ELEN-1:0] a, input logic [ELEN-1:0] b,
                                             input logic [ELEN-1:0] c, input logic [1:0] mode);
    longint m, ua, ub, uc, sa, sb, ua2, sa2, v, smax, smin, umax;
    longint unsigned uu;
    int sh, sh2;
    logic sat;
    begin
      m    = (64'sd1 <<< w) - 1;
      ua   = longint'(a) & m;
      ub   = longint'(b) & m;
      uc   = longint'(c) & m;
      sa   = ua[w-1] ? (ua - (64'sd1 <<< w)) : ua;
      sb   = ub[w-1] ? (ub - (64'sd1 <<< w)) : ub;
      ua2  = longint'(a) & ((64'sd1 <<< (2 * w)) - 1);
      sa2  = ua2[2*w-1] ? (ua2 - (64'sd1 <<< (2 * w))) : ua2;
      smax = (64'sd1 <<< (w - 1)) - 1;
      smin = -(64'sd1 <<< (w - 1));
      umax = m;
      sh   = int'(b) & (w - 1);
      sh2  = int'(b) & (2 * w - 1);
      sat  = 1'b0;
      case (o)
        VEC_MUL: v = sa * sb;
        VEC_MULH: v = (sa * sb) >>> w;
        VEC_MULHU: begin
          uu = longint'(ua) * longint'(ub);
          v  = longint'(uu >> w);
        end
        VEC_MULHSU: v = (sa * ub) >>> w;
        VEC_MACC: v = (ua * ub) + uc;
        VEC_NMSAC: v = uc - (ua * ub);
        VEC_MADD: v = (uc * ub) + ua;
        VEC_NMSUB: v = ua - (uc * ub);
        VEC_SADDU: begin
          v = ua + ub;
          if (v > umax) begin
            sat = 1'b1;
            v   = umax;
          end
        end
        VEC_SSUBU: begin
          v = ua - ub;
          if (v < 0) begin
            sat = 1'b1;
            v   = 0;
          end
        end
        VEC_SADD, VEC_SSUB, VEC_SMUL, VEC_NCLIP: begin
          case (o)
            VEC_SADD: v = sa + sb;
            VEC_SSUB: v = sa - sb;
            VEC_SMUL: v = ((sa * sb) >>> (w - 1)) + ref_round(sa * sb, w - 1, mode);
            default:  v = (sa2 >>> sh2) + ref_round(sa2, sh2, mode);
          endcase
          if (v > smax) begin
            sat = 1'b1;
            v   = smax;
          end else if (v < smin) begin
            sat = 1'b1;
            v   = smin;
          end
        end
        VEC_SSRL: v = (ua >> sh) + ref_round(ua, sh, mode);
        VEC_SSRA: v = (sa >>> sh) + ref_round(sa, sh, mode);
        VEC_NCLIPU: begin
          v = (ua2 >> sh2) + ref_round(ua2, sh2, mode);
          if (v > umax) begin
            sat = 1'b1;
            v   = umax;
          end
        end
        VEC_AADDU: v = ((ua + ub) >>> 1) + ref_round(ua + ub, 1, mode);
        VEC_AADD: v = ((sa + sb) >>> 1) + ref_round(sa + sb, 1, mode);
        VEC_ASUBU: v = ((ua - ub) >>> 1) + ref_round(ua - ub, 1, mode);
        VEC_ASUB: v = ((sa - sb) >>> 1) + ref_round(sa - sb, 1, mode);
        VEC_DIVU: v = (ub == 0) ? umax : (ua / ub);
        VEC_REMU: v = (ub == 0) ? ua : (ua % ub);
        VEC_DIV: begin
          if (sb == 0) v = -1;
          else if ((sa == smin) && (sb == -1)) v = smin;
          else v = sa / sb;
        end
        VEC_REM: begin
          if (sb == 0) v = sa;
          else if ((sa == smin) && (sb == -1)) v = 0;
          else v = sa % sb;
        end
        default: v = 0;
      endcase
      return {sat, ELEN'(v & m)};
    end
  endfunction

  function automatic logic [5:0] lane_funct6(input vec_op_e o);
    case (o)
      VEC_MULHU:  return 6'b100100;
      VEC_MUL:    return 6'b100101;
      VEC_MULHSU: return 6'b100110;
      VEC_MULH:   return 6'b100111;
      VEC_MADD:   return 6'b101001;
      VEC_NMSUB:  return 6'b101011;
      VEC_MACC:   return 6'b101101;
      VEC_NMSAC:  return 6'b101111;
      VEC_SADDU:  return 6'b100000;
      VEC_SADD:   return 6'b100001;
      VEC_SSUBU:  return 6'b100010;
      VEC_SSUB:   return 6'b100011;
      VEC_SMUL:   return 6'b100111;
      VEC_SSRL:   return 6'b101010;
      VEC_SSRA:   return 6'b101011;
      VEC_NCLIPU: return 6'b101110;
      VEC_DIVU:   return 6'b100000;
      VEC_DIV:    return 6'b100001;
      VEC_REMU:   return 6'b100010;
      VEC_REM:    return 6'b100011;
      VEC_AADDU:  return 6'b001000;
      VEC_AADD:   return 6'b001001;
      VEC_ASUBU:  return 6'b001010;
      VEC_ASUB:   return 6'b001011;
      default:    return 6'b101111;
    endcase
  endfunction

  function automatic logic avg_form(input vec_op_e o);
    return (o == VEC_AADDU) || (o == VEC_AADD) || (o == VEC_ASUBU) || (o == VEC_ASUB);
  endfunction

  // Encode lane op
  function automatic logic [31:0] lane_instr(
      input vec_op_e o, input int form, input logic [AWIDTH-1:0] s1, input logic [AWIDTH-1:0] s2,
      input logic [AWIDTH-1:0] d, input logic vmb, input logic [AWIDTH-1:0] im);
    logic opm;
    logic [2:0] f3;
    logic [AWIDTH-1:0] f2;
    begin
      opm = (vec_class(o) == VEC_CLS_MUL) || avg_form(o);
      case (form)
        0: f3 = opm ? 3'b010 : 3'b000;
        1: f3 = opm ? 3'b110 : 3'b100;
        default: f3 = 3'b011;
      endcase
      case (form)
        0: f2 = s1;
        1: f2 = AWIDTH'(1);
        default: f2 = im;
      endcase
      return enc(lane_funct6(o), vmb, s2, f2, f3, d);
    end
  endfunction

  // Lane op model
  task automatic model_lane(input vec_op_e o, input int form, input logic [AWIDTH-1:0] s1,
                            input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d,
                            input logic vmb, input logic [XLEN-1:0] xd, input logic [AWIDTH-1:0] im,
                            input int w, input int regs, input logic [VlW-1:0] len,
                            input logic [1:0] mode, output logic want_sat);
    logic narrow;
    logic uimm;
    logic sat;
    logic [ELEN-1:0] a;
    logic [ELEN-1:0] b;
    logic [ELEN-1:0] r;
    begin
      narrow = (o == VEC_NCLIPU) || (o == VEC_NCLIP);
      uimm = narrow || (o == VEC_SSRL) || (o == VEC_SSRA);
      want_sat = 1'b0;
      for (int i = 0; i < group_elems(w, regs); i++) begin
        if ((i < len) && (vmb || shadow[0][i])) begin
          a = narrow ? grp_get(s2, 2 * w, i) : grp_get(s2, w, i);
          case (form)
            0: b = grp_get(s1, w, i);
            1: b = xd;
            default: b = uimm ? ELEN'(im) : ELEN'($signed(im));
          endcase
          {sat, r} = ref_lane(o, w, a, b, grp_get(d, w, i), mode);
          grp_set(d, w, i, r);
          want_sat = want_sat || sat;
        end
      end
    end
  endtask  // Automatic

  task automatic run_lane(input vec_op_e o, input int form, input logic [AWIDTH-1:0] s1,
                          input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d, input logic vmb,
                          input logic [XLEN-1:0] xd, input logic [AWIDTH-1:0] im,
                          input logic [2:0] sew, input logic [2:0] lmul, input logic [VlW-1:0] len,
                          input logic [1:0] mode);
    logic want_sat;
    int   w;
    int   regs;
    begin
      w = 8 << sew;
      regs = lmul[2] ? 1 : (1 << lmul[1:0]);
      csr_poke(VxrmAddr, XLEN'(mode));
      csr_poke(VxsatAddr, '0);
      vsew = sew;
      vlmul = lmul;
      vl = len;
      xdata = xd;
      model_lane(o, form, s1, s2, d, vmb, xd, im, w, regs, len, mode, want_sat);
      issue(lane_instr(o, form, s1, s2, d, vmb, im));
      drain();
      check_regs($sformatf("lane %0s sew %0d form %0d", o.name(), w, form));
      check($sformatf("vxsat after %0s", o.name()), XLEN'(vxsat), XLEN'(want_sat));
    end
  endtask  // Automatic

  // Most negative elements
  function automatic logic [VLEN-1:0] min_vec(input int w);
    min_vec = '0;
    for (int e = 0; e < VLEN / w; e++) min_vec[e*w+w-1] = 1'b1;
  endfunction

  // Widening multiply model
  function automatic logic [ELEN-1:0] ref_wmul(input vec_op_e o, input int w,
                                               input logic [ELEN-1:0] a, input logic [ELEN-1:0] b,
                                               input logic [ELEN-1:0] c);
    longint m, ua, ub, sa, sb, v;
    begin
      m  = (64'sd1 <<< w) - 1;
      ua = longint'(a) & m;
      ub = longint'(b) & m;
      sa = ua[w-1] ? (ua - (64'sd1 <<< w)) : ua;
      sb = ub[w-1] ? (ub - (64'sd1 <<< w)) : ub;
      case (o)
        VEC_WMULU:   v = ua * ub;
        VEC_WMULSU:  v = sa * ub;
        VEC_WMUL:    v = sa * sb;
        VEC_WMACCU:  v = (ua * ub) + longint'(c);
        VEC_WMACC:   v = (sa * sb) + longint'(c);
        VEC_WMACCSU: v = (ua * sb) + longint'(c);
        VEC_WMACCUS: v = (sa * ub) + longint'(c);
        default:     v = 0;
      endcase
      return ELEN'(v & ((64'sd1 <<< (2 * w)) - 1));
    end
  endfunction

  function automatic logic [5:0] wmul_funct6(input vec_op_e o);
    case (o)
      VEC_WMULU:   return 6'b111000;
      VEC_WMULSU:  return 6'b111010;
      VEC_WMUL:    return 6'b111011;
      VEC_WMACCU:  return 6'b111100;
      VEC_WMACC:   return 6'b111101;
      VEC_WMACCUS: return 6'b111110;
      default:     return 6'b111111;
    endcase
  endfunction

  task automatic run_wmul(input vec_op_e o, input int form, input logic [AWIDTH-1:0] s1,
                          input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d, input logic vmb,
                          input logic [XLEN-1:0] xd, input logic [2:0] sew, input logic [2:0] lmul,
                          input logic [VlW-1:0] len);
    int w;
    int regs;
    logic [ELEN-1:0] b;
    begin
      w = 8 << sew;
      regs = lmul[2] ? 1 : (1 << lmul[1:0]);
      vsew = sew;
      vlmul = lmul;
      vl = len;
      xdata = xd;
      for (int i = 0; i < group_elems(w, regs); i++) begin
        if ((i < int'(len)) && (vmb || shadow[0][i])) begin
          b = (form == 0) ? grp_get(s1, w, i) : xd;
          grp_set(d, 2 * w, i, ref_wmul(o, w, grp_get(s2, w, i), b, grp_get(d, 2 * w, i)));
        end
      end
      issue(enc(
            wmul_funct6(o), vmb, s2, (form == 0) ? s1 : AWIDTH'(1), (form == 0) ? 3'b010 : 3'b110, d
            ));
      drain();
      check_regs($sformatf("wmul %0s sew %0d form %0d", o.name(), w, form));
    end
  endtask  // Automatic

  task automatic check_widening_muls();
    vec_op_e ops[7] = '{
        VEC_WMULU,
        VEC_WMULSU,
        VEC_WMUL,
        VEC_WMACCU,
        VEC_WMACC,
        VEC_WMACCSU,
        VEC_WMACCUS
    };
    seed_all();
    for (int k = 0; k < 7; k++) begin
      for (int s = 0; s < 2; s++) begin
        if (ops[k] != VEC_WMACCUS)
          run_wmul(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(16), 1'b1, '0, 3'(s), 3'd0,
                   VlW'(VLEN / (8 << s)));
        run_wmul(ops[k], 1, AWIDTH'(0), AWIDTH'(8), AWIDTH'(18), 1'b1, XLEN'($urandom), 3'(s), 3'd0,
                 VlW'(VLEN / (8 << s)));
        run_wmul(ops[k], 1, AWIDTH'(0), AWIDTH'(8), AWIDTH'(20), 1'b0, XLEN'($urandom), 3'(s), 3'd1,
                 VlW'(2 * VLEN / (8 << s)));
      end
      if (ops[k] != VEC_WMACCUS) begin
        run_wmul(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(24), 1'b1, '0, 3'd0, 3'd1, VlW'(32));
        run_wmul(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(16), 1'b0, '0, 3'd1, 3'd0, VlW'(8));
        run_wmul(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(16), 1'b1, '0, 3'd0, 3'd0, VlW'(5));
      end
    end
    // Carries past SEW
    seed_reg(AWIDTH'(4), '1);
    seed_reg(AWIDTH'(8), '1);
    seed_reg(AWIDTH'(16), {(VLEN / 16) {16'h00ff}});
    seed_reg(AWIDTH'(17), {(VLEN / 16) {16'h00ff}});
    run_wmul(VEC_WMACCU, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(16), 1'b1, '0, 3'd0, 3'd0, VlW'(16));
    run_wmul(VEC_WMACCU, 1, AWIDTH'(0), AWIDTH'(8), AWIDTH'(16), 1'b1, XLEN'('hff), 3'd0, 3'd0,
             VlW'(16));
    seed_reg(AWIDTH'(16), {(VLEN / ELEN) {ELEN'('h0000_ffff)}});
    seed_reg(AWIDTH'(17), {(VLEN / ELEN) {ELEN'('h0000_ffff)}});
    run_wmul(VEC_WMACCU, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(16), 1'b1, '0, 3'd1, 3'd0, VlW'(8));
    run_wmul(VEC_WMACC, 1, AWIDTH'(0), AWIDTH'(8), AWIDTH'(16), 1'b1, XLEN'('h8000), 3'd1, 3'd0,
             VlW'(8));
    seed_all();
  endtask  // Automatic

  // Slide model
  task automatic ref_slide(input logic up, input int form, input logic [AWIDTH-1:0] s2,
                           input logic [AWIDTH-1:0] d, input logic vmb, input logic [XLEN-1:0] sc,
                           input logic [2:0] sew, input logic [2:0] lmul, input int len);
    logic [VLEN-1:0] src[Depth];
    int w;
    int per_reg;
    int vlmax;
    longint amt;
    longint from;
    logic [ELEN-1:0] val;
    begin
      w = 8 << sew;
      per_reg = VLEN / w;
      vlmax = lmul[2] ? (per_reg >> (3'd0 - lmul)) : (per_reg << lmul);
      if (form == 1) amt = longint'(sc[AWIDTH-1:0]);
      else if (form >= 2) amt = 1;
      else amt = longint'({XLEN'(0), sc});
      for (int r = 0; r < Depth; r++) src[r] = shadow[r];
      for (int i = 0; i < len; i++) begin
        if (!(vmb || src[0][i])) continue;
        if (up && (form >= 2) && (i == 0)) val = ELEN'(sc);
        else if (!up && (form >= 2) && (i == len - 1)) val = ELEN'(sc);
        else if (up && (longint'(i) < amt)) continue;
        else begin
          from = up ? (longint'(i) - amt) : (longint'(i) + amt);
          if (from >= longint'(vlmax)) val = '0;
          else val = get_elem(src[(XLEN'(s2)+XLEN'(from)/per_reg)%Depth], w, XLEN'(from) % per_reg);
        end
        grp_set(d, w, i, val);
      end
    end
  endtask  // Automatic

  function automatic logic [31:0] slide_instr(
      input logic up, input int form, input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d,
      input logic vmb, input logic [XLEN-1:0] sc);
    logic [2:0] f3;
    case (form)
      0: f3 = 3'b100;
      1: f3 = 3'b011;
      2: f3 = 3'b110;
      default: f3 = 3'b101;
    endcase
    return enc(
        up ? 6'b001110 : 6'b001111, vmb, s2, (form == 1) ? sc[AWIDTH-1:0] : AWIDTH'(1), f3, d
    );
  endfunction

  task automatic run_slide(input logic up, input int form, input logic [AWIDTH-1:0] s2,
                           input logic [AWIDTH-1:0] d, input logic vmb, input logic [XLEN-1:0] sc,
                           input logic [2:0] sew, input logic [2:0] lmul,
                           input logic [VlW-1:0] len);
    begin
      vsew  = sew;
      vlmul = lmul;
      vl    = len;
      xdata = sc;
      fdata = sc;
      ref_slide(up, form, s2, d, vmb, sc, sew, lmul, int'(len));
      issue(slide_instr(up, form, s2, d, vmb, sc));
      xdata = XLEN'($urandom);
      fdata = XLEN'($urandom);
      drain();
      check_regs($sformatf("slide up %0d form %0d sew %0d lmul %0d", up, form, sew, lmul));
    end
  endtask  // Automatic

  task automatic check_slide_rules();
    begin
      vill  = 1'b0;
      vlmul = 3'd1;
      vl    = VlW'(8);
      vsew  = 3'd2;
      instr = slide_instr(1'b1, 0, AWIDTH'(8), AWIDTH'(8), 1'b1, '0);
      @(negedge clk);
      check("slideup onto its source", XLEN'(is_vector), XLEN'(0));
      instr = slide_instr(1'b1, 2, AWIDTH'(8), AWIDTH'(8), 1'b1, '0);
      @(negedge clk);
      check("slide1up onto its source", XLEN'(is_vector), XLEN'(0));
      instr = slide_instr(1'b1, 1, AWIDTH'(8), AWIDTH'(10), 1'b1, '0);
      @(negedge clk);
      check("slideup beside its source", XLEN'(is_vector), XLEN'(1));
      instr = slide_instr(1'b0, 0, AWIDTH'(8), AWIDTH'(8), 1'b1, '0);
      @(negedge clk);
      check("slidedown onto its source", XLEN'(is_vector), XLEN'(1));
      instr = slide_instr(1'b0, 0, AWIDTH'(8), AWIDTH'(9), 1'b1, '0);
      @(negedge clk);
      check("slidedown misaligned", XLEN'(is_vector), XLEN'(0));
      instr = slide_instr(1'b0, 2, AWIDTH'(8), AWIDTH'(0), 1'b0, '0);
      @(negedge clk);
      check("masked slide onto v0", XLEN'(is_vector), XLEN'(0));
      instr = slide_instr(1'b1, 3, AWIDTH'(8), AWIDTH'(10), 1'b1, '0);
      @(negedge clk);
      check("float slide at e32", XLEN'(is_vector), XLEN'(1));
      vsew = 3'd1;
      @(negedge clk);
      check("float slide at e16", XLEN'(is_vector), XLEN'(0));
      vsew = 3'd2;
      frm  = RmBad;
      @(negedge clk);
      check("float slide bad rounding", XLEN'(is_vector), XLEN'(0));
      frm   = fp_pkg::RmRne;
      instr = '0;
      @(negedge clk);
    end
  endtask  // Automatic

  task automatic check_slides();
    logic [XLEN-1:0] offs[6] = '{
        XLEN'(0),
        XLEN'(1),
        XLEN'(5),
        XLEN'(17),
        XLEN'(130),
        XLEN'('hFFFF_FFFF)
    };
    begin
      seed_all();
      for (int f = 0; f < 4; f++) begin
        for (int u = 0; u < 2; u++) begin
          for (int s = 0; s < 3; s++) begin
            if ((f == 3) && (s != 2)) continue;
            for (int k = 0; k < 6; k++) begin
              if ((f >= 2) && (k > 0)) continue;
              run_slide(1'(u), f, AWIDTH'(8), AWIDTH'(16), 1'b1,
                        (f >= 2) ? XLEN'($urandom) : offs[k], 3'(s), 3'd0, VlW'(VLEN / (8 << s)));
            end
            run_slide(1'(u), f, AWIDTH'(8), AWIDTH'(16), 1'b0,
                      (f >= 2) ? XLEN'($urandom) : XLEN'(3), 3'(s), 3'd1,
                      VlW'(2 * VLEN / (8 << s) - 3));
            run_slide(1'(u), f, AWIDTH'(8), AWIDTH'(24), 1'b1,
                      (f >= 2) ? XLEN'($urandom) : XLEN'(9), 3'(s), 3'd3, VlW'(VLEN / (1 << s)));
            run_slide(1'(u), f, AWIDTH'(8), AWIDTH'(12), 1'b1,
                      (f >= 2) ? XLEN'($urandom) : XLEN'(1), 3'(s), 3'd7, VlW'(VLEN / (16 << s)));
            if (u == 0)
              run_slide(1'b0, f, AWIDTH'(8), AWIDTH'(8), 1'b0, XLEN'(6), 3'(s), 3'd2, VlW'(11));
            run_slide(1'(u), f, AWIDTH'(8), AWIDTH'(16), 1'b1, XLEN'(2), 3'(s), 3'd0, VlW'(0));
          end
        end
      end
      seed_all();
    end
  endtask  // Automatic

  // Slides behind lanes
  task automatic check_slide_stream();
    begin
      stall_pct = StallPct;
      seed_all();
      vsew  = 3'd0;
      vlmul = 3'd0;
      vl    = VlW'(16);
      ref_apply(VEC_ADD, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, '0, AWIDTH'(0), 8, 1, 16);
      ref_slide(1'b0, 0, AWIDTH'(12), AWIDTH'(16), 1'b1, XLEN'(3), 3'd0, 3'd0, 16);
      ref_apply(VEC_ADD, 0, AWIDTH'(4), AWIDTH'(16), AWIDTH'(20), 1'b1, '0, AWIDTH'(0), 8, 1, 16);
      ref_slide(1'b1, 1, AWIDTH'(20), AWIDTH'(24), 1'b1, XLEN'(5), 3'd0, 3'd0, 16);
      ref_apply(VEC_ADD, 0, AWIDTH'(24), AWIDTH'(4), AWIDTH'(26), 1'b1, '0, AWIDTH'(0), 8, 1, 16);
      issue(enc(6'b000000, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(12)));
      xdata = XLEN'(3);
      issue(slide_instr(1'b0, 0, AWIDTH'(12), AWIDTH'(16), 1'b1, XLEN'(3)));
      issue(enc(6'b000000, 1'b1, AWIDTH'(16), AWIDTH'(4), 3'b000, AWIDTH'(20)));
      issue(slide_instr(1'b1, 1, AWIDTH'(20), AWIDTH'(24), 1'b1, XLEN'(5)));
      issue(enc(6'b000000, 1'b1, AWIDTH'(4), AWIDTH'(24), 3'b000, AWIDTH'(26)));
      drain();
      check_regs("slide stream");
      seed_all();
      stall_pct = 0;
    end
  endtask  // Automatic

  task automatic check_multiplies();
    vec_op_e ops[8] = '{
        VEC_MUL,
        VEC_MULH,
        VEC_MULHU,
        VEC_MULHSU,
        VEC_MACC,
        VEC_NMSAC,
        VEC_MADD,
        VEC_NMSUB
    };
    seed_all();
    for (int k = 0; k < 8; k++) begin
      for (int s = 0; s < 3; s++) begin
        run_lane(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, '0, AWIDTH'(0), 3'(s), 3'd0,
                 VlW'(VLEN / (8 << s)), 2'd0);
        run_lane(ops[k], 1, AWIDTH'(0), AWIDTH'(8), AWIDTH'(13), 1'b1, XLEN'($urandom), AWIDTH'(0),
                 3'(s), 3'd0, VlW'(VLEN / (8 << s)), 2'd0);
      end
      run_lane(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(16), 1'b1, '0, AWIDTH'(0), 3'd1, 3'd1,
               VlW'(16), 2'd0);
      run_lane(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b0, '0, AWIDTH'(0), 3'd0, 3'd0,
               VlW'(16), 2'd0);
      run_lane(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, '0, AWIDTH'(0), 3'd2, 3'd0,
               VlW'(3), 2'd0);
    end
    seed_reg(AWIDTH'(4), min_vec(32));
    seed_reg(AWIDTH'(8), min_vec(32));
    run_lane(VEC_MULH, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, '0, AWIDTH'(0), 3'd2, 3'd0,
             VlW'(4), 2'd0);
    run_lane(VEC_MULHSU, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, '0, AWIDTH'(0), 3'd2, 3'd0,
             VlW'(4), 2'd0);
    seed_all();
  endtask  // Automatic

  task automatic check_fixed_ops();
    vec_op_e ops[7] = '{VEC_SADDU, VEC_SADD, VEC_SSUBU, VEC_SSUB, VEC_SMUL, VEC_SSRL, VEC_SSRA};
    int nforms;
    seed_all();
    for (int k = 0; k < 7; k++) begin
      nforms = ((ops[k] == VEC_SSUBU) || (ops[k] == VEC_SSUB) || (ops[k] == VEC_SMUL)) ? 2 : 3;
      for (int s = 0; s < 3; s++) begin
        for (int f = 0; f < nforms; f++) begin
          for (int md = 0; md < 4; md++) begin
            run_lane(ops[k], f, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, XLEN'($urandom),
                     AWIDTH'($urandom), 3'(s), 3'd0, VlW'(VLEN / (8 << s)), 2'(md));
          end
        end
      end
      run_lane(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(16), 1'b0, '0, AWIDTH'(0), 3'd1, 3'd1,
               VlW'(13), 2'd1);
    end
    for (int k = 0; k < 2; k++) begin
      for (int s = 0; s < 2; s++) begin
        for (int f = 0; f < 3; f++) begin
          for (int md = 0; md < 4; md++) begin
            run_lane((k == 1) ? VEC_NCLIP : VEC_NCLIPU, f, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12),
                     1'b1, XLEN'($urandom), AWIDTH'($urandom), 3'(s), 3'd0, VlW'(VLEN / (8 << s)),
                     2'(md));
          end
        end
        run_lane((k == 1) ? VEC_NCLIP : VEC_NCLIPU, 0, AWIDTH'(2), AWIDTH'(16), AWIDTH'(20), 1'b0,
                 '0, AWIDTH'(0), 3'(s), 3'd1, VlW'(VLEN / (8 << s) + 3), 2'd3);
      end
    end
    for (int s = 0; s < 3; s++) begin
      seed_reg(AWIDTH'(4), min_vec(8 << s));
      seed_reg(AWIDTH'(8), min_vec(8 << s));
      run_lane(VEC_SMUL, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, '0, AWIDTH'(0), 3'(s), 3'd0,
               VlW'(VLEN / (8 << s)), 2'd0);
      run_lane(VEC_SADD, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, '0, AWIDTH'(0), 3'(s), 3'd0,
               VlW'(VLEN / (8 << s)), 2'd0);
      run_lane(VEC_SSUB, 1, AWIDTH'(0), AWIDTH'(4), AWIDTH'(12), 1'b1, XLEN'(1), AWIDTH'(0), 3'(s),
               3'd0, VlW'(VLEN / (8 << s)), 2'd0);
    end
    seed_reg(AWIDTH'(4), '0);
    seed_reg(AWIDTH'(8), '1);
    run_lane(VEC_SADDU, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, '0, AWIDTH'(0), 3'd0, 3'd0,
             VlW'(16), 2'd0);
    seed_all();
  endtask  // Automatic

  // Zero even elements
  function automatic logic [VLEN-1:0] zero_even(input logic [VLEN-1:0] v, input int w);
    zero_even = v;
    for (int e = 0; e < VLEN / w; e += 2) zero_even = set_elem(zero_even, w, e, '0);
  endfunction

  // Divide forms
  task automatic check_divides();
    vec_op_e ops[4] = '{VEC_DIVU, VEC_DIV, VEC_REMU, VEC_REM};
    int n;
    seed_all();
    for (int k = 0; k < 4; k++) begin
      for (int s = 0; s < 3; s++) begin
        n = VLEN / (8 << s);
        run_lane(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, '0, AWIDTH'(0), 3'(s), 3'd0,
                 VlW'(n), 2'd0);
        run_lane(ops[k], 1, AWIDTH'(0), AWIDTH'(8), AWIDTH'(13), 1'b1, XLEN'($urandom), AWIDTH'(0),
                 3'(s), 3'd0, VlW'(n), 2'd0);
        run_lane(ops[k], 1, AWIDTH'(0), AWIDTH'(8), AWIDTH'(14), 1'b1, '0, AWIDTH'(0), 3'(s), 3'd0,
                 VlW'(n), 2'd0);
      end
      run_lane(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(16), 1'b1, '0, AWIDTH'(0), 3'd1, 3'd1,
               VlW'(16), 2'd0);
      run_lane(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(16), 1'b1, '0, AWIDTH'(0), 3'd2, 3'd2,
               VlW'(13), 2'd0);
      run_lane(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b0, '0, AWIDTH'(0), 3'd0, 3'd0,
               VlW'(16), 2'd0);
      run_lane(ops[k], 1, AWIDTH'(0), AWIDTH'(8), AWIDTH'(12), 1'b0, XLEN'($urandom), AWIDTH'(0),
               3'd2, 3'd0, VlW'(3), 2'd0);
    end
    for (int s = 0; s < 3; s++) begin
      n = VLEN / (8 << s);
      for (int c = 0; c < 3; c++) begin
        case (c)
          0: seed_reg(AWIDTH'(4), '0);
          1: seed_reg(AWIDTH'(4), zero_even(rand_vec(), 8 << s));
          default: begin
            seed_reg(AWIDTH'(4), '1);
            seed_reg(AWIDTH'(8), min_vec(8 << s));
          end
        endcase
        for (int k = 0; k < 4; k++) begin
          run_lane(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, '0, AWIDTH'(0), 3'(s),
                   3'd0, VlW'(n), 2'd0);
        end
      end
      run_lane(VEC_DIV, 1, AWIDTH'(0), AWIDTH'(8), AWIDTH'(13), 1'b1, '1, AWIDTH'(0), 3'(s), 3'd0,
               VlW'(n), 2'd0);
      run_lane(VEC_REM, 1, AWIDTH'(0), AWIDTH'(8), AWIDTH'(14), 1'b1, '1, AWIDTH'(0), 3'(s), 3'd0,
               VlW'(n), 2'd0);
      seed_all();
    end
  endtask  // Automatic

  // Averaging forms
  task automatic check_averaging();
    vec_op_e ops[4] = '{VEC_AADDU, VEC_AADD, VEC_ASUBU, VEC_ASUB};
    logic [VLEN-1:0] ext[3];
    int n;
    seed_all();
    for (int k = 0; k < 4; k++) begin
      for (int s = 0; s < 3; s++) begin
        for (int f = 0; f < 2; f++) begin
          for (int md = 0; md < 4; md++) begin
            run_lane(ops[k], f, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, XLEN'($urandom),
                     AWIDTH'(0), 3'(s), 3'd0, VlW'(VLEN / (8 << s)), 2'(md));
          end
        end
      end
      run_lane(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(16), 1'b0, '0, AWIDTH'(0), 3'd1, 3'd1,
               VlW'(13), 2'd1);
      run_lane(ops[k], 1, AWIDTH'(0), AWIDTH'(8), AWIDTH'(16), 1'b1, XLEN'($urandom), AWIDTH'(0),
               3'd0, 3'd2, VlW'(50), 2'd3);
    end
    for (int s = 0; s < 3; s++) begin
      n   = VLEN / (8 << s);
      ext = '{min_vec(8 << s), ~min_vec(8 << s), '1};
      for (int i = 0; i < 3; i++) begin
        for (int j = 0; j < 3; j++) begin
          seed_reg(AWIDTH'(8), ext[i]);
          seed_reg(AWIDTH'(4), ext[j]);
          for (int k = 0; k < 4; k++) begin
            for (int md = 0; md < 4; md++) begin
              run_lane(ops[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, '0, AWIDTH'(0), 3'(s),
                       3'd0, VlW'(n), 2'(md));
            end
          end
        end
      end
    end
    seed_all();
  endtask  // Automatic

  // Divide overlaps neighbours
  task automatic check_divide_overlap();
    logic sat;
    begin
      stall_pct = StallPct;
      seed_all();
      seed_reg(AWIDTH'(4), zero_even(rand_vec(), 8));
      csr_poke(VxrmAddr, XLEN'(1));
      vsew  = 3'd0;
      vlmul = 3'd0;
      vl    = VlW'(16);
      xdata = '0;
      model_lane(VEC_DIV, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, '0, AWIDTH'(0), 8, 1,
                 VlW'(16), 2'd1, sat);
      ref_apply(VEC_ADD, 0, AWIDTH'(5), AWIDTH'(6), AWIDTH'(20), 1'b1, '0, AWIDTH'(0), 8, 1, 16);
      model_lane(VEC_MUL, 0, AWIDTH'(12), AWIDTH'(8), AWIDTH'(24), 1'b1, '0, AWIDTH'(0), 8, 1,
                 VlW'(16), 2'd1, sat);
      model_lane(VEC_AADD, 0, AWIDTH'(12), AWIDTH'(20), AWIDTH'(28), 1'b1, '0, AWIDTH'(0), 8, 1,
                 VlW'(16), 2'd1, sat);
      model_lane(VEC_REMU, 0, AWIDTH'(4), AWIDTH'(12), AWIDTH'(13), 1'b0, '0, AWIDTH'(0), 8, 1,
                 VlW'(16), 2'd1, sat);
      model_lane(VEC_DIVU, 0, AWIDTH'(20), AWIDTH'(13), AWIDTH'(14), 1'b1, '0, AWIDTH'(0), 8, 1,
                 VlW'(16), 2'd1, sat);
      issue(lane_instr(VEC_DIV, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1, AWIDTH'(0)));
      issue(enc(funct6_of(VEC_ADD), 1'b1, AWIDTH'(6), AWIDTH'(5), 3'b000, AWIDTH'(20)));
      issue(lane_instr(VEC_MUL, 0, AWIDTH'(12), AWIDTH'(8), AWIDTH'(24), 1'b1, AWIDTH'(0)));
      issue(lane_instr(VEC_AADD, 0, AWIDTH'(12), AWIDTH'(20), AWIDTH'(28), 1'b1, AWIDTH'(0)));
      issue(lane_instr(VEC_REMU, 0, AWIDTH'(4), AWIDTH'(12), AWIDTH'(13), 1'b0, AWIDTH'(0)));
      issue(lane_instr(VEC_DIVU, 0, AWIDTH'(20), AWIDTH'(13), AWIDTH'(14), 1'b1, AWIDTH'(0)));
      drain();
      check_regs("divide overlap");
      stall_pct = 0;
    end
  endtask  // Automatic

  // Undrained lane ops
  task automatic check_lane_stream();
    vec_op_e ops[8] = '{
        VEC_SADD,
        VEC_MUL,
        VEC_NCLIP,
        VEC_AADDU,
        VEC_SMUL,
        VEC_MACC,
        VEC_SSRA,
        VEC_NCLIPU
    };
    logic [2:0] sews[8] = '{3'd0, 3'd2, 3'd1, 3'd2, 3'd0, 3'd1, 3'd2, 3'd0};
    vec_op_e o[8];
    logic [2:0] sew[8];
    logic sat;
    logic any_sat;
    begin
      stall_pct = StallPct;
      for (int r = 0; r < 4; r++) begin
        seed_all();
        csr_poke(VxrmAddr, XLEN'(r));
        csr_poke(VxsatAddr, '0);
        vlmul   = 3'd0;
        xdata   = '0;
        any_sat = 1'b0;
        for (int k = 0; k < 8; k++) begin
          o[k]   = ops[(k+r)%8];
          sew[k] = ((o[k] == VEC_NCLIP) || (o[k] == VEC_NCLIPU)) ? (sews[k] & 3'd1) : sews[k];
          model_lane(o[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12 + k), 1'b1, '0, AWIDTH'(0),
                     8 << sew[k], 1, VlW'(VLEN / (8 << sew[k])), 2'(r), sat);
          any_sat = any_sat || sat;
        end
        for (int k = 0; k < 8; k++) begin
          vsew = sew[k];
          vl   = VlW'(VLEN / (8 << sew[k]));
          issue(lane_instr(o[k], 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12 + k), 1'b1, AWIDTH'(0)));
        end
        drain();
        check_regs($sformatf("lane stream %0d", r));
        check($sformatf("vxsat after lane stream %0d", r), XLEN'(vxsat), XLEN'(any_sat));
      end
      seed_all();
      stall_pct = 0;
    end
  endtask  // Automatic

  // Random lane traffic
  task automatic soak_lanes(input int n);
    vec_op_e ops[25] = '{
        VEC_DIVU,
        VEC_DIV,
        VEC_REMU,
        VEC_REM,
        VEC_AADDU,
        VEC_AADD,
        VEC_ASUBU,
        VEC_ASUB,
        VEC_MACC,
        VEC_NMSAC,
        VEC_MADD,
        VEC_NMSUB,
        VEC_MUL,
        VEC_MULH,
        VEC_MULHU,
        VEC_MULHSU,
        VEC_SADDU,
        VEC_SADD,
        VEC_SSUBU,
        VEC_SSUB,
        VEC_SMUL,
        VEC_SSRL,
        VEC_SSRA,
        VEC_NCLIPU,
        VEC_NCLIP
    };
    vec_op_e o;
    int form;
    int smax;
    logic no_imm;
    logic [2:0] sew;
    logic [2:0] lmul;
    begin
      stall_pct = StallPct;
      seed_all();
      for (int i = 0; i < n; i++) begin
        o = ops[int'($urandom_range(24))];
        form = int'($urandom_range(2));
        no_imm = (o == VEC_SSUBU) || (o == VEC_SSUB) || (o == VEC_SMUL) ||
            (vec_class(o) == VEC_CLS_MUL) || avg_form(o);
        if ((form == 2) && no_imm) form = 1;
        smax = ((o == VEC_NCLIPU) || (o == VEC_NCLIP)) ? 2 : 3;
        sew  = 3'($urandom_range(smax - 1));
        lmul = 3'(1'($urandom));
        run_lane(o, form, AWIDTH'(4), AWIDTH'(16), AWIDTH'(24), 1'($urandom), XLEN'($urandom),
                 AWIDTH'($urandom), sew, lmul, VlW'($urandom_range(
                 (VLEN / (8 << sew)) * (int'(lmul) + 1))), 2'($urandom));
      end
      stall_pct = 0;
    end
  endtask  // Automatic

  // Forms left trapping
  task automatic check_lane_rules();
    begin
      vill  = 1'b0;
      vlmul = 3'd0;
      vl    = VlW'(4);
      vsew  = 3'd2;
      instr = enc(6'b101110, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(12));
      @(negedge clk);
      check("narrow clip at e32", XLEN'(is_vector), XLEN'(0));
      vsew = 3'd1;
      @(negedge clk);
      check("narrow clip at e16", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b101101, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b010, AWIDTH'(12));
      @(negedge clk);
      check("multiply add", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b111000, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b010, AWIDTH'(12));
      @(negedge clk);
      check("widening multiply", XLEN'(is_vector), XLEN'(1));
      vsew = 3'd2;
      @(negedge clk);
      check("widening multiply at e32", XLEN'(is_vector), XLEN'(0));
      vsew  = 3'd1;
      instr = enc(6'b001000, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b010, AWIDTH'(12));
      @(negedge clk);
      check("averaging add", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b100001, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b110, AWIDTH'(12));
      @(negedge clk);
      check("divide", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b100101, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b010, AWIDTH'(12));
      @(negedge clk);
      check("multiply", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b100111, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(12));
      @(negedge clk);
      check("fractional multiply", XLEN'(is_vector), XLEN'(1));
      instr = '0;
    end
  endtask  // Automatic

  function automatic logic f_nan(input logic [FLEN-1:0] x);
    return (x[FLEN-2-:FpExpW] == '1) && (x[FpFracW-1:0] != '0);
  endfunction

  function automatic logic f_snan(input logic [FLEN-1:0] x);
    return f_nan(x) && !x[FpFracW-1];
  endfunction

  function automatic logic f_inf(input logic [FLEN-1:0] x);
    return x[FLEN-2:0] == InfMag;
  endfunction

  function automatic logic f_zero(input logic [FLEN-1:0] x);
    return x[FLEN-2:0] == '0;
  endfunction

  // Finite value parts
  function automatic logic [FpSigW-1:0] f_sig(input logic [FLEN-1:0] x);
    return (x[FLEN-2-:FpExpW] == '0) ? {1'b0, x[FpFracW-1:0]} : {1'b1, x[FpFracW-1:0]};
  endfunction

  function automatic int f_exp(input logic [FLEN-1:0] x);
    if (x[FLEN-2-:FpExpW] == '0) return FpLsbMin;
    return int'(x[FLEN-2-:FpExpW]) - FpBias - FpFracW;
  endfunction

  function automatic int msb_of(input logic [RefW-1:0] v);
    logic [RefW-1:0] t;
    if (v == '0) return -1;
    t = v;
    msb_of = 0;
    for (int s = 1 << ($clog2(RefW) - 1); s > 0; s = s / 2) begin
      if ((t >> s) != '0) begin
        t = t >> s;
        msb_of = msb_of + s;
      end
    end
  endfunction

  // Drop low bits
  function automatic logic [RefW:0] round_off(input logic [RefW-1:0] mag, input int sh,
                                              input logic sticky, input logic [RmW-1:0] rm,
                                              input logic sign);
    logic [RefW-1:0] q;
    logic [RefW-1:0] low;
    logic guard;
    logic rest;
    logic up;
    if (sh <= 0) return {sticky, mag << (-sh)};
    q = mag >> sh;
    low = mag & ((RefW'(1) << sh) - RefW'(1));
    guard = low[sh-1];
    rest = sticky || ((low & ((RefW'(1) << (sh - 1)) - RefW'(1))) != '0);
    case (rm)
      fp_pkg::RmRne: up = guard && (rest || q[0]);
      fp_pkg::RmRtz: up = 1'b0;
      fp_pkg::RmRdn: up = sign && (guard || rest);
      fp_pkg::RmRup: up = !sign && (guard || rest);
      default: up = guard;
    endcase
    return {guard || rest, q + RefW'(up)};
  endfunction

  // Round exact value
  function automatic fres_t ref_pack(input logic sign, input logic [RefW-1:0] mag, input int e,
                                     input logic sticky, input logic [RmW-1:0] rm);
    logic [RefW:0] r;
    logic [RefW-1:0] q;
    logic inexact;
    logic tiny;
    logic to_max;
    logic [FlagW-1:0] flags;
    int p;
    int top;
    int lsb;
    p = msb_of(mag);
    r = round_off(mag, p - FpFracW, sticky, rm, sign);
    top = p + e + (r[FpSigW] ? 1 : 0);
    tiny = top < FpEMin;
    lsb = e + p - FpFracW;
    if (lsb < FpLsbMin) lsb = FpLsbMin;
    r = round_off(mag, lsb - e, sticky, rm, sign);
    inexact = r[RefW];
    q = r[RefW-1:0];
    if (q[FpSigW]) begin
      q   = q >> 1;
      lsb = lsb + 1;
    end
    flags = inexact ? fp_pkg::FlagNx : '0;
    if (tiny && inexact) flags = flags | fp_pkg::FlagUf;
    if (!q[FpFracW]) return {flags, sign, FpExpW'(0), q[FpFracW-1:0]};
    if (lsb + FpFracW + FpBias >= FpExpMax) begin
      to_max = (rm == fp_pkg::RmRtz) || ((rm == fp_pkg::RmRdn) && !sign) ||
          ((rm == fp_pkg::RmRup) && sign);
      return {fp_pkg::FlagOf | fp_pkg::FlagNx, sign, to_max ? MaxMag : InfMag};
    end
    return {flags, sign, FpExpW'(lsb + FpFracW + FpBias), q[FpFracW-1:0]};
  endfunction

  // Signed exact sum
  function automatic fres_t ref_sum(input logic sa, input logic [RefW-1:0] ma, input int ea,
                                    input logic sb, input logic [RefW-1:0] mb, input int eb,
                                    input logic [RmW-1:0] rm);
    logic [RefW-1:0] xa;
    logic [RefW-1:0] xb;
    logic [RefW-1:0] mag;
    logic sign;
    int e;
    e  = (ea < eb) ? ea : eb;
    xa = ma << (ea - e);
    xb = mb << (eb - e);
    if (sa == sb) begin
      mag  = xa + xb;
      sign = sa;
    end else if (xa >= xb) begin
      mag  = xa - xb;
      sign = sa;
    end else begin
      mag  = xb - xa;
      sign = sb;
    end
    if (mag == '0) return {FlagW'(0), (sa == sb) ? sa : (rm == fp_pkg::RmRdn), (FLEN - 1)'(0)};
    return ref_pack(sign, mag, e, 1'b0, rm);
  endfunction

  // Rounded exact sum
  function automatic fres_t ref_add(input logic [FLEN-1:0] a, input logic [FLEN-1:0] b,
                                    input logic [RmW-1:0] rm);
    if (f_nan(a) || f_nan(b))
      return {(f_snan(a) || f_snan(b)) ? fp_pkg::FlagNv : FlagW'(0), CanonNan};
    if (f_inf(a) && f_inf(b) && (a[FLEN-1] != b[FLEN-1])) return {fp_pkg::FlagNv, CanonNan};
    if (f_inf(a)) return {FlagW'(0), a};
    if (f_inf(b)) return {FlagW'(0), b};
    return ref_sum(a[FLEN-1], RefW'(f_sig(a)), f_exp(a), b[FLEN-1], RefW'(f_sig(b)), f_exp(b), rm);
  endfunction

  function automatic fres_t ref_mul(input logic [FLEN-1:0] a, input logic [FLEN-1:0] b,
                                    input logic [RmW-1:0] rm);
    logic sign;
    sign = a[FLEN-1] ^ b[FLEN-1];
    if (f_nan(a) || f_nan(b))
      return {(f_snan(a) || f_snan(b)) ? fp_pkg::FlagNv : FlagW'(0), CanonNan};
    if ((f_inf(a) && f_zero(b)) || (f_zero(a) && f_inf(b))) return {fp_pkg::FlagNv, CanonNan};
    if (f_inf(a) || f_inf(b)) return {FlagW'(0), sign, InfMag};
    if (f_zero(a) || f_zero(b)) return {FlagW'(0), sign, (FLEN - 1)'(0)};
    return ref_pack(sign, RefW'(f_sig(a)) * RefW'(f_sig(b)), f_exp(a) + f_exp(b), 1'b0, rm);
  endfunction

  // Fused multiply add
  function automatic fres_t ref_fma(input logic [FLEN-1:0] a, input logic [FLEN-1:0] b,
                                    input logic [FLEN-1:0] c, input logic [RmW-1:0] rm);
    logic sp;
    logic p_inf;
    sp = a[FLEN-1] ^ b[FLEN-1];
    if (f_nan(a) || f_nan(b))
      return {(f_snan(a) || f_snan(b) || f_snan(c)) ? fp_pkg::FlagNv : FlagW'(0), CanonNan};
    if ((f_inf(a) && f_zero(b)) || (f_zero(a) && f_inf(b))) return {fp_pkg::FlagNv, CanonNan};
    if (f_nan(c)) return {f_snan(c) ? fp_pkg::FlagNv : FlagW'(0), CanonNan};
    p_inf = f_inf(a) || f_inf(b);
    if (p_inf && f_inf(c) && (sp != c[FLEN-1])) return {fp_pkg::FlagNv, CanonNan};
    if (p_inf) return {FlagW'(0), sp, InfMag};
    if (f_inf(c)) return {FlagW'(0), c};
    if (f_zero(a) || f_zero(b)) begin
      if (!f_zero(c)) return {FlagW'(0), c};
      return {FlagW'(0), (sp == c[FLEN-1]) ? sp : (rm == fp_pkg::RmRdn), (FLEN - 1)'(0)};
    end
    return ref_sum(
        sp,
        RefW'(f_sig(
            a
        )) * RefW'(f_sig(
            b
        )),
        f_exp(
            a
        ) + f_exp(
            b
        ),
        c[FLEN-1],
        RefW'(f_sig(
            c
        )),
        f_exp(
            c
        ),
        rm
    );
  endfunction

  function automatic fres_t ref_div(input logic [FLEN-1:0] a, input logic [FLEN-1:0] b,
                                    input logic [RmW-1:0] rm);
    logic sign;
    logic [RefW-1:0] num;
    logic [RefW-1:0] den;
    sign = a[FLEN-1] ^ b[FLEN-1];
    if (f_nan(a) || f_nan(b))
      return {(f_snan(a) || f_snan(b)) ? fp_pkg::FlagNv : FlagW'(0), CanonNan};
    if ((f_inf(a) && f_inf(b)) || (f_zero(a) && f_zero(b))) return {fp_pkg::FlagNv, CanonNan};
    if (f_inf(a)) return {FlagW'(0), sign, InfMag};
    if (f_inf(b)) return {FlagW'(0), sign, (FLEN - 1)'(0)};
    if (f_zero(b)) return {fp_pkg::FlagDz, sign, InfMag};
    if (f_zero(a)) return {FlagW'(0), sign, (FLEN - 1)'(0)};
    num = RefW'(f_sig(a)) << DivShift;
    den = RefW'(f_sig(b));
    return ref_pack(sign, num / den, f_exp(a) - f_exp(b) - DivShift, (num % den) != '0, rm);
  endfunction

  function automatic logic [SqrtW:0] isqrt(input logic [SqrtW-1:0] v);
    logic [2*SqrtW-1:0] root;
    logic [2*SqrtW-1:0] trial;
    root = '0;
    for (int i = SqrtW / 2; i >= 0; i--) begin
      trial = root | ((2 * SqrtW)'(1) << i);
      if (trial * trial <= (2 * SqrtW)'(v)) root = trial;
    end
    return {(root * root) != (2 * SqrtW)'(v), SqrtW'(root)};
  endfunction

  function automatic fres_t ref_sqrt(input logic [FLEN-1:0] a, input logic [RmW-1:0] rm);
    logic [SqrtW-1:0] v;
    logic [SqrtW:0] r;
    int e;
    if (f_nan(a)) return {f_snan(a) ? fp_pkg::FlagNv : FlagW'(0), CanonNan};
    if (f_zero(a)) return {FlagW'(0), a};
    if (a[FLEN-1]) return {fp_pkg::FlagNv, CanonNan};
    if (f_inf(a)) return {FlagW'(0), a};
    v = SqrtW'(f_sig(a));
    e = f_exp(a);
    if ((e % 2) != 0) begin
      v = v << 1;
      e = e - 1;
    end
    v = v << (2 * SqrtShift);
    r = isqrt(v);
    return ref_pack(1'b0, RefW'(r[SqrtW-1:0]), (e - 2 * SqrtShift) / 2, r[SqrtW], rm);
  endfunction

  // Numeric order key
  function automatic logic signed [FLEN:0] f_key(input logic [FLEN-1:0] x);
    return x[FLEN-1] ? -(FLEN + 1)'(x[FLEN-2:0]) : (FLEN + 1)'(x[FLEN-2:0]);
  endfunction

  // Minimum number pair
  function automatic logic [FLEN-1:0] fred_pair(input vec_fop_e o, input logic [FLEN-1:0] x,
                                                input logic [FLEN-1:0] y);
    logic x_first;
    if (f_nan(x) && f_nan(y)) return CanonNan;
    if (f_nan(x)) return y;
    if (f_nan(y)) return x;
    if (f_key(x) == f_key(y)) x_first = (o == VEC_FMAX) ? !x[FLEN-1] : x[FLEN-1];
    else x_first = (o == VEC_FMAX) ? (f_key(x) > f_key(y)) : (f_key(x) < f_key(y));
    return x_first ? x : y;
  endfunction

  function automatic fres_t ref_minmax(input vec_fop_e o, input logic [FLEN-1:0] a,
                                       input logic [FLEN-1:0] b);
    return {(f_snan(a) || f_snan(b)) ? fp_pkg::FlagNv : FlagW'(0), fred_pair(o, a, b)};
  endfunction

  // Compare result bit
  function automatic fres_t ref_cmp(input vec_fop_e o, input logic [FLEN-1:0] a,
                                    input logic [FLEN-1:0] b);
    logic unord;
    logic eq;
    logic lt;
    logic r;
    unord = f_nan(a) || f_nan(b);
    eq = !unord && ((a == b) || (f_zero(a) && f_zero(b)));
    lt = !unord && !eq && (f_key(a) < f_key(b));
    case (o)
      VEC_MFEQ: r = eq;
      VEC_MFNE: r = !eq;
      VEC_MFLT: r = lt;
      VEC_MFLE: r = lt || eq;
      VEC_MFGT: r = !unord && !eq && !lt;
      default:  r = !unord && !lt;
    endcase
    if ((o == VEC_MFEQ) || (o == VEC_MFNE))
      return {(f_snan(a) || f_snan(b)) ? fp_pkg::FlagNv : FlagW'(0), FLEN'(r)};
    return {unord ? fp_pkg::FlagNv : FlagW'(0), FLEN'(r)};
  endfunction

  function automatic logic [FLEN-1:0] ref_class(input logic [FLEN-1:0] x);
    logic s;
    logic sub;
    s   = x[FLEN-1];
    sub = (x[FLEN-2-:FpExpW] == '0) && !f_zero(x);
    if (f_nan(x)) return f_snan(x) ? FLEN'(1 << 8) : FLEN'(1 << 9);
    if (f_inf(x)) return s ? FLEN'(1 << 0) : FLEN'(1 << 7);
    if (f_zero(x)) return s ? FLEN'(1 << 3) : FLEN'(1 << 4);
    if (sub) return s ? FLEN'(1 << 2) : FLEN'(1 << 5);
    return s ? FLEN'(1 << 1) : FLEN'(1 << 6);
  endfunction

  // Float to integer
  function automatic fres_t ref_f2i(input logic [FLEN-1:0] a, input logic uns, input int w,
                                    input logic [RmW-1:0] rm);
    logic [RefW:0] r;
    logic [RefW-1:0] mag;
    logic [FLEN-1:0] hi;
    logic [FLEN-1:0] lo;
    logic s;
    s  = a[FLEN-1];
    hi = uns ? FLEN'((FLEN'(1) << w) - 1) : FLEN'((FLEN'(1) << (w - 1)) - 1);
    lo = uns ? '0 : FLEN'(-(FLEN'(1) << (w - 1)));
    if (f_nan(a)) return {fp_pkg::FlagNv, hi};
    if (f_inf(a)) return {fp_pkg::FlagNv, s ? lo : hi};
    r   = round_off(RefW'(f_sig(a)), -f_exp(a), 1'b0, rm, s);
    mag = r[RefW-1:0];
    if (mag == '0) return {r[RefW] ? fp_pkg::FlagNx : FlagW'(0), FLEN'(0)};
    if (s && uns) return {fp_pkg::FlagNv, lo};
    if (!s && (mag > RefW'(hi))) return {fp_pkg::FlagNv, hi};
    if (s && (mag > (RefW'(1) << (w - 1)))) return {fp_pkg::FlagNv, lo};
    return {r[RefW] ? fp_pkg::FlagNx : FlagW'(0), s ? FLEN'(-FLEN'(mag)) : FLEN'(mag)};
  endfunction

  // Integer to float
  function automatic fres_t ref_i2f(input logic [FLEN-1:0] v, input logic uns, input int w,
                                    input logic [RmW-1:0] rm);
    logic [RefW-1:0] mag;
    logic s;
    mag = RefW'(v) & ((RefW'(1) << w) - RefW'(1));
    s   = !uns && mag[w-1];
    if (s) mag = ((RefW'(1) << w) - mag) & ((RefW'(1) << w) - RefW'(1));
    if (mag == '0) return '0;
    return ref_pack(s, mag, 0, 1'b0, rm);
  endfunction

  function automatic logic [6:0] rec_table(input logic [6:0] idx);
    case (idx)
      7'd0: rec_table = 7'd127;
      7'd1: rec_table = 7'd125;
      7'd2: rec_table = 7'd123;
      7'd3: rec_table = 7'd121;
      7'd4: rec_table = 7'd119;
      7'd5: rec_table = 7'd117;
      7'd6: rec_table = 7'd116;
      7'd7: rec_table = 7'd114;
      7'd8: rec_table = 7'd112;
      7'd9: rec_table = 7'd110;
      7'd10: rec_table = 7'd109;
      7'd11: rec_table = 7'd107;
      7'd12: rec_table = 7'd105;
      7'd13: rec_table = 7'd104;
      7'd14: rec_table = 7'd102;
      7'd15: rec_table = 7'd100;
      7'd16: rec_table = 7'd99;
      7'd17: rec_table = 7'd97;
      7'd18: rec_table = 7'd96;
      7'd19: rec_table = 7'd94;
      7'd20: rec_table = 7'd93;
      7'd21: rec_table = 7'd91;
      7'd22: rec_table = 7'd90;
      7'd23: rec_table = 7'd88;
      7'd24: rec_table = 7'd87;
      7'd25: rec_table = 7'd85;
      7'd26: rec_table = 7'd84;
      7'd27: rec_table = 7'd83;
      7'd28: rec_table = 7'd81;
      7'd29: rec_table = 7'd80;
      7'd30: rec_table = 7'd79;
      7'd31: rec_table = 7'd77;
      7'd32: rec_table = 7'd76;
      7'd33: rec_table = 7'd75;
      7'd34: rec_table = 7'd74;
      7'd35: rec_table = 7'd72;
      7'd36: rec_table = 7'd71;
      7'd37: rec_table = 7'd70;
      7'd38: rec_table = 7'd69;
      7'd39: rec_table = 7'd68;
      7'd40: rec_table = 7'd66;
      7'd41: rec_table = 7'd65;
      7'd42: rec_table = 7'd64;
      7'd43: rec_table = 7'd63;
      7'd44: rec_table = 7'd62;
      7'd45: rec_table = 7'd61;
      7'd46: rec_table = 7'd60;
      7'd47: rec_table = 7'd59;
      7'd48: rec_table = 7'd58;
      7'd49: rec_table = 7'd57;
      7'd50: rec_table = 7'd56;
      7'd51: rec_table = 7'd55;
      7'd52: rec_table = 7'd54;
      7'd53: rec_table = 7'd53;
      7'd54: rec_table = 7'd52;
      7'd55: rec_table = 7'd51;
      7'd56: rec_table = 7'd50;
      7'd57: rec_table = 7'd49;
      7'd58: rec_table = 7'd48;
      7'd59: rec_table = 7'd47;
      7'd60: rec_table = 7'd46;
      7'd61: rec_table = 7'd45;
      7'd62: rec_table = 7'd44;
      7'd63: rec_table = 7'd43;
      7'd64: rec_table = 7'd42;
      7'd65: rec_table = 7'd41;
      7'd66: rec_table = 7'd40;
      7'd67: rec_table = 7'd40;
      7'd68: rec_table = 7'd39;
      7'd69: rec_table = 7'd38;
      7'd70: rec_table = 7'd37;
      7'd71: rec_table = 7'd36;
      7'd72: rec_table = 7'd35;
      7'd73: rec_table = 7'd35;
      7'd74: rec_table = 7'd34;
      7'd75: rec_table = 7'd33;
      7'd76: rec_table = 7'd32;
      7'd77: rec_table = 7'd31;
      7'd78: rec_table = 7'd31;
      7'd79: rec_table = 7'd30;
      7'd80: rec_table = 7'd29;
      7'd81: rec_table = 7'd28;
      7'd82: rec_table = 7'd28;
      7'd83: rec_table = 7'd27;
      7'd84: rec_table = 7'd26;
      7'd85: rec_table = 7'd25;
      7'd86: rec_table = 7'd25;
      7'd87: rec_table = 7'd24;
      7'd88: rec_table = 7'd23;
      7'd89: rec_table = 7'd23;
      7'd90: rec_table = 7'd22;
      7'd91: rec_table = 7'd21;
      7'd92: rec_table = 7'd21;
      7'd93: rec_table = 7'd20;
      7'd94: rec_table = 7'd19;
      7'd95: rec_table = 7'd19;
      7'd96: rec_table = 7'd18;
      7'd97: rec_table = 7'd17;
      7'd98: rec_table = 7'd17;
      7'd99: rec_table = 7'd16;
      7'd100: rec_table = 7'd15;
      7'd101: rec_table = 7'd15;
      7'd102: rec_table = 7'd14;
      7'd103: rec_table = 7'd14;
      7'd104: rec_table = 7'd13;
      7'd105: rec_table = 7'd12;
      7'd106: rec_table = 7'd12;
      7'd107: rec_table = 7'd11;
      7'd108: rec_table = 7'd11;
      7'd109: rec_table = 7'd10;
      7'd110: rec_table = 7'd9;
      7'd111: rec_table = 7'd9;
      7'd112: rec_table = 7'd8;
      7'd113: rec_table = 7'd8;
      7'd114: rec_table = 7'd7;
      7'd115: rec_table = 7'd7;
      7'd116: rec_table = 7'd6;
      7'd117: rec_table = 7'd5;
      7'd118: rec_table = 7'd5;
      7'd119: rec_table = 7'd4;
      7'd120: rec_table = 7'd4;
      7'd121: rec_table = 7'd3;
      7'd122: rec_table = 7'd3;
      7'd123: rec_table = 7'd2;
      7'd124: rec_table = 7'd2;
      7'd125: rec_table = 7'd1;
      7'd126: rec_table = 7'd1;
      7'd127: rec_table = 7'd0;
      default: rec_table = 7'd0;
    endcase
  endfunction

  function automatic logic [6:0] rsq_table(input logic [6:0] idx);
    case (idx)
      7'd0: rsq_table = 7'd52;
      7'd1: rsq_table = 7'd51;
      7'd2: rsq_table = 7'd50;
      7'd3: rsq_table = 7'd48;
      7'd4: rsq_table = 7'd47;
      7'd5: rsq_table = 7'd46;
      7'd6: rsq_table = 7'd44;
      7'd7: rsq_table = 7'd43;
      7'd8: rsq_table = 7'd42;
      7'd9: rsq_table = 7'd41;
      7'd10: rsq_table = 7'd40;
      7'd11: rsq_table = 7'd39;
      7'd12: rsq_table = 7'd38;
      7'd13: rsq_table = 7'd36;
      7'd14: rsq_table = 7'd35;
      7'd15: rsq_table = 7'd34;
      7'd16: rsq_table = 7'd33;
      7'd17: rsq_table = 7'd32;
      7'd18: rsq_table = 7'd31;
      7'd19: rsq_table = 7'd30;
      7'd20: rsq_table = 7'd30;
      7'd21: rsq_table = 7'd29;
      7'd22: rsq_table = 7'd28;
      7'd23: rsq_table = 7'd27;
      7'd24: rsq_table = 7'd26;
      7'd25: rsq_table = 7'd25;
      7'd26: rsq_table = 7'd24;
      7'd27: rsq_table = 7'd23;
      7'd28: rsq_table = 7'd23;
      7'd29: rsq_table = 7'd22;
      7'd30: rsq_table = 7'd21;
      7'd31: rsq_table = 7'd20;
      7'd32: rsq_table = 7'd19;
      7'd33: rsq_table = 7'd19;
      7'd34: rsq_table = 7'd18;
      7'd35: rsq_table = 7'd17;
      7'd36: rsq_table = 7'd16;
      7'd37: rsq_table = 7'd16;
      7'd38: rsq_table = 7'd15;
      7'd39: rsq_table = 7'd14;
      7'd40: rsq_table = 7'd14;
      7'd41: rsq_table = 7'd13;
      7'd42: rsq_table = 7'd12;
      7'd43: rsq_table = 7'd12;
      7'd44: rsq_table = 7'd11;
      7'd45: rsq_table = 7'd10;
      7'd46: rsq_table = 7'd10;
      7'd47: rsq_table = 7'd9;
      7'd48: rsq_table = 7'd9;
      7'd49: rsq_table = 7'd8;
      7'd50: rsq_table = 7'd7;
      7'd51: rsq_table = 7'd7;
      7'd52: rsq_table = 7'd6;
      7'd53: rsq_table = 7'd6;
      7'd54: rsq_table = 7'd5;
      7'd55: rsq_table = 7'd4;
      7'd56: rsq_table = 7'd4;
      7'd57: rsq_table = 7'd3;
      7'd58: rsq_table = 7'd3;
      7'd59: rsq_table = 7'd2;
      7'd60: rsq_table = 7'd2;
      7'd61: rsq_table = 7'd1;
      7'd62: rsq_table = 7'd1;
      7'd63: rsq_table = 7'd0;
      7'd64: rsq_table = 7'd127;
      7'd65: rsq_table = 7'd125;
      7'd66: rsq_table = 7'd123;
      7'd67: rsq_table = 7'd121;
      7'd68: rsq_table = 7'd119;
      7'd69: rsq_table = 7'd118;
      7'd70: rsq_table = 7'd116;
      7'd71: rsq_table = 7'd114;
      7'd72: rsq_table = 7'd113;
      7'd73: rsq_table = 7'd111;
      7'd74: rsq_table = 7'd109;
      7'd75: rsq_table = 7'd108;
      7'd76: rsq_table = 7'd106;
      7'd77: rsq_table = 7'd105;
      7'd78: rsq_table = 7'd103;
      7'd79: rsq_table = 7'd102;
      7'd80: rsq_table = 7'd100;
      7'd81: rsq_table = 7'd99;
      7'd82: rsq_table = 7'd97;
      7'd83: rsq_table = 7'd96;
      7'd84: rsq_table = 7'd95;
      7'd85: rsq_table = 7'd93;
      7'd86: rsq_table = 7'd92;
      7'd87: rsq_table = 7'd91;
      7'd88: rsq_table = 7'd90;
      7'd89: rsq_table = 7'd88;
      7'd90: rsq_table = 7'd87;
      7'd91: rsq_table = 7'd86;
      7'd92: rsq_table = 7'd85;
      7'd93: rsq_table = 7'd84;
      7'd94: rsq_table = 7'd83;
      7'd95: rsq_table = 7'd82;
      7'd96: rsq_table = 7'd80;
      7'd97: rsq_table = 7'd79;
      7'd98: rsq_table = 7'd78;
      7'd99: rsq_table = 7'd77;
      7'd100: rsq_table = 7'd76;
      7'd101: rsq_table = 7'd75;
      7'd102: rsq_table = 7'd74;
      7'd103: rsq_table = 7'd73;
      7'd104: rsq_table = 7'd72;
      7'd105: rsq_table = 7'd71;
      7'd106: rsq_table = 7'd70;
      7'd107: rsq_table = 7'd70;
      7'd108: rsq_table = 7'd69;
      7'd109: rsq_table = 7'd68;
      7'd110: rsq_table = 7'd67;
      7'd111: rsq_table = 7'd66;
      7'd112: rsq_table = 7'd65;
      7'd113: rsq_table = 7'd64;
      7'd114: rsq_table = 7'd63;
      7'd115: rsq_table = 7'd63;
      7'd116: rsq_table = 7'd62;
      7'd117: rsq_table = 7'd61;
      7'd118: rsq_table = 7'd60;
      7'd119: rsq_table = 7'd59;
      7'd120: rsq_table = 7'd59;
      7'd121: rsq_table = 7'd58;
      7'd122: rsq_table = 7'd57;
      7'd123: rsq_table = 7'd56;
      7'd124: rsq_table = 7'd56;
      7'd125: rsq_table = 7'd55;
      7'd126: rsq_table = 7'd54;
      7'd127: rsq_table = 7'd53;
      default: rsq_table = 7'd0;
    endcase
  endfunction

  function automatic int lead_zeros(input logic [FpFracW-1:0] f);
    lead_zeros = FpFracW;
    for (int i = 0; i < FpFracW; i++) if (f[i]) lead_zeros = FpFracW - 1 - i;
  endfunction

  function automatic int norm_exp(input logic [FLEN-2:0] mag);
    if (mag[FLEN-2:FpFracW] == '0) norm_exp = -lead_zeros(mag[FpFracW-1:0]);
    else norm_exp = int'(mag[FLEN-2:FpFracW]);
  endfunction

  function automatic logic [FpFracW-1:0] norm_sig(input logic [FLEN-2:0] mag);
    if (mag[FLEN-2:FpFracW] == '0)
      norm_sig = mag[FpFracW-1:0] << (lead_zeros(mag[FpFracW-1:0]) + 1);
    else norm_sig = mag[FpFracW-1:0];
  endfunction

  function automatic fres_t ref_rec7(input logic [FLEN-1:0] x, input logic [RmW-1:0] mode);
    logic s;
    logic to_max;
    logic [FpFracW-1:0] sig;
    logic [FpFracW-1:0] osig;
    int oe;
    s = x[FLEN-1];
    to_max = (mode == fp_pkg::RmRtz) || ((mode == fp_pkg::RmRdn) && !s) ||
        ((mode == fp_pkg::RmRup) && s);
    if (x[FLEN-2:FpFracW] == '1 && x[FpFracW-1:0] != '0) begin
      ref_rec7 = {x[FpFracW-1] ? FlagW'(0) : fp_pkg::FlagNv, CanonNan};
    end else if (x[FLEN-2:FpFracW] == '1) begin
      ref_rec7 = {FlagW'(0), s, (FLEN - 1)'(0)};
    end else if (x[FLEN-2:0] == '0) begin
      ref_rec7 = {fp_pkg::FlagDz, s, InfMag};
    end else begin
      sig  = norm_sig(x[FLEN-2:0]);
      oe   = 2 * FpBias - 1 - norm_exp(x[FLEN-2:0]);
      osig = {rec_table(sig[FpFracW-1-:7]), FillW'(0)};
      if (oe > 2 * FpBias)
        ref_rec7 = {fp_pkg::FlagOf | fp_pkg::FlagNx, s, to_max ? MaxMag : InfMag};
      else if (oe <= 0) ref_rec7 = {FlagW'(0), s, FpExpW'(0), FpFracW'({1'b1, osig} >> (1 - oe))};
      else ref_rec7 = {FlagW'(0), s, FpExpW'(oe), osig};
    end
  endfunction

  function automatic fres_t ref_rsqrt7(input logic [FLEN-1:0] x);
    logic [FpFracW-1:0] sig;
    int ne;
    if (x[FLEN-2:FpFracW] == '1 && x[FpFracW-1:0] != '0) begin
      ref_rsqrt7 = {x[FpFracW-1] ? FlagW'(0) : fp_pkg::FlagNv, CanonNan};
    end else if (x[FLEN-2:0] == '0) begin
      ref_rsqrt7 = {fp_pkg::FlagDz, x[FLEN-1], InfMag};
    end else if (x[FLEN-1]) begin
      ref_rsqrt7 = {fp_pkg::FlagNv, CanonNan};
    end else if (x[FLEN-2:FpFracW] == '1) begin
      ref_rsqrt7 = '0;
    end else begin
      sig = norm_sig(x[FLEN-2:0]);
      ne = norm_exp(x[FLEN-2:0]);
      ref_rsqrt7 = {
        FlagW'(0),
        1'b0,
        FpExpW'((3 * FpBias - 1 - ne) / 2),
        rsq_table({ne[0], sig[FpFracW-1-:6]}),
        FillW'(0)
      };
    end
  endfunction

  function automatic logic [FLEN-1:0] fneg(input logic [FLEN-1:0] x);
    return {~x[FLEN-1], x[FLEN-2:0]};
  endfunction

  // Element float rule
  function automatic fres_t ref_fop(input vec_fop_e o, input logic [FLEN-1:0] a,
                                    input logic [FLEN-1:0] b, input logic [FLEN-1:0] c,
                                    input logic [RmW-1:0] rm);
    case (o)
      VEC_FADD:           return ref_add(a, b, rm);
      VEC_FSUB:           return ref_add(a, fneg(b), rm);
      VEC_FRSUB:          return ref_add(b, fneg(a), rm);
      VEC_FMUL:           return ref_mul(a, b, rm);
      VEC_FDIV:           return ref_div(a, b, rm);
      VEC_FRDIV:          return ref_div(b, a, rm);
      VEC_FSQRT:          return ref_sqrt(a, rm);
      VEC_FMACC:          return ref_fma(b, a, c, rm);
      VEC_FNMACC:         return ref_fma(fneg(b), a, fneg(c), rm);
      VEC_FMSAC:          return ref_fma(b, a, fneg(c), rm);
      VEC_FNMSAC:         return ref_fma(fneg(b), a, c, rm);
      VEC_FMADD:          return ref_fma(b, c, a, rm);
      VEC_FNMADD:         return ref_fma(fneg(b), c, fneg(a), rm);
      VEC_FMSUB:          return ref_fma(b, c, fneg(a), rm);
      VEC_FNMSUB:         return ref_fma(fneg(b), c, a, rm);
      VEC_FMIN, VEC_FMAX: return ref_minmax(o, a, b);
      VEC_FSGNJ:          return {FlagW'(0), b[FLEN-1], a[FLEN-2:0]};
      VEC_FSGNJN:         return {FlagW'(0), ~b[FLEN-1], a[FLEN-2:0]};
      VEC_FSGNJX:         return {FlagW'(0), a[FLEN-1] ^ b[FLEN-1], a[FLEN-2:0]};
      VEC_FCLASS:         return {FlagW'(0), ref_class(a)};
      VEC_FREC7:          return ref_rec7(a, rm);
      VEC_FRSQRT7:        return ref_rsqrt7(a);
      default:            return ref_cmp(o, a, b);
    endcase
  endfunction

  // Element conversion rule
  function automatic fres_t ref_cvt(input vec_fop_e o, input vec_eew_e e, input logic [FLEN-1:0] a,
                                    input logic [RmW-1:0] rm);
    int w;
    w = (e == VEC_EEW_SAME) ? FLEN : FLEN / 2;
    case (o)
      VEC_FCVT_XU_F:     return ref_f2i(a, 1'b1, w, rm);
      VEC_FCVT_X_F:      return ref_f2i(a, 1'b0, w, rm);
      VEC_FCVT_RTZ_XU_F: return ref_f2i(a, 1'b1, w, fp_pkg::RmRtz);
      VEC_FCVT_RTZ_X_F:  return ref_f2i(a, 1'b0, w, fp_pkg::RmRtz);
      VEC_FCVT_F_XU:     return ref_i2f(a, 1'b1, w, rm);
      default:           return ref_i2f(a, 1'b0, w, rm);
    endcase
  endfunction

  function automatic string rm_name(input int m);
    case (m)
      0: return "rne";
      1: return "rtz";
      2: return "rdn";
      3: return "rup";
      default: return "rmm";
    endcase
  endfunction

  function automatic int tf_open(input string path);
    tf_open = $fopen(path, "r");
    if (tf_open == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
  endfunction

  // Two operand vectors
  task automatic ref_file2(input string op, input int m);
    string path;
    int fd;
    logic [FLEN-1:0] a;
    logic [FLEN-1:0] b;
    logic [FLEN-1:0] r;
    logic [FlagW-1:0] f;
    fres_t got;
    path = {TfDir, "f32_", op, "_", rm_name(m), ".txt"};
    fd   = tf_open(path);
    for (int line = 1; line <= RefLines; line++) begin
      if ($fscanf(fd, "%h %h %h %h\n", a, b, r, f) != 4)
        $fatal(1, "TB BAD LINE: %s:%0d", path, line);
      if (op == "add") got = ref_fop(VEC_FADD, a, b, '0, RmW'(m));
      else if (op == "sub") got = ref_fop(VEC_FSUB, a, b, '0, RmW'(m));
      else if (op == "mul") got = ref_fop(VEC_FMUL, a, b, '0, RmW'(m));
      else got = ref_fop(VEC_FDIV, a, b, '0, RmW'(m));
      check_ref($sformatf("%0s:%0d", path, line), got, {f, r});
    end
    $fclose(fd);
  endtask  // Automatic

  // Fused vectors
  task automatic ref_file_fma(input int m);
    string path;
    int fd;
    logic [FLEN-1:0] a;
    logic [FLEN-1:0] b;
    logic [FLEN-1:0] c;
    logic [FLEN-1:0] r;
    logic [FlagW-1:0] f;
    path = {TfDir, "f32_mulAdd_", rm_name(m), ".txt"};
    fd   = tf_open(path);
    for (int line = 1; line <= RefLines; line++) begin
      if ($fscanf(fd, "%h %h %h %h %h\n", a, b, c, r, f) != 5)
        $fatal(1, "TB BAD LINE: %s:%0d", path, line);
      check_ref($sformatf("%0s:%0d", path, line), ref_fop(VEC_FMACC, b, a, c, RmW'(m)), {f, r});
    end
    $fclose(fd);
  endtask  // Automatic

  // One operand vectors
  task automatic ref_file1(input string op, input int m, input int lines);
    string path;
    int fd;
    int line;
    logic [FLEN-1:0] a;
    logic [FLEN-1:0] r;
    logic [FlagW-1:0] f;
    fres_t got;
    path = {TfDir, op, "_", rm_name(m), ".txt"};
    fd   = tf_open(path);
    line = 0;
    while ((line < lines) && ($fscanf(
        fd, "%h %h %h\n", a, r, f
    ) == 3)) begin
      line++;
      if (op == "f32_sqrt") got = ref_fop(VEC_FSQRT, a, '0, '0, RmW'(m));
      else if (op == "f32_to_i32") got = ref_cvt(VEC_FCVT_X_F, VEC_EEW_SAME, a, RmW'(m));
      else if (op == "f32_to_ui32") got = ref_cvt(VEC_FCVT_XU_F, VEC_EEW_SAME, a, RmW'(m));
      else if (op == "i32_to_f32") got = ref_cvt(VEC_FCVT_F_X, VEC_EEW_SAME, a, RmW'(m));
      else got = ref_cvt(VEC_FCVT_F_XU, VEC_EEW_SAME, a, RmW'(m));
      check_ref($sformatf("%0s:%0d", path, line), got, {f, r});
    end
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
  endtask  // Automatic

  // Compare vectors
  task automatic ref_file_cmp(input string op);
    string path;
    int fd;
    logic [FLEN-1:0] a;
    logic [FLEN-1:0] b;
    logic r;
    logic [FlagW-1:0] f;
    path = {TfDir, "f32_", op, ".txt"};
    fd   = tf_open(path);
    for (int line = 1; line <= RefLines; line++) begin
      if ($fscanf(fd, "%h %h %h %h\n", a, b, r, f) != 4)
        $fatal(1, "TB BAD LINE: %s:%0d", path, line);
      if (op == "eq") begin
        check_ref($sformatf("%0s:%0d", path, line), ref_fop(VEC_MFEQ, a, b, '0, '0), {f, FLEN'(r)});
        check_ref($sformatf("%0s:%0d ne", path, line), ref_fop(VEC_MFNE, a, b, '0, '0), {
                  f, FLEN'(!r)});
      end else if (op == "le") begin
        check_ref($sformatf("%0s:%0d", path, line), ref_fop(VEC_MFLE, a, b, '0, '0), {f, FLEN'(r)});
        check_ref($sformatf("%0s:%0d ge", path, line), ref_fop(VEC_MFGE, b, a, '0, '0), {f, FLEN'(r)
                  });
      end else begin
        check_ref($sformatf("%0s:%0d", path, line), ref_fop(VEC_MFLT, a, b, '0, '0), {f, FLEN'(r)});
        check_ref($sformatf("%0s:%0d gt", path, line), ref_fop(VEC_MFGT, b, a, '0, '0), {f, FLEN'(r)
                  });
      end
    end
    $fclose(fd);
  endtask  // Automatic

  // References against TestFloat
  task automatic check_references();
    for (int m = 0; m < 5; m++) begin
      ref_file2("add", m);
      ref_file2("sub", m);
      ref_file2("mul", m);
      ref_file2("div", m);
      ref_file_fma(m);
      ref_file1("f32_sqrt", m, RefLines);
      ref_file1("f32_to_i32", m, RefLines);
      ref_file1("f32_to_ui32", m, RefLines);
      ref_file1("i32_to_f32", m, RefLines);
      ref_file1("ui32_to_f32", m, RefLines);
    end
    ref_file_cmp("eq");
    ref_file_cmp("le");
    ref_file_cmp("lt");
    $display("references: %0d TestFloat lines agree", ref_checks);
  endtask  // Automatic

  function automatic logic fp_cmp_op(input vec_fop_e o);
    return (o == VEC_MFEQ) || (o == VEC_MFNE) || (o == VEC_MFLT) || (o == VEC_MFLE) ||
        (o == VEC_MFGT) || (o == VEC_MFGE);
  endfunction

  // Float operand values
  function automatic logic [FLEN-1:0] fp_pick();
    logic [FLEN-1:0] x;
    x = FLEN'($urandom);
    case ($urandom_range(
        7
    ))
      0: x[FLEN-2-:FpExpW] = '1;
      1: x[FLEN-2-:FpExpW] = '0;
      2: x[FLEN-2-:FpExpW] = FpExpW'(FpExpMax - 5 + $urandom_range(4));
      3: x[FLEN-2-:FpExpW] = FpExpW'($urandom_range(3));
      4: x = 1'($urandom) ? FpOne : {1'b0, MaxMag};
      default: x[FLEN-2-:FpExpW] = FpExpW'(FpBias - 7 + $urandom_range(14));
    endcase
    return x;
  endfunction

  function automatic logic [VLEN-1:0] fp_vec();
    for (int e = 0; e < FpElems; e++) fp_vec[e*FLEN+:FLEN] = fp_pick();
  endfunction

  task automatic seed_fp();
    for (int r = 0; r < Depth; r++) begin
      img[r]    = fp_vec();
      shadow[r] = img[r];
    end
    seed_image();
  endtask  // Automatic

  function automatic logic [31:0] fp_encode(
      input vec_fop_e o, input int form, input logic [AWIDTH-1:0] s1, input logic [AWIDTH-1:0] s2,
      input logic [AWIDTH-1:0] d, input logic vmb);
    logic [AWIDTH-1:0] rs1;
    case (o)
      VEC_FCLASS:  rs1 = 5'b10000;
      VEC_FREC7:   rs1 = 5'b00101;
      VEC_FRSQRT7: rs1 = 5'b00100;
      VEC_FSQRT:   rs1 = 5'b00000;
      default:     rs1 = (form != 0) ? AWIDTH'($urandom) : s1;
    endcase
    return enc(fp_funct6(o), vmb, s2, rs1, (form != 0) ? 3'b101 : 3'b001, d);
  endfunction

  // Float op model
  task automatic model_fp(input vec_fop_e o, input int form, input logic [AWIDTH-1:0] s1,
                          input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d, input logic vmb,
                          input logic [FLEN-1:0] fsc, input int regs, input logic [VlW-1:0] len,
                          input logic [RmW-1:0] rm, output logic [FlagW-1:0] want_flags);
    int ids[$];
    fres_t res[$];
    fres_t r;
    want_flags = '0;
    for (int i = 0; i < group_elems(FLEN, regs); i++) begin
      if ((i < len) && (vmb || shadow[0][i])) begin
        ids.push_back(i);
        res.push_back(ref_fop(
                      o,
                      FLEN'(grp_get(
                          s2, FLEN, i
                      )),
                      (form != 0) ? fsc : FLEN'(grp_get(
                          s1, FLEN, i
                      )),
                      FLEN'(grp_get(
                          d, FLEN, i
                      )),
                      rm
                      ));
      end
    end
    for (int k = 0; k < ids.size(); k++) begin
      r = res[k];
      want_flags = want_flags | r[FLEN+:FlagW];
      if (fp_cmp_op(o)) shadow[d][ids[k]] = r[0];
      else grp_set(d, FLEN, ids[k], ELEN'(r[FLEN-1:0]));
    end
  endtask  // Automatic

  // One float op
  task automatic run_fp(input vec_fop_e o, input int form, input logic [AWIDTH-1:0] s1,
                        input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d, input logic vmb,
                        input logic [2:0] lmul, input logic [VlW-1:0] len,
                        input logic [RmW-1:0] rm);
    logic [FlagW-1:0] want;
    logic [FLEN-1:0] fsc;
    int regs;
    regs  = lmul[2] ? 1 : (1 << lmul[1:0]);
    fsc   = fp_pick();
    vsew  = 3'd2;
    vlmul = lmul;
    vl    = len;
    frm   = rm;
    fdata = XLEN'(fsc);
    xdata = XLEN'($urandom);
    model_fp(o, form, s1, s2, d, vmb, fsc, regs, len, rm, want);
    flags_seen = '0;
    issue(fp_encode(o, form, s1, s2, d, vmb));
    frm   = RmW'($urandom_range(4));
    fdata = XLEN'($urandom);
    drain();
    check($sformatf("fflags after %0s", o.name()), XLEN'(flags_seen), XLEN'(want));
    check_regs($sformatf("float %0s form %0d lmul %0d", o.name(), form, lmul));
  endtask  // Automatic

  function automatic logic [5:0] fp_funct6(input vec_fop_e o);
    case (o)
      VEC_FADD:   return 6'b000000;
      VEC_FSUB:   return 6'b000010;
      VEC_FMIN:   return 6'b000100;
      VEC_FMAX:   return 6'b000110;
      VEC_FSGNJ:  return 6'b001000;
      VEC_FSGNJN: return 6'b001001;
      VEC_FSGNJX: return 6'b001010;
      VEC_FMUL:   return 6'b100100;
      VEC_FRSUB:  return 6'b100111;
      VEC_FMADD:  return 6'b101000;
      VEC_FNMADD: return 6'b101001;
      VEC_FMSUB:  return 6'b101010;
      VEC_FNMSUB: return 6'b101011;
      VEC_FMACC:  return 6'b101100;
      VEC_FNMACC: return 6'b101101;
      VEC_FMSAC:  return 6'b101110;
      VEC_FNMSAC: return 6'b101111;
      VEC_MFEQ:   return 6'b011000;
      VEC_MFLE:   return 6'b011001;
      VEC_MFLT:   return 6'b011011;
      VEC_MFNE:   return 6'b011100;
      VEC_MFGT:   return 6'b011101;
      VEC_FCLASS, VEC_FREC7, VEC_FRSQRT7, VEC_FSQRT: return 6'b010011;
      VEC_FDIV:   return 6'b100000;
      VEC_FRDIV:  return 6'b100001;
      default:    return 6'b011111;
    endcase
  endfunction

  // Scalar only forms
  function automatic logic fp_vf_only(input vec_fop_e o);
    return (o == VEC_FRSUB) || (o == VEC_MFGT) || (o == VEC_MFGE) || (o == VEC_FRDIV);
  endfunction

  // Vector only forms
  function automatic logic fp_vv_only(input vec_fop_e o);
    return (o == VEC_FCLASS) || (o == VEC_FREC7) || (o == VEC_FRSQRT7) || (o == VEC_FSQRT);
  endfunction

  // Iterative divide forms
  function automatic logic fp_div_op(input vec_fop_e o);
    return (o == VEC_FDIV) || (o == VEC_FRDIV) || (o == VEC_FSQRT);
  endfunction

  // Every float op
  task automatic check_fp_ops();
    vec_fop_e o;
    begin
      check("no flags from integer work", XLEN'(flags_seen), XLEN'(0));
      seed_fp();
      for (int k = 0; k < 29; k++) begin
        case (k)
          0: o = VEC_FADD;
          1: o = VEC_FSUB;
          2: o = VEC_FRSUB;
          3: o = VEC_FMUL;
          4: o = VEC_FMACC;
          5: o = VEC_FNMACC;
          6: o = VEC_FMSAC;
          7: o = VEC_FNMSAC;
          8: o = VEC_FMADD;
          9: o = VEC_FNMADD;
          10: o = VEC_FMSUB;
          11: o = VEC_FNMSUB;
          12: o = VEC_FMIN;
          13: o = VEC_FMAX;
          14: o = VEC_FSGNJ;
          15: o = VEC_FSGNJN;
          16: o = VEC_FSGNJX;
          17: o = VEC_MFEQ;
          18: o = VEC_MFNE;
          19: o = VEC_MFLT;
          20: o = VEC_MFLE;
          21: o = VEC_MFGT;
          22: o = VEC_MFGE;
          23: o = VEC_FCLASS;
          24: o = VEC_FREC7;
          25: o = VEC_FRSQRT7;
          26: o = VEC_FDIV;
          27: o = VEC_FRDIV;
          default: o = VEC_FSQRT;
        endcase
        for (int f = 0; f < 2; f++) begin
          if ((f == 0) && fp_vf_only(o)) continue;
          if ((f != 0) && fp_vv_only(o)) continue;
          for (int rm = 0; rm < 5; rm++)
          run_fp(o, f, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'($urandom), 3'd0,
                 VlW'(1 + $urandom_range(3)), 3'(rm));
        end
      end
    end
  endtask  // Automatic

  // Random float traffic
  task automatic soak_fp(input int n);
    vec_fop_e       o;
    int             form;
    logic     [2:0] lmul;
    int             regs;
    begin
      stall_pct = StallPct;
      seed_fp();
      for (int i = 0; i < n; i++) begin
        o = vec_fop_e'($urandom_range(XLEN'(VEC_FCLASS)));
        form = int'(1'($urandom));
        if (fp_vf_only(o)) form = 1;
        if (fp_vv_only(o)) form = 0;
        lmul = 3'($urandom_range(3));
        regs = 1 << lmul[1:0];
        run_fp(o, form, AWIDTH'(8), AWIDTH'(16), AWIDTH'(24), 1'($urandom), lmul,
               VlW'($urandom_range(4 * regs)), 3'($urandom_range(4)));
        if ($urandom_range(9) == 0) seed_fp();
      end
      stall_pct = 0;
    end
  endtask  // Automatic

  // Float mixed traffic
  task automatic check_fp_stream();
    logic [FlagW-1:0] want;
    logic [FlagW-1:0] f;
    logic [RmW-1:0] rm[6];
    logic [FLEN-1:0] fsc[6];
    logic sat;
    begin
      stall_pct = StallPct;
      for (int r = 0; r < 6; r++) begin
        seed_fp();
        vlmul = 3'd0;
        vl    = VlW'(4);
        vsew  = 3'd2;
        want  = '0;
        for (int k = 0; k < 6; k++) begin
          rm[k]  = RmW'($urandom_range(4));
          fsc[k] = fp_pick();
        end
        model_fp(VEC_FMUL, 0, AWIDTH'(1), AWIDTH'(2), AWIDTH'(10), 1'b1, '0, 1, VlW'(4), rm[0], f);
        want = want | f;
        ref_apply(VEC_ADD, 0, AWIDTH'(3), AWIDTH'(4), AWIDTH'(11), 1'b1, '0, AWIDTH'(0), 32, 1, 4);
        model_fp(VEC_FMACC, 1, AWIDTH'(0), AWIDTH'(5), AWIDTH'(12), 1'b1, fsc[2], 1, VlW'(4), rm[2],
                 f);
        want = want | f;
        model_lane(VEC_MUL, 0, AWIDTH'(6), AWIDTH'(7), AWIDTH'(13), 1'b1, '0, AWIDTH'(0), 32, 1,
                   VlW'(4), 2'd0, sat);
        model_fp(VEC_MFLT, 0, AWIDTH'(10), AWIDTH'(12), AWIDTH'(14), 1'b1, '0, 1, VlW'(4), rm[4],
                 f);
        want = want | f;
        model_fp(VEC_FADD, 1, AWIDTH'(0), AWIDTH'(13), AWIDTH'(15), 1'b1, fsc[5], 1, VlW'(4), rm[5],
                 f);
        want = want | f;
        flags_seen = '0;
        frm = rm[0];
        issue(fp_encode(VEC_FMUL, 0, AWIDTH'(1), AWIDTH'(2), AWIDTH'(10), 1'b1));
        issue(enc(6'b000000, 1'b1, AWIDTH'(4), AWIDTH'(3), 3'b000, AWIDTH'(11)));
        frm   = rm[2];
        fdata = fsc[2];
        issue(fp_encode(VEC_FMACC, 1, AWIDTH'(0), AWIDTH'(5), AWIDTH'(12), 1'b1));
        issue(lane_instr(VEC_MUL, 0, AWIDTH'(6), AWIDTH'(7), AWIDTH'(13), 1'b1, AWIDTH'(0)));
        frm = rm[4];
        issue(fp_encode(VEC_MFLT, 0, AWIDTH'(10), AWIDTH'(12), AWIDTH'(14), 1'b1));
        frm   = rm[5];
        fdata = fsc[5];
        issue(fp_encode(VEC_FADD, 1, AWIDTH'(0), AWIDTH'(13), AWIDTH'(15), 1'b1));
        frm = fp_pkg::RmRne;
        drain();
        check_regs($sformatf("float stream %0d", r));
        check($sformatf("fflags after float stream %0d", r), XLEN'(flags_seen), XLEN'(want));
      end
      stall_pct = 0;
    end
  endtask  // Automatic

  // Group before short
  task automatic check_fp_group_stream();
    logic [FlagW-1:0] want;
    logic             sat;
    begin
      stall_pct = StallPct;
      for (int r = 0; r < 4; r++) begin
        seed_fp();
        vsew  = 3'd2;
        vlmul = 3'd3;
        vl    = VlW'(32);
        frm   = RmW'(r);
        model_fp(VEC_FADD, 0, AWIDTH'(16), AWIDTH'(24), AWIDTH'(8), 1'b1, '0, 8, VlW'(32), 3'(r),
                 want);
        ref_apply(VEC_ADD, 0, AWIDTH'(1), AWIDTH'(2), AWIDTH'(3), 1'b1, '0, AWIDTH'(0), 32, 1, 4);
        model_lane(VEC_MUL, 0, AWIDTH'(4), AWIDTH'(5), AWIDTH'(6), 1'b1, '0, AWIDTH'(0), 32, 1,
                   VlW'(4), 2'd0, sat);
        ref_apply(VEC_XOR, 0, AWIDTH'(1), AWIDTH'(2), AWIDTH'(7), 1'b1, '0, AWIDTH'(0), 32, 1, 4);
        flags_seen = '0;
        issue(fp_encode(VEC_FADD, 0, AWIDTH'(16), AWIDTH'(24), AWIDTH'(8), 1'b1));
        vlmul = 3'd0;
        vl    = VlW'(4);
        issue(enc(6'b000000, 1'b1, AWIDTH'(2), AWIDTH'(1), 3'b000, AWIDTH'(3)));
        issue(lane_instr(VEC_MUL, 0, AWIDTH'(4), AWIDTH'(5), AWIDTH'(6), 1'b1, AWIDTH'(0)));
        issue(enc(6'b001011, 1'b1, AWIDTH'(2), AWIDTH'(1), 3'b000, AWIDTH'(7)));
        drain();
        check_regs($sformatf("float group stream %0d", r));
        check($sformatf("fflags after float group stream %0d", r), XLEN'(flags_seen), XLEN'(want));
      end
      stall_pct = 0;
    end
  endtask  // Automatic

  // Divide stream
  task automatic check_fdiv_stream();
    logic [FlagW-1:0] want;
    logic [FlagW-1:0] f;
    logic [  RmW-1:0] rm;
    logic [ FLEN-1:0] fsc;
    logic             vmb;
    logic             sat;
    begin
      stall_pct = StallPct;
      for (int r = 0; r < 8; r++) begin
        seed_fp();
        vlmul = 3'd0;
        vl    = VlW'(4);
        vsew  = 3'd2;
        rm    = RmW'($urandom_range(4));
        fsc   = fp_pick();
        vmb   = 1'(r);
        want  = '0;
        model_fp(VEC_FDIV, 0, AWIDTH'(1), AWIDTH'(2), AWIDTH'(10), vmb, '0, 1, VlW'(4), rm, f);
        want = want | f;
        ref_apply(VEC_ADD, 0, AWIDTH'(3), AWIDTH'(4), AWIDTH'(11), 1'b1, '0, AWIDTH'(0), 32, 1, 4);
        model_fp(VEC_FSQRT, 0, AWIDTH'(0), AWIDTH'(5), AWIDTH'(12), vmb, '0, 1, VlW'(4), rm, f);
        want = want | f;
        model_lane(VEC_MUL, 0, AWIDTH'(6), AWIDTH'(7), AWIDTH'(13), 1'b1, '0, AWIDTH'(0), 32, 1,
                   VlW'(4), 2'd0, sat);
        model_fp(VEC_FRDIV, 1, AWIDTH'(0), AWIDTH'(10), AWIDTH'(14), 1'b1, fsc, 1, VlW'(4), rm, f);
        want = want | f;
        model_fp(VEC_FADD, 0, AWIDTH'(14), AWIDTH'(12), AWIDTH'(15), 1'b1, '0, 1, VlW'(4), rm, f);
        want = want | f;
        flags_seen = '0;
        frm = rm;
        fdata = fsc;
        issue(fp_encode(VEC_FDIV, 0, AWIDTH'(1), AWIDTH'(2), AWIDTH'(10), vmb));
        issue(enc(6'b000000, 1'b1, AWIDTH'(4), AWIDTH'(3), 3'b000, AWIDTH'(11)));
        issue(fp_encode(VEC_FSQRT, 0, AWIDTH'(0), AWIDTH'(5), AWIDTH'(12), vmb));
        issue(lane_instr(VEC_MUL, 0, AWIDTH'(6), AWIDTH'(7), AWIDTH'(13), 1'b1, AWIDTH'(0)));
        issue(fp_encode(VEC_FRDIV, 1, AWIDTH'(0), AWIDTH'(10), AWIDTH'(14), 1'b1));
        issue(fp_encode(VEC_FADD, 0, AWIDTH'(14), AWIDTH'(12), AWIDTH'(15), 1'b1));
        frm = fp_pkg::RmRne;
        drain();
        check_regs($sformatf("float divide stream %0d", r));
        check($sformatf("fflags after float divide stream %0d", r), XLEN'(flags_seen), XLEN'(want));
      end
      stall_pct = 0;
    end
  endtask  // Automatic

  // Float forms legal
  task automatic check_fp_rules();
    begin
      vill  = 1'b0;
      vlmul = 3'd0;
      vl    = VlW'(4);
      vsew  = 3'd2;
      frm   = fp_pkg::RmRne;
      instr = fp_encode(VEC_FADD, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1);
      for (int s = 0; s < 3; s++) begin
        vsew = 3'(s);
        @(negedge clk);
        check($sformatf("float add at sew %0d", 8 << s), XLEN'(is_vector), XLEN'(s == 2));
      end
      for (int m = 0; m < 8; m++) begin
        frm = RmW'(m);
        @(negedge clk);
        check($sformatf("float add at frm %0d", m), XLEN'(is_vector), XLEN'(m < 5));
      end
      instr = fp_encode(VEC_MFLT, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1);
      for (int s = 0; s < 3; s++) begin
        vsew = 3'(s);
        for (int m = 0; m < 8; m++) begin
          frm = RmW'(m);
          @(negedge clk);
          check($sformatf("float compare at sew %0d frm %0d", 8 << s, m), XLEN'(is_vector),
                XLEN'((s == 2) && (m < 5)));
        end
      end
      vsew  = 3'd2;
      frm   = fp_pkg::RmRne;
      instr = fp_encode(VEC_MFGT, 1, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1);
      @(negedge clk);
      check("greater than scalar", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b011101, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b001, AWIDTH'(12));
      @(negedge clk);
      check("greater than vector", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b100000, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b001, AWIDTH'(12));
      @(negedge clk);
      check("float divide", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b100001, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b001, AWIDTH'(12));
      @(negedge clk);
      check("reverse divide vector", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010011, 1'b1, AWIDTH'(8), 5'b00000, 3'b001, AWIDTH'(12));
      vlmul = 3'd1;
      @(negedge clk);
      check("float root at lmul 2", XLEN'(is_vector), XLEN'(1));
      vlmul = 3'd0;
      vsew  = 3'd1;
      @(negedge clk);
      check("float root at sew 16", XLEN'(is_vector), XLEN'(0));
      vsew  = 3'd2;
      instr = enc(6'b010011, 1'b1, AWIDTH'(8), 5'b10000, 3'b001, AWIDTH'(12));
      @(negedge clk);
      check("float classify", XLEN'(is_vector), XLEN'(1));
      frm = RmBad;
      @(negedge clk);
      check("float classify at frm 5", XLEN'(is_vector), XLEN'(0));
      frm  = fp_pkg::RmRne;
      vsew = 3'd1;
      @(negedge clk);
      check("float classify at sew 16", XLEN'(is_vector), XLEN'(0));
      vsew  = 3'd2;
      instr = enc(6'b010011, 1'b1, AWIDTH'(8), 5'b10000, 3'b101, AWIDTH'(12));
      @(negedge clk);
      check("float classify scalar", XLEN'(is_vector), XLEN'(0));
      for (int u = 4; u < 6; u++) begin
        instr = enc(6'b010011, 1'b1, AWIDTH'(8), AWIDTH'(u), 3'b001, AWIDTH'(12));
        vlmul = 3'd1;
        @(negedge clk);
        check($sformatf("float estimate %0d at lmul 2", u), XLEN'(is_vector), XLEN'(1));
        vlmul = 3'd0;
        frm   = RmBad;
        @(negedge clk);
        check($sformatf("float estimate %0d at frm 5", u), XLEN'(is_vector), XLEN'(0));
        frm   = fp_pkg::RmRne;
        instr = enc(6'b010011, 1'b1, AWIDTH'(8), AWIDTH'(u), 3'b101, AWIDTH'(12));
        @(negedge clk);
        check($sformatf("float estimate %0d scalar", u), XLEN'(is_vector), XLEN'(0));
      end
      instr = fp_encode(VEC_FMACC, 0, AWIDTH'(4), AWIDTH'(8), AWIDTH'(3), 1'b1);
      vlmul = 3'd1;
      @(negedge clk);
      check("misaligned group", XLEN'(is_vector), XLEN'(0));
      instr = '0;
      vlmul = 3'd0;
    end
  endtask  // Automatic

  function automatic logic [AWIDTH-1:0] cvt_rs1(input vec_fop_e o, input vec_eew_e e);
    logic [AWIDTH-1:0] r;
    case (o)
      VEC_FCVT_XU_F:     r = 5'b00000;
      VEC_FCVT_X_F:      r = 5'b00001;
      VEC_FCVT_F_XU:     r = 5'b00010;
      VEC_FCVT_F_X:      r = 5'b00011;
      VEC_FCVT_RTZ_XU_F: r = 5'b00110;
      default:           r = 5'b00111;
    endcase
    if (e == VEC_EEW_WIDEN) r[3] = 1'b1;
    if (e == VEC_EEW_NARROW) r[4] = 1'b1;
    return r;
  endfunction

  // Conversion model
  task automatic model_cvt(input vec_fop_e o, input vec_eew_e e, input logic [AWIDTH-1:0] s2,
                           input logic [AWIDTH-1:0] d, input logic vmb, input logic [VlW-1:0] len,
                           input logic [RmW-1:0] rm, output logic [FlagW-1:0] want_flags);
    int ids[$];
    fres_t res[$];
    fres_t r;
    int sw;
    int dw;
    sw = (e == VEC_EEW_WIDEN) ? FLEN / 2 : FLEN;
    dw = (e == VEC_EEW_NARROW) ? FLEN / 2 : FLEN;
    want_flags = '0;
    for (int i = 0; i < int'(len); i++) begin
      if (vmb || shadow[0][i]) begin
        ids.push_back(i);
        res.push_back(ref_cvt(o, e, FLEN'(grp_get(s2, sw, i)), rm));
      end
    end
    for (int k = 0; k < ids.size(); k++) begin
      r = res[k];
      want_flags = want_flags | r[FLEN+:FlagW];
      grp_set(d, dw, ids[k], ELEN'(r[FLEN-1:0]));
    end
  endtask  // Automatic

  // One conversion
  task automatic run_cvt(input vec_fop_e o, input vec_eew_e e, input logic [AWIDTH-1:0] s2,
                         input logic [AWIDTH-1:0] d, input logic vmb, input logic [2:0] lmul,
                         input logic [VlW-1:0] len, input logic [RmW-1:0] rm);
    logic [FlagW-1:0] want;
    vsew  = (e == VEC_EEW_SAME) ? 3'd2 : 3'd1;
    vlmul = lmul;
    vl    = len;
    frm   = rm;
    model_cvt(o, e, s2, d, vmb, len, rm, want);
    flags_seen = '0;
    issue(enc(6'b010010, vmb, s2, cvt_rs1(o, e), 3'b001, d));
    frm = RmW'($urandom_range(4));
    drain();
    check($sformatf("fflags after %0s %0s", o.name(), e.name()), XLEN'(flags_seen), XLEN'(want));
    check_regs($sformatf("convert %0s %0s lmul %0d", o.name(), e.name(), lmul));
  endtask  // Automatic

  function automatic vec_fop_e cvt_op(input int k);
    case (k)
      0: return VEC_FCVT_XU_F;
      1: return VEC_FCVT_X_F;
      2: return VEC_FCVT_RTZ_XU_F;
      3: return VEC_FCVT_RTZ_X_F;
      4: return VEC_FCVT_F_XU;
      default: return VEC_FCVT_F_X;
    endcase
  endfunction

  // Every conversion form
  task automatic check_fcvt_ops();
    vec_fop_e o;
    begin
      seed_fp();
      for (int k = 0; k < 6; k++) begin
        o = cvt_op(k);
        for (int rm = 0; rm < 5; rm++) begin
          run_cvt(o, VEC_EEW_SAME, AWIDTH'(8), AWIDTH'(12), 1'($urandom), 3'd0,
                  VlW'(1 + $urandom_range(3)), 3'(rm));
          if (k >= 4)
            run_cvt(o, VEC_EEW_WIDEN, AWIDTH'(8), AWIDTH'(12), 1'($urandom), 3'd0, VlW'(8), 3'(rm));
          else
            run_cvt(o, VEC_EEW_NARROW, AWIDTH'(8), AWIDTH'(13), 1'($urandom), 3'd0, VlW'(8),
                    3'(rm));
        end
        run_cvt(o, VEC_EEW_SAME, AWIDTH'(16), AWIDTH'(24), 1'b0, 3'd3, VlW'(32), 3'd0);
        if (k >= 4) run_cvt(o, VEC_EEW_WIDEN, AWIDTH'(16), AWIDTH'(24), 1'b1, 3'd2, VlW'(32), 3'd0);
        else run_cvt(o, VEC_EEW_NARROW, AWIDTH'(16), AWIDTH'(16), 1'b0, 3'd2, VlW'(27), 3'd3);
        if (k >= 4) run_cvt(o, VEC_EEW_WIDEN, AWIDTH'(8), AWIDTH'(12), 1'b1, 3'd7, VlW'(4), 3'd2);
        else run_cvt(o, VEC_EEW_NARROW, AWIDTH'(8), AWIDTH'(12), 1'b1, 3'd7, VlW'(4), 3'd2);
      end
    end
  endtask  // Automatic

  // Random conversion traffic
  task automatic soak_fcvt(input int n);
    vec_fop_e       o;
    vec_eew_e       e;
    logic     [2:0] lmul;
    int             regs;
    begin
      stall_pct = StallPct;
      seed_fp();
      for (int i = 0; i < n; i++) begin
        o = cvt_op($urandom_range(5));
        e = VEC_EEW_SAME;
        if (1'($urandom) && (o == VEC_FCVT_F_X || o == VEC_FCVT_F_XU)) e = VEC_EEW_WIDEN;
        else if (1'($urandom)) e = VEC_EEW_NARROW;
        if ((e == VEC_EEW_NARROW) && (o == VEC_FCVT_F_X || o == VEC_FCVT_F_XU)) e = VEC_EEW_SAME;
        lmul = 3'($urandom_range(2));
        regs = 1 << lmul[1:0];
        if (e == VEC_EEW_SAME)
          run_cvt(o, e, AWIDTH'(8), AWIDTH'(16), 1'($urandom), lmul, VlW'($urandom_range(4 * regs)),
                  3'($urandom_range(4)));
        else
          run_cvt(o, e, AWIDTH'(8), AWIDTH'(16), 1'($urandom), lmul, VlW'($urandom_range(8 * regs)),
                  3'($urandom_range(4)));
        if ($urandom_range(9) == 0) seed_fp();
      end
      stall_pct = 0;
    end
  endtask  // Automatic

  // Conversion forms legal
  task automatic check_fcvt_rules();
    vec_eew_e e;
    begin
      vill  = 1'b0;
      vlmul = 3'd0;
      vl    = VlW'(4);
      frm   = fp_pkg::RmRne;
      for (int k = 0; k < 6; k++) begin
        for (int w = 0; w < 2; w++) begin
          if (w == 0) e = VEC_EEW_SAME;
          else if (k >= 4) e = VEC_EEW_WIDEN;
          else e = VEC_EEW_NARROW;
          instr = enc(6'b010010, 1'b1, AWIDTH'(8), cvt_rs1(cvt_op(k), e), 3'b001, AWIDTH'(16));
          for (int s = 0; s < 3; s++) begin
            vsew = 3'(s);
            @(negedge clk);
            check($sformatf("convert %0d form %0d at sew %0d", k, w, 8 << s), XLEN'(is_vector),
                  XLEN'(s == ((w == 0) ? 2 : 1)));
          end
          vsew = (w == 0) ? 3'd2 : 3'd1;
          @(negedge clk);
          frm = RmBad;
          @(negedge clk);
          check($sformatf("convert %0d form %0d at frm 5", k, w), XLEN'(is_vector), XLEN'(0));
          frm   = fp_pkg::RmRne;
          vlmul = 3'd3;
          @(negedge clk);
          check($sformatf("convert %0d form %0d at lmul 8", k, w), XLEN'(is_vector), XLEN'(w == 0));
          vlmul = 3'd0;
        end
      end
      vsew  = 3'd1;
      instr = enc(6'b010010, 1'b1, AWIDTH'(8), 5'b01011, 3'b001, AWIDTH'(8));
      @(negedge clk);
      check("widen onto source", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010010, 1'b1, AWIDTH'(8), 5'b01011, 3'b001, AWIDTH'(7));
      @(negedge clk);
      check("widen odd group", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010010, 1'b1, AWIDTH'(8), 5'b10001, 3'b001, AWIDTH'(8));
      @(negedge clk);
      check("narrow onto source", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b010010, 1'b1, AWIDTH'(8), 5'b10001, 3'b001, AWIDTH'(9));
      @(negedge clk);
      check("narrow into source top", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010010, 1'b1, AWIDTH'(7), 5'b10001, 3'b001, AWIDTH'(4));
      @(negedge clk);
      check("narrow odd source", XLEN'(is_vector), XLEN'(0));
      for (int u = 0; u < 32; u++) begin
        instr = enc(6'b010010, 1'b1, AWIDTH'(8), AWIDTH'(u), 3'b101, AWIDTH'(12));
        @(negedge clk);
        check($sformatf("convert %0d scalar form", u), XLEN'(is_vector), XLEN'(0));
      end
      instr = enc(6'b010010, 1'b1, AWIDTH'(8), 5'b01000, 3'b001, AWIDTH'(12));
      @(negedge clk);
      check("widen float to int", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010010, 1'b1, AWIDTH'(8), 5'b10011, 3'b001, AWIDTH'(12));
      @(negedge clk);
      check("narrow int to float", XLEN'(is_vector), XLEN'(0));
      instr = '0;
      vsew  = 3'd2;
    end
  endtask  // Automatic

  // Float merge model
  task automatic run_fmerge(input logic vmb, input logic [AWIDTH-1:0] s2,
                            input logic [AWIDTH-1:0] d, input logic [2:0] lmul,
                            input logic [VlW-1:0] len);
    logic [FLEN-1:0] fsc;
    logic [FLEN-1:0] e;
    begin
      fsc   = fp_pick();
      vsew  = 3'd2;
      vlmul = lmul;
      vl    = len;
      frm   = RmW'($urandom_range(4));
      fdata = fsc;
      xdata = XLEN'($urandom);
      for (int i = 0; i < int'(len); i++) begin
        e = (vmb || shadow[0][i]) ? fsc : XLEN'(grp_get(s2, FLEN, i));
        grp_set(d, FLEN, i, e);
      end
      flags_seen = '0;
      issue(enc(6'b010111, vmb, vmb ? AWIDTH'(0) : s2, AWIDTH'($urandom), 3'b101, d));
      fdata = XLEN'($urandom);
      xdata = XLEN'($urandom);
      frm   = RmW'($urandom);
      drain();
      check_regs($sformatf("%0s lmul %0d vl %0d", vmb ? "vfmv.v.f" : "vfmerge", lmul, len));
      check("float merge flags", XLEN'(flags_seen), XLEN'(0));
      frm = fp_pkg::RmRne;
    end
  endtask  // Automatic

  // Float to element
  task automatic run_fmv_sf(input logic [AWIDTH-1:0] d, input logic [2:0] lmul,
                            input logic [VlW-1:0] len);
    logic [FLEN-1:0] fsc;
    begin
      fsc   = fp_pick();
      vsew  = 3'd2;
      vlmul = lmul;
      vl    = len;
      fdata = fsc;
      xdata = XLEN'($urandom);
      if (len != '0) shadow[d][FLEN-1:0] = fsc;
      flags_seen = '0;
      issue(enc(6'b010000, 1'b1, AWIDTH'(0), AWIDTH'($urandom), 3'b101, d));
      fdata = XLEN'($urandom);
      xdata = XLEN'($urandom);
      drain();
      check_regs($sformatf("vfmv.s.f v%0d lmul %0d vl %0d", d, lmul, len));
      check("vfmv.s.f flags", XLEN'(flags_seen), XLEN'(0));
    end
  endtask  // Automatic

  // Float scalar read
  task automatic read_scalar(input logic [31:0] word, output logic held, output logic early,
                             output logic [XLEN-1:0] got);
    @(negedge clk);
    instr       = word;
    instr_valid = 1'b1;
    @(posedge clk);
    held  = vec_hold;
    early = xreg_valid;
    while (vec_hold) @(posedge clk);
    got = xreg_result;
    @(negedge clk);
    instr_valid = 1'b0;
  endtask  // Automatic

  // Element to float
  task automatic run_fmv_fs(input logic [AWIDTH-1:0] s2, input logic [2:0] lmul,
                            input logic [VlW-1:0] len);
    logic [FLEN-1:0] want;
    logic [XLEN-1:0] got;
    logic held;
    logic early;
    begin
      vsew  = 3'd2;
      vlmul = lmul;
      vl    = len;
      want  = shadow[s2][FLEN-1:0];
      flags_seen = '0;
      read_scalar(enc(6'b010000, 1'b1, s2, AWIDTH'(0), 3'b001, AWIDTH'($urandom)), held, early,
                  got);
      check("vfmv.f.s holds", XLEN'(held), XLEN'(1));
      check("vfmv.f.s not integer", XLEN'(early), XLEN'(0));
      drain();
      check($sformatf("vfmv.f.s v%0d lmul %0d vl %0d", s2, lmul, len), XLEN'(got), XLEN'(want));
      check_regs($sformatf("vfmv.f.s v%0d lmul %0d vl %0d", s2, lmul, len));
      check("vfmv.f.s flags", XLEN'(flags_seen), XLEN'(0));
    end
  endtask  // Automatic

  // Float move legality
  task automatic check_fp_move_rules();
    logic [31:0] forms[4];
    begin
      forms[0] = enc(6'b010111, 1'b0, AWIDTH'(8), AWIDTH'(1), 3'b101, AWIDTH'(12));
      forms[1] = enc(6'b010111, 1'b1, AWIDTH'(0), AWIDTH'(1), 3'b101, AWIDTH'(12));
      forms[2] = enc(6'b010000, 1'b1, AWIDTH'(0), AWIDTH'(1), 3'b101, AWIDTH'(12));
      forms[3] = enc(6'b010000, 1'b1, AWIDTH'(8), AWIDTH'(0), 3'b001, AWIDTH'(12));
      vill  = 1'b0;
      vlmul = 3'd0;
      vl    = VlW'(4);
      for (int k = 0; k < 4; k++) begin
        instr = forms[k];
        for (int sw = 0; sw < 3; sw++) begin
          vsew = 3'(sw);
          for (int m = 0; m < 8; m++) begin
            frm = RmW'(m);
            @(negedge clk);
            check($sformatf("float move %0d sew %0d frm %0d", k, 8 << sw, m), XLEN'(is_vector),
                  XLEN'((sw == 2) && (m < 5)));
          end
        end
        vsew = 3'd2;
        frm  = fp_pkg::RmRne;
        vill = 1'b1;
        @(negedge clk);
        check($sformatf("float move %0d vill", k), XLEN'(is_vector), XLEN'(0));
        vill = 1'b0;
      end
      instr = enc(6'b010000, 1'b0, AWIDTH'(0), AWIDTH'(1), 3'b101, AWIDTH'(12));
      @(negedge clk);
      check("vfmv.s.f masked", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010000, 1'b0, AWIDTH'(8), AWIDTH'(0), 3'b001, AWIDTH'(12));
      @(negedge clk);
      check("vfmv.f.s masked", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010111, 1'b0, AWIDTH'(8), AWIDTH'(1), 3'b101, AWIDTH'(0));
      @(negedge clk);
      check("vfmerge onto v0", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010111, 1'b1, AWIDTH'(0), AWIDTH'(1), 3'b101, AWIDTH'(0));
      @(negedge clk);
      check("vfmv.v.f onto v0", XLEN'(is_vector), XLEN'(1));
      vlmul = 3'd2;
      instr = enc(6'b010111, 1'b0, AWIDTH'(8), AWIDTH'(1), 3'b101, AWIDTH'(6));
      @(negedge clk);
      check("vfmerge misaligned vd", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010111, 1'b0, AWIDTH'(6), AWIDTH'(1), 3'b101, AWIDTH'(8));
      @(negedge clk);
      check("vfmerge misaligned vs2", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b010000, 1'b1, AWIDTH'(0), AWIDTH'(1), 3'b101, AWIDTH'(3));
      @(negedge clk);
      check("vfmv.s.f ignores lmul", XLEN'(is_vector), XLEN'(1));
      instr = enc(6'b010000, 1'b1, AWIDTH'(3), AWIDTH'(0), 3'b001, AWIDTH'(12));
      @(negedge clk);
      check("vfmv.f.s ignores lmul", XLEN'(is_vector), XLEN'(1));
      instr = '0;
      vlmul = 3'd0;
    end
  endtask  // Automatic

  function automatic logic fred_is_sum(input vec_fop_e o);
    return (o == VEC_FREDOSUM) || (o == VEC_FREDUSUM);
  endfunction

  task automatic ref_fred(input vec_fop_e o, input logic [AWIDTH-1:0] s1,
                          input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d, input logic vmb,
                          input int regs, input int len, input logic [RmW-1:0] rm,
                          output logic [FlagW-1:0] want_flags);
    logic [FLEN-1:0] acc;
    logic [FLEN-1:0] v;
    fres_t r;
    logic seen;
    want_flags = '0;
    seen       = 1'b0;
    if (len == 0) return;
    acc = FLEN'(grp_get(s1, FLEN, 0));
    for (int i = 0; i < group_elems(FLEN, regs); i++) begin
      if ((i < len) && (vmb || shadow[0][i])) begin
        v    = FLEN'(grp_get(s2, FLEN, i));
        seen = 1'b1;
        if (fred_is_sum(o)) r = ref_add(acc, v, rm);
        else r = ref_minmax(o, acc, v);
        acc        = r[FLEN-1:0];
        want_flags = want_flags | r[FLEN+:FlagW];
      end
    end
    if (!seen && (o == VEC_FREDUSUM) && f_nan(acc)) begin
      if (f_snan(acc)) want_flags = want_flags | fp_pkg::FlagNv;
      acc = CanonNan;
    end
    grp_set(d, FLEN, 0, ELEN'(acc));
  endtask  // Automatic

  task automatic run_fred(input vec_fop_e o, input logic [AWIDTH-1:0] s1,
                          input logic [AWIDTH-1:0] s2, input logic [AWIDTH-1:0] d, input logic vmb,
                          input logic [2:0] lmul, input logic [VlW-1:0] len,
                          input logic [RmW-1:0] rm);
    logic [FlagW-1:0] want;
    int regs;
    regs  = lmul[2] ? 1 : (1 << lmul[1:0]);
    vsew  = 3'd2;
    vlmul = lmul;
    vl    = len;
    frm   = rm;
    ref_fred(o, s1, s2, d, vmb, regs, int'(len), rm, want);
    flags_seen = '0;
    issue(fred_encode(o, s1, s2, d, vmb));
    frm = RmW'($urandom_range(4));
    drain();
    check($sformatf("fflags after %0s reduction", o.name()), XLEN'(flags_seen), XLEN'(want));
    check_regs($sformatf("%0s reduction lmul %0d vl %0d", o.name(), lmul, len));
  endtask  // Automatic

  // Signed zeros NaNs
  function automatic logic [FLEN-1:0] fred_pick();
    case ($urandom_range(
        7
    ))
      0: return 1'($urandom) ? FLEN'(0) : NegZero;
      1: return 1'($urandom) ? SnanPos : SnanNeg;
      2: return 1'($urandom) ? CanonNan : QnanNeg;
      default: return fp_pick();
    endcase
  endfunction

  task automatic seed_fred();
    for (int r = 0; r < Depth; r++) begin
      for (int e = 0; e < FpElems; e++) img[r][e*FLEN+:FLEN] = fred_pick();
      shadow[r] = img[r];
    end
    seed_image();
  endtask  // Automatic

  // Ordered sum order
  function automatic logic [VLEN-1:0] cancel_vec();
    cancel_vec = '0;
    cancel_vec[0*FLEN+:FLEN] = FpBig;
    cancel_vec[1*FLEN+:FLEN] = FpOne;
    cancel_vec[2*FLEN+:FLEN] = FpOne;
    cancel_vec[3*FLEN+:FLEN] = fneg(FpBig);
  endfunction

  // Cycles until idle
  task automatic idle_cycles(input logic [31:0] word, output int n);
    issue(word);
    n = 0;
    while (!vec_idle && (n < IdleWait)) begin
      @(negedge clk);
      n++;
    end
  endtask  // Automatic

  // Group step cadence
  task automatic check_fred_timing();
    logic [31:0] word;
    int one;
    int full;
    seed_fred();
    vsew = 3'd2;
    frm  = fp_pkg::RmRne;
    for (int k = 0; k < 4; k++) begin
      case (k)
        0: word = enc(funct6_of(VEC_ADD), 1'b1, AWIDTH'(8), AWIDTH'(16), 3'b000, AWIDTH'(24));
        1: word = fred_encode(VEC_FMIN, AWIDTH'(1), AWIDTH'(8), AWIDTH'(2), 1'b1);
        2: word = fred_encode(VEC_FREDOSUM, AWIDTH'(1), AWIDTH'(8), AWIDTH'(3), 1'b1);
        default: word = fred_encode(VEC_FREDUSUM, AWIDTH'(1), AWIDTH'(8), AWIDTH'(4), 1'b1);
      endcase
      vlmul = 3'd0;
      vl    = VlW'(FpElems);
      idle_cycles(word, one);
      vlmul = 3'd3;
      vl    = VlW'(GroupRegs * FpElems);
      idle_cycles(word, full);
      check(
          $sformatf("cadence of form %0d", k), XLEN'(full - one),
          (k < 2) ? XLEN'(GroupRegs - 1) : XLEN'(fp_pkg::FpAddLatency * FpElems * (GroupRegs - 1)));
    end
    seed_fred();
    vlmul = 3'd0;
    vl    = VlW'(FpElems);
  endtask  // Automatic

  function automatic logic [31:0] fred_encode(input vec_fop_e o, input logic [AWIDTH-1:0] s1,
                                              input logic [AWIDTH-1:0] s2,
                                              input logic [AWIDTH-1:0] d, input logic vmb);
    logic [5:0] f6;
    case (o)
      VEC_FREDUSUM: f6 = 6'b000001;
      VEC_FREDOSUM: f6 = 6'b000011;
      VEC_FMAX:     f6 = 6'b000111;
      default:      f6 = 6'b000101;
    endcase
    return enc(f6, vmb, s2, s1, 3'b001, d);
  endfunction

  task automatic check_fred_ops();
    vec_fop_e o;
    int       regs;
    begin
      for (int k = 0; k < 4; k++) begin
        case (k)
          0: o = VEC_FMIN;
          1: o = VEC_FMAX;
          2: o = VEC_FREDOSUM;
          default: o = VEC_FREDUSUM;
        endcase
        for (int lmul = 0; lmul < 4; lmul++) begin
          regs = 1 << lmul;
          for (int m = 0; m < 2; m++) begin
            seed_fred();
            run_fred(o, AWIDTH'(4), AWIDTH'(16), AWIDTH'(5), 1'(m), 3'(lmul), VlW'(0), 3'd0);
            run_fred(o, AWIDTH'(4), AWIDTH'(16), AWIDTH'(5), 1'(m), 3'(lmul), VlW'(1), 3'd1);
            run_fred(o, AWIDTH'(4), AWIDTH'(16), AWIDTH'(4), 1'(m), 3'(lmul), VlW'($urandom_range(
                     4 * regs, 1)), 3'd2);
            run_fred(o, AWIDTH'(4), AWIDTH'(16), AWIDTH'(16), 1'(m), 3'(lmul), VlW'(4 * regs),
                     3'd3);
            run_fred(o, AWIDTH'(4), AWIDTH'(16), AWIDTH'(0), 1'(m), 3'(lmul), VlW'(4 * regs), 3'd4);
          end
        end
      end
      seed_fred();
      seed_reg(AWIDTH'(16), cancel_vec());
      seed_reg(AWIDTH'(4), '0);
      for (int rm = 0; rm < 5; rm++) begin
        run_fred(VEC_FREDOSUM, AWIDTH'(4), AWIDTH'(16), AWIDTH'(5), 1'b1, 3'd0, VlW'(4), 3'(rm));
        run_fred(VEC_FREDUSUM, AWIDTH'(4), AWIDTH'(16), AWIDTH'(5), 1'b1, 3'd0, VlW'(4), 3'(rm));
      end
      seed_reg(AWIDTH'(4), {FpElems{SnanPos}});
      seed_reg(AWIDTH'(0), '0);
      run_fred(VEC_FREDOSUM, AWIDTH'(4), AWIDTH'(16), AWIDTH'(5), 1'b0, 3'd0, VlW'(4), 3'd0);
      run_fred(VEC_FREDUSUM, AWIDTH'(4), AWIDTH'(16), AWIDTH'(5), 1'b0, 3'd0, VlW'(4), 3'd0);
      seed_reg(AWIDTH'(16), {FpElems{NegZero}});
      seed_reg(AWIDTH'(4), '0);
      run_fred(VEC_FMIN, AWIDTH'(4), AWIDTH'(16), AWIDTH'(5), 1'b1, 3'd0, VlW'(4), 3'd0);
      run_fred(VEC_FMAX, AWIDTH'(4), AWIDTH'(16), AWIDTH'(5), 1'b1, 3'd0, VlW'(4), 3'd0);
      seed_reg(AWIDTH'(4), {FpElems{SnanPos}});
      seed_reg(AWIDTH'(0), '0);
      run_fred(VEC_FMIN, AWIDTH'(4), AWIDTH'(16), AWIDTH'(5), 1'b0, 3'd1, VlW'(8), 3'd0);
      run_fred(VEC_FMAX, AWIDTH'(4), AWIDTH'(16), AWIDTH'(6), 1'b1, 3'd1, VlW'(8), 3'd0);
    end
  endtask  // Automatic

  // Reductions among traffic
  task automatic check_fred_stream();
    logic [FlagW-1:0] want;
    logic [FlagW-1:0] f;
    logic             sat;
    begin
      stall_pct = StallPct;
      for (int r = 0; r < 6; r++) begin
        seed_fred();
        vsew  = 3'd2;
        vlmul = 3'd0;
        vl    = VlW'(4);
        frm   = RmW'(r % 5);
        want  = '0;
        model_fp(VEC_FMUL, 0, AWIDTH'(1), AWIDTH'(2), AWIDTH'(10), 1'b1, '0, 1, VlW'(4), 3'(r % 5),
                 f);
        want = want | f;
        ref_fred(VEC_FREDOSUM, AWIDTH'(3), AWIDTH'(10), AWIDTH'(11), 1'b1, 1, 4, frm, f);
        want = want | f;
        ref_apply(VEC_ADD, 0, AWIDTH'(4), AWIDTH'(5), AWIDTH'(12), 1'b1, '0, AWIDTH'(0), 32, 1, 4);
        ref_fred(VEC_FMAX, AWIDTH'(11), AWIDTH'(6), AWIDTH'(13), 1'b0, 1, 4, frm, f);
        want = want | f;
        model_lane(VEC_MUL, 0, AWIDTH'(7), AWIDTH'(8), AWIDTH'(14), 1'b1, '0, AWIDTH'(0), 32, 1,
                   VlW'(4), 2'd0, sat);
        ref_fred(VEC_FREDUSUM, AWIDTH'(13), AWIDTH'(14), AWIDTH'(15), 1'b1, 1, 4, frm, f);
        want = want | f;
        ref_fred(VEC_FREDOSUM, AWIDTH'(15), AWIDTH'(10), AWIDTH'(16), 1'b0, 1, 4, frm, f);
        want = want | f;
        ref_fred(VEC_FMIN, AWIDTH'(3), AWIDTH'(2), AWIDTH'(17), 1'b1, 1, 4, frm, f);
        want = want | f;
        ref_reduce(VEC_REDSUM, AWIDTH'(1), AWIDTH'(2), AWIDTH'(18), 1'b1, 32, 1, 4, 1'b0);
        flags_seen = '0;
        issue(fp_encode(VEC_FMUL, 0, AWIDTH'(1), AWIDTH'(2), AWIDTH'(10), 1'b1));
        issue(fred_encode(VEC_FREDOSUM, AWIDTH'(3), AWIDTH'(10), AWIDTH'(11), 1'b1));
        issue(enc(6'b000000, 1'b1, AWIDTH'(5), AWIDTH'(4), 3'b000, AWIDTH'(12)));
        issue(fred_encode(VEC_FMAX, AWIDTH'(11), AWIDTH'(6), AWIDTH'(13), 1'b0));
        issue(lane_instr(VEC_MUL, 0, AWIDTH'(7), AWIDTH'(8), AWIDTH'(14), 1'b1, AWIDTH'(0)));
        issue(fred_encode(VEC_FREDUSUM, AWIDTH'(13), AWIDTH'(14), AWIDTH'(15), 1'b1));
        issue(fred_encode(VEC_FREDOSUM, AWIDTH'(15), AWIDTH'(10), AWIDTH'(16), 1'b0));
        issue(fred_encode(VEC_FMIN, AWIDTH'(3), AWIDTH'(2), AWIDTH'(17), 1'b1));
        issue(enc(6'b000000, 1'b1, AWIDTH'(2), AWIDTH'(1), 3'b010, AWIDTH'(18)));
        frm = fp_pkg::RmRne;
        drain();
        check_regs($sformatf("reduction stream %0d", r));
        check($sformatf("fflags after reduction stream %0d", r), XLEN'(flags_seen), XLEN'(want));
      end
      stall_pct = 0;
    end
  endtask  // Automatic

  task automatic soak_fred(input int n);
    vec_fop_e       o;
    logic     [2:0] lmul;
    int             regs;
    begin
      stall_pct = StallPct;
      seed_fred();
      for (int i = 0; i < n; i++) begin
        lmul = 3'($urandom_range(3));
        regs = 1 << lmul[1:0];
        case ($urandom_range(
            3
        ))
          0: o = VEC_FMIN;
          1: o = VEC_FMAX;
          2: o = VEC_FREDOSUM;
          default: o = VEC_FREDUSUM;
        endcase
        run_fred(o, AWIDTH'($urandom_range(31)), AWIDTH'(8 * $urandom_range(3)),
                 AWIDTH'($urandom_range(31)), 1'($urandom), lmul, VlW'($urandom_range(4 * regs)),
                 3'($urandom_range(4)));
        if ($urandom_range(7) == 0) seed_fred();
      end
      stall_pct = 0;
    end
  endtask  // Automatic

  task automatic check_fred_rules();
    begin
      vill  = 1'b0;
      vlmul = 3'd0;
      vl    = VlW'(4);
      vsew  = 3'd2;
      frm   = fp_pkg::RmRne;
      instr = fred_encode(VEC_FMIN, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1);
      for (int s = 0; s < 3; s++) begin
        vsew = 3'(s);
        @(negedge clk);
        check($sformatf("float reduction at sew %0d", 8 << s), XLEN'(is_vector), XLEN'(s == 2));
      end
      for (int m = 0; m < 8; m++) begin
        frm = RmW'(m);
        @(negedge clk);
        check($sformatf("float reduction at frm %0d", m), XLEN'(is_vector), XLEN'(m < 5));
      end
      for (int k = 0; k < 2; k++) begin
        if (k == 0) instr = fred_encode(VEC_FREDOSUM, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b1);
        else instr = fred_encode(VEC_FREDUSUM, AWIDTH'(4), AWIDTH'(8), AWIDTH'(12), 1'b0);
        for (int s = 0; s < 3; s++) begin
          for (int m = 4; m < 7; m++) begin
            vsew = 3'(s);
            frm  = RmW'(m);
            @(negedge clk);
            check($sformatf("float sum %0d at sew %0d frm %0d", k, 8 << s, m), XLEN'(is_vector),
                  XLEN'((s == 2) && (m < 5)));
          end
        end
      end
      vsew  = 3'd2;
      frm   = fp_pkg::RmRne;
      instr = enc(6'b000001, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b101, AWIDTH'(12));
      @(negedge clk);
      check("float sum scalar form", XLEN'(is_vector), XLEN'(0));
      instr = enc(6'b000111, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b101, AWIDTH'(12));
      @(negedge clk);
      check("float reduction scalar form", XLEN'(is_vector), XLEN'(0));
      instr = fred_encode(VEC_FMAX, AWIDTH'(4), AWIDTH'(9), AWIDTH'(12), 1'b1);
      vlmul = 3'd1;
      @(negedge clk);
      check("misaligned reduction source", XLEN'(is_vector), XLEN'(0));
      instr = fred_encode(VEC_FMAX, AWIDTH'(5), AWIDTH'(8), AWIDTH'(13), 1'b0);
      @(negedge clk);
      check("reduction scalar and dest any", XLEN'(is_vector), XLEN'(1));
      instr = '0;
      vlmul = 3'd0;
    end
  endtask  // Automatic

  // Every float move
  task automatic check_fp_moves();
    logic [2:0] lmul;
    int regs;
    begin
      seed_fp();
      for (int g = 0; g < 4; g++) begin
        lmul = 3'(g);
        regs = 1 << g;
        run_fmerge(1'b0, AWIDTH'(16), AWIDTH'(8), lmul, VlW'(4 * regs));
        run_fmerge(1'b0, AWIDTH'(24), AWIDTH'(16), lmul, VlW'(1 + $urandom_range(4 * regs - 1)));
        run_fmerge(1'b1, AWIDTH'(0), AWIDTH'(8), lmul, VlW'(4 * regs));
        run_fmerge(1'b1, AWIDTH'(0), AWIDTH'(24), lmul, VlW'(1 + $urandom_range(4 * regs - 1)));
        run_fmerge(1'b0, AWIDTH'(8), AWIDTH'(8), lmul, VlW'(4 * regs));
        run_fmerge(1'b0, AWIDTH'(16), AWIDTH'(8), lmul, VlW'(0));
        run_fmerge(1'b1, AWIDTH'(0), AWIDTH'(8), lmul, VlW'(0));
        run_fmv_sf(AWIDTH'(8 + g), lmul, VlW'(1 + $urandom_range(4 * regs - 1)));
        run_fmv_sf(AWIDTH'(9), lmul, VlW'(0));
        run_fmv_fs(AWIDTH'(16 + g), lmul, VlW'(1 + $urandom_range(4 * regs - 1)));
        run_fmv_fs(AWIDTH'(17), lmul, VlW'(0));
        seed_fp();
      end
      run_fmerge(1'b1, AWIDTH'(0), AWIDTH'(0), 3'd0, VlW'(4));
    end
  endtask  // Automatic

  // Moves behind float
  task automatic check_fp_move_stream();
    logic [FlagW-1:0] f;
    logic [FLEN-1:0] fsc;
    logic [FLEN-1:0] want;
    logic [XLEN-1:0] got;
    logic held;
    logic early;
    begin
      for (int r = 0; r < 6; r++) begin
        seed_fp();
        vsew  = 3'd2;
        vlmul = 3'(r % 4);
        vl    = VlW'(FpElems << (r % 4));
        frm   = RmW'($urandom_range(4));
        fsc   = fp_pick();
        model_fp(VEC_FMUL, 0, AWIDTH'(16), AWIDTH'(24), AWIDTH'(8), 1'b1, '0, 1 << (r % 4), vl, frm,
                 f);
        for (int i = 0; i < int'(vl); i++)
        grp_set(AWIDTH'(16), FLEN, i, shadow[0][i] ? fsc : XLEN'(grp_get(AWIDTH'(8), FLEN, i)));
        want = shadow[16][FLEN-1:0];
        issue(fp_encode(VEC_FMUL, 0, AWIDTH'(16), AWIDTH'(24), AWIDTH'(8), 1'b1));
        fdata = fsc;
        issue(enc(6'b010111, 1'b0, AWIDTH'(8), AWIDTH'(1), 3'b101, AWIDTH'(16)));
        fdata = XLEN'($urandom);
        read_scalar(enc(6'b010000, 1'b1, AWIDTH'(16), AWIDTH'(0), 3'b001, AWIDTH'(3)), held, early,
                    got);
        drain();
        check($sformatf("vfmv.f.s after merge %0d", r), XLEN'(got), XLEN'(want));
        check_regs($sformatf("float move stream %0d", r));
        frm = fp_pkg::RmRne;
      end
    end
  endtask  // Automatic

  // Nonzero vstart traps
  task automatic check_vstart_rules();
    logic [ 5:0] f6;
    logic [ 2:0] f3;
    logic [31:0] form[18];
    begin
      vill  = 1'b0;
      vlmul = 3'd0;
      vl    = VlW'(4);
      frm   = fp_pkg::RmRne;
      for (int k = 0; k < 16; k++) begin
        f3 = 3'b010;
        case (k)
          8: begin
            f6 = 6'b110000;
            f3 = 3'b000;
          end
          9: begin
            f6 = 6'b110001;
            f3 = 3'b000;
          end
          10, 11, 12, 13: begin
            f6 = {3'b000, 2'(k - 10), 1'b1};
            f3 = 3'b001;
          end
          14: begin
            f6 = 6'b000000;
            f3 = 3'b000;
          end
          15: begin
            f6 = 6'b000000;
            f3 = 3'b001;
          end
          default: f6 = 6'(k);
        endcase
        vsew  = (f3 == 3'b001) ? 3'd2 : 3'd1;
        instr = enc(f6, 1'b1, AWIDTH'(8), AWIDTH'(4), f3, AWIDTH'(12));
        for (int v = 0; v < 2; v++) begin
          vstart_set = 1'(v);
          @(negedge clk);
          check($sformatf("form %0d with vstart set %0d", k, v), XLEN'(is_vector), XLEN'(v == 0));
        end
      end
      vsew = 3'd2;
      form = '{
          enc(6'b010100, 1'b1, AWIDTH'(8), 5'b00001, 3'b010, AWIDTH'(12)),
          enc(6'b010100, 1'b1, AWIDTH'(8), 5'b00011, 3'b010, AWIDTH'(12)),
          enc(6'b010100, 1'b1, AWIDTH'(8), 5'b00010, 3'b010, AWIDTH'(12)),
          enc(6'b010100, 1'b1, AWIDTH'(8), 5'b10000, 3'b010, AWIDTH'(12)),
          enc(6'b010100, 1'b1, AWIDTH'(0), 5'b10001, 3'b010, AWIDTH'(12)),
          enc(6'b010000, 1'b1, AWIDTH'(8), 5'b10000, 3'b010, AWIDTH'(12)),
          enc(6'b010000, 1'b1, AWIDTH'(8), 5'b10001, 3'b010, AWIDTH'(12)),
          enc(6'b010000, 1'b1, AWIDTH'(8), AWIDTH'(0), 3'b010, AWIDTH'(12)),
          enc(6'b010000, 1'b1, AWIDTH'(0), AWIDTH'(4), 3'b110, AWIDTH'(12)),
          enc(6'b011001, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b010, AWIDTH'(12)),
          enc(6'b011000, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(12)),
          enc(6'b100101, 1'b1, AWIDTH'(8), AWIDTH'(4), 3'b010, AWIDTH'(12)),
          enc(6'b100111, 1'b1, AWIDTH'(8), AWIDTH'(0), 3'b011, AWIDTH'(12)),
          enc(6'b010111, 1'b0, AWIDTH'(8), AWIDTH'(4), 3'b000, AWIDTH'(12)),
          enc_mem(1'b0, 2'd2, 1'b0, 1'b0, 1'b1, AWIDTH'(12)),
          enc_mem(1'b1, 2'd2, 1'b0, 1'b0, 1'b1, AWIDTH'(12)),
          enc_mem(1'b0, 2'd2, 1'b0, 1'b1, 1'b1, AWIDTH'(12)),
          enc_mem(1'b0, 2'd2, 1'b1, 1'b0, 1'b1, AWIDTH'(12))
      };
      for (int k = 0; k < 18; k++) begin
        instr = form[k];
        for (int v = 0; v < 2; v++) begin
          vstart_set = 1'(v);
          @(negedge clk);
          check($sformatf("class %0d with vstart set %0d", k, v), XLEN'(is_vector),
                XLEN'((k >= 14) || (v == 0)));
        end
      end
      vstart_set = 1'b0;
      instr      = '0;
      vsew       = 3'd2;
    end
  endtask  // Automatic

  task automatic do_verdict();
    if (ref_checks < MinRefChecks)
      $fatal(
          1, "TB UNDER-RAN: %0d reference checks, expected at least %0d", ref_checks, MinRefChecks
      );
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial watchdog();

  initial begin
    check_references();
    do_reset();
    seed_all();

    // Integer element ops
    check_snapshot();
    check_not_vector();
    check_tail();
    check_masked();
    check_groups();
    check_forms();
    check_zero_length();
    soak(120);

    // Legality and masks
    check_mem_rules();
    check_group_rules();
    check_fixed_point();
    check_compares();
    check_carry();
    check_mask_logic();
    check_mask_set();
    check_mask_index();
    check_mask_unary_rules();
    check_mask_scalar();

    // Memory moves
    check_mem_cancel();
    check_mem_pending();
    check_moves();
    soak_mem(300);
    check_whole_rules();
    check_whole();

    // Mixed width forms
    check_widening();
    check_narrowing();
    check_extensions();
    check_reductions();
    check_scalar_moves();

    // Multiply and fixed point
    check_lane_rules();
    check_multiplies();
    check_widening_muls();
    check_slide_rules();
    check_slides();
    check_slide_stream();
    check_fixed_ops();
    check_divides();
    check_averaging();
    check_divide_overlap();
    check_lane_stream();
    soak_lanes(200);

    // Float lanes
    check_fp_rules();
    check_fp_ops();
    check_fp_stream();
    check_fp_group_stream();
    check_fdiv_stream();
    soak_fp(200);
    check_fcvt_rules();
    check_fcvt_ops();
    soak_fcvt(120);
    check_fp_move_rules();
    check_fp_moves();
    check_fp_move_stream();

    // Float reductions
    check_fred_rules();
    check_vstart_rules();
    check_fred_ops();
    check_fred_stream();
    check_fred_timing();
    soak_fred(150);

    do_verdict();
  end

  // Memory model
  assign line_base = mem_addr & ~XLEN'(LineB - 1);
  always_comb begin
    if (img_mode) mem_rdata = img[(line_base/LineB)%Depth];
    else for (int k = 0; k < LineB; k++) mem_rdata[k*8+:8] = mem[(line_base+XLEN'(k))%Bytes];
  end

  always @(negedge clk) mem_ready = ($urandom_range(99) < ready_pct);

  always @(posedge clk) begin
    if (rst_n && core_en && mem_req && mem_ready) begin
      for (int k = 0; k < LineB; k++) begin
        if (mem_wstrb[k] && img_mode) dump[(line_base/LineB)%Depth][k*8+:8] <= mem_wdata[k*8+:8];
        else if (mem_wstrb[k]) mem[(line_base+XLEN'(k))%Bytes] <= mem_wdata[k*8+:8];
      end
    end
  end

  // Flags reaching fflags
  always @(negedge clk) if (rst_n && core_en) flags_seen = flags_seen | fflags;

endmodule

`default_nettype wire
