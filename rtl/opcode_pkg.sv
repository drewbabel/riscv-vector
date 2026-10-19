`default_nettype none

package opcode_pkg;

  // RV32I base opcodes
  localparam logic [6:0] OpcodeOp = 7'b0110011;
  localparam logic [6:0] OpcodeOpImm = 7'b0010011;
  localparam logic [6:0] OpcodeLoad = 7'b0000011;
  localparam logic [6:0] OpcodeStore = 7'b0100011;
  localparam logic [6:0] OpcodeBranch = 7'b1100011;
  localparam logic [6:0] OpcodeJal = 7'b1101111;
  localparam logic [6:0] OpcodeJalr = 7'b1100111;
  localparam logic [6:0] OpcodeLui = 7'b0110111;
  localparam logic [6:0] OpcodeAuipc = 7'b0010111;
  localparam logic [6:0] OpcodeMiscMem = 7'b0001111;
  localparam logic [6:0] OpcodeSystem = 7'b1110011;

  // Vector opcodes
  localparam logic [6:0] OpcodeOpV = 7'b1010111;
  localparam logic [6:0] OpcodeLoadFp = 7'b0000111;
  localparam logic [6:0] OpcodeStoreFp = 7'b0100111;
  localparam logic [2:0] Funct3Opcfg = 3'b111;

  // Float opcodes
  localparam logic [6:0] OpcodeOpFp = 7'b1010011;
  localparam logic [6:0] OpcodeFmadd = 7'b1000011;
  localparam logic [6:0] OpcodeFmsub = 7'b1000111;
  localparam logic [6:0] OpcodeFnmsub = 7'b1001011;
  localparam logic [6:0] OpcodeFnmadd = 7'b1001111;
  localparam logic [2:0] Funct3FpWord = 3'b010;

endpackage

`default_nettype wire
