`default_nettype none

module vec_decode
  import vec_pkg::*;
  import opcode_pkg::*;
(
    input  wire      [arch_pkg::ILEN-1:0] instr,
    output logic                          valid,
    output vec_op_e                       op,
    output vec_src_e                      src,
    output vec_eew_e                      eew,
    output logic                          vm,
    output logic     [               4:0] vs1,
    output logic     [               4:0] vs2,
    output logic     [               4:0] vd,
    output logic     [               4:0] simm,
    output logic                          reads_vd,
    output logic                          reads_xreg,
    output logic                          writes_xreg,
    output logic                          writes_mask,

    // Float forms
    output vec_fop_e fop,
    output logic     reads_freg,
    output logic     writes_freg,

    // Memory forms
    output logic [1:0] mem_width,
    output logic       mem_whole,
    output logic [2:0] mem_nf,
    output logic       mem_mask,
    output logic       mem_strided
);

  localparam logic [2:0] Funct3Opivv = 3'b000;
  localparam logic [2:0] Funct3Opivx = 3'b100;
  localparam logic [2:0] Funct3Opivi = 3'b011;
  localparam logic [2:0] Funct3Opmvv = 3'b010;
  localparam logic [2:0] Funct3Opmvx = 3'b110;
  localparam logic [2:0] Funct3Opfvv = 3'b001;
  localparam logic [2:0] Funct3Opfvf = 3'b101;
  localparam logic [2:0] Funct3Ve8 = 3'b000;
  localparam logic [2:0] Funct3Ve16 = 3'b101;
  localparam logic [2:0] Funct3Ve32 = 3'b110;
  localparam logic [1:0] MopUnit = 2'b00;
  localparam logic [1:0] MopStrided = 2'b10;
  localparam logic [4:0] LumopWhole = 5'b01000;
  localparam logic [4:0] LumopMask = 5'b01011;

  // Instruction fields
  logic [5:0] funct6;
  logic [2:0] funct3;
  logic [2:0] nf;
  logic is_opv;
  logic is_v, is_x, is_i, is_mv, is_mx;
  logic is_fv, is_ff;
  logic    is_load;
  logic    is_store;
  logic    width_ok;
  logic    nf_ok;
  logic    nf_zero;
  logic    vs1_zero;
  logic    vs2_zero;
  vec_op_e mem_op;

  assign funct6 = instr[31:26];
  assign funct3 = instr[14:12];
  assign nf = instr[31:29];
  assign vm = instr[25];
  assign vs2 = instr[24:20];
  assign vs1 = instr[19:15];
  assign simm = instr[19:15];
  assign vd = instr[11:7];

  // Instruction forms
  assign is_opv = (instr[6:0] == OpcodeOpV);
  assign is_v = is_opv && (funct3 == Funct3Opivv);
  assign is_x = is_opv && (funct3 == Funct3Opivx);
  assign is_i = is_opv && (funct3 == Funct3Opivi);
  assign is_mv = is_opv && (funct3 == Funct3Opmvv);
  assign is_mx = is_opv && (funct3 == Funct3Opmvx);
  assign is_fv = is_opv && (funct3 == Funct3Opfvv);
  assign is_ff = is_opv && (funct3 == Funct3Opfvf);
  assign is_load = (instr[6:0] == OpcodeLoadFp);
  assign is_store = (instr[6:0] == OpcodeStoreFp);

  // Whole register counts
  assign nf_zero = (nf == 3'd0);
  assign nf_ok = nf_zero || (nf == 3'd1) || (nf == 3'd3) || (nf == 3'd7);
  assign vs1_zero = (vs1 == '0);
  assign vs2_zero = (vs2 == '0);

  always_comb begin
    op = VEC_ILLEGAL;
    eew = VEC_EEW_SAME;
    reads_vd = 1'b0;
    writes_xreg = 1'b0;
    writes_mask = 1'b0;
    writes_freg = 1'b0;
    fop = VEC_FADD;
    mem_width = 2'd0;
    mem_whole = 1'b0;
    mem_nf = 3'd0;
    mem_mask = 1'b0;
    mem_strided = 1'b0;
    width_ok = 1'b0;
    mem_op = VEC_LOAD;

    // Loads and stores
    if ((is_load || is_store) && !instr[28]) begin
      case (funct3)
        Funct3Ve8: width_ok = 1'b1;
        Funct3Ve16: begin
          width_ok  = 1'b1;
          mem_width = 2'd1;
        end
        Funct3Ve32: begin
          width_ok  = 1'b1;
          mem_width = 2'd2;
        end
        default:   width_ok = 1'b0;
      endcase
      mem_op = vec_pkg::vec_op_e'(is_load ? VEC_LOAD : VEC_STORE);
      if (width_ok) begin
        case (instr[27:26])
          MopUnit: begin
            if (vs2_zero && nf_zero) op = mem_op;
            if ((vs2 == LumopWhole) && vm && nf_ok && (is_load || funct3 == Funct3Ve8)) begin
              op = mem_op;
              mem_whole = 1'b1;
              mem_nf = nf;
            end
            if ((vs2 == LumopMask) && vm && (funct3 == Funct3Ve8) && nf_zero) begin
              op = mem_op;
              mem_mask = 1'b1;
            end
          end
          MopStrided: begin
            if (nf_zero) begin
              op = mem_op;
              mem_strided = 1'b1;
            end
          end
          default: ;
        endcase
      end
    end

    // Integer arithmetic
    if (is_v || is_x || is_i) begin
      case (funct6)
        6'b000000: op = VEC_ADD;
        6'b000010: if (is_v || is_x) op = VEC_SUB;
        6'b000011: if (is_x || is_i) op = VEC_RSUB;
        6'b000100: if (is_v || is_x) op = VEC_MINU;
        6'b000101: if (is_v || is_x) op = VEC_MIN;
        6'b000110: if (is_v || is_x) op = VEC_MAXU;
        6'b000111: if (is_v || is_x) op = VEC_MAX;
        6'b001001: op = VEC_AND;
        6'b001010: op = VEC_OR;
        6'b001011: op = VEC_XOR;
        6'b001100: op = VEC_RGATHER;
        6'b001110: op = vec_pkg::vec_op_e'(is_v ? VEC_RGATHEREI16 : VEC_SLIDEUP);
        6'b001111: if (is_x || is_i) op = VEC_SLIDEDOWN;
        6'b010000: op = VEC_ADC;
        6'b010001: begin
          op = VEC_MADC;
          writes_mask = 1'b1;
        end
        6'b010010: if (is_v || is_x) op = VEC_SBC;
        6'b010011:
        if (is_v || is_x) begin
          op = VEC_MSBC;
          writes_mask = 1'b1;
        end
        6'b010111: if (!vm || vs2_zero) op = VEC_MERGE;
        6'b011000: begin
          op = VEC_MSEQ;
          writes_mask = 1'b1;
        end
        6'b011001: begin
          op = VEC_MSNE;
          writes_mask = 1'b1;
        end
        6'b011010:
        if (is_v || is_x) begin
          op = VEC_MSLTU;
          writes_mask = 1'b1;
        end
        6'b011011:
        if (is_v || is_x) begin
          op = VEC_MSLT;
          writes_mask = 1'b1;
        end
        6'b011100: begin
          op = VEC_MSLEU;
          writes_mask = 1'b1;
        end
        6'b011101: begin
          op = VEC_MSLE;
          writes_mask = 1'b1;
        end
        6'b011110:
        if (is_x || is_i) begin
          op = VEC_MSGTU;
          writes_mask = 1'b1;
        end
        6'b011111:
        if (is_x || is_i) begin
          op = VEC_MSGT;
          writes_mask = 1'b1;
        end
        6'b100000: op = VEC_SADDU;
        6'b100001: op = VEC_SADD;
        6'b100010: if (is_v || is_x) op = VEC_SSUBU;
        6'b100011: if (is_v || is_x) op = VEC_SSUB;
        6'b100101: op = VEC_SLL;
        6'b100111: begin
          if (!is_i) op = VEC_SMUL;
          else if (vm && (simm == 5'd0 || simm == 5'd1 || simm == 5'd3 || simm == 5'd7))
            op = VEC_MVNRR;
        end
        6'b101000: op = VEC_SRL;
        6'b101001: op = VEC_SRA;
        6'b101010: op = VEC_SSRL;
        6'b101011: op = VEC_SSRA;
        6'b101100: begin
          op  = VEC_NSRL;
          eew = VEC_EEW_NARROW;
        end
        6'b101101: begin
          op  = VEC_NSRA;
          eew = VEC_EEW_NARROW;
        end
        6'b101110: begin
          op  = VEC_NCLIPU;
          eew = VEC_EEW_NARROW;
        end
        6'b101111: begin
          op  = VEC_NCLIP;
          eew = VEC_EEW_NARROW;
        end
        6'b110000:
        if (is_v) begin
          op  = VEC_WREDSUMU;
          eew = VEC_EEW_WIDEN;
        end
        6'b110001:
        if (is_v) begin
          op  = VEC_WREDSUM;
          eew = VEC_EEW_WIDEN;
        end
        default:   ;
      endcase
    end

    // Mask and multiply
    if (is_mv || is_mx) begin
      case (funct6)
        6'b000000: if (is_mv) op = VEC_REDSUM;
        6'b000001: if (is_mv) op = VEC_REDAND;
        6'b000010: if (is_mv) op = VEC_REDOR;
        6'b000011: if (is_mv) op = VEC_REDXOR;
        6'b000100: if (is_mv) op = VEC_REDMINU;
        6'b000101: if (is_mv) op = VEC_REDMIN;
        6'b000110: if (is_mv) op = VEC_REDMAXU;
        6'b000111: if (is_mv) op = VEC_REDMAX;
        6'b001000: op = VEC_AADDU;
        6'b001001: op = VEC_AADD;
        6'b001010: op = VEC_ASUBU;
        6'b001011: op = VEC_ASUB;
        6'b001110: if (is_mx) op = VEC_SLIDE1UP;
        6'b001111: if (is_mx) op = VEC_SLIDE1DOWN;

        // Unary spaces
        6'b010000: begin
          if (is_mv) begin
            case (vs1)
              5'b00000: begin
                op = VEC_MV_X_S;
                writes_xreg = 1'b1;
              end
              5'b10000: begin
                op = VEC_CPOP;
                writes_xreg = 1'b1;
              end
              5'b10001: begin
                op = VEC_FIRST;
                writes_xreg = 1'b1;
              end
              default: ;
            endcase
          end else if (vs2_zero) begin
            op = VEC_MV_S_X;
          end
        end
        6'b010010:
        if (is_mv) begin
          case (vs1)
            5'b00010: op = VEC_ZEXT8;
            5'b00011: op = VEC_SEXT8;
            5'b00100: op = VEC_ZEXT4;
            5'b00101: op = VEC_SEXT4;
            5'b00110: op = VEC_ZEXT2;
            5'b00111: op = VEC_SEXT2;
            default:  ;
          endcase
        end
        6'b010100:
        if (is_mv) begin
          case (vs1)
            5'b00001: begin
              op = VEC_MSBF;
              writes_mask = 1'b1;
            end
            5'b00010: begin
              op = VEC_MSOF;
              writes_mask = 1'b1;
            end
            5'b00011: begin
              op = VEC_MSIF;
              writes_mask = 1'b1;
            end
            5'b10000: op = VEC_IOTA;
            5'b10001: op = VEC_ID;
            default:  ;
          endcase
        end
        6'b010111: if (is_mv) op = VEC_COMPRESS;

        // Mask logical
        6'b011000:
        if (is_mv) begin
          op = VEC_MANDN;
          writes_mask = 1'b1;
        end
        6'b011001:
        if (is_mv) begin
          op = VEC_MAND;
          writes_mask = 1'b1;
        end
        6'b011010:
        if (is_mv) begin
          op = VEC_MOR;
          writes_mask = 1'b1;
        end
        6'b011011:
        if (is_mv) begin
          op = VEC_MXOR;
          writes_mask = 1'b1;
        end
        6'b011100:
        if (is_mv) begin
          op = VEC_MORN;
          writes_mask = 1'b1;
        end
        6'b011101:
        if (is_mv) begin
          op = VEC_MNAND;
          writes_mask = 1'b1;
        end
        6'b011110:
        if (is_mv) begin
          op = VEC_MNOR;
          writes_mask = 1'b1;
        end
        6'b011111:
        if (is_mv) begin
          op = VEC_MXNOR;
          writes_mask = 1'b1;
        end

        // Divide and multiply
        6'b100000: op = VEC_DIVU;
        6'b100001: op = VEC_DIV;
        6'b100010: op = VEC_REMU;
        6'b100011: op = VEC_REM;
        6'b100100: op = VEC_MULHU;
        6'b100101: op = VEC_MUL;
        6'b100110: op = VEC_MULHSU;
        6'b100111: op = VEC_MULH;
        6'b101001: begin
          op = VEC_MADD;
          reads_vd = 1'b1;
        end
        6'b101011: begin
          op = VEC_NMSUB;
          reads_vd = 1'b1;
        end
        6'b101101: begin
          op = VEC_MACC;
          reads_vd = 1'b1;
        end
        6'b101111: begin
          op = VEC_NMSAC;
          reads_vd = 1'b1;
        end

        // Widening
        6'b110000: begin
          op  = VEC_WADDU;
          eew = VEC_EEW_WIDEN;
        end
        6'b110001: begin
          op  = VEC_WADD;
          eew = VEC_EEW_WIDEN;
        end
        6'b110010: begin
          op  = VEC_WSUBU;
          eew = VEC_EEW_WIDEN;
        end
        6'b110011: begin
          op  = VEC_WSUB;
          eew = VEC_EEW_WIDEN;
        end
        6'b110100: begin
          op  = VEC_WADDU;
          eew = VEC_EEW_WIDEN_W;
        end
        6'b110101: begin
          op  = VEC_WADD;
          eew = VEC_EEW_WIDEN_W;
        end
        6'b110110: begin
          op  = VEC_WSUBU;
          eew = VEC_EEW_WIDEN_W;
        end
        6'b110111: begin
          op  = VEC_WSUB;
          eew = VEC_EEW_WIDEN_W;
        end
        6'b111000: begin
          op  = VEC_WMULU;
          eew = VEC_EEW_WIDEN;
        end
        6'b111010: begin
          op  = VEC_WMULSU;
          eew = VEC_EEW_WIDEN;
        end
        6'b111011: begin
          op  = VEC_WMUL;
          eew = VEC_EEW_WIDEN;
        end
        6'b111100: begin
          op       = VEC_WMACCU;
          eew      = VEC_EEW_WIDEN;
          reads_vd = 1'b1;
        end
        6'b111101: begin
          op       = VEC_WMACC;
          eew      = VEC_EEW_WIDEN;
          reads_vd = 1'b1;
        end
        6'b111110:
        if (is_mx) begin
          op       = VEC_WMACCUS;
          eew      = VEC_EEW_WIDEN;
          reads_vd = 1'b1;
        end
        6'b111111: begin
          op       = VEC_WMACCSU;
          eew      = VEC_EEW_WIDEN;
          reads_vd = 1'b1;
        end
        default: ;
      endcase
    end

    // Float arithmetic
    if (is_fv || is_ff) begin
      case (funct6)
        6'b000000: begin
          op  = VEC_FARITH;
          fop = VEC_FADD;
        end
        6'b000010: begin
          op  = VEC_FARITH;
          fop = VEC_FSUB;
        end
        6'b000100: begin
          op  = VEC_FARITH;
          fop = VEC_FMIN;
        end
        6'b000110: begin
          op  = VEC_FARITH;
          fop = VEC_FMAX;
        end

        // Float reductions
        6'b000001:
        if (is_fv) begin
          op  = VEC_FRED;
          fop = VEC_FREDUSUM;
        end
        6'b000011:
        if (is_fv) begin
          op  = VEC_FRED;
          fop = VEC_FREDOSUM;
        end
        6'b000101:
        if (is_fv) begin
          op  = VEC_FRED;
          fop = VEC_FMIN;
        end
        6'b000111:
        if (is_fv) begin
          op  = VEC_FRED;
          fop = VEC_FMAX;
        end
        6'b001000: begin
          op  = VEC_FARITH;
          fop = VEC_FSGNJ;
        end
        6'b001001: begin
          op  = VEC_FARITH;
          fop = VEC_FSGNJN;
        end
        6'b001010: begin
          op  = VEC_FARITH;
          fop = VEC_FSGNJX;
        end
        6'b100100: begin
          op  = VEC_FARITH;
          fop = VEC_FMUL;
        end
        6'b100000: begin
          op  = VEC_FARITH;
          fop = VEC_FDIV;
        end
        6'b100001:
        if (is_ff) begin
          op  = VEC_FARITH;
          fop = VEC_FRDIV;
        end

        // Float conversions
        6'b010010:
        if (is_fv) begin
          case (vs1)
            5'b00000: begin
              op  = VEC_FARITH;
              fop = VEC_FCVT_XU_F;
            end
            5'b00001: begin
              op  = VEC_FARITH;
              fop = VEC_FCVT_X_F;
            end
            5'b00010: begin
              op  = VEC_FARITH;
              fop = VEC_FCVT_F_XU;
            end
            5'b00011: begin
              op  = VEC_FARITH;
              fop = VEC_FCVT_F_X;
            end
            5'b00110: begin
              op  = VEC_FARITH;
              fop = VEC_FCVT_RTZ_XU_F;
            end
            5'b00111: begin
              op  = VEC_FARITH;
              fop = VEC_FCVT_RTZ_X_F;
            end
            5'b01010: begin
              op  = VEC_FARITH;
              fop = VEC_FCVT_F_XU;
              eew = VEC_EEW_WIDEN;
            end
            5'b01011: begin
              op  = VEC_FARITH;
              fop = VEC_FCVT_F_X;
              eew = VEC_EEW_WIDEN;
            end
            5'b10000: begin
              op  = VEC_FARITH;
              fop = VEC_FCVT_XU_F;
              eew = VEC_EEW_NARROW;
            end
            5'b10001: begin
              op  = VEC_FARITH;
              fop = VEC_FCVT_X_F;
              eew = VEC_EEW_NARROW;
            end
            5'b10110: begin
              op  = VEC_FARITH;
              fop = VEC_FCVT_RTZ_XU_F;
              eew = VEC_EEW_NARROW;
            end
            5'b10111: begin
              op  = VEC_FARITH;
              fop = VEC_FCVT_RTZ_X_F;
              eew = VEC_EEW_NARROW;
            end
            default: ;
          endcase
        end

        // Float unary
        6'b010011:
        if (is_fv) begin
          case (vs1)
            5'b00000: begin
              op  = VEC_FARITH;
              fop = VEC_FSQRT;
            end
            5'b00100: begin
              op  = VEC_FARITH;
              fop = VEC_FRSQRT7;
            end
            5'b00101: begin
              op  = VEC_FARITH;
              fop = VEC_FREC7;
            end
            5'b10000: begin
              op  = VEC_FARITH;
              fop = VEC_FCLASS;
            end
            default: ;
          endcase
        end
        6'b100111:
        if (is_ff) begin
          op  = VEC_FARITH;
          fop = VEC_FRSUB;
        end

        // Fused multiply add
        6'b101000: begin
          op       = VEC_FARITH;
          fop      = VEC_FMADD;
          reads_vd = 1'b1;
        end
        6'b101001: begin
          op       = VEC_FARITH;
          fop      = VEC_FNMADD;
          reads_vd = 1'b1;
        end
        6'b101010: begin
          op       = VEC_FARITH;
          fop      = VEC_FMSUB;
          reads_vd = 1'b1;
        end
        6'b101011: begin
          op       = VEC_FARITH;
          fop      = VEC_FNMSUB;
          reads_vd = 1'b1;
        end
        6'b101100: begin
          op       = VEC_FARITH;
          fop      = VEC_FMACC;
          reads_vd = 1'b1;
        end
        6'b101101: begin
          op       = VEC_FARITH;
          fop      = VEC_FNMACC;
          reads_vd = 1'b1;
        end
        6'b101110: begin
          op       = VEC_FARITH;
          fop      = VEC_FMSAC;
          reads_vd = 1'b1;
        end
        6'b101111: begin
          op       = VEC_FARITH;
          fop      = VEC_FNMSAC;
          reads_vd = 1'b1;
        end

        // Float compares
        6'b011000: begin
          op          = VEC_FCMP;
          fop         = VEC_MFEQ;
          writes_mask = 1'b1;
        end
        6'b011001: begin
          op          = VEC_FCMP;
          fop         = VEC_MFLE;
          writes_mask = 1'b1;
        end
        6'b011011: begin
          op          = VEC_FCMP;
          fop         = VEC_MFLT;
          writes_mask = 1'b1;
        end
        6'b011100: begin
          op          = VEC_FCMP;
          fop         = VEC_MFNE;
          writes_mask = 1'b1;
        end
        6'b011101:
        if (is_ff) begin
          op          = VEC_FCMP;
          fop         = VEC_MFGT;
          writes_mask = 1'b1;
        end
        6'b011111:
        if (is_ff) begin
          op          = VEC_FCMP;
          fop         = VEC_MFGE;
          writes_mask = 1'b1;
        end

        // Float slides
        6'b001110: if (is_ff) op = VEC_SLIDE1UP;
        6'b001111: if (is_ff) op = VEC_SLIDE1DOWN;

        // Float moves
        6'b010111: if (is_ff && (!vm || vs2_zero)) op = VEC_MERGE;
        6'b010000: begin
          if (is_fv && vs1_zero) begin
            op          = VEC_MV_X_S;
            writes_freg = 1'b1;
          end
          if (is_ff && vs2_zero) op = VEC_MV_S_X;
        end
        default:   ;
      endcase
    end
  end

  // Source form
  always_comb begin
    if (!is_opv) begin
      src = VEC_SRC_NONE;
    end else begin
      case (funct3)
        Funct3Opivv, Funct3Opmvv, Funct3Opfvv: src = VEC_SRC_VV;
        Funct3Opivx, Funct3Opmvx, Funct3Opfvf: src = VEC_SRC_VX;
        Funct3Opivi: src = VEC_SRC_VI;
        default: src = VEC_SRC_NONE;
      endcase
    end
  end

  assign valid = (op != VEC_ILLEGAL);
  assign reads_freg = is_ff && valid;
  assign reads_xreg = (((src == VEC_SRC_VX) && !is_ff) || is_load || is_store) && valid;

endmodule

`default_nettype wire
