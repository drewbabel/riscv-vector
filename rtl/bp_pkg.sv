`default_nettype none

package bp_pkg;

  // History length
  parameter int GhistLen  = arch_pkg::GhistLen;
  parameter int PhtDepth  = 1 << GhistLen;

  // Direct mapped BTB
  parameter int BtbIdxLen = arch_pkg::BtbIdxLen;
  parameter int BtbDepth  = 1 << BtbIdxLen;

endpackage

`default_nettype wire
