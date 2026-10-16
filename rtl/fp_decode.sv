`default_nettype none

module fp_decode
  import fp_pkg::*;
  import opcode_pkg::*;
(
    input  wire      [31:0] instr,
    input  wire      [ 2:0] frm,
    output logic            is_fp,
    output logic            illegal,
    output fp_unit_e        unit,
    output logic            frs1_read,
    output logic            frs2_read,
    output logic            frs3_read,
    output logic            frd_write,
    output logic            xrd_write,
    output logic            xrs1_read,
    output logic     [ 2:0] rm,
    output logic            sub,
    output logic            neg_prod,
    output logic            neg_add,
    output logic            to_int,
    output logic            is_unsigned,
    output logic            sqrt,
    output logic     [ 4:0] funct5,
    output logic     [ 2:0] funct3
);

  localparam logic [2:0] RmRmm = 3'b100;
  localparam logic [2:0] RmDyn = 3'b111;

  localparam logic [4:0] Rs2Zero = 5'b00000;
  localparam logic [4:0] Rs2W = 5'b00000;
  localparam logic [4:0] Rs2Wu = 5'b00001;

  localparam logic [2:0] Funct3Fsgnj = 3'b000;
  localparam logic [2:0] Funct3Fsgnjn = 3'b001;
  localparam logic [2:0] Funct3Fsgnjx = 3'b010;
  localparam logic [2:0] Funct3Fmin = 3'b000;
  localparam logic [2:0] Funct3Fmax = 3'b001;
  localparam logic [2:0] Funct3Fle = 3'b000;
  localparam logic [2:0] Funct3Flt = 3'b001;
  localparam logic [2:0] Funct3Feq = 3'b010;
  localparam logic [2:0] Funct3Fmv = 3'b000;
  localparam logic [2:0] Funct3Fclass = 3'b001;

  // Instruction fields
  logic [6:0] opcode;
  logic [1:0] fmt;
  logic [4:0] rs2;
  logic [9:0] unused_regs;

  logic [2:0] rm_eff;
  logic       rm_ok;
  logic       legal;

  assign opcode = instr[6:0];
  assign funct5 = instr[31:27];
  assign fmt = instr[26:25];
  assign rs2 = instr[24:20];
  assign funct3 = instr[14:12];
  assign unused_regs = {instr[19:15], instr[11:7]};

  assign rm_eff = (funct3 == RmDyn) ? frm : funct3;
  assign rm_ok = (rm_eff <= RmRmm);

  assign illegal = is_fp && !legal;

  always_comb begin
    is_fp       = 1'b0;
    legal       = 1'b0;
    unit        = FP_NONE;
    frs1_read   = 1'b0;
    frs2_read   = 1'b0;
    frs3_read   = 1'b0;
    frd_write   = 1'b0;
    xrd_write   = 1'b0;
    xrs1_read   = 1'b0;
    rm          = 3'b000;
    sub         = 1'b0;
    neg_prod    = 1'b0;
    neg_add     = 1'b0;
    to_int      = 1'b0;
    is_unsigned = 1'b0;
    sqrt        = 1'b0;

    case (opcode)
      OpcodeLoadFp: begin
        if (funct3 == Funct3Flw) begin
          is_fp     = 1'b1;
          legal     = 1'b1;
          unit      = FP_LOAD;
          xrs1_read = 1'b1;
          frd_write = 1'b1;
        end
      end

      OpcodeStoreFp: begin
        if (funct3 == Funct3Flw) begin
          is_fp     = 1'b1;
          legal     = 1'b1;
          unit      = FP_STORE;
          xrs1_read = 1'b1;
          frs2_read = 1'b1;
        end
      end

      OpcodeFmadd, OpcodeFmsub, OpcodeFnmsub, OpcodeFnmadd: begin
        is_fp = 1'b1;
        if ((fmt == FmtS) && rm_ok) begin
          legal     = 1'b1;
          unit      = FP_FMA;
          frs1_read = 1'b1;
          frs2_read = 1'b1;
          frs3_read = 1'b1;
          frd_write = 1'b1;
          rm        = rm_eff;
          neg_prod  = (opcode == OpcodeFnmsub) || (opcode == OpcodeFnmadd);
          neg_add   = (opcode == OpcodeFmsub) || (opcode == OpcodeFnmadd);
        end
      end

      OpcodeOpFp: begin
        is_fp = 1'b1;
        if (fmt == FmtS) begin
          case (funct5)
            Funct5Fadd, Funct5Fsub: begin
              if (rm_ok) begin
                legal     = 1'b1;
                unit      = FP_ADD;
                frs1_read = 1'b1;
                frs2_read = 1'b1;
                frd_write = 1'b1;
                rm        = rm_eff;
                sub       = (funct5 == Funct5Fsub);
              end
            end

            Funct5Fmul: begin
              if (rm_ok) begin
                legal     = 1'b1;
                unit      = FP_MUL;
                frs1_read = 1'b1;
                frs2_read = 1'b1;
                frd_write = 1'b1;
                rm        = rm_eff;
              end
            end

            Funct5Fdiv: begin
              if (rm_ok) begin
                legal     = 1'b1;
                unit      = FP_DIV_SQRT;
                frs1_read = 1'b1;
                frs2_read = 1'b1;
                frd_write = 1'b1;
                rm        = rm_eff;
              end
            end

            Funct5Fsqrt: begin
              if ((rs2 == Rs2Zero) && rm_ok) begin
                legal     = 1'b1;
                unit      = FP_DIV_SQRT;
                frs1_read = 1'b1;
                frd_write = 1'b1;
                rm        = rm_eff;
                sqrt      = 1'b1;
              end
            end

            Funct5Fsgnj: begin
              if ((funct3 == Funct3Fsgnj) || (funct3 == Funct3Fsgnjn) ||
                  (funct3 == Funct3Fsgnjx)) begin
                legal     = 1'b1;
                unit      = FP_MISC;
                frs1_read = 1'b1;
                frs2_read = 1'b1;
                frd_write = 1'b1;
              end
            end

            Funct5Fminmax: begin
              if ((funct3 == Funct3Fmin) || (funct3 == Funct3Fmax)) begin
                legal     = 1'b1;
                unit      = FP_MISC;
                frs1_read = 1'b1;
                frs2_read = 1'b1;
                frd_write = 1'b1;
              end
            end

            Funct5Fcmp: begin
              if ((funct3 == Funct3Fle) || (funct3 == Funct3Flt) || (funct3 == Funct3Feq)) begin
                legal     = 1'b1;
                unit      = FP_MISC;
                frs1_read = 1'b1;
                frs2_read = 1'b1;
                xrd_write = 1'b1;
              end
            end

            Funct5FcvtWS: begin
              if (((rs2 == Rs2W) || (rs2 == Rs2Wu)) && rm_ok) begin
                legal       = 1'b1;
                unit        = FP_CVT;
                frs1_read   = 1'b1;
                xrd_write   = 1'b1;
                rm          = rm_eff;
                to_int      = 1'b1;
                is_unsigned = (rs2 == Rs2Wu);
              end
            end

            Funct5FcvtSW: begin
              if (((rs2 == Rs2W) || (rs2 == Rs2Wu)) && rm_ok) begin
                legal       = 1'b1;
                unit        = FP_CVT;
                xrs1_read   = 1'b1;
                frd_write   = 1'b1;
                rm          = rm_eff;
                is_unsigned = (rs2 == Rs2Wu);
              end
            end

            Funct5FmvXW: begin
              if ((rs2 == Rs2Zero) && (funct3 == Funct3Fmv)) begin
                legal     = 1'b1;
                unit      = FP_MV_X_W;
                frs1_read = 1'b1;
                xrd_write = 1'b1;
              end else if ((rs2 == Rs2Zero) && (funct3 == Funct3Fclass)) begin
                legal     = 1'b1;
                unit      = FP_MISC;
                frs1_read = 1'b1;
                xrd_write = 1'b1;
              end
            end

            Funct5FmvWX: begin
              if ((rs2 == Rs2Zero) && (funct3 == Funct3Fmv)) begin
                legal     = 1'b1;
                unit      = FP_MV_W_X;
                xrs1_read = 1'b1;
                frd_write = 1'b1;
              end
            end

            default: ;
          endcase
        end
      end

      default: ;
    endcase
  end

endmodule

`default_nettype wire
