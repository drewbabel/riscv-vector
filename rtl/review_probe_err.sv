`default_nettype none

module review_probe_err (
    input  logic [7:0] a,
    output logic [7:0] b
);

  assign b = a_missing;

endmodule

`default_nettype wire
