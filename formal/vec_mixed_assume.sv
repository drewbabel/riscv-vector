`default_nettype none

module vec_mixed_assume
  import vec_pkg::*;
#(
    parameter  int ELEN   = arch_pkg::ELEN,
    localparam int SewTop = $clog2(ELEN / 8)
) (
    input wire vec_op_e             op,
    input wire          [VsewW-1:0] vsew
);

  always_comb begin
    assume (int'(vsew) <= SewTop);
    if ((op == VEC_ZEXT4) || (op == VEC_SEXT4)) assume (int'(vsew) >= 2);
    if ((op == VEC_ZEXT2) || (op == VEC_SEXT2)) assume (int'(vsew) >= 1);
    if ((op == VEC_WADDU) || (op == VEC_WADD) || (op == VEC_WSUBU) || (op == VEC_WSUB) ||
        (op == VEC_NSRL) || (op == VEC_NSRA))
      assume (int'(vsew) < SewTop);
  end

endmodule

`default_nettype wire
