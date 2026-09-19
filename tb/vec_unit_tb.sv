`default_nettype none

module vec_unit_tb
  import vec_pkg::*;
();

  localparam int AWIDTH = 5;
  localparam int VLEN = 128;
  localparam int Depth = 2 ** AWIDTH;
  localparam int Bytes = 256;
  localparam int Timeout = 100000;

  int checks = 0;
  int errors = 0;

  logic clk = 1'b0;
  logic rst_n;
  logic core_en;
  logic [31:0] instr;
  logic instr_valid;
  logic cancel;
  logic [31:0] xdata;
  logic [31:0] xstride;
  logic vill;
  logic [7:0] vl;
  logic [2:0] vsew;
  logic [2:0] vlmul;
  logic [1:0] vxrm;
  logic is_vector;
  logic vec_hold;
  logic vec_idle;
  logic load_pending;
  logic store_pending;
  logic mem_misaligned;
  logic [31:0] mem_bad_addr;
  logic xreg_valid;
  logic [31:0] xreg_result;

  logic [VLEN-1:0] shadow[Depth];

  // Memory model
  logic [31:0] mem_rdata;
  logic mem_ready;
  logic mem_req;
  logic [31:0] mem_addr;
  logic [31:0] mem_wdata;
  logic [3:0] mem_wstrb;
  logic [7:0] mem[Bytes];
  logic [7:0] gmem[Bytes];
  int ready_pct = 100;

  always #5 clk = ~clk;

  vec_unit #(
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .instr(instr),
      .instr_valid(instr_valid),
      .cancel(cancel),
      .xdata(xdata),
      .xstride(xstride),
      .vill(vill),
      .vl(vl),
      .vsew(vsew),
      .vlmul(vlmul),
      .vxrm(vxrm),
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

  assign mem_rdata = {
    mem[(mem_addr+3)%Bytes], mem[(mem_addr+2)%Bytes], mem[(mem_addr+1)%Bytes], mem[mem_addr%Bytes]
  };

  always @(posedge clk) begin
    #2;
    mem_ready = ($urandom_range(99) < ready_pct);
  end

  always @(posedge clk) begin
    if (rst_n && core_en && mem_req && mem_ready) begin
      for (int k = 0; k < 4; k++)
      if (mem_wstrb[k]) mem[(mem_addr+32'(k))%Bytes] <= mem_wdata[k*8+:8];
    end
  end

  // Element access
  function automatic logic [VLEN-1:0] wmask(input int w);
    wmask = (VLEN'(1) << w) - VLEN'(1);
  endfunction

  function automatic logic [31:0] get_elem(input logic [VLEN-1:0] v, input int w, input int e);
    get_elem = 32'((v >> (e * w)) & wmask(w));
  endfunction

  function automatic logic [VLEN-1:0] set_elem(input logic [VLEN-1:0] v, input int w, input int e,
                                               input logic [31:0] val);
    set_elem = (v & ~(wmask(w) << (e * w))) | ((VLEN'(val) & wmask(w)) << (e * w));
  endfunction

  function automatic logic [31:0] sext(input logic [31:0] v, input int w);
    sext = v[w-1] ? (v | ~(32'((32'h1 << w) - 32'h1))) : (v & 32'((32'h1 << w) - 32'h1));
  endfunction

  // Element rule
  function automatic logic [31:0] ref_op(input vec_op_e o, input int w, input logic [31:0] ra,
                                         input logic [31:0] rb, input logic cin, input logic vmb);
    logic [31:0] m;
    logic [31:0] a;
    logic [31:0] b;
    logic [31:0] sa;
    logic [31:0] sb;
    logic [31:0] sr;
    int sh;
    begin
      m  = 32'((32'h1 << w) - 32'h1);
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

  task automatic seed_all();
    for (int r = 0; r < Depth; r++) seed_reg(AWIDTH'(r), {$urandom, $urandom, $urandom, $urandom});
  endtask

  task automatic init_signals();
    rst_n       = 1'b0;
    core_en     = 1'b1;
    instr       = '0;
    instr_valid = 1'b0;
    cancel      = 1'b0;
    xdata       = '0;
    xstride     = '0;
    vill        = 1'b0;
    mem_ready   = 1'b1;
    for (int b = 0; b < Bytes; b++) begin
      mem[b]  = 8'($urandom);
      gmem[b] = mem[b];
    end
    vl    = 8'd4;
    vsew  = 3'd2;
    vlmul = 3'd0;
    vxrm  = 2'd0;
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
      end
      @(negedge clk);
    end
  endtask

  // Model one instruction
  task automatic ref_apply(input vec_op_e o, input int form, input logic [4:0] s1,
                           input logic [4:0] s2, input logic [4:0] d, input logic vmb,
                           input logic [31:0] xd, input logic [4:0] im, input int w, input int regs,
                           input int len);
    int per_reg;
    int idx;
    logic [31:0] ea;
    logic [31:0] eb;
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
              1: eb = xd & 32'((32'h1 << w) - 32'h1);
              default: eb = {{27{im[4]}}, im} & 32'((32'h1 << w) - 32'h1);
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
      end
    end
  endtask

  // Run one operation
  task automatic run_one(input vec_op_e o, input int form, input logic [4:0] s1,
                         input logic [4:0] s2, input logic [4:0] d, input logic vmb,
                         input logic [31:0] xd, input logic [4:0] im, input logic [2:0] sew,
                         input logic [2:0] lmul, input logic [7:0] len);
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
      ref_apply(VEC_ADD, 0, 5'd3, 5'd11, 5'd19, 1'b1, '0, 5'd0, 8, 8, 70);
      issue(enc(6'b000000, 1'b1, 5'd11, 5'd3, 3'b000, 5'd19));
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
      issue(enc(6'b000000, 1'b1, 5'd4, 5'd3, 3'b001, 5'd5));
      drain();
      check_regs("float form");
      issue(enc(6'b001100, 1'b1, 5'd4, 5'd3, 3'b000, 5'd5));
      drain();
      check_regs("gather");
      issue(enc(6'b011000, 1'b1, 5'd4, 5'd3, 3'b000, 5'd5));
      drain();
      check_regs("compare");
      issue(enc(6'b100101, 1'b1, 5'd4, 5'd3, 3'b010, 5'd5));
      drain();
      check_regs("multiply");
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
    logic [7:0] len;
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
        len  = 8'($urandom % ((128 >> sew) * (1 << lmul) + 1));
        vmb  = 1'($urandom);
        if (o == VEC_MERGE) vmb = 1'b0;
        run_one(o, form, 5'd2, 5'd10, 5'd18, vmb, $urandom, 5'($urandom), sew, lmul, len);
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
                         input logic [31:0] b, input logic [31:0] st, input int len);
    int bytes;
    int per_reg;
    int r;
    logic [31:0] a;
    logic [31:0] e;
    begin
      bytes   = 1 << w;
      per_reg = 16 >> w;
      for (int i = 0; i < len; i++) begin
        a = b + 32'(i) * st;
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
      end
    end
  endtask

  task automatic note(input string what, input logic [31:0] got, input logic [31:0] want);
    checks = checks + 1;
    if (got !== want) begin
      errors = errors + 1;
      $display("FAIL %0s got=%h want=%h at %0t", what, got, want, $time);
    end
  endtask

  // Run one move
  task automatic run_mem(input logic store, input logic [1:0] w, input logic whole,
                         input logic strided, input logic vmb, input logic [4:0] d,
                         input logic [31:0] b, input logic [31:0] st, input logic [2:0] sew,
                         input logic [2:0] lmul, input logic [7:0] len);
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
      run_mem(1'b0, 2'd1, 1'b0, 1'b0, 1'b1, 5'd13, 32'd40, '0, 3'd0, 3'd0, 8'd12);
      run_mem(1'b1, 2'd0, 1'b0, 1'b0, 1'b1, 5'd20, 32'd0, '0, 3'd0, 3'd3, 8'd100);
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
    logic [7:0] len;
    int emul;
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
        vlmax     = (VLEN << lmul) >> (3 + sew);
        len       = 8'($urandom % ((vlmax > 255 ? 255 : vlmax) + 1));
        d         = (!vmb && !store) ? 5'd23 - 5'($urandom % 20) : 5'($urandom);
        ready_pct = (($urandom % 2) == 0) ? 100 : 40;
        run_mem(store, w, whole, strided, vmb, d, 32'($urandom % Bytes) & ~((32'd1 << w) - 1),
                32'($signed(32'($urandom % 13)) - 6) << w, sew, lmul, len);
      end
      ready_pct = 100;
    end
  endtask


  // Group element access
  function automatic logic [31:0] grp_get(input logic [4:0] base, input int w, input int i);
    int roff;
    int pos;
    roff = (i * w) / VLEN;
    pos  = ((i * w) % VLEN) / w;
    return get_elem(shadow[(32'(base)+roff)%Depth], w, pos);
  endfunction

  task automatic grp_set(input logic [4:0] base, input int w, input int i,
                         input logic [31:0] val);
    int roff;
    int pos;
    roff = (i * w) / VLEN;
    pos  = ((i * w) % VLEN) / w;
    shadow[(32'(base)+roff)%Depth] = set_elem(shadow[(32'(base)+roff)%Depth], w, pos, val);
  endtask

  function automatic int group_elems(input int sew, input int regs);
    return regs * (VLEN / sew);
  endfunction

  // Widening model
  task automatic ref_widen(input vec_op_e o, input int form, input logic [4:0] s1,
                           input logic [4:0] s2, input logic [4:0] d, input logic vmb,
                           input logic [31:0] xd, input int sew, input int regs, input int len,
                           input logic wv);
    int dw;
    logic [31:0] a;
    logic [31:0] b;
    logic sgn;
    dw  = sew * 2;
    sgn = (o == VEC_WADD) || (o == VEC_WSUB);
    for (int i = 0; i < group_elems(sew, regs); i++) begin
      if ((i < len) && (vmb || shadow[0][i])) begin
        if (wv) a = grp_get(s2, dw, i);
        else a = sgn ? sext(grp_get(s2, sew, i), sew) : grp_get(s2, sew, i);
        b = (form == 0) ? grp_get(s1, sew, i) : (xd & 32'((32'h1 << sew) - 32'h1));
        if (sgn) b = sext(b, sew);
        grp_set(d, dw, i, ((o == VEC_WSUBU) || (o == VEC_WSUB)) ? (a - b) : (a + b));
      end
    end
  endtask

  // Narrowing model
  task automatic ref_narrow(input vec_op_e o, input int form, input logic [4:0] s1,
                            input logic [4:0] s2, input logic [4:0] d, input logic vmb,
                            input logic [31:0] xd, input logic [4:0] im, input int sew,
                            input int regs, input int len);
    logic [31:0] w;
    logic [31:0] r;
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
    logic [31:0] a;
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
  function automatic logic [31:0] ref_fold(input vec_op_e o, input logic [31:0] x,
                                           input logic [31:0] y);
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
    logic [31:0] acc;
    logic [31:0] v;
    logic sgn;
    accw = wide ? sew * 2 : sew;
    sgn  = (o == VEC_REDMIN) || (o == VEC_REDMAX) || (o == VEC_WREDSUM);
    if (len == 0) return;
    acc = grp_get(s1, accw, 0);
    if (sgn) acc = sext(acc, accw);
    for (int i = 0; i < group_elems(sew, regs); i++) begin
      if ((i < len) && (vmb || shadow[0][i])) begin
        v   = grp_get(s2, sew, i);
        if (sgn) v = sext(v, sew);
        acc = ref_fold(o, acc, v);
      end
    end
    grp_set(d, accw, 0, acc);
  endtask

  // Mixed width runs
  task automatic run_widen(input vec_op_e o, input int form, input logic [4:0] s1,
                           input logic [4:0] s2, input logic [4:0] d, input logic vmb,
                           input logic [31:0] xd, input logic [2:0] sew, input logic [2:0] lmul,
                           input logic [7:0] len, input logic wv);
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
                            input logic [31:0] xd, input logic [4:0] im, input logic [2:0] sew,
                            input logic [2:0] lmul, input logic [7:0] len);
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
                            input logic [7:0] len);
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
                            input logic [2:0] lmul, input logic [7:0] len);
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
  task automatic run_move_sx(input logic [4:0] d, input logic [31:0] xd, input logic [2:0] sew,
                             input logic [7:0] len);
    vsew  = sew;
    vlmul = 3'd0;
    vl    = len;
    xdata = xd;
    if (len != 8'd0) grp_set(d, 8 << sew, 0, xd);
    issue(enc(6'b010000, 1'b1, 5'b00000, 5'd3, 3'b110, d));
    drain();
    check_regs("move sx");
  endtask

  task automatic run_move_xs(input logic [4:0] s2, input logic [2:0] sew, input logic [7:0] len);
    logic [31:0] want;
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
    seed_reg(5'd1, {4{32'hFFFF_FFFF}});
    seed_reg(5'd2, {4{32'hA5A5_A5A5}});
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

  task automatic verdict();
    $display("vec_unit: %0d checks, %0d errors", checks, errors);
    if (errors != 0) $fatal(1, "vec_unit FAILED");
    $finish;
  endtask

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

    // Trap drops instruction
    check_mem_cancel();

    // Pending until drained
    check_mem_pending();

    // Directed moves
    check_moves();

    // Random moves
    soak_mem(300);

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

    verdict();
  end

endmodule

`default_nettype wire
