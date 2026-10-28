`default_nettype none

package arch_pkg;

  // Scalar core
  parameter int XLEN = 32;
  parameter int RegAddrW = 5;
  parameter int NumRegs = 1 << RegAddrW;

  // Vector unit
  parameter int VLEN = 128;
  parameter int ELEN = 32;
  parameter int MulLanes = 4;

  // Cache line
  parameter int LineWords = 4;

  // Instruction cache
  parameter int IcIdxLen = 9;

  // Data cache
  parameter int DcIdxLen = 7;
  parameter int DcWays = 4;

  // Branch prediction
  parameter int GhistLen = 10;
  parameter int BtbIdxLen = 6;

  // Clocks and serial
  parameter int BoardClkHz = 100_000_000;
  parameter int ClkDiv = 2;
  parameter int BaudRate = 28_800;

  // Simulated memory latency
  parameter int MemLatency = 20;

  // Peripheral address tags
  parameter logic [7:0] ClintTag = 8'h02;
  parameter logic [7:0] GpioTag = 8'h03;
  parameter logic [7:0] UartTag = 8'h04;
  parameter logic [7:0] PmuTag = 8'h05;

  // Instruction fetch
  parameter int ILEN = 32;
  parameter int InstrBytes = ILEN / 8;
  parameter int InstrLsb = $clog2(InstrBytes);
  parameter logic [XLEN-1:0] ResetAddr = '0;

  // Board parameters
  parameter int MemWords = 16384;
  parameter int PeriphTagW = $bits(ClintTag);
  parameter int CoreClkHz = BoardClkHz / ClkDiv;
  parameter int UartDataBits = 8;

  // Memory controller
  parameter int MigAddrW = 29;
  parameter int MigCmdW = 3;

endpackage

`default_nettype wire
