`default_nettype none

module rr_arbiter #(
    parameter int N = 4
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         core_en,
    input  logic [N-1:0] req,         // Request
    input  logic         hold,
    output logic [N-1:0] grant,
    output logic         grant_valid
);

  logic [N-1:0] mask;  // Above last winner
  logic [N-1:0] masked_req;
  logic [N-1:0] grant_masked;
  logic [N-1:0] grant_unmasked;
  logic [N-1:0] held_grant;
  logic [N-1:0] rr_grant;
  logic         holding;

  assign masked_req = req & mask;
  assign grant_masked = masked_req & (~masked_req + 1);  // Lowest set bit
  assign grant_unmasked = req & (~req + 1);

  // Round robin rotation
  always_comb begin
    if (masked_req == '0) rr_grant = grant_unmasked;  // Overflow
    else rr_grant = grant_masked;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mask <= '1;  // Full request set
      holding <= 1'b0;
    end else if (core_en) begin
      if (|grant) mask <= ~(grant | (grant - 1));

      if (grant_valid) holding <= hold;
      if (!holding) held_grant <= rr_grant;
    end
  end

  // Grant result
  always_comb begin
    if (holding) grant = held_grant;
    else grant = rr_grant;
  end

  assign grant_valid = |grant;

endmodule

`default_nettype wire
