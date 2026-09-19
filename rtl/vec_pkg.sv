`default_nettype none

package vec_pkg;

  // Source operand form
  typedef enum logic [1:0] {
    VEC_SRC_VV,
    VEC_SRC_VX,
    VEC_SRC_VI,
    VEC_SRC_NONE
  } vec_src_e;

  // Operand width shape
  typedef enum logic [1:0] {
    VEC_EEW_SAME,
    VEC_EEW_WIDEN,
    VEC_EEW_WIDEN_W,
    VEC_EEW_NARROW
  } vec_eew_e;

  // Width against SEW
  typedef enum logic [1:0] {
    VEC_REL_SAME,
    VEC_REL_WIDE,
    VEC_REL_HALF,
    VEC_REL_QUARTER
  } vec_rel_e;

  typedef enum logic [6:0] {
    VEC_ADD,
    VEC_SUB,
    VEC_RSUB,
    VEC_MINU,
    VEC_MIN,
    VEC_MAXU,
    VEC_MAX,
    VEC_AND,
    VEC_OR,
    VEC_XOR,
    VEC_RGATHER,
    VEC_RGATHEREI16,
    VEC_SLIDEUP,
    VEC_SLIDEDOWN,
    VEC_ADC,
    VEC_MADC,
    VEC_SBC,
    VEC_MSBC,
    VEC_MERGE,
    VEC_MSEQ,
    VEC_MSNE,
    VEC_MSLTU,
    VEC_MSLT,
    VEC_MSLEU,
    VEC_MSLE,
    VEC_MSGTU,
    VEC_MSGT,
    VEC_SADDU,
    VEC_SADD,
    VEC_SSUBU,
    VEC_SSUB,
    VEC_SLL,
    VEC_SMUL,
    VEC_MVNRR,
    VEC_SRL,
    VEC_SRA,
    VEC_SSRL,
    VEC_SSRA,
    VEC_NSRL,
    VEC_NSRA,
    VEC_NCLIPU,
    VEC_NCLIP,
    VEC_WREDSUMU,
    VEC_WREDSUM,
    VEC_REDSUM,
    VEC_REDAND,
    VEC_REDOR,
    VEC_REDXOR,
    VEC_REDMINU,
    VEC_REDMIN,
    VEC_REDMAXU,
    VEC_REDMAX,
    VEC_AADDU,
    VEC_AADD,
    VEC_ASUBU,
    VEC_ASUB,
    VEC_SLIDE1UP,
    VEC_SLIDE1DOWN,
    VEC_MV_X_S,
    VEC_CPOP,
    VEC_FIRST,
    VEC_MV_S_X,
    VEC_ZEXT2,
    VEC_ZEXT4,
    VEC_ZEXT8,
    VEC_SEXT2,
    VEC_SEXT4,
    VEC_SEXT8,
    VEC_MSBF,
    VEC_MSOF,
    VEC_MSIF,
    VEC_IOTA,
    VEC_ID,
    VEC_COMPRESS,
    VEC_MANDN,
    VEC_MAND,
    VEC_MOR,
    VEC_MXOR,
    VEC_MORN,
    VEC_MNAND,
    VEC_MNOR,
    VEC_MXNOR,
    VEC_DIVU,
    VEC_DIV,
    VEC_REMU,
    VEC_REM,
    VEC_MULHU,
    VEC_MUL,
    VEC_MULHSU,
    VEC_MULH,
    VEC_MADD,
    VEC_NMSUB,
    VEC_MACC,
    VEC_NMSAC,
    VEC_WADDU,
    VEC_WADD,
    VEC_WSUBU,
    VEC_WSUB,
    VEC_WMULU,
    VEC_WMULSU,
    VEC_WMUL,
    VEC_WMACCU,
    VEC_WMACC,
    VEC_WMACCUS,
    VEC_WMACCSU,
    VEC_LOAD,
    VEC_STORE,
    VEC_ILLEGAL
  } vec_op_e;

  // Datapath class
  typedef enum logic [2:0] {
    VEC_CLS_NONE,
    VEC_CLS_ALU,
    VEC_CLS_MIXED,
    VEC_CLS_MUL,
    VEC_CLS_RED,
    VEC_CLS_MEM,
    VEC_CLS_XS,
    VEC_CLS_SX
  } vec_cls_e;

  typedef struct packed {
    vec_rel_e d;
    vec_rel_e s1;
    vec_rel_e s2;
    logic     mul_rate;
    logic     single_write;
    logic     widen;
  } vec_geom_t;

  function automatic logic [2:0] vec_rel_log2(input vec_rel_e rel, input logic [2:0] base);
    case (rel)
      VEC_REL_WIDE:    vec_rel_log2 = base + 3'd1;
      VEC_REL_HALF:    vec_rel_log2 = base - 3'd1;
      VEC_REL_QUARTER: vec_rel_log2 = base - 3'd2;
      default:         vec_rel_log2 = base;
    endcase
  endfunction

  function automatic logic [4:0] vec_rel_regs(input vec_rel_e rel, input logic [3:0] base);
    case (rel)
      VEC_REL_WIDE:    vec_rel_regs = 5'(base) << 1;
      VEC_REL_HALF:    vec_rel_regs = (base > 4'd1) ? 5'(base >> 1) : 5'd1;
      VEC_REL_QUARTER: vec_rel_regs = (base > 4'd3) ? 5'(base >> 2) : 5'd1;
      default:         vec_rel_regs = 5'(base);
    endcase
  endfunction

  function automatic vec_cls_e vec_class(input vec_op_e op);
    case (op)
      VEC_ADD, VEC_SUB, VEC_RSUB, VEC_MINU, VEC_MIN, VEC_MAXU, VEC_MAX, VEC_AND, VEC_OR, VEC_XOR,
      VEC_ADC, VEC_SBC, VEC_MERGE, VEC_SLL, VEC_SRL, VEC_SRA:
      vec_class = VEC_CLS_ALU;
      VEC_WADDU, VEC_WADD, VEC_WSUBU, VEC_WSUB, VEC_NSRL, VEC_NSRA, VEC_ZEXT2, VEC_ZEXT4,
      VEC_SEXT2, VEC_SEXT4:
      vec_class = VEC_CLS_MIXED;
      VEC_MULHU, VEC_MUL, VEC_MULHSU, VEC_MULH, VEC_MADD, VEC_NMSUB, VEC_MACC, VEC_NMSAC,
      VEC_WMULU, VEC_WMULSU, VEC_WMUL, VEC_WMACCU, VEC_WMACC, VEC_WMACCUS, VEC_WMACCSU:
      vec_class = VEC_CLS_MUL;
      VEC_REDSUM, VEC_REDAND, VEC_REDOR, VEC_REDXOR, VEC_REDMINU, VEC_REDMIN, VEC_REDMAXU,
      VEC_REDMAX, VEC_WREDSUMU, VEC_WREDSUM:
      vec_class = VEC_CLS_RED;
      VEC_LOAD, VEC_STORE: vec_class = VEC_CLS_MEM;
      VEC_MV_X_S:          vec_class = VEC_CLS_XS;
      VEC_MV_S_X:          vec_class = VEC_CLS_SX;
      default:             vec_class = VEC_CLS_NONE;
    endcase
  endfunction

  function automatic vec_geom_t vec_geom(input vec_op_e op, input vec_eew_e eew);
    vec_geom.d = VEC_REL_SAME;
    vec_geom.s1 = VEC_REL_SAME;
    vec_geom.s2 = VEC_REL_SAME;
    vec_geom.mul_rate = 1'b0;
    vec_geom.single_write = 1'b0;
    vec_geom.widen = 1'b0;
    case (vec_class(op))
      VEC_CLS_MIXED: begin
        case (eew)
          VEC_EEW_WIDEN: vec_geom.d = VEC_REL_WIDE;
          VEC_EEW_WIDEN_W: begin
            vec_geom.d  = VEC_REL_WIDE;
            vec_geom.s2 = VEC_REL_WIDE;
          end
          VEC_EEW_NARROW: vec_geom.s2 = VEC_REL_WIDE;
          default: begin
            if ((op == VEC_ZEXT4) || (op == VEC_SEXT4)) vec_geom.s2 = VEC_REL_QUARTER;
            else vec_geom.s2 = VEC_REL_HALF;
          end
        endcase
      end
      VEC_CLS_MUL: begin
        vec_geom.mul_rate = 1'b1;
        if (eew == VEC_EEW_WIDEN) begin
          vec_geom.d     = VEC_REL_WIDE;
          vec_geom.widen = 1'b1;
        end
      end
      VEC_CLS_RED: begin
        vec_geom.single_write = 1'b1;
        if (eew == VEC_EEW_WIDEN) begin
          vec_geom.d     = VEC_REL_WIDE;
          vec_geom.widen = 1'b1;
        end
      end
      VEC_CLS_XS, VEC_CLS_SX: vec_geom.single_write = 1'b1;
      default: ;
    endcase
  endfunction

endpackage

`default_nettype wire
