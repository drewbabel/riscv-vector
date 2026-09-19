`default_nettype none

module vec_decode_tb
  import vec_pkg::*;
  import opcode_pkg::*;
();

  int              checks = 0;
  int              errors = 0;

  logic     [31:0] instr;
  logic            valid;
  vec_op_e         op;
  vec_src_e        src;
  vec_eew_e        eew;
  logic            vm;
  logic     [ 4:0] vs1;
  logic     [ 4:0] vs2;
  logic     [ 4:0] vd;
  logic     [ 4:0] simm;
  logic            reads_vd;
  logic            reads_xreg;
  logic            writes_xreg;
  logic            writes_mask;
  logic     [ 1:0] mem_width;
  logic            mem_whole;
  logic            mem_mask;
  logic            mem_strided;

  localparam logic [2:0] Fvv = 3'b000;
  localparam logic [2:0] Fvx = 3'b100;
  localparam logic [2:0] Fvi = 3'b011;
  localparam logic [2:0] Fmv = 3'b010;
  localparam logic [2:0] Fmx = 3'b110;

  vec_decode dut (
      .instr      (instr),
      .valid      (valid),
      .op         (op),
      .src        (src),
      .eew        (eew),
      .vm         (vm),
      .vs1        (vs1),
      .vs2        (vs2),
      .vd         (vd),
      .simm       (simm),
      .reads_vd   (reads_vd),
      .reads_xreg (reads_xreg),
      .writes_xreg(writes_xreg),
      .writes_mask(writes_mask),
      .mem_width  (mem_width),
      .mem_whole  (mem_whole),
      .mem_mask   (mem_mask),
      .mem_strided(mem_strided)
  );

  function automatic logic [31:0] enc(input logic [5:0] funct6, input logic mask_bit,
                                      input logic [4:0] rs2, input logic [4:0] rs1,
                                      input logic [2:0] funct3, input logic [4:0] rd);
    return {funct6, mask_bit, rs2, rs1, funct3, rd, OpcodeOpV};
  endfunction

  function automatic logic [31:0] enc_mem(input logic [6:0] top, input logic [4:0] rs2,
                                          input logic [2:0] width, input logic store);
    return {top, rs2, 5'd10, width, 5'd3, store ? OpcodeStoreFp : OpcodeLoadFp};
  endfunction

  // Reference memory forms
  function automatic logic [5:0] ref_mem(input logic [6:0] top, input logic [4:0] rs2,
                                         input logic [2:0] width, input logic store);
    logic [2:0] nf;
    logic mew, mask_bit;
    logic [1:0] mop, w;
    nf = top[6:4];
    mew = top[3];
    mop = top[2:1];
    mask_bit = top[0];
    case (width)
      3'b000: w = 2'd0;
      3'b101: w = 2'd1;
      3'b110: w = 2'd2;
      default: return 6'b0;
    endcase
    if (nf != 3'b000 || mew) return 6'b0;
    if (mop == 2'b10) return {1'b1, w, 3'b010};
    if (mop != 2'b00) return 6'b0;
    if (rs2 == 5'b00000) return {1'b1, w, 3'b000};
    if (rs2 == 5'b01000 && mask_bit && (!store || width == 3'b000)) return {1'b1, w, 3'b100};
    if (rs2 == 5'b01011 && mask_bit && width == 3'b000) return {1'b1, w, 3'b001};
    return 6'b0;
  endfunction

  // Reference legality
  function automatic logic ref_valid(input logic [2:0] funct3, input logic [5:0] funct6,
                                     input logic [4:0] rs1, input logic [4:0] rs2);
    logic v, x, i;
    v = (funct3 == Fvv);
    x = (funct3 == Fvx);
    i = (funct3 == Fvi);
    if (v || x || i) begin
      case (funct6)
        6'b000000: return 1'b1;
        6'b000010: return v || x;
        6'b000011: return x || i;
        6'b000100, 6'b000101, 6'b000110, 6'b000111: return v || x;
        6'b001001, 6'b001010, 6'b001011, 6'b001100: return 1'b1;
        6'b001110: return 1'b1;
        6'b001111: return x || i;
        6'b010000, 6'b010001: return 1'b1;
        6'b010010, 6'b010011: return v || x;
        6'b010111: return 1'b1;
        6'b011000, 6'b011001: return 1'b1;
        6'b011010, 6'b011011: return v || x;
        6'b011100, 6'b011101: return 1'b1;
        6'b011110, 6'b011111: return x || i;
        6'b100000, 6'b100001: return 1'b1;
        6'b100010, 6'b100011: return v || x;
        6'b100101: return 1'b1;
        6'b100111: return 1'b1;
        6'b101000, 6'b101001, 6'b101010, 6'b101011: return 1'b1;
        6'b101100, 6'b101101, 6'b101110, 6'b101111: return 1'b1;
        6'b110000, 6'b110001: return v;
        default: return 1'b0;
      endcase
    end else if (funct3 == Fmv || funct3 == Fmx) begin
      case (funct6)
        6'b000000, 6'b000001, 6'b000010, 6'b000011: return funct3 == Fmv;
        6'b000100, 6'b000101, 6'b000110, 6'b000111: return funct3 == Fmv;
        6'b001000, 6'b001001, 6'b001010, 6'b001011: return 1'b1;
        6'b001110, 6'b001111: return funct3 == Fmx;
        6'b010000:
        if (funct3 == Fmv) return rs1 == 5'b00000 || rs1 == 5'b10000 || rs1 == 5'b10001;
        else return rs2 == 5'b00000;
        6'b010010:
        return (funct3 == Fmv) && (rs1 == 5'b00010 || rs1 == 5'b00011 || rs1 == 5'b00100 ||
                                   rs1 == 5'b00101 || rs1 == 5'b00110 || rs1 == 5'b00111);
        6'b010100:
        return (funct3 == Fmv) && (rs1 == 5'b00001 || rs1 == 5'b00010 || rs1 == 5'b00011 ||
                                   rs1 == 5'b10000 || rs1 == 5'b10001);
        6'b010111: return funct3 == Fmv;
        6'b011000, 6'b011001, 6'b011010, 6'b011011: return funct3 == Fmv;
        6'b011100, 6'b011101, 6'b011110, 6'b011111: return funct3 == Fmv;
        6'b100000, 6'b100001, 6'b100010, 6'b100011: return 1'b1;
        6'b100100, 6'b100101, 6'b100110, 6'b100111: return 1'b1;
        6'b101001, 6'b101011, 6'b101101, 6'b101111: return 1'b1;
        6'b110000, 6'b110001, 6'b110010, 6'b110011: return 1'b1;
        6'b110100, 6'b110101, 6'b110110, 6'b110111: return 1'b1;
        6'b111000, 6'b111010, 6'b111011: return 1'b1;
        6'b111100, 6'b111101, 6'b111111: return 1'b1;
        6'b111110: return funct3 == Fmx;
        default: return 1'b0;
      endcase
    end
    return 1'b0;
  endfunction

  // Checks
  task automatic chk_op(input logic [5:0] funct6, input logic [2:0] funct3, input logic [4:0] rs1,
                        input vec_op_e exp_op, input vec_src_e exp_src, input vec_eew_e exp_eew);
    instr = enc(funct6, 1'b1, 5'd2, rs1, funct3, 5'd3);
    #1;
    checks++;
    if (op !== exp_op || src !== exp_src || eew !== exp_eew || !valid) begin
      errors++;
      $display("FAIL op f6=%b f3=%b got=%0d/%0d/%0d exp=%0d/%0d/%0d at %0t", funct6, funct3, op,
               src, eew, exp_op, exp_src, exp_eew, $time);
    end
  endtask

  task automatic chk_flags(input logic [5:0] funct6, input logic [2:0] funct3,
                           input logic [4:0] rs1, input logic [3:0] exp);
    logic [3:0] got;
    instr = enc(funct6, 1'b1, 5'd2, rs1, funct3, 5'd3);
    #1;
    got = {reads_vd, reads_xreg, writes_xreg, writes_mask};
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL flags f6=%b f3=%b got=%b exp=%b at %0t", funct6, funct3, got, exp, $time);
    end
  endtask

  task automatic chk_illegal(input logic [5:0] funct6, input logic [2:0] funct3,
                             input logic [4:0] rs1);
    instr = enc(funct6, 1'b1, 5'd2, rs1, funct3, 5'd3);
    #1;
    checks++;
    if (valid !== 1'b0 || op !== VEC_ILLEGAL) begin
      errors++;
      $display("FAIL illegal f6=%b f3=%b got=%0d at %0t", funct6, funct3, op, $time);
    end
  endtask

  task automatic chk_fields(input logic [4:0] rs2, input logic [4:0] rs1, input logic [4:0] rd,
                            input logic mask_bit);
    instr = enc(6'b000000, mask_bit, rs2, rs1, Fvv, rd);
    #1;
    checks++;
    if (vs2 !== rs2 || vs1 !== rs1 || simm !== rs1 || vd !== rd || vm !== mask_bit) begin
      errors++;
      $display("FAIL fields got vs2=%0d vs1=%0d vd=%0d vm=%b at %0t", vs2, vs1, vd, vm, $time);
    end
  endtask

  task automatic sweep();
    logic [2:0] forms[5];
    logic       exp;
    forms[0] = Fvv;
    forms[1] = Fvx;
    forms[2] = Fvi;
    forms[3] = Fmv;
    forms[4] = Fmx;
    for (int f = 0; f < 5; f++) begin
      for (int c = 0; c < 64; c++) begin
        for (int u = 0; u < 32; u++) begin
          instr = enc(6'(c), 1'b1, 5'd0, 5'(u), forms[f], 5'd3);
          #1;
          exp = ref_valid(forms[f], 6'(c), 5'(u), 5'd0);
          checks++;
          if (valid !== exp) begin
            errors++;
            $display("FAIL sweep f3=%b f6=%b vs1=%0d got=%b exp=%b at %0t", forms[f], 6'(c), u,
                     valid, exp, $time);
          end
        end
      end
    end
  endtask

  task automatic chk_mem(input logic [6:0] top, input logic [4:0] rs2, input logic [2:0] width,
                         input logic store, input logic [5:0] exp);
    logic [5:0] got;
    vec_op_e    exp_op;
    instr = enc_mem(top, rs2, width, store);
    #1;
    exp_op = vec_op_e'(!exp[5] ? VEC_ILLEGAL : (store ? VEC_STORE : VEC_LOAD));
    got = {valid, mem_width, mem_whole, mem_strided, mem_mask};
    if (!exp[5]) got[4:0] = 5'b0;
    checks++;
    if (got !== exp || op !== exp_op || (exp[5] && (!reads_xreg || vd !== 5'd3 ||
        vm !== top[0] || src !== VEC_SRC_NONE))) begin
      errors++;
      $display("FAIL mem top=%b rs2=%b w=%b store=%b got=%b exp=%b at %0t", top, rs2, width,
               store, got, exp, $time);
    end
  endtask

  task automatic sweep_mem();
    for (int s = 0; s < 2; s++)
    for (int t = 0; t < 128; t++)
    for (int r = 0; r < 32; r++)
    for (int w = 0; w < 8; w++)
    chk_mem(7'(t), 5'(r), 3'(w), 1'(s), ref_mem(7'(t), 5'(r), 3'(w), 1'(s)));
  endtask

  task automatic chk_not_vector();
    instr = {25'b0, OpcodeOp};
    #1;
    checks++;
    if (valid !== 1'b0 || src !== VEC_SRC_NONE) begin
      errors++;
      $display("FAIL non vector opcode at %0t", $time);
    end
  endtask

  task automatic verdict();
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask

  initial begin
    $dumpfile("vec_decode_tb.vcd");
    $dumpvars(0, vec_decode_tb);

    // Field extraction
    chk_fields(5'd31, 5'd17, 5'd9, 1'b0);
    chk_fields(5'd0, 5'd0, 5'd0, 1'b1);
    chk_not_vector();

    // Integer arithmetic
    chk_op(6'b000000, Fvv, 5'd1, VEC_ADD, VEC_SRC_VV, VEC_EEW_SAME);
    chk_op(6'b000000, Fvx, 5'd1, VEC_ADD, VEC_SRC_VX, VEC_EEW_SAME);
    chk_op(6'b000000, Fvi, 5'd1, VEC_ADD, VEC_SRC_VI, VEC_EEW_SAME);
    chk_op(6'b000010, Fvv, 5'd1, VEC_SUB, VEC_SRC_VV, VEC_EEW_SAME);
    chk_op(6'b000011, Fvi, 5'd1, VEC_RSUB, VEC_SRC_VI, VEC_EEW_SAME);
    chk_op(6'b001011, Fvv, 5'd1, VEC_XOR, VEC_SRC_VV, VEC_EEW_SAME);
    chk_op(6'b100101, Fvi, 5'd1, VEC_SLL, VEC_SRC_VI, VEC_EEW_SAME);
    chk_op(6'b101001, Fvx, 5'd1, VEC_SRA, VEC_SRC_VX, VEC_EEW_SAME);

    // Form illegal
    chk_illegal(6'b000010, Fvi, 5'd1);
    chk_illegal(6'b000011, Fvv, 5'd1);
    chk_illegal(6'b011111, Fvv, 5'd1);
    chk_illegal(6'b000001, Fvv, 5'd1);
    chk_illegal(6'b100100, Fvv, 5'd1);

    // Shared encodings
    chk_op(6'b001110, Fvv, 5'd1, VEC_RGATHEREI16, VEC_SRC_VV, VEC_EEW_SAME);
    chk_op(6'b001110, Fvx, 5'd1, VEC_SLIDEUP, VEC_SRC_VX, VEC_EEW_SAME);
    chk_op(6'b100111, Fvv, 5'd1, VEC_SMUL, VEC_SRC_VV, VEC_EEW_SAME);
    chk_op(6'b100111, Fvi, 5'd1, VEC_MVNRR, VEC_SRC_VI, VEC_EEW_SAME);

    // Narrowing
    chk_op(6'b101100, Fvv, 5'd1, VEC_NSRL, VEC_SRC_VV, VEC_EEW_NARROW);
    chk_op(6'b101111, Fvi, 5'd1, VEC_NCLIP, VEC_SRC_VI, VEC_EEW_NARROW);

    // Widening
    chk_op(6'b110001, Fmv, 5'd1, VEC_WADD, VEC_SRC_VV, VEC_EEW_WIDEN);
    chk_op(6'b110101, Fmx, 5'd1, VEC_WADD, VEC_SRC_VX, VEC_EEW_WIDEN_W);
    chk_op(6'b111011, Fmv, 5'd1, VEC_WMUL, VEC_SRC_VV, VEC_EEW_WIDEN);
    chk_op(6'b110000, Fvv, 5'd1, VEC_WREDSUMU, VEC_SRC_VV, VEC_EEW_WIDEN);

    // Reductions
    chk_op(6'b000000, Fmv, 5'd1, VEC_REDSUM, VEC_SRC_VV, VEC_EEW_SAME);
    chk_op(6'b000111, Fmv, 5'd1, VEC_REDMAX, VEC_SRC_VV, VEC_EEW_SAME);
    chk_illegal(6'b000000, Fmx, 5'd1);

    // Unary spaces
    chk_op(6'b010000, Fmv, 5'b00000, VEC_MV_X_S, VEC_SRC_VV, VEC_EEW_SAME);
    chk_op(6'b010000, Fmv, 5'b10000, VEC_CPOP, VEC_SRC_VV, VEC_EEW_SAME);
    chk_op(6'b010000, Fmv, 5'b10001, VEC_FIRST, VEC_SRC_VV, VEC_EEW_SAME);
    chk_illegal(6'b010000, Fmv, 5'b00001);
    chk_op(6'b010010, Fmv, 5'b00110, VEC_ZEXT2, VEC_SRC_VV, VEC_EEW_SAME);
    chk_op(6'b010100, Fmv, 5'b10000, VEC_IOTA, VEC_SRC_VV, VEC_EEW_SAME);

    // Mask logical
    chk_op(6'b011001, Fmv, 5'd1, VEC_MAND, VEC_SRC_VV, VEC_EEW_SAME);
    chk_op(6'b011111, Fmv, 5'd1, VEC_MXNOR, VEC_SRC_VV, VEC_EEW_SAME);

    // Multiply add
    chk_op(6'b101101, Fmv, 5'd1, VEC_MACC, VEC_SRC_VV, VEC_EEW_SAME);
    chk_op(6'b101111, Fmx, 5'd1, VEC_NMSAC, VEC_SRC_VX, VEC_EEW_SAME);

    // Flag bits
    chk_flags(6'b000000, Fvv, 5'd1, 4'b0000);
    chk_flags(6'b000000, Fvx, 5'd1, 4'b0100);
    chk_flags(6'b011000, Fvv, 5'd1, 4'b0001);
    chk_flags(6'b010001, Fvi, 5'd1, 4'b0001);
    chk_flags(6'b101101, Fmv, 5'd1, 4'b1000);
    chk_flags(6'b101101, Fmx, 5'd1, 4'b1100);
    chk_flags(6'b010000, Fmv, 5'b00000, 4'b0010);
    chk_flags(6'b010000, Fmv, 5'b10000, 4'b0010);
    chk_flags(6'b010000, Fmv, 5'b10001, 4'b0010);
    chk_flags(6'b010000, Fmx, 5'd1, 4'b0000);
    chk_flags(6'b111101, Fmv, 5'd1, 4'b1000);
    chk_flags(6'b011001, Fmv, 5'd1, 4'b0001);

    // Loads and stores
    chk_mem(7'b0000001, 5'b00000, 3'b000, 1'b0, 6'b100000);
    chk_mem(7'b0000000, 5'b00000, 3'b101, 1'b0, 6'b101000);
    chk_mem(7'b0000001, 5'b00000, 3'b110, 1'b1, 6'b110000);
    chk_mem(7'b0000100, 5'd12, 3'b101, 1'b0, 6'b101010);
    chk_mem(7'b0000101, 5'd13, 3'b000, 1'b1, 6'b100010);
    chk_mem(7'b0000001, 5'b01000, 3'b101, 1'b0, 6'b101100);
    chk_mem(7'b0000001, 5'b01000, 3'b000, 1'b1, 6'b100100);
    chk_mem(7'b0000001, 5'b01011, 3'b000, 1'b0, 6'b100001);
    chk_mem(7'b0000001, 5'b01011, 3'b000, 1'b1, 6'b100001);
    chk_mem(7'b0000000, 5'b01011, 3'b000, 1'b0, 6'b000000);
    chk_mem(7'b0000001, 5'b01011, 3'b101, 1'b0, 6'b000000);

    // Memory form illegal
    chk_mem(7'b0000001, 5'b01000, 3'b101, 1'b1, 6'b000000);
    chk_mem(7'b0000000, 5'b01000, 3'b000, 1'b0, 6'b000000);
    chk_mem(7'b0000001, 5'b00000, 3'b111, 1'b0, 6'b000000);
    chk_mem(7'b0000001, 5'b10000, 3'b000, 1'b0, 6'b000000);
    chk_mem(7'b0010001, 5'b00000, 3'b000, 1'b0, 6'b000000);
    chk_mem(7'b0001001, 5'b00000, 3'b000, 1'b0, 6'b000000);
    chk_mem(7'b0000111, 5'd12, 3'b000, 1'b0, 6'b000000);

    // Exhaustive legality
    sweep();
    sweep_mem();

    verdict();
  end

endmodule

`default_nettype wire
