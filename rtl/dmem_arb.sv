`default_nettype none

module dmem_arb #(
    parameter int XLEN = 32
) (
    input logic clk,
    input logic rst_n,
    input logic core_en,

    // Scalar side
    input  logic            s_req,
    input  logic [XLEN-1:0] s_addr,
    input  logic [XLEN-1:0] s_wdata,
    input  logic [     3:0] s_wstrb,
    output logic            s_ready,

    // Vector side
    input  logic            v_req,
    input  logic [XLEN-1:0] v_addr,
    input  logic [XLEN-1:0] v_wdata,
    input  logic [     3:0] v_wstrb,
    output logic            v_ready,

    // Shared port
    output logic            req,
    output logic [XLEN-1:0] addr,
    output logic [XLEN-1:0] wdata,
    output logic [     3:0] wstrb,
    input  logic            ready
);

  logic [1:0] grant;
  logic       grant_vec;

  rr_arbiter #(
      .N(2)
  ) u_arb (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .req({v_req, s_req}),
      .hold(!ready),
      .grant(grant),
      .grant_valid()
  );

  assign grant_vec = grant[1];

  assign req       = s_req || v_req;
  assign addr      = grant_vec ? v_addr : s_addr;
  assign wdata     = grant_vec ? v_wdata : s_wdata;
  assign wstrb     = grant_vec ? v_wstrb : s_wstrb;
  assign s_ready   = ready && grant[0];
  assign v_ready   = ready && grant_vec;

endmodule

`default_nettype wire
