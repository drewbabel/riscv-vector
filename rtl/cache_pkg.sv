`default_nettype none

package cache_pkg;

  // Line geometry
  parameter int LineWords = arch_pkg::LineWords;
  parameter int WordBytes = arch_pkg::XLEN / 8;
  parameter int WordLsb = $clog2(WordBytes);
  parameter int LineBits = 8 * WordBytes * LineWords;
  parameter int LineBytes = WordBytes * LineWords;
  parameter int BlkOffLen = $clog2(LineWords);
  parameter int IdxLsb = WordLsb + BlkOffLen;

  // Instruction cache
  parameter int IcIdxLen = arch_pkg::IcIdxLen;
  parameter int IcSets = 1 << IcIdxLen;
  parameter int IcTagLen = arch_pkg::XLEN - IdxLsb - IcIdxLen;

  // Data cache
  parameter int DcIdxLen = arch_pkg::DcIdxLen;
  parameter int DcSets = 1 << DcIdxLen;
  parameter int DcWays = arch_pkg::DcWays;
  parameter int DcWaySel = $clog2(DcWays);
  parameter int DcTagLen = arch_pkg::XLEN - IdxLsb - DcIdxLen;

endpackage

`default_nettype wire
