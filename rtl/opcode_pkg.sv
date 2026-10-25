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

  // Field widths
  localparam int OpcodeW = 7;
  localparam int Funct3W = 3;
  localparam logic [31:0] InstrNop = 32'h0000_0013;

  // Integer funct3
  localparam logic [Funct3W-1:0] Funct3AddSub = 3'b000;
  localparam logic [Funct3W-1:0] Funct3Sll = 3'b001;
  localparam logic [Funct3W-1:0] Funct3Slt = 3'b010;
  localparam logic [Funct3W-1:0] Funct3Sltu = 3'b011;
  localparam logic [Funct3W-1:0] Funct3Xor = 3'b100;
  localparam logic [Funct3W-1:0] Funct3Sr = 3'b101;
  localparam logic [Funct3W-1:0] Funct3Or = 3'b110;
  localparam logic [Funct3W-1:0] Funct3And = 3'b111;

  // Branch funct3
  localparam logic [Funct3W-1:0] Funct3Beq = 3'b000;
  localparam logic [Funct3W-1:0] Funct3Bne = 3'b001;
  localparam logic [Funct3W-1:0] Funct3Blt = 3'b100;
  localparam logic [Funct3W-1:0] Funct3Bge = 3'b101;
  localparam logic [Funct3W-1:0] Funct3Bltu = 3'b110;
  localparam logic [Funct3W-1:0] Funct3Bgeu = 3'b111;

  // Memory funct3
  localparam logic [Funct3W-1:0] Funct3Lb = 3'b000;
  localparam logic [Funct3W-1:0] Funct3Lh = 3'b001;
  localparam logic [Funct3W-1:0] Funct3Lw = 3'b010;
  localparam logic [Funct3W-1:0] Funct3Lbu = 3'b100;
  localparam logic [Funct3W-1:0] Funct3Lhu = 3'b101;
  localparam logic [Funct3W-1:0] Funct3Sb = 3'b000;
  localparam logic [Funct3W-1:0] Funct3Sh = 3'b001;
  localparam logic [Funct3W-1:0] Funct3Sw = 3'b010;
  localparam logic [Funct3W-1:0] Funct3Fence = 3'b000;

  // Immediate select
  localparam int ImmSrcW = 3;
  localparam logic [ImmSrcW-1:0] ImmI = 3'd0;
  localparam logic [ImmSrcW-1:0] ImmS = 3'd1;
  localparam logic [ImmSrcW-1:0] ImmB = 3'd2;
  localparam logic [ImmSrcW-1:0] ImmU = 3'd3;
  localparam logic [ImmSrcW-1:0] ImmJ = 3'd4;

  // Operand A select
  localparam int SrcAW = 2;
  localparam logic [SrcAW-1:0] SrcARs1 = 2'd0;
  localparam logic [SrcAW-1:0] SrcAPc = 2'd1;
  localparam logic [SrcAW-1:0] SrcAZero = 2'd2;

  // Writeback select
  localparam int ResSrcW = 2;
  localparam logic [ResSrcW-1:0] ResAlu = 2'd0;
  localparam logic [ResSrcW-1:0] ResMem = 2'd1;
  localparam logic [ResSrcW-1:0] ResPc4 = 2'd2;

  // ALU class
  localparam int AluOpW = 2;
  localparam logic [AluOpW-1:0] AluOpAdd = 2'b00;
  localparam logic [AluOpW-1:0] AluOpBranch = 2'b01;
  localparam logic [AluOpW-1:0] AluOpFunct = 2'b10;

  // Forwarding select
  localparam int FwdW = 2;
  localparam logic [FwdW-1:0] FwdNone = 2'b00;
  localparam logic [FwdW-1:0] FwdMem = 2'b01;
  localparam logic [FwdW-1:0] FwdWb = 2'b10;

endpackage

`default_nettype wire
