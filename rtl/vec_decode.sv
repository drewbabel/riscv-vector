`default_nettype none

module vec_decode
  import vec_pkg::*;
  import opcode_pkg::*;
(
    input  logic     [31:0] instr,
    output logic            valid,
    output vec_op_e         op,
    output vec_src_e        src,
    output vec_eew_e        eew,
    output logic            vm,
    output logic     [ 4:0] vs1,
    output logic     [ 4:0] vs2,
    output logic     [ 4:0] vd,
    output logic     [ 4:0] simm,
    output logic            reads_vd,
    output logic            reads_xreg,
    output logic            writes_xreg,
    output logic            writes_mask,

    // Memory forms
    output logic [1:0] mem_width,
    output logic       mem_whole,
    output logic       mem_mask,
    output logic       mem_strided
);

  localparam logic [2:0] Funct3Opivv = 3'b000;
  localparam logic [2:0] Funct3Opivx = 3'b100;
  localparam logic [2:0] Funct3Opivi = 3'b011;
  localparam logic [2:0] Funct3Opmvv = 3'b010;
  localparam logic [2:0] Funct3Opmvx = 3'b110;

  // Instruction fields
  logic [5:0] funct6;
  logic [2:0] funct3;
  logic is_opv;
  logic is_v, is_x, is_i, is_mv, is_mx;
  logic    is_load;
  logic    is_store;
  logic    width_ok;
  vec_op_e mem_op;

  assign funct6 = instr[31:26];
  assign funct3 = instr[14:12];
  assign vm = instr[25];
  assign vs2 = instr[24:20];
  assign vs1 = instr[19:15];
  assign simm = instr[19:15];
  assign vd = instr[11:7];

  // Instruction forms
  assign is_opv = (instr[6:0] == OpcodeOpV);
  assign is_v = (instr[6:0] == OpcodeOpV) && (funct3 == Funct3Opivv);
  assign is_x = (instr[6:0] == OpcodeOpV) && (funct3 == Funct3Opivx);
  assign is_i = (instr[6:0] == OpcodeOpV) && (funct3 == Funct3Opivi);
  assign is_mv = (instr[6:0] == OpcodeOpV) && (funct3 == Funct3Opmvv);
  assign is_mx = (instr[6:0] == OpcodeOpV) && (funct3 == Funct3Opmvx);
  assign is_load = (instr[6:0] == OpcodeLoadFp);
  assign is_store = (instr[6:0] == OpcodeStoreFp);

  always_comb begin
    op = VEC_ILLEGAL;
    eew = VEC_EEW_SAME;
    reads_vd = 1'b0;
    writes_xreg = 1'b0;
    writes_mask = 1'b0;
    mem_width = 2'd0;
    mem_whole = 1'b0;
    mem_mask = 1'b0;
    mem_strided = 1'b0;
    width_ok = 1'b0;
    mem_op = VEC_LOAD;

    // Loads and stores
    if ((is_load || is_store) && (instr[31:28] == 4'b0000)) begin
      case (funct3)
        3'b000:  width_ok = 1'b1;
        3'b101:  width_ok = 1'b1;
        3'b110:  width_ok = 1'b1;
        default: width_ok = 1'b0;
      endcase
      mem_width = (funct3 == 3'b110) ? 2'd2 : ((funct3 == 3'b101) ? 2'd1 : 2'd0);
      mem_op = vec_pkg::vec_op_e'(is_load ? VEC_LOAD : VEC_STORE);
      if (width_ok) begin
        case (instr[27:26])
          2'b00: begin
            if (vs2 == 5'b00000) op = mem_op;
            if ((vs2 == 5'b01000) && vm && (is_load || funct3 == 3'b000)) begin
              op = mem_op;
              mem_whole = 1'b1;
            end
            if ((vs2 == 5'b01011) && vm && (funct3 == 3'b000)) begin
              op = mem_op;
              mem_mask = 1'b1;
            end
          end
          2'b10: begin
            op = mem_op;
            mem_strided = 1'b1;
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
        6'b010111: op = VEC_MERGE;
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
        6'b100111: op = vec_pkg::vec_op_e'(is_i ? VEC_MVNRR : VEC_SMUL);
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
          end else if (vs2 == 5'b00000) begin
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
  end

  // Source form
  always_comb begin
    if (!is_opv) begin
      src = VEC_SRC_NONE;
    end else begin
      case (funct3)
        Funct3Opivv, Funct3Opmvv: src = VEC_SRC_VV;
        Funct3Opivx, Funct3Opmvx: src = VEC_SRC_VX;
        Funct3Opivi: src = VEC_SRC_VI;
        default: src = VEC_SRC_NONE;
      endcase
    end
  end

  assign reads_xreg = ((src == VEC_SRC_VX) || is_load || is_store) && (op != VEC_ILLEGAL);
  assign valid = (op != VEC_ILLEGAL);

endmodule

`default_nettype wire
