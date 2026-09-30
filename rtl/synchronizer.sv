`default_nettype none

module synchronizer (
    input  wire  clk,
    input  wire  core_en,
    input  wire  d,
    output logic q
);

  logic ff;

  always_ff @(posedge clk)
    if (core_en) begin
      ff <= d;
      q  <= ff;
    end

endmodule

`default_nettype wire
