`default_nettype none

module extend #(
    parameter int XLEN = arch_pkg::XLEN
) (
    input  wire  [    31:0] instr,
    input  wire  [     2:0] imm_src,
    output logic [XLEN-1:0] imm_ext
);

  always_comb begin
    case (imm_src)
      3'd0: imm_ext = XLEN'($signed(instr[31:20]));  // I-type
      3'd1: imm_ext = XLEN'($signed({instr[31:25], instr[11:7]}));  // S-type
      // SB/B-type
      3'd2: imm_ext = XLEN'($signed({instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}));
      3'd3: imm_ext = XLEN'($signed({instr[31:12], 12'b0}));  // U-type
      // UJ/J-type
      3'd4: imm_ext = XLEN'($signed({instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}));
      default: imm_ext = 'x;
    endcase
  end

endmodule

`default_nettype wire
