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
  localparam int Timeout = 200000;
  localparam int MinChecks = 140000;

  int               checks = 0;
  int               errors = 0;
  int               max_errors = 0;

  logic             clk = 1'b0;
  logic             rst_n;
  logic             core_en;
  logic [     31:0] instr;
  logic             instr_valid;
  logic             cancel;
  logic [ XLEN-1:0] xdata;
  logic [ XLEN-1:0] xstride;
  logic [ XLEN-1:0] fdata;
  logic [      2:0] frm;
  logic [      4:0] fflags;
  logic             vstart_set;
  logic [      4:0] flags_seen;
  logic             vill;
  logic [  VlW-1:0] vl;
  logic [      2:0] vsew;
  logic [      2:0] vlmul;
  logic [      1:0] vxrm;
  logic             vxsat;
  logic             csr_we;
  logic [     11:0] csr_waddr;
  logic [ XLEN-1:0] csr_wdata;
  logic             csr_wait;
  logic             is_vector;
  logic             vec_hold;
  logic             vec_idle;
  logic             load_pending;
  logic             store_pending;
  logic             mem_misaligned;
  logic [ XLEN-1:0] mem_bad_addr;
  logic             xreg_valid;
  logic [ XLEN-1:0] xreg_result;

  logic [ VLEN-1:0] shadow          [Depth];

  // Memory model
  logic [ VLEN-1:0] mem_rdata;
  logic             mem_ready;
  logic             mem_req;
  logic [ XLEN-1:0] mem_addr;
  logic [ VLEN-1:0] mem_wdata;
  logic [LineB-1:0] mem_wstrb;
  logic [ XLEN-1:0] line_base;
  logic [      7:0] mem             [Bytes];
  logic [      7:0] gmem            [Bytes];
  int               ready_pct = 100;

  always #5 clk = ~clk;

  logic dec_valid;
  vec_op_e dec_op;
  vec_src_e dec_src;
  vec_eew_e dec_eew;
  logic dec_vm;
  logic [4:0] dec_vs1;
  logic [4:0] dec_vs2;
  logic [4:0] dec_vd;
  logic [4:0] dec_simm;
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

  assign line_base = mem_addr & ~XLEN'(LineB - 1);
  always_comb begin
    for (int k = 0; k < LineB; k++) mem_rdata[k*8+:8] = mem[(line_base+XLEN'(k))%Bytes];
  end

  always @(posedge clk) begin
    #2;
    mem_ready = ($urandom_range(99) < ready_pct);
  end

  always @(posedge clk) begin
    if (rst_n && core_en && mem_req && mem_ready) begin
      for (int k = 0; k < LineB; k++)
      if (mem_wstrb[k]) mem[(line_base+XLEN'(k))%Bytes] <= mem_wdata[k*8+:8];
    end
  end

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
        VEC_ADC:   ref_op = (a + b + {31'd0, cin}) & m;
        VEC_SBC:   ref_op = (a - b - {31'd0, cin}) & m;
        VEC_MERGE: ref_op = (vmb || cin) ? b : a;
        default:   ref_op = 32'd0;
      endcase
    end
  endfunction

  // Encode one instruction
  function automatic logic [31:0] enc(input logic [5:0] f6, input logic vmb, input logic [4:0] s2,
                                      input logic [4:0] s1, input logic [2:0] f3,
                                      input logic [4:0] d);
    enc = {f6, vmb, s2, s1, f3, d, 7'b1010111};
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

  // Peek and seed
  logic [VLEN-1:0] peek[Depth];
  logic seed_pulse = 1'b0;
  logic [AWIDTH-1:0] seed_addr = '0;
  logic [VLEN-1:0] seed_data = '0;

  for (genvar b = 0; b < VLEN; b++) begin : g_tap
    for (genvar r = 0; r < Depth; r++) begin : g_reg
      assign peek[r][b] = dut.u_regfile.g_bit[b].bmem[r];
    end
    always @(seed_pulse) dut.u_regfile.g_bit[b].bmem[seed_addr] = seed_data[b];
  end

  task automatic seed_reg(input logic [AWIDTH-1:0] r, input logic [VLEN-1:0] data);
    seed_addr  = r;
    seed_data  = data;
    seed_pulse = ~seed_pulse;
    #0;
    shadow[r] = data;
  endtask

  function automatic logic [VLEN-1:0] rand_vec();
    for (int w = VLEN / 32 - 1; w >= 0; w--) rand_vec[w*32+:32] = $urandom;
  endfunction

  task automatic seed_all();
    for (int r = 0; r < Depth; r++) seed_reg(AWIDTH'(r), rand_vec());
  endtask

  task automatic init_signals();
    rst_n       = 1'b0;
    core_en     = 1'b1;
    instr       = '0;
    instr_valid = 1'b0;
    cancel      = 1'b0;
    xdata       = '0;
    xstride     = '0;
    fdata       = '0;
    frm         = 3'd0;
    vstart_set  = 1'b0;
    vill        = 1'b0;
    mem_ready   = 1'b1;
    for (int b = 0; b < Bytes; b++) begin
      mem[b]  = 8'($urandom);
      gmem[b] = mem[b];
    end
    vl    = 8'd4;
    vsew  = 3'd2;
    vlmul = 3'd0;
    csr_we = 1'b0;
    csr_waddr = 12'd0;
    csr_wdata = '0;
    csr_wait = 1'b0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    seed_all();
    @(negedge clk);
  endtask

  // Present one instruction
  task automatic issue(input logic [31:0] enc_instr);
    @(negedge clk);
    instr       = enc_instr;
    instr_valid = 1'b1;
    #1;
    while (vec_hold) @(negedge clk);
    @(posedge clk);
    #1 instr_valid = 1'b0;
  endtask

  task automatic drain();
    int guard;
    begin
      guard = 0;
      while (!vec_idle && guard < 400) begin
        @(negedge clk);
        guard = guard + 1;
      end
      checks = checks + 1;
      if (!vec_idle) begin
        errors = errors + 1;
        $display("FAIL never went idle at %0t", $time);
        if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
      end
      checks = checks + 1;
      if (dut.u_issue.u_busy.busy != '0) begin
        errors = errors + 1;
        $display("FAIL busy %h at idle %0t", dut.u_issue.u_busy.busy, $time);
        if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
      end
      @(negedge clk);
    end
  endtask

  // Model one instruction
  task automatic ref_apply(input vec_op_e o, input int form, input logic [4:0] s1,
                           input logic [4:0] s2, input logic [4:0] d, input logic vmb,
                           input logic [XLEN-1:0] xd, input logic [4:0] im, input int w,
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
            ea = get_elem(shadow[(32'(s2)+r)%Depth], w, e);
            case (form)
              0: eb = get_elem(shadow[(32'(s1)+r)%Depth], w, e);
              1: eb = xd & ELEN'((ELEN'(1) << w) - ELEN'(1));
              default: eb = ELEN'($signed(im)) & ELEN'((ELEN'(1) << w) - ELEN'(1));
            endcase
            shadow[(32'(d)+r)%Depth] =
                set_elem(shadow[(32'(d)+r)%Depth], w, e, ref_op(o, w, ea, eb, cin, vmb));
          end
        end
      end
    end
  endtask

  task automatic check_regs(input string tag);
    logic [VLEN-1:0] got;
    for (int r = 0; r < Depth; r++) begin
      got = peek[r];
      checks = checks + 1;
      if (got !== shadow[r]) begin
        errors = errors + 1;
        if (errors < 12)
          $display("FAIL %0s v%0d got=%h want=%h at %0t", tag, r, got, shadow[r], $time);
        if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
      end
    end
  endtask

  // Run one operation
  task automatic run_one(input vec_op_e o, input int form, input logic [4:0] s1,
                         input logic [4:0] s2, input logic [4:0] d, input logic vmb,
                         input logic [XLEN-1:0] xd, input logic [4:0] im, input logic [2:0] sew,
                         input logic [2:0] lmul, input logic [VlW-1:0] len);
    logic [2:0] f3;
    logic [4:0] f2;
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
        1: f2 = 5'd1;
        default: f2 = im;
      endcase
      xdata = xd;
      ref_apply(o, form, s1, s2, d, vmb, xd, im, 8 << sew, regs, int'(len));
      issue(enc(funct6_of(o), vmb, s2, f2, f3, d));
      drain();
      check_regs("run_one");
    end
  endtask

  // Snapshot survives reconfigure
  task automatic check_snapshot();
    begin
      seed_all();
      vsew  = 3'd0;
      vlmul = 3'd3;
      vl    = 8'd70;
      ref_apply(VEC_ADD, 0, 5'd8, 5'd16, 5'd24, 1'b1, '0, 5'd0, 8, 8, 70);
      issue(enc(6'b000000, 1'b1, 5'd16, 5'd8, 3'b000, 5'd24));
      vsew  = 3'd2;
      vlmul = 3'd0;
      vl    = 8'd1;
      drain();
      check_regs("snapshot");
    end
  endtask

  // Non vector ignored
  task automatic check_not_vector();
    begin
      seed_all();
      vsew  = 3'd2;
      vlmul = 3'd0;
      vl    = 8'd4;
      issue(32'h0010_0093);
      drain();
      check_regs("addi");
      issue(enc(6'b100000, 1'b1, 5'd4, 5'd3, 3'b001, 5'd5));
      drain();
      check_regs("float divide");
      issue(enc(6'b001100, 1'b1, 5'd4, 5'd3, 3'b000, 5'd5));
      drain();
      check_regs("gather");
      issue(enc(6'b111000, 1'b1, 5'd4, 5'd3, 3'b010, 5'd6));
      drain();
      check_regs("widening multiply");
    end
  endtask

  // Tail stays untouched
  task automatic check_tail();
    begin
      seed_all();
      run_one(VEC_ADD, 0, 5'd6, 5'd7, 5'd8, 1'b1, '0, 5'd0, 3'd2, 3'd0, 8'd2);
      run_one(VEC_XOR, 0, 5'd9, 5'd10, 5'd11, 1'b1, '0, 5'd0, 3'd1, 3'd0, 8'd3);
      run_one(VEC_OR, 0, 5'd12, 5'd13, 5'd14, 1'b1, '0, 5'd0, 3'd0, 3'd0, 8'd5);
    end
  endtask

  // Mask gates writes
  task automatic check_masked();
    begin
      seed_all();
      run_one(VEC_ADD, 0, 5'd2, 5'd3, 5'd4, 1'b0, '0, 5'd0, 3'd2, 3'd0, 8'd4);
      run_one(VEC_SUB, 0, 5'd5, 5'd6, 5'd7, 1'b0, '0, 5'd0, 3'd1, 3'd0, 8'd8);
      run_one(VEC_MERGE, 0, 5'd8, 5'd9, 5'd10, 1'b0, '0, 5'd0, 3'd0, 3'd0, 8'd16);
    end
  endtask

  // Groups walk registers
  task automatic check_groups();
    begin
      seed_all();
      run_one(VEC_ADD, 0, 5'd4, 5'd8, 5'd12, 1'b1, '0, 5'd0, 3'd2, 3'd1, 8'd8);
      run_one(VEC_AND, 0, 5'd4, 5'd8, 5'd16, 1'b1, '0, 5'd0, 3'd2, 3'd2, 8'd16);
      run_one(VEC_XOR, 0, 5'd8, 5'd16, 5'd24, 1'b1, '0, 5'd0, 3'd1, 3'd1, 8'd16);
    end
  endtask

  // Scalar and immediate
  task automatic check_forms();
    begin
      seed_all();
      run_one(VEC_ADD, 1, 5'd0, 5'd3, 5'd5, 1'b1, 32'hDEAD_BEEF, 5'd0, 3'd2, 3'd0, 8'd4);
      run_one(VEC_RSUB, 1, 5'd0, 5'd6, 5'd7, 1'b1, 32'h1234_5678, 5'd0, 3'd1, 3'd0, 8'd8);
      run_one(VEC_ADD, 2, 5'd0, 5'd9, 5'd11, 1'b1, '0, 5'd19, 3'd0, 3'd0, 8'd16);
      run_one(VEC_SLL, 2, 5'd0, 5'd12, 5'd13, 1'b1, '0, 5'd3, 3'd2, 3'd0, 8'd4);
    end
  endtask

  // Zero length
  task automatic check_zero_length();
    begin
      seed_all();
      run_one(VEC_ADD, 0, 5'd1, 5'd2, 5'd3, 1'b1, '0, 5'd0, 3'd2, 3'd0, 8'd0);
    end
  endtask

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
        case ($urandom % 13)
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
        form = int'($urandom % 2);
        sew  = 3'($urandom % 3);
        lmul = 3'($urandom % 3);
        len  = VlW'($urandom % ((VLEN >> sew) * (1 << lmul) + 1));
        vmb  = 1'($urandom);
        if (o == VEC_MERGE) vmb = 1'b0;
        run_one(o, form, 5'd4, 5'd8, 5'd16, vmb, $urandom, 5'($urandom), sew, lmul, len);
      end
    end
  endtask

  // Memory encode
  function automatic logic [31:0] enc_mem(input logic store, input logic [1:0] w, input logic whole,
                                          input logic strided, input logic vmb,
                                          input logic [4:0] d);
    logic [2:0] f3;
    f3 = (w == 2'd2) ? 3'b110 : ((w == 2'd1) ? 3'b101 : 3'b000);
    enc_mem = {
      3'b000,
      1'b0,
      strided ? 2'b10 : 2'b00,
      vmb,
      whole ? 5'b01000 : (strided ? 5'd12 : 5'd0),
      5'd10,
      f3,
      d,
      store ? 7'b0100111 : 7'b0000111
    };
  endfunction

  // Memory reference
  task automatic ref_mem(input logic store, input int w, input logic vmb, input logic [4:0] d,
                         input logic [XLEN-1:0] b, input logic [XLEN-1:0] st, input int len);
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
          e = 32'h0;
          for (int k = 0; k < bytes; k++) e[k*8+:8] = gmem[(a+32'(k))%Bytes];
          shadow[r] = set_elem(shadow[r], bytes * 8, i % per_reg, e);
        end else begin
          e = get_elem(shadow[r], bytes * 8, i % per_reg);
          for (int k = 0; k < bytes; k++) gmem[(a+32'(k))%Bytes] = e[k*8+:8];
        end
      end
    end
  endtask

  task automatic check_mem(input string tag);
    for (int k = 0; k < Bytes; k++) begin
      checks = checks + 1;
      if (mem[k] !== gmem[k]) begin
        errors = errors + 1;
        if (errors < 12) $display("FAIL %0s byte %0d got=%h want=%h", tag, k, mem[k], gmem[k]);
        if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
      end
    end
  endtask

  task automatic note(input string what, input logic [XLEN-1:0] got, input logic [XLEN-1:0] want);
    checks = checks + 1;
    if (got !== want) begin
      errors = errors + 1;
      $display("FAIL %0s got=%h want=%h at %0t", what, got, want, $time);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask

  // Run one move
  task automatic run_mem(input logic store, input logic [1:0] w, input logic whole,
                         input logic strided, input logic vmb, input logic [4:0] d,
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
      ref_mem(store, int'(w), vmb || whole, d, b, strided ? st : (32'd1 << w), count);
      issue(enc_mem(store, w, whole, strided, vmb || whole, d));
      drain();
      check_regs("run_mem");
      check_mem("run_mem");
    end
  endtask

  // Legality and alignment
  task automatic check_mem_rules();
    begin
      vsew  = 3'd0;
      vlmul = 3'd0;
      vl    = 8'd4;
      vill  = 1'b1;
      instr = enc_mem(1'b0, 2'd0, 1'b0, 1'b0, 1'b1, 5'd3);
      #1 note("element load under vill", 32'(is_vector), 32'd0);
      instr = enc_mem(1'b0, 2'd1, 1'b1, 1'b0, 1'b1, 5'd3);
      #1 note("whole load under vill", 32'(is_vector), 32'd1);
      vill  = 1'b0;
      vlmul = 3'd3;
      instr = enc_mem(1'b1, 2'd1, 1'b0, 1'b0, 1'b1, 5'd3);
      #1 note("group too wide", 32'(is_vector), 32'd0);
      vsew  = 3'd2;
      vlmul = 3'b101;
      instr = enc_mem(1'b0, 2'd0, 1'b0, 1'b0, 1'b1, 5'd3);
      #1 note("group too narrow", 32'(is_vector), 32'd0);
      vsew  = 3'd1;
      vlmul = 3'd0;
      xdata = 32'h0000_0101;
      instr = enc_mem(1'b0, 2'd1, 1'b0, 1'b0, 1'b1, 5'd3);
      #1 note("half base misaligned", 32'(mem_misaligned), 32'd1);
      note("half base address", mem_bad_addr, 32'h0000_0101);
      xdata   = 32'h0000_0100;
      xstride = 32'd3;
      instr   = enc_mem(1'b1, 2'd1, 1'b0, 1'b1, 1'b1, 5'd3);
      #1 note("half stride misaligned", 32'(mem_misaligned), 32'd1);
      note("half stride address", mem_bad_addr, 32'h0000_0103);
      vl = 8'd1;
      #1 note("one element stride", 32'(mem_misaligned), 32'd0);
      vl = 8'd0;
      xdata = 32'h0000_0103;
      #1 note("empty base", 32'(mem_misaligned), 32'd0);
      vl = 8'd4;
      instr = enc_mem(1'b1, 2'd0, 1'b0, 1'b1, 1'b1, 5'd3);
      #1 note("byte never misaligned", 32'(mem_misaligned), 32'd0);
      vsew  = 3'd2;
      xdata = 32'h0000_0102;
      instr = enc_mem(1'b0, 2'd2, 1'b1, 1'b0, 1'b1, 5'd3);
      #1 note("whole word misaligned", 32'(mem_misaligned), 32'd1);
      xdata   = '0;
      xstride = '0;
    end
  endtask

  // Write one register
  task automatic csr_poke(input logic [11:0] addr, input logic [XLEN-1:0] val);
    @(negedge clk);
    csr_we    = 1'b1;
    csr_waddr = addr;
    csr_wdata = val;
    @(posedge clk);
    #1 csr_we = 1'b0;
  endtask

  // Rounding and saturation
  task automatic check_fixed_point();
    begin
      csr_poke(VxrmAddr, 32'd2);
      note("vxrm takes a write", 32'(vxrm), 32'd2);
      note("vxsat untouched", 32'(vxsat), 32'd0);
      csr_poke(VxsatAddr, 32'd1);
      note("vxsat takes a write", 32'(vxsat), 32'd1);
      note("vxrm untouched", 32'(vxrm), 32'd2);
      csr_poke(VcsrAddr, 32'd3);
      note("vcsr sets the mode", 32'(vxrm), 32'd1);
      note("vcsr sets the flag", 32'(vxsat), 32'd1);
      csr_poke(VcsrAddr, 32'd0);
      note("vcsr clears both", 32'({vxrm, vxsat}), 32'd0);

      vsew  = 3'd0;
      vlmul = 3'd3;
      vl    = 8'd128;
      issue(enc(6'b000000, 1'b1, 5'd16, 5'd8, 3'b000, 5'd24));
      @(negedge clk);
      csr_wait = 1'b1;
      #1 note("the access waits", 32'(vec_hold), 32'd1);
      drain();
      #1 note("the access lands", 32'(vec_hold), 32'd0);
      csr_wait = 1'b0;
      vlmul = 3'd0;
      seed_all();
    end
  endtask

  // Reserved register numbers
  task automatic check_group_rules();
    begin
      vill  = 1'b0;
      vsew  = 3'd0;
      vl    = 8'd8;
      vlmul = 3'd2;
      instr = enc(6'b000000, 1'b1, 5'd8, 5'd4, 3'b000, 5'd1);
      #1 note("base off the multiple", 32'(is_vector), 32'd0);
      instr = enc(6'b000000, 1'b1, 5'd8, 5'd4, 3'b000, 5'd4);
      #1 note("base on the multiple", 32'(is_vector), 32'd1);
      instr = enc(6'b000000, 1'b1, 5'd6, 5'd4, 3'b010, 5'd1);
      #1 note("reduction source off", 32'(is_vector), 32'd0);
      instr = enc(6'b000000, 1'b1, 5'd4, 5'd4, 3'b010, 5'd1);
      #1 note("reduction source on", 32'(is_vector), 32'd1);
      vlmul = 3'd0;
      instr = enc(6'b110000, 1'b1, 5'd2, 5'd1, 3'b010, 5'd2);
      #1 note("wide over the low half", 32'(is_vector), 32'd0);
      instr = enc(6'b110000, 1'b1, 5'd3, 5'd1, 3'b010, 5'd2);
      #1 note("wide over the high half", 32'(is_vector), 32'd1);
      instr = enc(6'b110000, 1'b1, 5'd6, 5'd1, 3'b010, 5'd2);
      #1 note("wide clear of the source", 32'(is_vector), 32'd1);
      instr = enc(6'b101100, 1'b1, 5'd2, 5'd1, 3'b000, 5'd3);
      #1 note("narrow over the high half", 32'(is_vector), 32'd0);
      instr = enc(6'b101100, 1'b1, 5'd2, 5'd1, 3'b000, 5'd2);
      #1 note("narrow over the low half", 32'(is_vector), 32'd1);
      instr = enc(6'b110001, 1'b1, 5'd2, 5'd1, 3'b000, 5'd2);
      #1 note("reduction over its source", 32'(is_vector), 32'd1);
      instr = enc(6'b000000, 1'b0, 5'd8, 5'd4, 3'b000, 5'd0);
      #1 note("masked onto the mask", 32'(is_vector), 32'd0);
      instr = enc(6'b000000, 1'b0, 5'd8, 5'd4, 3'b000, 5'd1);
      #1 note("masked clear of the mask", 32'(is_vector), 32'd1);
      vlmul = 3'd3;
      instr = enc(6'b110000, 1'b1, 5'd8, 5'd16, 3'b010, 5'd0);
      #1 note("multiplier past eight", 32'(is_vector), 32'd0);
      vlmul = 3'd1;
      instr = enc(6'b011000, 1'b1, 5'd8, 5'd4, 3'b000, 5'd9);
      #1 note("compare over vs2 high", 32'(is_vector), 32'd0);
      instr = enc(6'b011000, 1'b1, 5'd8, 5'd4, 3'b000, 5'd8);
      #1 note("compare over vs2 low", 32'(is_vector), 32'd1);
      instr = enc(6'b011000, 1'b1, 5'd8, 5'd4, 3'b000, 5'd5);
      #1 note("compare over vs1 high", 32'(is_vector), 32'd0);
      instr = enc(6'b011000, 1'b1, 5'd8, 5'd4, 3'b000, 5'd4);
      #1 note("compare over vs1 low", 32'(is_vector), 32'd1);
      instr = enc(6'b011000, 1'b1, 5'd8, 5'd3, 3'b011, 5'd9);
      #1 note("immediate over vs2 high", 32'(is_vector), 32'd0);
      instr = enc(6'b011000, 1'b1, 5'd8, 5'd5, 3'b100, 5'd5);
      #1 note("scalar ignores vs1 field", 32'(is_vector), 32'd1);
      instr = enc(6'b010001, 1'b0, 5'd8, 5'd4, 3'b000, 5'd9);
      #1 note("carry over vs2 high", 32'(is_vector), 32'd0);
      instr = enc(6'b010011, 1'b1, 5'd8, 5'd4, 3'b000, 5'd8);
      #1 note("borrow over vs2 low", 32'(is_vector), 32'd1);
      instr = enc(6'b010001, 1'b0, 5'd8, 5'd4, 3'b000, 5'd0);
      #1 note("carry onto the mask", 32'(is_vector), 32'd1);
      instr = enc(6'b011001, 1'b1, 5'd8, 5'd4, 3'b010, 5'd9);
      #1 note("mask logic over source", 32'(is_vector), 32'd1);
      vlmul = 3'b111;
      instr = enc(6'b011000, 1'b1, 5'd8, 5'd4, 3'b000, 5'd8);
      #1 note("fractional compare over vs2", 32'(is_vector), 32'd1);
      vlmul = 3'd0;
      instr = enc(6'b010000, 1'b1, 5'd8, 5'd4, 3'b000, 5'd1);
      #1 note("unmasked vadc vv", 32'(is_vector), 32'd0);
      instr = enc(6'b010000, 1'b1, 5'd8, 5'd5, 3'b011, 5'd1);
      #1 note("unmasked vadc vi", 32'(is_vector), 32'd0);
      instr = enc(6'b010010, 1'b1, 5'd8, 5'd5, 3'b100, 5'd1);
      #1 note("unmasked vsbc vx", 32'(is_vector), 32'd0);
      instr = enc(6'b010000, 1'b0, 5'd8, 5'd4, 3'b000, 5'd1);
      #1 note("masked vadc vv", 32'(is_vector), 32'd1);
      instr = enc(6'b010010, 1'b0, 5'd8, 5'd4, 3'b000, 5'd1);
      #1 note("masked vsbc vv", 32'(is_vector), 32'd1);
      instr = enc(6'b010001, 1'b1, 5'd8, 5'd4, 3'b000, 5'd1);
      #1 note("unmasked vmadc vv", 32'(is_vector), 32'd1);
      instr = enc(6'b010111, 1'b1, 5'd0, 5'd4, 3'b000, 5'd1);
      #1 note("unmasked merge is a move", 32'(is_vector), 32'd1);
      vlmul = 3'd0;
      instr = 32'd0;
    end
  endtask

  // Trap drops instruction
  task automatic check_mem_cancel();
    begin
      vsew   = 3'd0;
      vlmul  = 3'd0;
      vl     = 8'd16;
      xdata  = 32'd16;
      cancel = 1'b1;
      issue(enc_mem(1'b1, 2'd0, 1'b0, 1'b0, 1'b1, 5'd5));
      cancel = 1'b0;
      drain();
      check_regs("cancel");
      check_mem("cancel");
    end
  endtask

  // Pending until drained
  task automatic check_mem_pending();
    begin
      ready_pct = 20;
      vsew = 3'd0;
      vlmul = 3'd0;
      vl = 8'd16;
      xdata = 32'd40;
      ref_mem(1'b1, 0, 1'b1, 5'd6, 32'd40, 32'd1, 16);
      issue(enc_mem(1'b1, 2'd0, 1'b0, 1'b0, 1'b1, 5'd6));
      note("store pending", 32'(store_pending), 32'd1);
      note("no load pending", 32'(load_pending), 32'd0);
      xdata = 32'd80;
      ref_mem(1'b0, 0, 1'b1, 5'd7, 32'd80, 32'd1, 16);
      issue(enc_mem(1'b0, 2'd0, 1'b0, 1'b0, 1'b1, 5'd7));
      note("load pending", 32'(load_pending), 32'd1);
      drain();
      note("store cleared", 32'(store_pending), 32'd0);
      note("load cleared", 32'(load_pending), 32'd0);
      check_regs("pending");
      check_mem("pending");
      ready_pct = 100;
    end
  endtask

  // Directed moves
  task automatic check_moves();
    begin
      seed_all();
      run_mem(1'b0, 2'd0, 1'b0, 1'b0, 1'b1, 5'd3, 32'd8, '0, 3'd0, 3'd0, 8'd5);
      run_mem(1'b0, 2'd1, 1'b0, 1'b0, 1'b1, 5'd4, 32'd20, '0, 3'd1, 3'd0, 8'd8);
      run_mem(1'b1, 2'd2, 1'b0, 1'b0, 1'b1, 5'd5, 32'd64, '0, 3'd2, 3'd0, 8'd4);
      run_mem(1'b1, 2'd1, 1'b0, 1'b1, 1'b1, 5'd6, 32'd100, -32'sd6, 3'd1, 3'd0, 8'd7);
      run_mem(1'b0, 2'd0, 1'b0, 1'b1, 1'b0, 5'd8, 32'd7, 32'd3, 3'd0, 3'd0, 8'd9);
      run_mem(1'b1, 2'd0, 1'b0, 1'b0, 1'b0, 5'd9, 32'd140, '0, 3'd0, 3'd0, 8'd16);
      run_mem(1'b0, 2'd0, 1'b1, 1'b0, 1'b1, 5'd10, 32'd33, '0, 3'd2, 3'd0, 8'd1);
      run_mem(1'b1, 2'd0, 1'b1, 1'b0, 1'b1, 5'd11, 32'd200, '0, 3'd1, 3'd0, 8'd0);
      run_mem(1'b0, 2'd2, 1'b1, 1'b0, 1'b1, 5'd12, 32'd16, '0, 3'd0, 3'd0, 8'd3);
      run_mem(1'b0, 2'd1, 1'b0, 1'b0, 1'b1, 5'd14, 32'd40, '0, 3'd0, 3'd0, 8'd12);
      run_mem(1'b1, 2'd0, 1'b0, 1'b0, 1'b1, 5'd16, 32'd0, '0, 3'd0, 3'd3, 8'd100);
      run_mem(1'b0, 2'd0, 1'b0, 1'b0, 1'b1, 5'd24, 32'd0, '0, 3'd0, 3'd0, 8'd0);
    end
  endtask

  // Random moves
  task automatic soak_mem(input int n);
    logic store;
    logic [1:0] w;
    logic whole;
    logic strided;
    logic vmb;
    logic [2:0] sew;
    logic [2:0] lmul;
    logic [4:0] d;
    logic [VlW-1:0] len;
    int emul;
    int nregs;
    int vlmax;
    begin
      seed_all();
      for (int i = 0; i < n; i++) begin
        store   = 1'($urandom);
        w       = 2'($urandom % 3);
        whole   = (($urandom % 4) == 0) && (store == 1'b0 || w == 2'd0);
        strided = !whole && 1'($urandom);
        vmb     = whole || 1'($urandom);
        emul    = 9;
        while (emul > 3 || emul < -3) begin
          sew  = 3'($urandom % 3);
          lmul = 3'($urandom % 4);
          emul = whole ? 0 : int'(lmul) + int'(w) - int'(sew);
        end
        vlmax = (VLEN << lmul) >> (3 + sew);
        len   = VlW'($urandom % ((vlmax > VlMax ? VlMax : vlmax) + 1));
        nregs = (emul <= 0) ? 1 : (1 << emul);
        d     = ((!vmb && !store) ? 5'd23 - 5'($urandom % 20) : 5'($urandom)) & ~5'(nregs - 1);
        if (!vmb && !store && (d == 5'd0)) d = 5'(nregs);
        ready_pct = (($urandom % 2) == 0) ? 100 : 40;
        run_mem(store, w, whole, strided, vmb, d, 32'($urandom % Bytes) & ~((32'd1 << w) - 1),
                32'($signed(32'($urandom % 13)) - 6) << w, sew, lmul, len);
      end
      ready_pct = 100;
    end
  endtask

  // Live state ignored
  task automatic scramble_cfg();
    vill  = 1'($urandom);
    vsew  = 3'($urandom % 3);
    vlmul = 3'($urandom % 4);
    vl    = VlW'($urandom % 17);
  endtask

  // Whole register transfer
  task automatic run_whole(input logic store, input logic [1:0] w, input logic [2:0] nf,
                           input logic [4:0] d, input logic [XLEN-1:0] b);
    begin
      scramble_cfg();
      xdata = b;
      ref_mem(store, int'(w), 1'b1, d, b, 32'd1 << w, (int'(nf) + 1) * (VLEN >> (3 + w)));
      issue(enc_mem(store, w, 1'b1, 1'b0, 1'b1, d) | {nf, 29'd0});
      drain();
      check_regs("run_whole");
      check_mem("run_whole");
      vill = 1'b0;
    end
  endtask

  // Whole register move
  task automatic run_mvnr(input logic [2:0] nf, input logic [4:0] s2, input logic [4:0] d);
    logic [VLEN-1:0] src[8];
    begin
      scramble_cfg();
      for (int r = 0; r <= int'(nf); r++) src[r] = shadow[(32'(s2)+r)%Depth];
      for (int r = 0; r <= int'(nf); r++) shadow[(32'(d)+r)%Depth] = src[r];
      issue(enc(6'b100111, 1'b1, s2, 5'(nf), 3'b011, d));
      drain();
      check_regs("run_mvnr");
      vill = 1'b0;
    end
  endtask

  // Whole register rules
  task automatic check_whole_rules();
    begin
      vill  = 1'b1;
      vsew  = 3'd2;
      vlmul = 3'd0;
      vl    = 8'd0;
      instr = enc(6'b100111, 1'b1, 5'd8, 5'd3, 3'b011, 5'd4);
      #1 note("move under vill", 32'(is_vector), 32'd1);
      instr = enc_mem(1'b0, 2'd2, 1'b1, 1'b0, 1'b1, 5'd8) | {3'd7, 29'd0};
      #1 note("eight loads under vill", 32'(is_vector), 32'd1);
      vill  = 1'b0;
      instr = enc(6'b100111, 1'b1, 5'd8, 5'd1, 3'b011, 5'd3);
      #1 note("move dest off two", 32'(is_vector), 32'd0);
      instr = enc(6'b100111, 1'b1, 5'd6, 5'd3, 3'b011, 5'd8);
      #1 note("move source off four", 32'(is_vector), 32'd0);
      instr = enc(6'b100111, 1'b1, 5'd8, 5'd7, 3'b011, 5'd0);
      #1 note("eight onto v0", 32'(is_vector), 32'd1);
      instr = enc(6'b100111, 1'b1, 5'd8, 5'd2, 3'b011, 5'd0);
      #1 note("three registers", 32'(is_vector), 32'd0);
      instr = enc(6'b100111, 1'b1, 5'd20, 5'd3, 3'b011, 5'd20);
      #1 note("copy onto itself", 32'(is_vector), 32'd1);
      note("self copy is empty", 32'(dut.issue_vl), 32'd0);
      instr = enc(6'b100111, 1'b1, 5'd20, 5'd3, 3'b011, 5'd24);
      #1 note("four copied bytes", 32'(dut.issue_vl), 32'd64);
      instr = enc_mem(1'b0, 2'd0, 1'b1, 1'b0, 1'b1, 5'd5) | {3'd1, 29'd0};
      #1 note("load pair off two", 32'(is_vector), 32'd0);
      instr = enc_mem(1'b1, 2'd0, 1'b1, 1'b0, 1'b1, 5'd12) | {3'd3, 29'd0};
      #1 note("store four on four", 32'(is_vector), 32'd1);
      instr = enc_mem(1'b1, 2'd0, 1'b1, 1'b0, 1'b1, 5'd12) | {3'd7, 29'd0};
      #1 note("store eight off eight", 32'(is_vector), 32'd0);
      xdata = 32'h0000_0102;
      instr = enc_mem(1'b0, 2'd2, 1'b1, 1'b0, 1'b1, 5'd8) | {3'd1, 29'd0};
      #1 note("pair word misaligned", 32'(mem_misaligned), 32'd1);
      xdata = '0;
      vl    = 8'd4;
      instr = 32'd0;
    end
  endtask

  // Whole register groups
  task automatic check_whole();
    logic [2:0] nf;
    logic [1:0] w;
    logic store;
    begin
      seed_all();
      run_whole(1'b0, 2'd0, 3'd1, 5'd2, 32'd5);
      run_whole(1'b0, 2'd1, 3'd3, 5'd4, 32'd34);
      run_whole(1'b0, 2'd2, 3'd7, 5'd8, 32'd100);
      run_whole(1'b1, 2'd0, 3'd1, 5'd6, 32'd3);
      run_whole(1'b1, 2'd0, 3'd7, 5'd16, 32'd64);
      run_mvnr(3'd0, 5'd3, 5'd9);
      run_mvnr(3'd1, 5'd10, 5'd12);
      run_mvnr(3'd3, 5'd16, 5'd4);
      run_mvnr(3'd7, 5'd8, 5'd24);
      run_mvnr(3'd3, 5'd20, 5'd20);
      for (int i = 0; i < 60; i++) begin
        case ($urandom % 4)
          0: nf = 3'd0;
          1: nf = 3'd1;
          2: nf = 3'd3;
          default: nf = 3'd7;
        endcase
        store = 1'($urandom);
        w = store ? 2'd0 : 2'($urandom % 3);
        ready_pct = (($urandom % 2) == 0) ? 100 : 40;
        if (($urandom % 3) == 0) run_mvnr(nf, 5'($urandom) & ~5'(nf), 5'($urandom) & ~5'(nf));
        else
          run_whole(store, w, nf, 5'($urandom) & ~5'(nf),
                    32'($urandom % Bytes) & ~((32'd1 << w) - 1));
      end
      ready_pct = 100;
    end
  endtask

  // Group element access
  function automatic logic [ELEN-1:0] grp_get(input logic [4:0] base, input int w, input int i);
    int roff;
    int pos;
    roff = (i * w) / VLEN;
    pos  = ((i * w) % VLEN) / w;
    return get_elem(shadow[(32'(base)+roff)%Depth], w, pos);
  endfunction

  task automatic grp_set(input logic [4:0] base, input int w, input int i,
                         input logic [ELEN-1:0] val);
    int roff;
    int pos;
    roff = (i * w) / VLEN;
    pos = ((i * w) % VLEN) / w;
    shadow[(32'(base)+roff)%Depth] = set_elem(shadow[(32'(base)+roff)%Depth], w, pos, val);
  endtask

  function automatic int group_elems(input int sew, input int regs);
    return regs * (VLEN / sew);
  endfunction

  // Widening model
  task automatic ref_widen(input vec_op_e o, input int form, input logic [4:0] s1,
                           input logic [4:0] s2, input logic [4:0] d, input logic vmb,
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
  endtask

  // Narrowing model
  task automatic ref_narrow(input vec_op_e o, input int form, input logic [4:0] s1,
                            input logic [4:0] s2, input logic [4:0] d, input logic vmb,
                            input logic [XLEN-1:0] xd, input logic [4:0] im, input int sew,
                            input int regs, input int len);
    logic [ELEN-1:0] w;
    logic [ELEN-1:0] r;
    int sh;
    for (int i = 0; i < group_elems(sew, regs); i++) begin
      if ((i < len) && (vmb || shadow[0][i])) begin
        w  = grp_get(s2, sew * 2, i);
        sh = (form == 0) ? int'(grp_get(s1, sew, i)) : ((form == 1) ? int'(xd[5:0]) : int'(im));
        sh = sh % (sew * 2);
        r  = (o == VEC_NSRA) ? 32'($signed(sext(w, sew * 2)) >>> sh) : (w >> sh);
        grp_set(d, sew, i, r);
      end
    end
  endtask

  // Extension model
  task automatic ref_extend(input vec_op_e o, input logic [4:0] s2, input logic [4:0] d,
                            input logic vmb, input int sew, input int regs, input int len,
                            input int factor);
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
  endtask

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

  task automatic ref_reduce(input vec_op_e o, input logic [4:0] s1, input logic [4:0] s2,
                            input logic [4:0] d, input logic vmb, input int sew, input int regs,
                            input int len, input logic wide);
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
  endtask

  // Mixed width runs
  task automatic run_widen(input vec_op_e o, input int form, input logic [4:0] s1,
                           input logic [4:0] s2, input logic [4:0] d, input logic vmb,
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
  endtask

  task automatic run_narrow(input vec_op_e o, input int form, input logic [4:0] s1,
                            input logic [4:0] s2, input logic [4:0] d, input logic vmb,
                            input logic [XLEN-1:0] xd, input logic [4:0] im, input logic [2:0] sew,
                            input logic [2:0] lmul, input logic [VlW-1:0] len);
    logic [5:0] f6;
    logic [2:0] f3;
    logic [4:0] sf;
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
        sf = 5'd1;
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
  endtask

  task automatic run_extend(input vec_op_e o, input logic [4:0] s2, input logic [4:0] d,
                            input logic vmb, input logic [2:0] sew, input logic [2:0] lmul,
                            input logic [VlW-1:0] len);
    logic [4:0] sel;
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
  endtask

  task automatic run_reduce(input vec_op_e o, input logic [4:0] s1, input logic [4:0] s2,
                            input logic [4:0] d, input logic vmb, input logic [2:0] sew,
                            input logic [2:0] lmul, input logic [VlW-1:0] len);
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
  endtask

  // Scalar moves
  task automatic run_move_sx(input logic [4:0] d, input logic [XLEN-1:0] xd, input logic [2:0] sew,
                             input logic [VlW-1:0] len);
    vsew  = sew;
    vlmul = 3'd0;
    vl    = len;
    xdata = xd;
    if (len != 8'd0) grp_set(d, 8 << sew, 0, xd);
    issue(enc(6'b010000, 1'b1, 5'b00000, 5'd3, 3'b110, d));
    drain();
    check_regs("move sx");
  endtask

  task automatic run_move_xs(input logic [4:0] s2, input logic [2:0] sew,
                             input logic [VlW-1:0] len);
    logic [ELEN-1:0] want;
    vsew  = sew;
    vlmul = 3'd0;
    vl    = len;
    want  = sext(get_elem(shadow[s2], 8 << sew, 0), 8 << sew);
    issue(enc(6'b010000, 1'b1, s2, 5'b00000, 3'b010, 5'd7));
    drain();
    check_regs("move xs");
    checks = checks + 1;
    if (xreg_result !== want) begin
      errors = errors + 1;
      $display("FAIL move xs got=%h want=%h at %0t", xreg_result, want, $time);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask

  task automatic check_widening();
    seed_all();
    run_widen(VEC_WADDU, 0, 5'd1, 5'd4, 5'd16, 1'b1, '0, 3'd0, 3'd0, 8'd16, 1'b0);
    run_widen(VEC_WADD, 0, 5'd1, 5'd4, 5'd16, 1'b1, '0, 3'd0, 3'd0, 8'd16, 1'b0);
    run_widen(VEC_WSUBU, 0, 5'd1, 5'd4, 5'd16, 1'b1, '0, 3'd1, 3'd0, 8'd8, 1'b0);
    run_widen(VEC_WSUB, 0, 5'd1, 5'd4, 5'd16, 1'b1, '0, 3'd1, 3'd0, 8'd8, 1'b0);
    run_widen(VEC_WADD, 1, 5'd1, 5'd4, 5'd16, 1'b1, 32'h0000_00a5, 3'd0, 3'd0, 8'd16, 1'b0);
    run_widen(VEC_WADDU, 0, 5'd2, 5'd6, 5'd20, 1'b1, '0, 3'd0, 3'd1, 8'd32, 1'b0);
    run_widen(VEC_WSUB, 0, 5'd2, 5'd6, 5'd20, 1'b1, '0, 3'd1, 3'd1, 8'd16, 1'b0);
    run_widen(VEC_WADDU, 0, 5'd1, 5'd16, 5'd24, 1'b1, '0, 3'd0, 3'd0, 8'd16, 1'b1);
    run_widen(VEC_WSUB, 0, 5'd1, 5'd16, 5'd24, 1'b1, '0, 3'd1, 3'd0, 8'd8, 1'b1);
    run_widen(VEC_WADD, 0, 5'd1, 5'd4, 5'd16, 1'b0, '0, 3'd0, 3'd0, 8'd16, 1'b0);
    run_widen(VEC_WADD, 0, 5'd1, 5'd4, 5'd16, 1'b1, '0, 3'd0, 3'd0, 8'd5, 1'b0);
  endtask

  task automatic check_narrowing();
    seed_all();
    run_narrow(VEC_NSRL, 0, 5'd1, 5'd16, 5'd8, 1'b1, '0, 5'd0, 3'd0, 3'd0, 8'd16);
    run_narrow(VEC_NSRA, 0, 5'd1, 5'd16, 5'd8, 1'b1, '0, 5'd0, 3'd0, 3'd0, 8'd16);
    run_narrow(VEC_NSRL, 1, 5'd1, 5'd16, 5'd8, 1'b1, 32'd5, 5'd0, 3'd1, 3'd0, 8'd8);
    run_narrow(VEC_NSRA, 2, 5'd1, 5'd16, 5'd8, 1'b1, '0, 5'd9, 3'd1, 3'd0, 8'd8);
    run_narrow(VEC_NSRL, 0, 5'd2, 5'd16, 5'd8, 1'b1, '0, 5'd0, 3'd0, 3'd1, 8'd32);
    run_narrow(VEC_NSRA, 0, 5'd1, 5'd16, 5'd8, 1'b0, '0, 5'd0, 3'd0, 3'd0, 8'd16);
    run_narrow(VEC_NSRL, 0, 5'd1, 5'd16, 5'd8, 1'b1, '0, 5'd0, 3'd0, 3'd0, 8'd7);
  endtask

  task automatic check_extensions();
    seed_all();
    run_extend(VEC_ZEXT2, 5'd4, 5'd16, 1'b1, 3'd1, 3'd0, 8'd8);
    run_extend(VEC_SEXT2, 5'd4, 5'd16, 1'b1, 3'd1, 3'd0, 8'd8);
    run_extend(VEC_ZEXT2, 5'd4, 5'd16, 1'b1, 3'd2, 3'd0, 8'd4);
    run_extend(VEC_SEXT2, 5'd4, 5'd16, 1'b1, 3'd2, 3'd0, 8'd4);
    run_extend(VEC_ZEXT4, 5'd4, 5'd16, 1'b1, 3'd2, 3'd0, 8'd4);
    run_extend(VEC_SEXT4, 5'd4, 5'd16, 1'b1, 3'd2, 3'd0, 8'd4);
    run_extend(VEC_SEXT2, 5'd4, 5'd18, 1'b1, 3'd2, 3'd1, 8'd8);
    run_extend(VEC_SEXT2, 5'd4, 5'd16, 1'b0, 3'd2, 3'd0, 8'd4);
  endtask

  task automatic check_reductions();
    seed_all();
    seed_reg(5'd1, {(VLEN / 32) {32'hFFFF_FFFF}});
    seed_reg(5'd2, {(VLEN / 32) {32'hA5A5_A5A5}});
    run_reduce(VEC_REDSUM, 5'd2, 5'd1, 5'd18, 1'b1, 3'd2, 3'd0, 8'd4);
    run_reduce(VEC_REDAND, 5'd2, 5'd1, 5'd19, 1'b1, 3'd2, 3'd0, 8'd4);
    run_reduce(VEC_REDOR, 5'd2, 5'd1, 5'd20, 1'b1, 3'd2, 3'd0, 8'd4);
    run_reduce(VEC_REDXOR, 5'd2, 5'd1, 5'd21, 1'b1, 3'd2, 3'd0, 8'd4);
    seed_all();
    run_reduce(VEC_REDSUM, 5'd1, 5'd4, 5'd16, 1'b1, 3'd2, 3'd0, 8'd4);
    run_reduce(VEC_REDAND, 5'd1, 5'd4, 5'd16, 1'b1, 3'd2, 3'd0, 8'd4);
    run_reduce(VEC_REDOR, 5'd1, 5'd4, 5'd16, 1'b1, 3'd1, 3'd0, 8'd8);
    run_reduce(VEC_REDXOR, 5'd1, 5'd4, 5'd16, 1'b1, 3'd0, 3'd0, 8'd16);
    run_reduce(VEC_REDMINU, 5'd1, 5'd4, 5'd16, 1'b1, 3'd2, 3'd0, 8'd4);
    run_reduce(VEC_REDMIN, 5'd1, 5'd4, 5'd16, 1'b1, 3'd2, 3'd0, 8'd4);
    run_reduce(VEC_REDMAXU, 5'd1, 5'd4, 5'd16, 1'b1, 3'd1, 3'd0, 8'd8);
    run_reduce(VEC_REDMAX, 5'd1, 5'd4, 5'd16, 1'b1, 3'd0, 3'd0, 8'd16);
    run_reduce(VEC_REDSUM, 5'd1, 5'd4, 5'd16, 1'b1, 3'd2, 3'd2, 8'd16);
    run_reduce(VEC_REDSUM, 5'd1, 5'd4, 5'd16, 1'b0, 3'd2, 3'd0, 8'd4);
    run_reduce(VEC_REDSUM, 5'd1, 5'd4, 5'd16, 1'b1, 3'd2, 3'd0, 8'd0);
    run_reduce(VEC_WREDSUMU, 5'd1, 5'd4, 5'd16, 1'b1, 3'd1, 3'd0, 8'd8);
    run_reduce(VEC_WREDSUM, 5'd1, 5'd4, 5'd16, 1'b1, 3'd1, 3'd0, 8'd8);
    run_reduce(VEC_WREDSUM, 5'd1, 5'd4, 5'd16, 1'b1, 3'd0, 3'd1, 8'd32);
  endtask

  task automatic check_scalar_moves();
    seed_all();
    run_move_sx(5'd9, 32'hdead_beef, 3'd2, 8'd4);
    run_move_sx(5'd9, 32'h0000_00a5, 3'd0, 8'd4);
    run_move_sx(5'd9, 32'hffff_8001, 3'd1, 8'd8);
    run_move_sx(5'd9, 32'h1234_5678, 3'd2, 8'd0);
    run_move_xs(5'd4, 3'd2, 8'd4);
    run_move_xs(5'd4, 3'd1, 8'd8);
    run_move_xs(5'd4, 3'd0, 8'd16);
    run_move_xs(5'd4, 3'd2, 8'd0);
  endtask

  // Mask bit read
  function automatic logic mbit(input logic [4:0] r, input int i);
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
  task automatic run_cmp(input vec_op_e o, input int form, input logic [4:0] s1,
                         input logic [4:0] s2, input logic [4:0] d, input logic vmb,
                         input logic [XLEN-1:0] xd, input logic [4:0] im, input logic [2:0] sew,
                         input logic [2:0] lmul, input logic [VlW-1:0] len);
    int w;
    logic [ELEN-1:0] b;
    logic [2:0] f3;
    logic [4:0] f2;
    begin
      vsew  = sew;
      vlmul = lmul;
      vl    = len;
      xdata = xd;
      w     = 8 << sew;
      for (int i = 0; i < int'(len); i++) begin
        if (vmb || mbit(5'd0, i)) begin
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
        1:       f2 = 5'd1;
        default: f2 = im;
      endcase
      issue(enc(cmp_funct6(o), vmb, s2, f2, f3, d));
      drain();
      check_regs($sformatf(
                 "cmp op=%0d form=%0d sew=%0d lmul=%0d len=%0d vm=%0b", o, form, sew, lmul, len, vmb
                 ));
    end
  endtask

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
        run_cmp(list[i], (i >= 6) ? 1 : 0, 5'd4, 5'd8, 5'd20, 1'b1, 32'h5, 5'd5, 3'd0, 3'd0, 8'd8);
        run_cmp(list[i], ((i == 2) || (i == 3)) ? 1 : 2, 5'd4, 5'd8, 5'd20, 1'b1, 32'h5, 5'd5, 3'd1,
                3'd0, 8'd4);
      end
      for (int i = 0; i < 8; i++) begin
        for (int k = 0; k < 8; k++) begin
          o = list[i];
          if ((o == VEC_MSGTU) || (o == VEC_MSGT)) form = 1 + int'($urandom % 2);
          else if ((o == VEC_MSLTU) || (o == VEC_MSLT)) form = int'($urandom % 2);
          else form = int'($urandom % 3);
          sew  = 3'($urandom % 3);
          lmul = 3'($urandom % 3);
          len  = VlW'($urandom % (((VLEN >> (3 + sew)) << lmul) + 1));
          vmb  = 1'($urandom);
          run_cmp(o, form, 5'd4, 5'd8, 5'd20, vmb, $urandom, 5'($urandom), sew, lmul, len);
        end
      end
      run_cmp(VEC_MSEQ, 0, 5'd4, 5'd8, 5'd20, 1'b1, '0, 5'd0, 3'd0, 3'd0, 8'd0);
      run_cmp(VEC_MSLT, 0, 5'd4, 5'd4, 5'd20, 1'b1, '0, 5'd0, 3'd2, 3'd0, 8'd4);
      run_cmp(VEC_MSEQ, 0, 5'd4, 5'd8, 5'd4, 1'b1, '0, 5'd0, 3'd0, 3'd0, 8'd16);
    end
  endtask

  // Carry or borrow out
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

  // Run one carry compare
  task automatic run_carry(input vec_op_e o, input int form, input logic [4:0] s1,
                           input logic [4:0] s2, input logic [4:0] d, input logic vmb,
                           input logic [XLEN-1:0] xd, input logic [4:0] im, input logic [2:0] sew,
                           input logic [2:0] lmul, input logic [VlW-1:0] len);
    int w;
    logic [ELEN-1:0] b;
    logic [VLEN-1:0] cin;
    logic [2:0] f3;
    logic [4:0] f2;
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
        1:       f2 = 5'd1;
        default: f2 = im;
      endcase
      issue(enc((o == VEC_MADC) ? 6'b010001 : 6'b010011, vmb, s2, f2, f3, d));
      drain();
      check_regs(
          $sformatf(
          "carry op=%0d form=%0d sew=%0d lmul=%0d len=%0d vm=%0b", o, form, sew, lmul, len, vmb));
    end
  endtask

  // Every carry shape
  task automatic check_carry();
    vec_op_e o;
    int form;
    logic [2:0] sew;
    logic [2:0] lmul;
    logic [VlW-1:0] len;
    logic [4:0] d;
    begin
      seed_all();
      for (int k = 0; k < 2; k++) begin
        o = vec_op_e'((k == 0) ? VEC_MADC : VEC_MSBC);
        for (int f = 0; f < 3; f++) begin
          if ((o == VEC_MSBC) && (f == 2)) continue;
          for (int s = 0; s < 3; s++) begin
            for (int m = 0; m < 2; m++) begin
              run_carry(o, f, 5'd4, 5'd8, 5'd20, 1'(m), $urandom, 5'($urandom), 3'(s), 3'd0,
                        VlW'(VLEN >> (3 + s)));
            end
          end
        end
      end
      for (int k = 0; k < 40; k++) begin
        o    = vec_op_e'((k % 2 == 0) ? VEC_MADC : VEC_MSBC);
        form = (o == VEC_MADC) ? int'($urandom % 3) : int'($urandom % 2);
        sew  = 3'($urandom % 3);
        lmul = 3'($urandom % 4);
        len  = VlW'($urandom % (((VLEN >> (3 + sew)) << lmul) + 1));
        run_carry(o, form, 5'd8, 5'd16, 5'd24, 1'($urandom), $urandom, 5'($urandom), sew, lmul,
                  len);
      end

      // Carry ripples out
      seed_reg(5'd0, '1);
      seed_reg(5'd4, '1);
      seed_reg(5'd8, '0);
      for (int s = 0; s < 3; s++) begin
        run_carry(VEC_MADC, 0, 5'd4, 5'd8, 5'd20, 1'b0, '0, 5'd0, 3'(s), 3'd0, 8'd4);
        run_carry(VEC_MADC, 0, 5'd4, 5'd8, 5'd21, 1'b1, '0, 5'd0, 3'(s), 3'd0, 8'd4);
        run_carry(VEC_MSBC, 0, 5'd8, 5'd8, 5'd22, 1'b0, '0, 5'd0, 3'(s), 3'd0, 8'd4);
        run_carry(VEC_MSBC, 0, 5'd8, 5'd8, 5'd23, 1'b1, '0, 5'd0, 3'(s), 3'd0, 8'd4);
        run_carry(VEC_MADC, 2, 5'd0, 5'd4, 5'd24, 1'b1, '0, 5'd1, 3'(s), 3'd0, 8'd4);
      end

      // Destination is v0
      seed_all();
      for (int s = 0; s < 3; s++) begin
        d = 5'd0;
        run_carry(VEC_MADC, 0, 5'd4, 5'd8, d, 1'b0, '0, 5'd0, 3'(s), 3'd1,
                  VlW'((VLEN >> (3 + s)) << 1));
        run_carry(VEC_MSBC, 1, 5'd4, 5'd8, d, 1'b0, $urandom, 5'd0, 3'(s), 3'd0, 8'd3);
      end

      // Destination is a source
      run_carry(VEC_MADC, 0, 5'd4, 5'd8, 5'd8, 1'b0, '0, 5'd0, 3'd2, 3'd1, 8'd8);
      run_carry(VEC_MSBC, 0, 5'd4, 5'd8, 5'd4, 1'b0, '0, 5'd0, 3'd0, 3'd0, 8'd16);
      run_carry(VEC_MADC, 1, 5'd4, 5'd8, 5'd20, 1'b0, '0, 5'd0, 3'd0, 3'd0, 8'd0);
    end
  endtask

  // One logic form
  task automatic run_mlogic(input logic [5:0] f6, input logic [4:0] s1, input logic [4:0] s2,
                            input logic [4:0] d, input logic [VlW-1:0] len);
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
  endtask

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
        run_mlogic(list[i], 5'd3, 5'd9, 5'd21, VlW'(1 + ($urandom % VLEN)));
      end
      run_mlogic(6'b011001, 5'd3, 5'd9, 5'd21, 8'd0);
      run_mlogic(6'b011010, 5'd3, 5'd3, 5'd3, 8'd128);
    end
  endtask

  // First set bit
  function automatic int ref_first_bit(input logic [4:0] s2, input logic vmb,
                                       input logic [VlW-1:0] len);
    begin
      ref_first_bit = -1;
      for (int i = int'(len) - 1; i >= 0; i--) begin
        if ((vmb || mbit(5'd0, i)) && mbit(s2, i)) ref_first_bit = i;
      end
    end
  endfunction

  // One set form
  task automatic run_mset(input logic [4:0] sel, input logic [4:0] s2, input logic [4:0] d,
                          input logic vmb, input logic [VlW-1:0] len);
    int   f;
    logic want;
    begin
      vsew  = 3'd0;
      vlmul = 3'd0;
      vl    = len;
      f     = ref_first_bit(s2, vmb, len);
      for (int i = 0; i < int'(len); i++) begin
        if (vmb || mbit(5'd0, i)) begin
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
  endtask

  // Every set shape
  task automatic check_mask_set();
    begin
      seed_all();
      for (int k = 0; k < 12; k++) begin
        run_mset(5'b00001, 5'd5, 5'd22, 1'($urandom), VlW'($urandom % (VLEN + 1)));
        run_mset(5'b00011, 5'd5, 5'd23, 1'($urandom), VlW'($urandom % (VLEN + 1)));
        run_mset(5'b00010, 5'd5, 5'd24, 1'($urandom), VlW'($urandom % (VLEN + 1)));
      end
      seed_reg(5'd5, '0);
      run_mset(5'b00001, 5'd5, 5'd22, 1'b1, 8'd64);
      run_mset(5'b00011, 5'd5, 5'd23, 1'b1, 8'd64);
      run_mset(5'b00010, 5'd5, 5'd24, 1'b1, 8'd64);
    end
  endtask

  // One index form
  task automatic run_index(input logic is_id, input logic [4:0] s2, input logic [4:0] d,
                           input logic vmb, input logic [2:0] sew, input logic [2:0] lmul,
                           input logic [VlW-1:0] len);
    int w;
    int count;
    begin
      vsew  = sew;
      vlmul = lmul;
      vl    = len;
      w     = 8 << sew;
      count = 0;
      for (int i = 0; i < int'(len); i++) begin
        if (vmb || mbit(5'd0, i)) grp_set(d, w, i, is_id ? 32'(i) : 32'(count));
        if (!is_id && (vmb || mbit(5'd0, i)) && mbit(s2, i)) count = count + 1;
      end
      issue(enc(6'b010100, vmb, is_id ? 5'd0 : s2, is_id ? 5'b10001 : 5'b10000, 3'b010, d));
      drain();
      check_regs("mask index");
    end
  endtask

  // Every index shape
  task automatic check_mask_index();
    logic [2:0] sew;
    logic [2:0] lmul;
    logic [VlW-1:0] len;
    begin
      seed_all();
      for (int k = 0; k < 10; k++) begin
        sew  = 3'($urandom % 3);
        lmul = 3'($urandom % 3);
        len  = VlW'($urandom % (((VLEN >> (3 + sew)) << lmul) + 1));
        run_index(1'b0, 5'd6, 5'd16, 1'($urandom), sew, lmul, len);
        run_index(1'b1, 5'd0, 5'd24, 1'($urandom), sew, lmul, len);
      end
      run_index(1'b0, 5'd6, 5'd16, 1'b1, 3'd0, 3'd0, 8'd0);
      run_index(1'b1, 5'd0, 5'd24, 1'b1, 3'd2, 3'd2, 8'd16);
    end
  endtask

  // One summary form
  task automatic run_msum(input logic is_pop, input logic [4:0] s2, input logic vmb,
                          input logic [VlW-1:0] len);
    int count;
    logic [ELEN-1:0] want;
    begin
      vsew  = 3'd0;
      vlmul = 3'd0;
      vl    = len;
      count = 0;
      for (int i = 0; i < int'(len); i++) begin
        if ((vmb || mbit(5'd0, i)) && mbit(s2, i)) count = count + 1;
      end
      want = is_pop ? 32'(count) :
          ((ref_first_bit(s2, vmb, len) < 0) ? 32'hFFFF_FFFF : 32'(ref_first_bit(s2, vmb, len)));
      issue(enc(6'b010000, vmb, s2, is_pop ? 5'b10000 : 5'b10001, 3'b010, 5'd7));
      drain();
      checks = checks + 1;
      if (xreg_result !== want) begin
        errors = errors + 1;
        $display("FAIL mask summary got=%h want=%h at %0t", xreg_result, want, $time);
        if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
      end
      check_regs("mask summary");
    end
  endtask

  // Every summary shape
  task automatic check_mask_scalar();
    begin
      seed_all();
      for (int k = 0; k < 14; k++) begin
        run_msum(1'b1, 5'd7, 1'($urandom), VlW'($urandom % (VLEN + 1)));
        run_msum(1'b0, 5'd7, 1'($urandom), VlW'($urandom % (VLEN + 1)));
      end
      seed_reg(5'd7, '0);
      run_msum(1'b1, 5'd7, 1'b1, 8'd128);
      run_msum(1'b0, 5'd7, 1'b1, 8'd128);
    end
  endtask

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
  function automatic logic [31:0] lane_instr(input vec_op_e o, input int form, input logic [4:0] s1,
                                             input logic [4:0] s2, input logic [4:0] d,
                                             input logic vmb, input logic [4:0] im);
    logic opm;
    logic [2:0] f3;
    logic [4:0] f2;
    begin
      opm = (vec_class(o) == VEC_CLS_MUL) || avg_form(o);
      case (form)
        0: f3 = opm ? 3'b010 : 3'b000;
        1: f3 = opm ? 3'b110 : 3'b100;
        default: f3 = 3'b011;
      endcase
      case (form)
        0: f2 = s1;
        1: f2 = 5'd1;
        default: f2 = im;
      endcase
      return enc(lane_funct6(o), vmb, s2, f2, f3, d);
    end
  endfunction

  // Lane op model
  task automatic model_lane(input vec_op_e o, input int form, input logic [4:0] s1,
                            input logic [4:0] s2, input logic [4:0] d, input logic vmb,
                            input logic [XLEN-1:0] xd, input logic [4:0] im, input int w,
                            input int regs, input logic [VlW-1:0] len, input logic [1:0] mode,
                            output logic want_sat);
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
  endtask

  task automatic run_lane(input vec_op_e o, input int form, input logic [4:0] s1,
                          input logic [4:0] s2, input logic [4:0] d, input logic vmb,
                          input logic [XLEN-1:0] xd, input logic [4:0] im, input logic [2:0] sew,
                          input logic [2:0] lmul, input logic [VlW-1:0] len,
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
      note($sformatf("vxsat after %0s", o.name()), 32'(vxsat), 32'(want_sat));
    end
  endtask

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

  task automatic run_wmul(input vec_op_e o, input int form, input logic [4:0] s1,
                          input logic [4:0] s2, input logic [4:0] d, input logic vmb,
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
      issue(enc(wmul_funct6(o), vmb, s2, (form == 0) ? s1 : 5'd1, (form == 0) ? 3'b010 : 3'b110, d
            ));
      drain();
      check_regs($sformatf("wmul %0s sew %0d form %0d", o.name(), w, form));
    end
  endtask

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
          run_wmul(ops[k], 0, 5'd4, 5'd8, 5'd16, 1'b1, '0, 3'(s), 3'd0, 8'(VLEN / (8 << s)));
        run_wmul(ops[k], 1, 5'd0, 5'd8, 5'd18, 1'b1, $urandom, 3'(s), 3'd0, 8'(VLEN / (8 << s)));
        run_wmul(ops[k], 1, 5'd0, 5'd8, 5'd20, 1'b0, $urandom, 3'(s), 3'd1,
                 8'(2 * VLEN / (8 << s)));
      end
      if (ops[k] != VEC_WMACCUS) begin
        run_wmul(ops[k], 0, 5'd4, 5'd8, 5'd24, 1'b1, '0, 3'd0, 3'd1, 8'd32);
        run_wmul(ops[k], 0, 5'd4, 5'd8, 5'd16, 1'b0, '0, 3'd1, 3'd0, 8'd8);
        run_wmul(ops[k], 0, 5'd4, 5'd8, 5'd16, 1'b1, '0, 3'd0, 3'd0, 8'd5);
      end
    end
    // Accumulate carries past SEW
    seed_reg(5'd4, '1);
    seed_reg(5'd8, '1);
    seed_reg(5'd16, {(VLEN / 16) {16'h00ff}});
    seed_reg(5'd17, {(VLEN / 16) {16'h00ff}});
    run_wmul(VEC_WMACCU, 0, 5'd4, 5'd8, 5'd16, 1'b1, '0, 3'd0, 3'd0, 8'd16);
    run_wmul(VEC_WMACCU, 1, 5'd0, 5'd8, 5'd16, 1'b1, 32'hff, 3'd0, 3'd0, 8'd16);
    seed_reg(5'd16, {(VLEN / 32) {32'h0000_ffff}});
    seed_reg(5'd17, {(VLEN / 32) {32'h0000_ffff}});
    run_wmul(VEC_WMACCU, 0, 5'd4, 5'd8, 5'd16, 1'b1, '0, 3'd1, 3'd0, 8'd8);
    run_wmul(VEC_WMACC, 1, 5'd0, 5'd8, 5'd16, 1'b1, 32'h8000, 3'd1, 3'd0, 8'd8);
    seed_all();
  endtask

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
        run_lane(ops[k], 0, 5'd4, 5'd8, 5'd12, 1'b1, '0, 5'd0, 3'(s), 3'd0, 8'(VLEN / (8 << s)),
                 2'd0);
        run_lane(ops[k], 1, 5'd0, 5'd8, 5'd13, 1'b1, $urandom, 5'd0, 3'(s), 3'd0,
                 8'(VLEN / (8 << s)), 2'd0);
      end
      run_lane(ops[k], 0, 5'd4, 5'd8, 5'd16, 1'b1, '0, 5'd0, 3'd1, 3'd1, 8'd16, 2'd0);
      run_lane(ops[k], 0, 5'd4, 5'd8, 5'd12, 1'b0, '0, 5'd0, 3'd0, 3'd0, 8'd16, 2'd0);
      run_lane(ops[k], 0, 5'd4, 5'd8, 5'd12, 1'b1, '0, 5'd0, 3'd2, 3'd0, 8'd3, 2'd0);
    end
    seed_reg(5'd4, min_vec(32));
    seed_reg(5'd8, min_vec(32));
    run_lane(VEC_MULH, 0, 5'd4, 5'd8, 5'd12, 1'b1, '0, 5'd0, 3'd2, 3'd0, 8'd4, 2'd0);
    run_lane(VEC_MULHSU, 0, 5'd4, 5'd8, 5'd12, 1'b1, '0, 5'd0, 3'd2, 3'd0, 8'd4, 2'd0);
    seed_all();
  endtask

  task automatic check_fixed_ops();
    vec_op_e ops[7] = '{VEC_SADDU, VEC_SADD, VEC_SSUBU, VEC_SSUB, VEC_SMUL, VEC_SSRL, VEC_SSRA};
    int nforms;
    seed_all();
    for (int k = 0; k < 7; k++) begin
      nforms = ((ops[k] == VEC_SSUBU) || (ops[k] == VEC_SSUB) || (ops[k] == VEC_SMUL)) ? 2 : 3;
      for (int s = 0; s < 3; s++) begin
        for (int f = 0; f < nforms; f++) begin
          for (int md = 0; md < 4; md++) begin
            run_lane(ops[k], f, 5'd4, 5'd8, 5'd12, 1'b1, $urandom, 5'($urandom), 3'(s), 3'd0,
                     8'(VLEN / (8 << s)), 2'(md));
          end
        end
      end
      run_lane(ops[k], 0, 5'd4, 5'd8, 5'd16, 1'b0, '0, 5'd0, 3'd1, 3'd1, 8'd13, 2'd1);
    end
    for (int k = 0; k < 2; k++) begin
      for (int s = 0; s < 2; s++) begin
        for (int f = 0; f < 3; f++) begin
          for (int md = 0; md < 4; md++) begin
            run_lane((k == 1) ? VEC_NCLIP : VEC_NCLIPU, f, 5'd4, 5'd8, 5'd12, 1'b1, $urandom,
                     5'($urandom), 3'(s), 3'd0, 8'(VLEN / (8 << s)), 2'(md));
          end
        end
        run_lane((k == 1) ? VEC_NCLIP : VEC_NCLIPU, 0, 5'd2, 5'd16, 5'd20, 1'b0, '0, 5'd0, 3'(s),
                 3'd1, 8'(VLEN / (8 << s) + 3), 2'd3);
      end
    end
    for (int s = 0; s < 3; s++) begin
      seed_reg(5'd4, min_vec(8 << s));
      seed_reg(5'd8, min_vec(8 << s));
      run_lane(VEC_SMUL, 0, 5'd4, 5'd8, 5'd12, 1'b1, '0, 5'd0, 3'(s), 3'd0, 8'(VLEN / (8 << s)),
               2'd0);
      run_lane(VEC_SADD, 0, 5'd4, 5'd8, 5'd12, 1'b1, '0, 5'd0, 3'(s), 3'd0, 8'(VLEN / (8 << s)),
               2'd0);
      run_lane(VEC_SSUB, 1, 5'd0, 5'd4, 5'd12, 1'b1, 32'd1, 5'd0, 3'(s), 3'd0, 8'(VLEN / (8 << s)),
               2'd0);
    end
    seed_reg(5'd4, '0);
    seed_reg(5'd8, '1);
    run_lane(VEC_SADDU, 0, 5'd4, 5'd8, 5'd12, 1'b1, '0, 5'd0, 3'd0, 3'd0, 8'd16, 2'd0);
    seed_all();
  endtask

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
        run_lane(ops[k], 0, 5'd4, 5'd8, 5'd12, 1'b1, '0, 5'd0, 3'(s), 3'd0, 8'(n), 2'd0);
        run_lane(ops[k], 1, 5'd0, 5'd8, 5'd13, 1'b1, $urandom, 5'd0, 3'(s), 3'd0, 8'(n), 2'd0);
        run_lane(ops[k], 1, 5'd0, 5'd8, 5'd14, 1'b1, '0, 5'd0, 3'(s), 3'd0, 8'(n), 2'd0);
      end
      run_lane(ops[k], 0, 5'd4, 5'd8, 5'd16, 1'b1, '0, 5'd0, 3'd1, 3'd1, 8'd16, 2'd0);
      run_lane(ops[k], 0, 5'd4, 5'd8, 5'd16, 1'b1, '0, 5'd0, 3'd2, 3'd2, 8'd13, 2'd0);
      run_lane(ops[k], 0, 5'd4, 5'd8, 5'd12, 1'b0, '0, 5'd0, 3'd0, 3'd0, 8'd16, 2'd0);
      run_lane(ops[k], 1, 5'd0, 5'd8, 5'd12, 1'b0, $urandom, 5'd0, 3'd2, 3'd0, 8'd3, 2'd0);
    end
    for (int s = 0; s < 3; s++) begin
      n = VLEN / (8 << s);
      for (int c = 0; c < 3; c++) begin
        case (c)
          0: seed_reg(5'd4, '0);
          1: seed_reg(5'd4, zero_even(rand_vec(), 8 << s));
          default: begin
            seed_reg(5'd4, '1);
            seed_reg(5'd8, min_vec(8 << s));
          end
        endcase
        for (int k = 0; k < 4; k++) begin
          run_lane(ops[k], 0, 5'd4, 5'd8, 5'd12, 1'b1, '0, 5'd0, 3'(s), 3'd0, 8'(n), 2'd0);
        end
      end
      run_lane(VEC_DIV, 1, 5'd0, 5'd8, 5'd13, 1'b1, '1, 5'd0, 3'(s), 3'd0, 8'(n), 2'd0);
      run_lane(VEC_REM, 1, 5'd0, 5'd8, 5'd14, 1'b1, '1, 5'd0, 3'(s), 3'd0, 8'(n), 2'd0);
      seed_all();
    end
  endtask

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
            run_lane(ops[k], f, 5'd4, 5'd8, 5'd12, 1'b1, $urandom, 5'd0, 3'(s), 3'd0,
                     8'(VLEN / (8 << s)), 2'(md));
          end
        end
      end
      run_lane(ops[k], 0, 5'd4, 5'd8, 5'd16, 1'b0, '0, 5'd0, 3'd1, 3'd1, 8'd13, 2'd1);
      run_lane(ops[k], 1, 5'd0, 5'd8, 5'd16, 1'b1, $urandom, 5'd0, 3'd0, 3'd2, 8'd50, 2'd3);
    end
    for (int s = 0; s < 3; s++) begin
      n   = VLEN / (8 << s);
      ext = '{min_vec(8 << s), ~min_vec(8 << s), '1};
      for (int i = 0; i < 3; i++) begin
        for (int j = 0; j < 3; j++) begin
          seed_reg(5'd8, ext[i]);
          seed_reg(5'd4, ext[j]);
          for (int k = 0; k < 4; k++) begin
            for (int md = 0; md < 4; md++) begin
              run_lane(ops[k], 0, 5'd4, 5'd8, 5'd12, 1'b1, '0, 5'd0, 3'(s), 3'd0, 8'(n), 2'(md));
            end
          end
        end
      end
    end
    seed_all();
  endtask

  // Divide overlaps neighbours
  task automatic check_divide_overlap();
    logic sat;
    begin
      seed_all();
      seed_reg(5'd4, zero_even(rand_vec(), 8));
      csr_poke(VxrmAddr, 32'd1);
      vsew  = 3'd0;
      vlmul = 3'd0;
      vl    = 8'd16;
      xdata = '0;
      model_lane(VEC_DIV, 0, 5'd4, 5'd8, 5'd12, 1'b1, '0, 5'd0, 8, 1, 8'd16, 2'd1, sat);
      ref_apply(VEC_ADD, 0, 5'd5, 5'd6, 5'd20, 1'b1, '0, 5'd0, 8, 1, 16);
      model_lane(VEC_MUL, 0, 5'd12, 5'd8, 5'd24, 1'b1, '0, 5'd0, 8, 1, 8'd16, 2'd1, sat);
      model_lane(VEC_AADD, 0, 5'd12, 5'd20, 5'd28, 1'b1, '0, 5'd0, 8, 1, 8'd16, 2'd1, sat);
      model_lane(VEC_REMU, 0, 5'd4, 5'd12, 5'd13, 1'b0, '0, 5'd0, 8, 1, 8'd16, 2'd1, sat);
      model_lane(VEC_DIVU, 0, 5'd20, 5'd13, 5'd14, 1'b1, '0, 5'd0, 8, 1, 8'd16, 2'd1, sat);
      issue(lane_instr(VEC_DIV, 0, 5'd4, 5'd8, 5'd12, 1'b1, 5'd0));
      issue(enc(funct6_of(VEC_ADD), 1'b1, 5'd6, 5'd5, 3'b000, 5'd20));
      issue(lane_instr(VEC_MUL, 0, 5'd12, 5'd8, 5'd24, 1'b1, 5'd0));
      issue(lane_instr(VEC_AADD, 0, 5'd12, 5'd20, 5'd28, 1'b1, 5'd0));
      issue(lane_instr(VEC_REMU, 0, 5'd4, 5'd12, 5'd13, 1'b0, 5'd0));
      issue(lane_instr(VEC_DIVU, 0, 5'd20, 5'd13, 5'd14, 1'b1, 5'd0));
      drain();
      check_regs("divide overlap");
    end
  endtask

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
          model_lane(o[k], 0, 5'd4, 5'd8, 5'(12 + k), 1'b1, '0, 5'd0, 8 << sew[k], 1,
                     8'(VLEN / (8 << sew[k])), 2'(r), sat);
          any_sat = any_sat || sat;
        end
        for (int k = 0; k < 8; k++) begin
          vsew = sew[k];
          vl   = 8'(VLEN / (8 << sew[k]));
          issue(lane_instr(o[k], 0, 5'd4, 5'd8, 5'(12 + k), 1'b1, 5'd0));
        end
        drain();
        check_regs($sformatf("lane stream %0d", r));
        note($sformatf("vxsat after lane stream %0d", r), 32'(vxsat), 32'(any_sat));
      end
      seed_all();
    end
  endtask

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
      seed_all();
      for (int i = 0; i < n; i++) begin
        o = ops[int'($urandom_range(24))];
        form = int'($urandom_range(2));
        no_imm = (o == VEC_SSUBU) || (o == VEC_SSUB) || (o == VEC_SMUL) ||
            (vec_class(o) == VEC_CLS_MUL) || avg_form(o);
        if ((form == 2) && no_imm) form = 1;
        smax = ((o == VEC_NCLIPU) || (o == VEC_NCLIP)) ? 2 : 3;
        sew  = 3'($urandom_range(smax - 1));
        lmul = 3'($urandom_range(1));
        run_lane(o, form, 5'd4, 5'd16, 5'd24, 1'($urandom), $urandom, 5'($urandom), sew, lmul,
                 8'($urandom_range((VLEN / (8 << sew)) * (int'(lmul) + 1))), 2'($urandom));
      end
    end
  endtask

  // Forms left trapping
  task automatic check_lane_rules();
    begin
      vill  = 1'b0;
      vlmul = 3'd0;
      vl    = 8'd4;
      vsew  = 3'd2;
      instr = enc(6'b101110, 1'b1, 5'd8, 5'd4, 3'b000, 5'd12);
      @(negedge clk);
      note("narrow clip at e32", 32'(is_vector), 32'd0);
      vsew = 3'd1;
      @(negedge clk);
      note("narrow clip at e16", 32'(is_vector), 32'd1);
      instr = enc(6'b101101, 1'b1, 5'd8, 5'd4, 3'b010, 5'd12);
      @(negedge clk);
      note("multiply add", 32'(is_vector), 32'd1);
      instr = enc(6'b111000, 1'b1, 5'd8, 5'd4, 3'b010, 5'd12);
      @(negedge clk);
      note("widening multiply", 32'(is_vector), 32'd1);
      vsew = 3'd2;
      @(negedge clk);
      note("widening multiply at e32", 32'(is_vector), 32'd0);
      vsew  = 3'd1;
      instr = enc(6'b001000, 1'b1, 5'd8, 5'd4, 3'b010, 5'd12);
      @(negedge clk);
      note("averaging add", 32'(is_vector), 32'd1);
      instr = enc(6'b100001, 1'b1, 5'd8, 5'd4, 3'b110, 5'd12);
      @(negedge clk);
      note("divide", 32'(is_vector), 32'd1);
      instr = enc(6'b100101, 1'b1, 5'd8, 5'd4, 3'b010, 5'd12);
      @(negedge clk);
      note("multiply", 32'(is_vector), 32'd1);
      instr = enc(6'b100111, 1'b1, 5'd8, 5'd4, 3'b000, 5'd12);
      @(negedge clk);
      note("fractional multiply", 32'(is_vector), 32'd1);
      instr = 32'd0;
    end
  endtask

  // Reference float lane
  logic            fref_valid = 1'b0;
  vec_fop_e        fref_op = VEC_FADD;
  logic     [ 2:0] fref_rm = 3'd0;
  logic     [31:0] fref_a = '0;
  logic     [31:0] fref_b = '0;
  logic     [31:0] fref_c = '0;
  logic     [31:0] fref_res;
  logic     [ 4:0] fref_flags;
  logic            fref_rvalid;

  vec_fp_lane u_ref (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(1'b1),
      .valid(fref_valid),
      .op(fref_op),
      .rm(fref_rm),
      .a(fref_a),
      .b(fref_b),
      .c(fref_c),
      .result(fref_res),
      .fflags(fref_flags),
      .result_valid(fref_rvalid)
  );

  // Flags reaching fflags
  initial flags_seen = '0;
  always @(negedge clk) if (rst_n && core_en) flags_seen = flags_seen | fflags;

  // Write port uses
  int wb_writes = 0;
  always @(negedge clk) if (rst_n && core_en && dut.wen_wb) wb_writes = wb_writes + 1;

  function automatic logic fp_cmp_op(input vec_fop_e o);
    return (o == VEC_MFEQ) || (o == VEC_MFNE) || (o == VEC_MFLT) || (o == VEC_MFLE) ||
        (o == VEC_MFGT) || (o == VEC_MFGE);
  endfunction

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
      VEC_FCLASS, VEC_FREC7, VEC_FRSQRT7: return 6'b010011;
      default:    return 6'b011111;
    endcase
  endfunction

  // Scalar only forms
  function automatic logic fp_vf_only(input vec_fop_e o);
    return (o == VEC_FRSUB) || (o == VEC_MFGT) || (o == VEC_MFGE);
  endfunction

  // Vector only forms
  function automatic logic fp_vv_only(input vec_fop_e o);
    return (o == VEC_FCLASS) || (o == VEC_FREC7) || (o == VEC_FRSQRT7);
  endfunction

  // Float operand values
  function automatic logic [31:0] fp_pick();
    logic [31:0] x;
    x = $urandom;
    case ($urandom_range(
        7
    ))
      0: x[30:23] = 8'hFF;
      1: x[30:23] = 8'h00;
      2: x[30:23] = 8'(250 + $urandom_range(4));
      3: x[30:23] = 8'($urandom_range(3));
      4: x = ($urandom_range(1) != 0) ? 32'h3F80_0000 : 32'h7F7F_FFFF;
      default: x[30:23] = 8'(120 + $urandom_range(14));
    endcase
    return x;
  endfunction

  function automatic logic [VLEN-1:0] fp_vec();
    for (int e = 0; e < VLEN / 32; e++) fp_vec[e*32+:32] = fp_pick();
  endfunction

  task automatic seed_fp();
    for (int r = 0; r < Depth; r++) seed_reg(AWIDTH'(r), fp_vec());
  endtask

  function automatic logic [31:0] fp_encode(input vec_fop_e o, input int form, input logic [4:0] s1,
                                            input logic [4:0] s2, input logic [4:0] d,
                                            input logic vmb);
    logic [4:0] rs1;
    case (o)
      VEC_FCLASS:  rs1 = 5'b10000;
      VEC_FREC7:   rs1 = 5'b00101;
      VEC_FRSQRT7: rs1 = 5'b00100;
      default:     rs1 = (form != 0) ? 5'($urandom) : s1;
    endcase
    return enc(fp_funct6(o), vmb, s2, rs1, (form != 0) ? 3'b101 : 3'b001, d);
  endfunction

  // Float op model
  task automatic model_fp(input vec_fop_e o, input int form, input logic [4:0] s1,
                          input logic [4:0] s2, input logic [4:0] d, input logic vmb,
                          input logic [31:0] fsc, input int regs, input logic [VlW-1:0] len,
                          input logic [2:0] rm, output logic [4:0] want_flags);
    int          ids   [$];
    logic [31:0] av    [$];
    logic [31:0] bv    [$];
    logic [31:0] cv    [$];
    int          sent;
    int          got;
    int          guard;
    logic [31:0] r;
    begin
      want_flags = '0;
      for (int i = 0; i < group_elems(32, regs); i++) begin
        if ((i < len) && (vmb || shadow[0][i])) begin
          ids.push_back(i);
          av.push_back(grp_get(s2, 32, i));
          bv.push_back((form != 0) ? fsc : grp_get(s1, 32, i));
          cv.push_back(grp_get(d, 32, i));
        end
      end
      sent  = 0;
      got   = 0;
      guard = 0;
      while ((got < ids.size()) && (guard < 200)) begin
        @(negedge clk);
        guard = guard + 1;
        if (fref_rvalid) begin
          r = fref_res;
          want_flags = want_flags | fref_flags;
          if (fp_cmp_op(o)) shadow[d][ids[got]] = r[0];
          else grp_set(d, 32, ids[got], r);
          got = got + 1;
        end
        fref_valid = (sent < ids.size());
        if (sent < ids.size()) begin
          fref_op = o;
          fref_rm = rm;
          fref_a = av[sent];
          fref_b = bv[sent];
          fref_c = cv[sent];
          sent = sent + 1;
        end
      end
      fref_valid = 1'b0;
      if (got != ids.size()) $fatal(1, "TB REFERENCE LANE STALLED");
    end
  endtask

  // Run one float op
  task automatic run_fp(input vec_fop_e o, input int form, input logic [4:0] s1,
                        input logic [4:0] s2, input logic [4:0] d, input logic vmb,
                        input logic [2:0] lmul, input logic [VlW-1:0] len, input logic [2:0] rm);
    logic [ 4:0] want;
    logic [31:0] fsc;
    int          regs;
    int          phases;
    logic        hit;
    begin
      regs   = lmul[2] ? 1 : (1 << lmul[1:0]);
      phases = 0;
      for (int p = 0; p < regs; p++) begin
        hit = 1'b0;
        for (int e = 0; e < 4; e++)
        if (((p * 4 + e) < int'(len)) && (vmb || shadow[0][p*4+e])) hit = 1'b1;
        if (hit) phases = phases + 1;
      end
      fsc   = fp_pick();
      vsew  = 3'd2;
      vlmul = lmul;
      vl    = len;
      frm   = rm;
      fdata = fsc;
      xdata = $urandom;
      model_fp(o, form, s1, s2, d, vmb, fsc, regs, len, rm, want);
      flags_seen = '0;
      wb_writes  = 0;
      issue(fp_encode(o, form, s1, s2, d, vmb));
      frm   = 3'($urandom_range(4));
      fdata = $urandom;
      drain();
      check_regs($sformatf("float %0s form %0d lmul %0d", o.name(), form, lmul));
      note($sformatf("fflags after %0s", o.name()), 32'(flags_seen), 32'(want));
      note($sformatf("writes by %0s", o.name()), 32'(wb_writes), 32'(phases));
    end
  endtask

  // Every float op
  task automatic check_fp_ops();
    vec_fop_e o;
    begin
      note("no flags from integer work", 32'(flags_seen), 32'd0);
      seed_fp();
      for (int k = 0; k < 26; k++) begin
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
          default: o = VEC_FRSQRT7;
        endcase
        for (int f = 0; f < 2; f++) begin
          if ((f == 0) && fp_vf_only(o)) continue;
          if ((f != 0) && fp_vv_only(o)) continue;
          for (int rm = 0; rm < 5; rm++)
          run_fp(o, f, 5'd4, 5'd8, 5'd12, 1'($urandom), 3'd0, 8'(1 + $urandom_range(3)), 3'(rm));
        end
      end
    end
  endtask

  // Random float traffic
  task automatic soak_fp(input int n);
    vec_fop_e       o;
    int             form;
    logic     [2:0] lmul;
    int             regs;
    begin
      seed_fp();
      for (int i = 0; i < n; i++) begin
        o = vec_fop_e'($urandom_range(32'(VEC_FCLASS)));
        if ((o == VEC_FDIV) || (o == VEC_FRDIV) || (o == VEC_FSQRT)) o = VEC_FMACC;
        form = int'($urandom_range(1));
        if (fp_vf_only(o)) form = 1;
        if (fp_vv_only(o)) form = 0;
        lmul = 3'($urandom_range(3));
        regs = 1 << lmul[1:0];
        run_fp(o, form, 5'd8, 5'd16, 5'd24, 1'($urandom), lmul, 8'($urandom_range(4 * regs)),
               3'($urandom_range(4)));
        if ($urandom_range(9) == 0) seed_fp();
      end
    end
  endtask

  // Float mixed in flight
  task automatic check_fp_stream();
    logic [4:0] want;
    logic [4:0] f;
    logic [2:0] rm[6];
    logic [31:0] fsc[6];
    logic sat;
    begin
      for (int r = 0; r < 6; r++) begin
        seed_fp();
        vlmul = 3'd0;
        vl    = 8'd4;
        vsew  = 3'd2;
        want  = '0;
        for (int k = 0; k < 6; k++) begin
          rm[k]  = 3'($urandom_range(4));
          fsc[k] = fp_pick();
        end
        model_fp(VEC_FMUL, 0, 5'd1, 5'd2, 5'd10, 1'b1, '0, 1, 8'd4, rm[0], f);
        want = want | f;
        ref_apply(VEC_ADD, 0, 5'd3, 5'd4, 5'd11, 1'b1, '0, 5'd0, 32, 1, 4);
        model_fp(VEC_FMACC, 1, 5'd0, 5'd5, 5'd12, 1'b1, fsc[2], 1, 8'd4, rm[2], f);
        want = want | f;
        model_lane(VEC_MUL, 0, 5'd6, 5'd7, 5'd13, 1'b1, '0, 5'd0, 32, 1, 8'd4, 2'd0, sat);
        model_fp(VEC_MFLT, 0, 5'd10, 5'd12, 5'd14, 1'b1, '0, 1, 8'd4, rm[4], f);
        want = want | f;
        model_fp(VEC_FADD, 1, 5'd0, 5'd13, 5'd15, 1'b1, fsc[5], 1, 8'd4, rm[5], f);
        want = want | f;
        flags_seen = '0;
        frm = rm[0];
        issue(fp_encode(VEC_FMUL, 0, 5'd1, 5'd2, 5'd10, 1'b1));
        issue(enc(6'b000000, 1'b1, 5'd4, 5'd3, 3'b000, 5'd11));
        frm   = rm[2];
        fdata = fsc[2];
        issue(fp_encode(VEC_FMACC, 1, 5'd0, 5'd5, 5'd12, 1'b1));
        issue(lane_instr(VEC_MUL, 0, 5'd6, 5'd7, 5'd13, 1'b1, 5'd0));
        frm = rm[4];
        issue(fp_encode(VEC_MFLT, 0, 5'd10, 5'd12, 5'd14, 1'b1));
        frm   = rm[5];
        fdata = fsc[5];
        issue(fp_encode(VEC_FADD, 1, 5'd0, 5'd13, 5'd15, 1'b1));
        frm = 3'd0;
        drain();
        check_regs($sformatf("float stream %0d", r));
        note($sformatf("fflags after float stream %0d", r), 32'(flags_seen), 32'(want));
      end
    end
  endtask

  // Group then short ops
  task automatic check_fp_group_stream();
    logic [4:0] want;
    logic       sat;
    begin
      for (int r = 0; r < 4; r++) begin
        seed_fp();
        vsew  = 3'd2;
        vlmul = 3'd3;
        vl    = 8'd32;
        frm   = 3'(r);
        model_fp(VEC_FADD, 0, 5'd16, 5'd24, 5'd8, 1'b1, '0, 8, 8'd32, 3'(r), want);
        ref_apply(VEC_ADD, 0, 5'd1, 5'd2, 5'd3, 1'b1, '0, 5'd0, 32, 1, 4);
        model_lane(VEC_MUL, 0, 5'd4, 5'd5, 5'd6, 1'b1, '0, 5'd0, 32, 1, 8'd4, 2'd0, sat);
        ref_apply(VEC_XOR, 0, 5'd1, 5'd2, 5'd7, 1'b1, '0, 5'd0, 32, 1, 4);
        flags_seen = '0;
        issue(fp_encode(VEC_FADD, 0, 5'd16, 5'd24, 5'd8, 1'b1));
        vlmul = 3'd0;
        vl    = 8'd4;
        issue(enc(6'b000000, 1'b1, 5'd2, 5'd1, 3'b000, 5'd3));
        issue(lane_instr(VEC_MUL, 0, 5'd4, 5'd5, 5'd6, 1'b1, 5'd0));
        issue(enc(6'b001011, 1'b1, 5'd2, 5'd1, 3'b000, 5'd7));
        drain();
        check_regs($sformatf("float group stream %0d", r));
        note($sformatf("fflags after float group stream %0d", r), 32'(flags_seen), 32'(want));
      end
    end
  endtask

  // Float forms legal
  task automatic check_fp_rules();
    begin
      vill  = 1'b0;
      vlmul = 3'd0;
      vl    = 8'd4;
      vsew  = 3'd2;
      frm   = 3'd0;
      instr = fp_encode(VEC_FADD, 0, 5'd4, 5'd8, 5'd12, 1'b1);
      for (int s = 0; s < 3; s++) begin
        vsew = 3'(s);
        @(negedge clk);
        note($sformatf("float add at sew %0d", 8 << s), 32'(is_vector), 32'(s == 2));
      end
      for (int m = 0; m < 8; m++) begin
        frm = 3'(m);
        @(negedge clk);
        note($sformatf("float add at frm %0d", m), 32'(is_vector), 32'(m < 5));
      end
      instr = fp_encode(VEC_MFLT, 0, 5'd4, 5'd8, 5'd12, 1'b1);
      for (int s = 0; s < 3; s++) begin
        vsew = 3'(s);
        for (int m = 0; m < 8; m++) begin
          frm = 3'(m);
          @(negedge clk);
          note($sformatf("float compare at sew %0d frm %0d", 8 << s, m), 32'(is_vector),
               32'((s == 2) && (m < 5)));
        end
      end
      vsew  = 3'd2;
      frm   = 3'd0;
      instr = fp_encode(VEC_MFGT, 1, 5'd4, 5'd8, 5'd12, 1'b1);
      @(negedge clk);
      note("greater than scalar", 32'(is_vector), 32'd1);
      instr = enc(6'b011101, 1'b1, 5'd8, 5'd4, 3'b001, 5'd12);
      @(negedge clk);
      note("greater than vector", 32'(is_vector), 32'd0);
      instr = enc(6'b100000, 1'b1, 5'd8, 5'd4, 3'b001, 5'd12);
      @(negedge clk);
      note("float divide", 32'(is_vector), 32'd0);
      instr = enc(6'b010011, 1'b1, 5'd8, 5'b10000, 3'b001, 5'd12);
      @(negedge clk);
      note("float classify", 32'(is_vector), 32'd1);
      note("classify reads no vs1", 32'(dut.rd1_regs), 32'd0);
      frm = 3'd5;
      @(negedge clk);
      note("float classify at frm 5", 32'(is_vector), 32'd0);
      frm  = 3'd0;
      vsew = 3'd1;
      @(negedge clk);
      note("float classify at sew 16", 32'(is_vector), 32'd0);
      vsew  = 3'd2;
      instr = enc(6'b010011, 1'b1, 5'd8, 5'b10000, 3'b101, 5'd12);
      @(negedge clk);
      note("float classify scalar", 32'(is_vector), 32'd0);
      for (int u = 4; u < 6; u++) begin
        instr = enc(6'b010011, 1'b1, 5'd8, 5'(u), 3'b001, 5'd12);
        vlmul = 3'd1;
        @(negedge clk);
        note($sformatf("float estimate %0d at lmul 2", u), 32'(is_vector), 32'd1);
        note($sformatf("float estimate %0d reads no vs1", u), 32'(dut.rd1_regs), 32'd0);
        vlmul = 3'd0;
        frm   = 3'd5;
        @(negedge clk);
        note($sformatf("float estimate %0d at frm 5", u), 32'(is_vector), 32'd0);
        frm   = 3'd0;
        instr = enc(6'b010011, 1'b1, 5'd8, 5'(u), 3'b101, 5'd12);
        @(negedge clk);
        note($sformatf("float estimate %0d scalar", u), 32'(is_vector), 32'd0);
      end
      instr = fp_encode(VEC_FMACC, 0, 5'd4, 5'd8, 5'd3, 1'b1);
      vlmul = 3'd1;
      @(negedge clk);
      note("misaligned group", 32'(is_vector), 32'd0);
      instr = 32'd0;
      vlmul = 3'd0;
    end
  endtask

  // Float merge model
  task automatic run_fmerge(input logic vmb, input logic [4:0] s2, input logic [4:0] d,
                            input logic [2:0] lmul, input logic [VlW-1:0] len);
    logic [31:0] fsc;
    logic [31:0] e;
    begin
      fsc   = fp_pick();
      vsew  = 3'd2;
      vlmul = lmul;
      vl    = len;
      frm   = 3'($urandom_range(4));
      fdata = fsc;
      xdata = 32'($urandom);
      for (int i = 0; i < int'(len); i++) begin
        e = (vmb || shadow[0][i]) ? fsc : 32'(grp_get(s2, 32, i));
        grp_set(d, 32, i, e);
      end
      flags_seen = '0;
      issue(enc(6'b010111, vmb, vmb ? 5'd0 : s2, 5'($urandom), 3'b101, d));
      fdata = 32'($urandom);
      xdata = 32'($urandom);
      frm   = 3'($urandom);
      drain();
      check_regs($sformatf("%0s lmul %0d vl %0d", vmb ? "vfmv.v.f" : "vfmerge", lmul, len));
      note("float merge flags", 32'(flags_seen), 32'd0);
      frm = 3'd0;
    end
  endtask

  // Float to element
  task automatic run_fmv_sf(input logic [4:0] d, input logic [2:0] lmul, input logic [VlW-1:0] len);
    logic [31:0] fsc;
    begin
      fsc   = fp_pick();
      vsew  = 3'd2;
      vlmul = lmul;
      vl    = len;
      fdata = fsc;
      xdata = 32'($urandom);
      if (len != '0) shadow[d][31:0] = fsc;
      flags_seen = '0;
      issue(enc(6'b010000, 1'b1, 5'd0, 5'($urandom), 3'b101, d));
      fdata = 32'($urandom);
      xdata = 32'($urandom);
      drain();
      check_regs($sformatf("vfmv.s.f v%0d lmul %0d vl %0d", d, lmul, len));
      note("vfmv.s.f flags", 32'(flags_seen), 32'd0);
    end
  endtask

  // Element to float
  task automatic run_fmv_fs(input logic [4:0] s2, input logic [2:0] lmul,
                            input logic [VlW-1:0] len);
    logic [31:0] want;
    logic [31:0] got;
    begin
      vsew  = 3'd2;
      vlmul = lmul;
      vl    = len;
      want  = shadow[s2][31:0];
      flags_seen = '0;
      @(negedge clk);
      instr       = enc(6'b010000, 1'b1, s2, 5'd0, 3'b001, 5'($urandom));
      instr_valid = 1'b1;
      #1;
      note("vfmv.f.s holds", 32'(vec_hold), 32'd1);
      note("vfmv.f.s not integer", 32'(xreg_valid), 32'd0);
      while (vec_hold) @(negedge clk);
      got = xreg_result;
      @(posedge clk);
      #1 instr_valid = 1'b0;
      drain();
      check_regs($sformatf("vfmv.f.s v%0d lmul %0d vl %0d", s2, lmul, len));
      note($sformatf("vfmv.f.s v%0d lmul %0d vl %0d", s2, lmul, len), got, want);
      note("vfmv.f.s flags", 32'(flags_seen), 32'd0);
    end
  endtask

  // Float move legality
  task automatic check_fp_move_rules();
    logic [31:0] forms[4];
    begin
      forms[0] = enc(6'b010111, 1'b0, 5'd8, 5'd1, 3'b101, 5'd12);
      forms[1] = enc(6'b010111, 1'b1, 5'd0, 5'd1, 3'b101, 5'd12);
      forms[2] = enc(6'b010000, 1'b1, 5'd0, 5'd1, 3'b101, 5'd12);
      forms[3] = enc(6'b010000, 1'b1, 5'd8, 5'd0, 3'b001, 5'd12);
      vill  = 1'b0;
      vlmul = 3'd0;
      vl    = 8'd4;
      for (int k = 0; k < 4; k++) begin
        instr = forms[k];
        for (int sw = 0; sw < 3; sw++) begin
          vsew = 3'(sw);
          for (int m = 0; m < 8; m++) begin
            frm = 3'(m);
            @(negedge clk);
            note($sformatf("float move %0d sew %0d frm %0d", k, 8 << sw, m), 32'(is_vector),
                 32'((sw == 2) && (m < 5)));
          end
        end
        vsew = 3'd2;
        frm  = 3'd0;
        vill = 1'b1;
        @(negedge clk);
        note($sformatf("float move %0d vill", k), 32'(is_vector), 32'd0);
        vill = 1'b0;
      end
      instr = enc(6'b010000, 1'b0, 5'd0, 5'd1, 3'b101, 5'd12);
      @(negedge clk);
      note("vfmv.s.f masked", 32'(is_vector), 32'd0);
      instr = enc(6'b010000, 1'b0, 5'd8, 5'd0, 3'b001, 5'd12);
      @(negedge clk);
      note("vfmv.f.s masked", 32'(is_vector), 32'd0);
      instr = enc(6'b010111, 1'b0, 5'd8, 5'd1, 3'b101, 5'd0);
      @(negedge clk);
      note("vfmerge onto v0", 32'(is_vector), 32'd0);
      instr = enc(6'b010111, 1'b1, 5'd0, 5'd1, 3'b101, 5'd0);
      @(negedge clk);
      note("vfmv.v.f onto v0", 32'(is_vector), 32'd1);
      vlmul = 3'd2;
      instr = enc(6'b010111, 1'b0, 5'd8, 5'd1, 3'b101, 5'd6);
      @(negedge clk);
      note("vfmerge misaligned vd", 32'(is_vector), 32'd0);
      instr = enc(6'b010111, 1'b0, 5'd6, 5'd1, 3'b101, 5'd8);
      @(negedge clk);
      note("vfmerge misaligned vs2", 32'(is_vector), 32'd0);
      instr = enc(6'b010000, 1'b1, 5'd0, 5'd1, 3'b101, 5'd3);
      @(negedge clk);
      note("vfmv.s.f ignores lmul", 32'(is_vector), 32'd1);
      instr = enc(6'b010000, 1'b1, 5'd3, 5'd0, 3'b001, 5'd12);
      @(negedge clk);
      note("vfmv.f.s ignores lmul", 32'(is_vector), 32'd1);
      instr = 32'd0;
      vlmul = 3'd0;
    end
  endtask

  function automatic logic fred_snan(input logic [31:0] x);
    return (x[30:23] == 8'hFF) && (x[22:0] != '0) && !x[22];
  endfunction

  // Numeric order key
  function automatic logic signed [32:0] fred_key(input logic [31:0] x);
    return x[31] ? -33'(x[30:0]) : 33'(x[30:0]);
  endfunction

  // Minimum number pair
  function automatic logic [31:0] fred_pair(input vec_fop_e o, input logic [31:0] x,
                                            input logic [31:0] y);
    logic x_nan;
    logic y_nan;
    logic x_first;
    x_nan = (x[30:23] == 8'hFF) && (x[22:0] != '0);
    y_nan = (y[30:23] == 8'hFF) && (y[22:0] != '0);
    if (x_nan && y_nan) return 32'h7FC0_0000;
    if (x_nan) return y;
    if (y_nan) return x;
    if (fred_key(x) == fred_key(y)) x_first = (o == VEC_FMAX) ? !x[31] : x[31];
    else x_first = (o == VEC_FMAX) ? (fred_key(x) > fred_key(y)) : (fred_key(x) < fred_key(y));
    return x_first ? x : y;
  endfunction

  // Element order fold
  // Exact sum then round
  function automatic logic [36:0] ref_add(input logic [31:0] a, input logic [31:0] b,
                                          input logic [2:0] rm);
    logic signed [299:0] xa;
    logic signed [299:0] xb;
    logic signed [299:0] sum;
    logic        [299:0] mag;
    logic        [299:0] rem;
    logic        [299:0] half;
    logic        [299:0] q;
    logic                a_nan;
    logic                b_nan;
    logic                sign;
    logic                up;
    int                  p;
    int                  shift;
    int                  e;
    a_nan = (a[30:23] == 8'hFF) && (a[22:0] != '0);
    b_nan = (b[30:23] == 8'hFF) && (b[22:0] != '0);
    if (a_nan || b_nan)
      return {((a_nan && !a[22]) || (b_nan && !b[22])) ? 5'b10000 : 5'b0, 32'h7FC0_0000};
    if ((a[30:0] == 31'h7F80_0000) && (b[30:0] == 31'h7F80_0000))
      return (a[31] != b[31]) ? {5'b10000, 32'h7FC0_0000} : {5'b0, a};
    if (a[30:0] == 31'h7F80_0000) return {5'b0, a};
    if (b[30:0] == 31'h7F80_0000) return {5'b0, b};
    xa = (a[30:23] == 0) ? 300'(a[22:0]) : (300'({1'b1, a[22:0]}) << (a[30:23] - 1));
    xb = (b[30:23] == 0) ? 300'(b[22:0]) : (300'({1'b1, b[22:0]}) << (b[30:23] - 1));
    if (a[31]) xa = -xa;
    if (b[31]) xb = -xb;
    sum = xa + xb;
    if (sum == 0) return {5'b0, (a[31] == b[31]) ? a[31] : (rm == 3'd2), 31'b0};
    sign = sum < 0;
    mag = sign ? -sum : sum;
    p = 0;
    for (int i = 0; i < 300; i++) if (mag[i]) p = i;
    shift = (p > 23) ? p - 23 : 0;
    q = mag >> shift;
    rem = (shift > 0) ? (mag & ((300'(1) << shift) - 1)) : '0;
    half = (shift > 0) ? (300'(1) << (shift - 1)) : '0;
    case (rm)
      3'd0: up = (rem > half) || ((rem == half) && (rem != 0) && q[0]);
      3'd1: up = 1'b0;
      3'd2: up = (rem != 0) && sign;
      3'd3: up = (rem != 0) && !sign;
      default: up = (rem != 0) && (rem >= half);
    endcase
    q = q + 300'(up);
    e = shift;
    if (q[24]) begin
      q = q >> 1;
      e = e + 1;
    end
    if (!q[23]) return {(rem != 0) ? 5'b00011 : 5'b0, sign, 8'h00, q[22:0]};
    if (e + 1 >= 255) begin
      if ((rm == 3'd1) || ((rm == 3'd2) && !sign) || ((rm == 3'd3) && sign))
        return {5'b00101, sign, 31'h7F7F_FFFF};
      return {5'b00101, sign, 31'h7F80_0000};
    end
    return {(rem != 0) ? 5'b00001 : 5'b0, sign, 8'(e + 1), q[22:0]};
  endfunction

  function automatic logic fred_is_sum(input vec_fop_e o);
    return (o == VEC_FREDOSUM) || (o == VEC_FREDUSUM);
  endfunction

  task automatic ref_fred(input vec_fop_e o, input logic [4:0] s1, input logic [4:0] s2,
                          input logic [4:0] d, input logic vmb, input int regs, input int len,
                          input logic [2:0] rm, output logic [4:0] want_flags);
    logic [31:0] acc;
    logic [31:0] v;
    logic [36:0] r;
    logic        seen;
    want_flags = '0;
    seen       = 1'b0;
    if (len == 0) return;
    acc = grp_get(s1, 32, 0);
    for (int i = 0; i < group_elems(32, regs); i++) begin
      if ((i < len) && (vmb || shadow[0][i])) begin
        v    = grp_get(s2, 32, i);
        seen = 1'b1;
        if (fred_is_sum(o)) begin
          r          = ref_add(acc, v, rm);
          acc        = r[31:0];
          want_flags = want_flags | r[36:32];
        end else begin
          if (fred_snan(acc) || fred_snan(v)) want_flags = 5'b10000;
          acc = fred_pair(o, acc, v);
        end
      end
    end
    if (!seen && (o == VEC_FREDUSUM) && (acc[30:23] == 8'hFF) && (acc[22:0] != '0)) begin
      if (fred_snan(acc)) want_flags = 5'b10000;
      acc = 32'h7FC0_0000;
    end
    grp_set(d, 32, 0, acc);
  endtask

  function automatic logic [31:0] fred_encode(input vec_fop_e o, input logic [4:0] s1,
                                              input logic [4:0] s2, input logic [4:0] d,
                                              input logic vmb);
    logic [5:0] f6;
    case (o)
      VEC_FREDUSUM: f6 = 6'b000001;
      VEC_FREDOSUM: f6 = 6'b000011;
      VEC_FMAX:     f6 = 6'b000111;
      default:      f6 = 6'b000101;
    endcase
    return enc(f6, vmb, s2, s1, 3'b001, d);
  endfunction

  task automatic run_fred(input vec_fop_e o, input logic [4:0] s1, input logic [4:0] s2,
                          input logic [4:0] d, input logic vmb, input logic [2:0] lmul,
                          input logic [VlW-1:0] len, input logic [2:0] rm);
    logic [4:0] want;
    int         regs;
    begin
      regs  = lmul[2] ? 1 : (1 << lmul[1:0]);
      vsew  = 3'd2;
      vlmul = lmul;
      vl    = len;
      frm   = rm;
      ref_fred(o, s1, s2, d, vmb, regs, int'(len), rm, want);
      flags_seen = '0;
      wb_writes  = 0;
      issue(fred_encode(o, s1, s2, d, vmb));
      frm = 3'($urandom_range(4));
      drain();
      check_regs($sformatf("%0s reduction lmul %0d vl %0d", o.name(), lmul, len));
      note($sformatf("fflags after %0s reduction", o.name()), 32'(flags_seen), 32'(want));
      note($sformatf("writes by %0s reduction", o.name()), 32'(wb_writes), 32'(len != 0));
    end
  endtask

  // Signed zeros and NaNs
  function automatic logic [31:0] fred_pick();
    case ($urandom_range(
        7
    ))
      0: return ($urandom_range(1) != 0) ? 32'h0000_0000 : 32'h8000_0000;
      1: return ($urandom_range(1) != 0) ? 32'h7F80_0001 : 32'hFFA0_0000;
      2: return ($urandom_range(1) != 0) ? 32'h7FC0_0000 : 32'hFFC0_1234;
      default: return fp_pick();
    endcase
  endfunction

  task automatic seed_fred();
    logic [VLEN-1:0] v;
    for (int r = 0; r < Depth; r++) begin
      for (int e = 0; e < VLEN / 32; e++) v[e*32+:32] = fred_pick();
      seed_reg(AWIDTH'(r), v);
    end
  endtask

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
            run_fred(o, 5'd4, 5'd16, 5'd5, 1'(m), 3'(lmul), 8'd0, 3'd0);
            run_fred(o, 5'd4, 5'd16, 5'd5, 1'(m), 3'(lmul), 8'd1, 3'd1);
            run_fred(o, 5'd4, 5'd16, 5'd4, 1'(m), 3'(lmul), 8'($urandom_range(4 * regs, 1)), 3'd2);
            run_fred(o, 5'd4, 5'd16, 5'd16, 1'(m), 3'(lmul), 8'(4 * regs), 3'd3);
            run_fred(o, 5'd4, 5'd16, 5'd0, 1'(m), 3'(lmul), 8'(4 * regs), 3'd4);
          end
        end
      end
      seed_fred();
      seed_reg(5'd16, {32'hCB80_0000, 32'h3F80_0000, 32'h3F80_0000, 32'h4B80_0000});
      seed_reg(5'd4, '0);
      for (int rm = 0; rm < 5; rm++) begin
        run_fred(VEC_FREDOSUM, 5'd4, 5'd16, 5'd5, 1'b1, 3'd0, 8'd4, 3'(rm));
        run_fred(VEC_FREDUSUM, 5'd4, 5'd16, 5'd5, 1'b1, 3'd0, 8'd4, 3'(rm));
      end
      seed_reg(5'd4, {(VLEN / 32) {32'h7F80_0001}});
      seed_reg(5'd0, '0);
      run_fred(VEC_FREDOSUM, 5'd4, 5'd16, 5'd5, 1'b0, 3'd0, 8'd4, 3'd0);
      run_fred(VEC_FREDUSUM, 5'd4, 5'd16, 5'd5, 1'b0, 3'd0, 8'd4, 3'd0);
      seed_reg(5'd16, {(VLEN / 32) {32'h8000_0000}});
      seed_reg(5'd4, {(VLEN / 32) {32'h0000_0000}});
      run_fred(VEC_FMIN, 5'd4, 5'd16, 5'd5, 1'b1, 3'd0, 8'd4, 3'd0);
      run_fred(VEC_FMAX, 5'd4, 5'd16, 5'd5, 1'b1, 3'd0, 8'd4, 3'd0);
      seed_reg(5'd4, {(VLEN / 32) {32'h7F80_0001}});
      seed_reg(5'd0, '0);
      run_fred(VEC_FMIN, 5'd4, 5'd16, 5'd5, 1'b0, 3'd1, 8'd8, 3'd0);
      run_fred(VEC_FMAX, 5'd4, 5'd16, 5'd6, 1'b1, 3'd1, 8'd8, 3'd0);
    end
  endtask

  // Reductions among traffic
  task automatic check_fred_stream();
    logic [4:0] want;
    logic [4:0] f;
    logic       sat;
    begin
      for (int r = 0; r < 6; r++) begin
        seed_fred();
        vsew  = 3'd2;
        vlmul = 3'd0;
        vl    = 8'd4;
        frm   = 3'(r % 5);
        want  = '0;
        model_fp(VEC_FMUL, 0, 5'd1, 5'd2, 5'd10, 1'b1, '0, 1, 8'd4, 3'(r % 5), f);
        want = want | f;
        ref_fred(VEC_FREDOSUM, 5'd3, 5'd10, 5'd11, 1'b1, 1, 4, frm, f);
        want = want | f;
        ref_apply(VEC_ADD, 0, 5'd4, 5'd5, 5'd12, 1'b1, '0, 5'd0, 32, 1, 4);
        ref_fred(VEC_FMAX, 5'd11, 5'd6, 5'd13, 1'b0, 1, 4, frm, f);
        want = want | f;
        model_lane(VEC_MUL, 0, 5'd7, 5'd8, 5'd14, 1'b1, '0, 5'd0, 32, 1, 8'd4, 2'd0, sat);
        ref_fred(VEC_FREDUSUM, 5'd13, 5'd14, 5'd15, 1'b1, 1, 4, frm, f);
        want = want | f;
        ref_fred(VEC_FREDOSUM, 5'd15, 5'd10, 5'd16, 1'b0, 1, 4, frm, f);
        want = want | f;
        ref_fred(VEC_FMIN, 5'd3, 5'd2, 5'd17, 1'b1, 1, 4, frm, f);
        want = want | f;
        ref_reduce(VEC_REDSUM, 5'd1, 5'd2, 5'd18, 1'b1, 32, 1, 4, 1'b0);
        flags_seen = '0;
        issue(fp_encode(VEC_FMUL, 0, 5'd1, 5'd2, 5'd10, 1'b1));
        issue(fred_encode(VEC_FREDOSUM, 5'd3, 5'd10, 5'd11, 1'b1));
        issue(enc(6'b000000, 1'b1, 5'd5, 5'd4, 3'b000, 5'd12));
        issue(fred_encode(VEC_FMAX, 5'd11, 5'd6, 5'd13, 1'b0));
        issue(lane_instr(VEC_MUL, 0, 5'd7, 5'd8, 5'd14, 1'b1, 5'd0));
        issue(fred_encode(VEC_FREDUSUM, 5'd13, 5'd14, 5'd15, 1'b1));
        issue(fred_encode(VEC_FREDOSUM, 5'd15, 5'd10, 5'd16, 1'b0));
        issue(fred_encode(VEC_FMIN, 5'd3, 5'd2, 5'd17, 1'b1));
        issue(enc(6'b000000, 1'b1, 5'd2, 5'd1, 3'b010, 5'd18));
        frm = 3'd0;
        drain();
        check_regs($sformatf("reduction stream %0d", r));
        note($sformatf("fflags after reduction stream %0d", r), 32'(flags_seen), 32'(want));
      end
    end
  endtask

  task automatic soak_fred(input int n);
    vec_fop_e       o;
    logic     [2:0] lmul;
    int             regs;
    begin
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
        run_fred(o, 5'($urandom_range(31)), 5'(8 * $urandom_range(3)), 5'($urandom_range(31)),
                 1'($urandom), lmul, 8'($urandom_range(4 * regs)), 3'($urandom_range(4)));
        if ($urandom_range(7) == 0) seed_fred();
      end
    end
  endtask

  task automatic check_fred_rules();
    begin
      vill  = 1'b0;
      vlmul = 3'd0;
      vl    = 8'd4;
      vsew  = 3'd2;
      frm   = 3'd0;
      instr = fred_encode(VEC_FMIN, 5'd4, 5'd8, 5'd12, 1'b1);
      for (int s = 0; s < 3; s++) begin
        vsew = 3'(s);
        @(negedge clk);
        note($sformatf("float reduction at sew %0d", 8 << s), 32'(is_vector), 32'(s == 2));
      end
      for (int m = 0; m < 8; m++) begin
        frm = 3'(m);
        @(negedge clk);
        note($sformatf("float reduction at frm %0d", m), 32'(is_vector), 32'(m < 5));
      end
      for (int k = 0; k < 2; k++) begin
        if (k == 0) instr = fred_encode(VEC_FREDOSUM, 5'd4, 5'd8, 5'd12, 1'b1);
        else instr = fred_encode(VEC_FREDUSUM, 5'd4, 5'd8, 5'd12, 1'b0);
        for (int s = 0; s < 3; s++) begin
          for (int m = 4; m < 7; m++) begin
            vsew = 3'(s);
            frm  = 3'(m);
            @(negedge clk);
            note($sformatf("float sum %0d at sew %0d frm %0d", k, 8 << s, m), 32'(is_vector),
                 32'((s == 2) && (m < 5)));
          end
        end
      end
      vsew  = 3'd2;
      frm   = 3'd0;
      instr = enc(6'b000001, 1'b1, 5'd8, 5'd4, 3'b101, 5'd12);
      @(negedge clk);
      note("float sum scalar form", 32'(is_vector), 32'd0);
      instr = enc(6'b000111, 1'b1, 5'd8, 5'd4, 3'b101, 5'd12);
      @(negedge clk);
      note("float reduction scalar form", 32'(is_vector), 32'd0);
      instr = fred_encode(VEC_FMAX, 5'd4, 5'd9, 5'd12, 1'b1);
      vlmul = 3'd1;
      @(negedge clk);
      note("misaligned reduction source", 32'(is_vector), 32'd0);
      instr = fred_encode(VEC_FMAX, 5'd5, 5'd8, 5'd13, 1'b0);
      @(negedge clk);
      note("reduction scalar and dest any", 32'(is_vector), 32'd1);
      instr = 32'd0;
      vlmul = 3'd0;
    end
  endtask

  // Every float move
  task automatic check_fp_moves();
    logic [2:0] lmul;
    int regs;
    begin
      seed_fp();
      for (int g = 0; g < 4; g++) begin
        lmul = 3'(g);
        regs = 1 << g;
        run_fmerge(1'b0, 5'd16, 5'd8, lmul, 8'(4 * regs));
        run_fmerge(1'b0, 5'd24, 5'd16, lmul, 8'(1 + $urandom_range(4 * regs - 1)));
        run_fmerge(1'b1, 5'd0, 5'd8, lmul, 8'(4 * regs));
        run_fmerge(1'b1, 5'd0, 5'd24, lmul, 8'(1 + $urandom_range(4 * regs - 1)));
        run_fmerge(1'b0, 5'd8, 5'd8, lmul, 8'(4 * regs));
        run_fmerge(1'b0, 5'd16, 5'd8, lmul, 8'd0);
        run_fmerge(1'b1, 5'd0, 5'd8, lmul, 8'd0);
        run_fmv_sf(5'(8 + g), lmul, 8'(1 + $urandom_range(4 * regs - 1)));
        run_fmv_sf(5'd9, lmul, 8'd0);
        run_fmv_fs(5'(16 + g), lmul, 8'(1 + $urandom_range(4 * regs - 1)));
        run_fmv_fs(5'd17, lmul, 8'd0);
        seed_fp();
      end
      run_fmerge(1'b1, 5'd0, 5'd0, 3'd0, 8'd4);
    end
  endtask

  // Moves behind float
  task automatic check_fp_move_stream();
    logic [ 4:0] f;
    logic [31:0] fsc;
    logic [31:0] want;
    logic [31:0] got;
    begin
      for (int r = 0; r < 6; r++) begin
        seed_fp();
        vsew  = 3'd2;
        vlmul = 3'(r % 4);
        vl    = 8'(4 << (r % 4));
        frm   = 3'($urandom_range(4));
        fsc   = fp_pick();
        model_fp(VEC_FMUL, 0, 5'd16, 5'd24, 5'd8, 1'b1, '0, 1 << (r % 4), vl, frm, f);
        for (int i = 0; i < int'(vl); i++)
        grp_set(5'd16, 32, i, shadow[0][i] ? fsc : 32'(grp_get(5'd8, 32, i)));
        want = shadow[16][31:0];
        issue(fp_encode(VEC_FMUL, 0, 5'd16, 5'd24, 5'd8, 1'b1));
        fdata = fsc;
        issue(enc(6'b010111, 1'b0, 5'd8, 5'd1, 3'b101, 5'd16));
        fdata = 32'($urandom);
        @(negedge clk);
        instr       = enc(6'b010000, 1'b1, 5'd16, 5'd0, 3'b001, 5'd3);
        instr_valid = 1'b1;
        #1;
        while (vec_hold) @(negedge clk);
        got = xreg_result;
        @(posedge clk);
        #1 instr_valid = 1'b0;
        drain();
        check_regs($sformatf("float move stream %0d", r));
        note($sformatf("vfmv.f.s after merge %0d", r), got, want);
        frm = 3'd0;
      end
    end
  endtask

  // Nonzero vstart traps
  task automatic check_vstart_rules();
    logic [5:0] f6;
    logic [2:0] f3;
    begin
      vill  = 1'b0;
      vlmul = 3'd0;
      vl    = 8'd4;
      frm   = 3'd0;
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
        instr = enc(f6, 1'b1, 5'd8, 5'd4, f3, 5'd12);
        for (int v = 0; v < 2; v++) begin
          vstart_set = 1'(v);
          @(negedge clk);
          note($sformatf("form %0d with vstart set %0d", k, v), 32'(is_vector),
               32'((k >= 14) || (v == 0)));
        end
      end
      vstart_set = 1'b0;
      instr      = 32'd0;
      vsew       = 3'd2;
    end
  endtask

  int busy_cycles = 0;
  always @(negedge clk) if (rst_n && core_en && dut.seq_busy) busy_cycles = busy_cycles + 1;

  // Group step cadence
  task automatic check_fred_timing();
    begin
      seed_fred();
      vsew  = 3'd2;
      vlmul = 3'd3;
      vl    = 8'd32;
      frm   = 3'd0;
      for (int k = 0; k < 4; k++) begin
        busy_cycles = 0;
        case (k)
          0: issue(enc(6'b000000, 1'b1, 5'd8, 5'd16, 3'b000, 5'd24));
          1: issue(fred_encode(VEC_FMIN, 5'd1, 5'd8, 5'd2, 1'b1));
          2: issue(fred_encode(VEC_FREDOSUM, 5'd1, 5'd8, 5'd3, 1'b1));
          default: issue(fred_encode(VEC_FREDUSUM, 5'd1, 5'd8, 5'd4, 1'b1));
        endcase
        drain();
        note($sformatf("busy cycles of form %0d", k), 32'(busy_cycles), (k < 2) ? 32'd8 : 32'd63);
      end
      seed_fred();
      vlmul = 3'd0;
      vl    = 8'd4;
    end
  endtask

  // Compress model
  task automatic ref_compress(input logic [4:0] s1, input logic [4:0] s2, input logic [4:0] d,
                              input int w, input logic [VlW-1:0] len);
    int pos;
    begin
      pos = 0;
      for (int i = 0; i < int'(len); i++) begin
        if (mbit(s1, i)) begin
          grp_set(d, w, pos, grp_get(s2, w, i));
          pos = pos + 1;
        end
      end
    end
  endtask

  // One compress
  task automatic run_compress(input logic [4:0] s1, input logic [4:0] s2, input logic [4:0] d,
                              input logic [2:0] sew, input logic [2:0] lmul,
                              input logic [VlW-1:0] len);
    begin
      vsew  = sew;
      vlmul = lmul;
      vl    = len;
      ref_compress(s1, s2, d, 8 << sew, len);
      issue(enc(6'b010111, 1'b1, s2, s1, 3'b010, d));
      drain();
      check_regs("compress");
    end
  endtask

  // Every compress shape
  task automatic check_compress();
    int vlmax;
    logic [2:0] sew;
    begin
      seed_all();
      for (int e = 0; e < 3; e++) begin
        sew = 3'(e);
        for (int lmul = 0; lmul < 2; lmul++) begin
          vlmax = (VLEN >> (3 + sew)) << lmul;
          run_compress(5'd3, 5'd8, 5'd12, sew, 3'(lmul), VlW'(vlmax));
          run_compress(5'd3, 5'd8, 5'd12, sew, 3'(lmul), VlW'(1 + ($urandom % vlmax)));
          seed_reg(5'd3, '0);
          run_compress(5'd3, 5'd8, 5'd12, sew, 3'(lmul), VlW'(vlmax));
          seed_reg(5'd3, '1);
          run_compress(5'd3, 5'd8, 5'd12, sew, 3'(lmul), VlW'(vlmax));
          run_compress(5'd3, 5'd8, 5'd12, sew, 3'(lmul), VlW'(vlmax / 2 - 1));
          seed_reg(5'd3, rand_vec());
          run_compress(5'd3, 5'd8, 5'd12, sew, 3'(lmul), VlW'(vlmax - 3));
          run_compress(5'd0, 5'd16, 5'd20, sew, 3'(lmul), VlW'(vlmax));
        end
      end
      run_compress(5'd3, 5'd8, 5'd16, 3'd0, 3'd3, 8'd0);
      for (int k = 0; k < 12; k++) begin
        sew = 3'($urandom % 3);
        seed_reg(5'd3, rand_vec());
        run_compress(5'd3, 5'd8, 5'd16, sew, 3'd2,
                     VlW'($urandom % (((VLEN >> (3 + sew)) << 2) + 1)));
      end
    end
  endtask

  // Compress back to back
  task automatic check_compress_stream();
    begin
      seed_all();
      vsew  = 3'd2;
      vlmul = 3'd1;
      vl    = 8'd8;
      ref_apply(VEC_ADD, 0, 5'd4, 5'd6, 5'd8, 1'b1, '0, 5'd0, 32, 2, 8);
      issue(enc(6'b000000, 1'b1, 5'd6, 5'd4, 3'b000, 5'd8));
      ref_compress(5'd3, 5'd8, 5'd12, 32, 8'd8);
      issue(enc(6'b010111, 1'b1, 5'd8, 5'd3, 3'b010, 5'd12));
      ref_apply(VEC_XOR, 0, 5'd12, 5'd8, 5'd14, 1'b1, '0, 5'd0, 32, 2, 8);
      issue(enc(6'b001011, 1'b1, 5'd8, 5'd12, 3'b000, 5'd14));
      drain();
      check_regs("compress stream");
    end
  endtask

  // Compress encodings trap
  task automatic check_compress_rules();
    begin
      vill  = 1'b0;
      vsew  = 3'd0;
      vl    = 8'd8;
      vlmul = 3'd1;
      instr = enc(6'b010111, 1'b1, 5'd8, 5'd3, 3'b010, 5'd12);
      #1 note("compress legal", 32'(is_vector), 32'd1);
      instr = enc(6'b010111, 1'b0, 5'd8, 5'd3, 3'b010, 5'd12);
      #1 note("compress masked", 32'(is_vector), 32'd0);
      instr = enc(6'b010111, 1'b1, 5'd8, 5'd3, 3'b010, 5'd8);
      #1 note("compress onto source", 32'(is_vector), 32'd0);
      instr = enc(6'b010111, 1'b1, 5'd8, 5'd13, 3'b010, 5'd12);
      #1 note("compress onto mask", 32'(is_vector), 32'd0);
      instr = enc(6'b010111, 1'b1, 5'd8, 5'd12, 3'b010, 5'd12);
      #1 note("compress mask is base", 32'(is_vector), 32'd0);
      instr = enc(6'b010111, 1'b1, 5'd8, 5'd3, 3'b010, 5'd13);
      #1 note("compress base off", 32'(is_vector), 32'd0);
      instr = enc(6'b010111, 1'b1, 5'd8, 5'd0, 3'b010, 5'd10);
      #1 note("compress beside source", 32'(is_vector), 32'd1);
      vlmul = 3'd0;
      instr = 32'd0;
    end
  endtask

  task automatic verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors != 0) $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $display("PASS: %0d checks", checks);
    $finish;
  endtask

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    repeat (Timeout) @(posedge clk);
    $fatal(1, "vec_unit timeout, %0d errors, %0d checks", errors, checks);
  end

  initial begin
    // Quiet start
    init_signals();

    // Snapshot survives reconfigure
    check_snapshot();

    // Non vector ignored
    check_not_vector();

    // Tail stays untouched
    check_tail();

    // Mask gates writes
    check_masked();

    // Groups walk registers
    check_groups();

    // Scalar and immediate
    check_forms();

    // Zero length
    check_zero_length();

    // Random traffic
    soak(120);

    // Legality and alignment
    check_mem_rules();
    check_group_rules();
    check_fixed_point();
    check_compares();
    check_carry();
    check_mask_logic();
    check_mask_set();
    check_mask_index();
    check_mask_scalar();

    // Trap drops instruction
    check_mem_cancel();

    // Pending until drained
    check_mem_pending();

    // Directed moves
    check_moves();

    // Random moves
    soak_mem(300);

    // Whole register groups
    check_whole_rules();
    check_whole();

    // Widening forms
    check_widening();

    // Narrowing shifts
    check_narrowing();

    // Extension forms
    check_extensions();

    // Reduction forms
    check_reductions();

    // Scalar moves
    check_scalar_moves();

    check_lane_rules();
    check_multiplies();
    check_widening_muls();
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
    soak_fp(200);
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

    check_compress_rules();
    check_compress();
    check_compress_stream();

    verdict();
  end

endmodule

`default_nettype wire
