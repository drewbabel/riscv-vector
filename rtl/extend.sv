`default_nettype none

module extend
  import opcode_pkg::*;
#(
    parameter  int XLEN = arch_pkg::XLEN,
    localparam int ILEN = arch_pkg::ILEN
) (
    input  wire  [ILEN-1:0] instr,
    input  wire  [ImmSrcW-1:0] imm_src,
    output logic [   XLEN-1:0] imm_ext
);

  always_comb begin
    case (imm_src)
      ImmI: imm_ext = XLEN'($signed(instr[31:20]));
      ImmS: imm_ext = XLEN'($signed({instr[31:25], instr[11:7]}));
      // SB/B-type
      ImmB: imm_ext = XLEN'($signed({instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}));
      ImmU: imm_ext = XLEN'($signed({instr[31:12], 12'b0}));
      // UJ/J-type
      ImmJ: imm_ext = XLEN'($signed({instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}));
      default: imm_ext = 'x;
    endcase
  end

endmodule

`default_nettype wire
