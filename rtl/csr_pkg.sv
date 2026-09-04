`default_nettype none

package csr_pkg;

  // CSR addresses
  localparam logic [11:0] MstatusAddr = 12'h300;  // STATUS
  localparam logic [11:0] MieAddr = 12'h304;  // Interrupt Enable
  localparam logic [11:0] MtvecAddr = 12'h305;  // Trap-VECtor
  localparam logic [11:0] MscratchAddr = 12'h340;  // SCRATCH
  localparam logic [11:0] MepcAddr = 12'h341;  // Exception Program Counter
  localparam logic [11:0] McauseAddr = 12'h342;  // CAUSE
  localparam logic [11:0] MtvalAddr = 12'h343;  // Trap VALue
  localparam logic [11:0] MipAddr = 12'h344;  // Interrupt Pending
  localparam logic [11:0] McycleAddr = 12'hB00;  // CYCLE
  localparam logic [11:0] MinstretAddr = 12'hB02;  // INSTructions RETired
  localparam logic [11:0] McyclehAddr = 12'hB80;  // CYCLE High
  localparam logic [11:0] MinstrethAddr = 12'hB82;  // INSTructions RETired High

  // Vector CSR addresses
  localparam logic [11:0] VstartAddr = 12'h008;  // element index
  localparam logic [11:0] VxsatAddr = 12'h009;  // SATuration flag
  localparam logic [11:0] VxrmAddr = 12'h00A;  // Rounding Mode
  localparam logic [11:0] VcsrAddr = 12'h00F;  // Vector CSR
  localparam logic [11:0] VlAddr = 12'hC20;  // Vector Length
  localparam logic [11:0] VtypeAddr = 12'hC21;  // Vector TYPE
  localparam logic [11:0] VlenbAddr = 12'hC22;  // VLEN in Bytes


  // mstatus bit positions
  localparam int MstatusMie = 3;  // Interrupt Enable
  localparam int MstatusMpie = 7;  // Previous Interrupt Enable
  localparam int MstatusVsLo = 9;  // Vector Status Low
  localparam int MstatusMppLo = 11;  // Previous Privilege Low
  localparam int MstatusSd = 31;  // State Dirty
  localparam logic [1:0] PrivMachine = 2'b11;

  // Vector Status encodings
  localparam logic [1:0] VsOff = 2'b00;  // disabled
  localparam logic [1:0] VsInitial = 2'b01;  // registers zero
  localparam logic [1:0] VsClean = 2'b10;  // matches saved copy
  localparam logic [1:0] VsDirty = 2'b11;  // written since save

  // Writable bits
  localparam logic [31:0] MstatusMask = (32'd1 << MstatusMie) | (32'd1 << MstatusMpie) |
      (32'd3 << MstatusVsLo) | (32'd3 << MstatusMppLo);

  // Machine timer bit
  localparam int Mtie = 7;
  localparam int Mtip = 7;

  localparam int Meie = 11;
  localparam int Meip = 11;

  // mtvec[1:0]
  localparam logic [1:0] MtvecDirect = 2'b00;  // Every trap jumps to same address
  localparam logic [1:0] MtvecVectored = 2'b01;  // Exceptions & interrupts treated differently

  // Exception codes
  localparam logic [3:0] CauseInstrMisaligned = 4'd0;
  localparam logic [3:0] CauseIllegalInstr = 4'd2;
  localparam logic [3:0] CauseBreakpoint = 4'd3;  // Hit breakpoint (likely from EBREAK)
  localparam logic [3:0] CauseLoadMisaligned = 4'd4;
  localparam logic [3:0] CauseStoreMisaligned = 4'd6;
  localparam logic [3:0] CauseEcallM = 4'd11;  // Environment Call from M-mode

  // Interrupt codes
  localparam logic [3:0] CauseMachineTimerIrq = 4'd7;
  localparam logic [3:0] CauseMachineExternalIrq = 4'd11;

  // funct3
  localparam logic [2:0] Funct3Priv = 3'b000;  // PRIVileged instructions = ecall/ebreak/mret
  localparam logic [2:0] Funct3Csrrw = 3'b001;  // CSR Read, then Write
  localparam logic [2:0] Funct3Csrrs = 3'b010;  // CSR Read, then Set bits
  localparam logic [2:0] Funct3Csrrc = 3'b011;  // CSR Read, then Clear bits
  localparam logic [2:0] Funct3Csrrwi = 3'b101;  // CSR Read, then Write from Immediate
  localparam logic [2:0] Funct3Csrrsi = 3'b110;  // CSR Read, then Set from Immediate
  localparam logic [2:0] Funct3Csrrci = 3'b111;  // CSR Read, then Clear from Immediate

  // Priv funct12
  localparam logic [11:0] Funct12Ecall = 12'h000;  // Request for more privileged service
  localparam logic [11:0] Funct12Ebreak = 12'h001;  // Stops execution for debugging tools
  localparam logic [11:0] Funct12Mret = 12'h302;  // Exits m-mode trap handler, returns to program

  // CLINT offsets
  localparam logic [15:0] ClintMtimecmpOffset = 16'h4000;
  localparam logic [15:0] ClintMtimeOffset = 16'hBFF8;

endpackage

`default_nettype wire
