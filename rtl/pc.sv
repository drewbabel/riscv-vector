`default_nettype none

module pc #(
    parameter int XLEN = arch_pkg::XLEN,
    parameter logic [XLEN-1:0] RESET_ADDR = '0
) (
    input  wire             clk,
    input  wire             core_en,
    input  wire             rst_n,
    input  wire  [XLEN-1:0] pc_next,
    output logic [XLEN-1:0] pc_q
);

  always_ff @(posedge clk) begin
    if (!rst_n) pc_q <= RESET_ADDR;
    else if (core_en) pc_q <= pc_next;
  end

endmodule

`default_nettype wire
