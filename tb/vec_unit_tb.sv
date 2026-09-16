`default_nettype none

module vec_unit_tb
  import vec_pkg::*;
();

  localparam int AWIDTH = 5;
  localparam int VLEN = 128;
  localparam int Depth = 2 ** AWIDTH;

  int checks = 0;
  int errors = 0;

  logic clk = 1'b0;
  logic rst_n;
  logic core_en;
  logic [31:0] instr;
  logic instr_valid;
  logic [31:0] xdata;
  logic [7:0] vl;
  logic [2:0] vsew;
  logic [2:0] vlmul;
  logic [1:0] vxrm;
  logic is_vector;
  logic vec_hold;
  logic vec_idle;

  logic [VLEN-1:0] shadow[Depth];

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
      .xdata(xdata),
      .vl(vl),
      .vsew(vsew),
      .vlmul(vlmul),
      .vxrm(vxrm),
      .mem_rdata('0),
      .mem_ready(1'b0),
      .mem_req(),
      .mem_addr(),
      .mem_wdata(),
      .mem_wstrb(),
      .is_vector(is_vector),
      .vec_hold(vec_hold),
      .vec_idle(vec_idle)
  );

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
    xdata       = '0;
    vl          = 8'd4;
    vsew        = 3'd2;
    vlmul       = 3'd0;
    vxrm        = 2'd0;
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

  task automatic verdict();
    $display("vec_unit: %0d checks, %0d errors", checks, errors);
    if (errors != 0) $fatal(1, "vec_unit FAILED");
    $finish;
  endtask

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

    verdict();
  end

endmodule

`default_nettype wire
