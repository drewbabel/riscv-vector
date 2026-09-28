`default_nettype none

module vec_busy_bits #(
    parameter  int NREGS  = 32,
    localparam int AddrW  = $clog2(NREGS),
    localparam int CountW = AddrW + 1
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               core_en,
    input  wire               start,
    input  wire  [ AddrW-1:0] vd,
    input  wire  [CountW-1:0] vd_regs,
    input  wire  [ AddrW-1:0] vs1,
    input  wire  [CountW-1:0] vs1_regs,
    input  wire  [ AddrW-1:0] vs2,
    input  wire  [CountW-1:0] vs2_regs,
    input  wire               masked,
    input  wire               clear,
    input  wire  [ AddrW-1:0] clear_addr,
    output logic              ready
);

  // Group to bits
  function automatic logic [NREGS-1:0] group(input logic [AddrW-1:0] base,
                                             input logic [CountW-1:0] regs);
    logic [NREGS-1:0] bits;
    for (int i = 0; i < NREGS; i++) begin
      bits[i] = (i >= int'(base)) && (i < int'(base) + int'(regs));
    end
    return bits;
  endfunction

  logic [NREGS-1:0] busy;
  logic [NREGS-1:0] vd_bits;
  logic [NREGS-1:0] need;
  logic [NREGS-1:0] clear_bits;

  assign vd_bits = group(vd, vd_regs);
  assign need = vd_bits | group(vs1, vs1_regs) | group(vs2, vs2_regs) | NREGS'(masked);
  assign ready = !(|(busy & need));
  assign clear_bits = NREGS'(clear) << clear_addr;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      busy <= '0;
    end else if (core_en) begin
      busy <= (busy & ~clear_bits) | (start ? vd_bits : '0);
    end
  end

endmodule

`default_nettype wire
