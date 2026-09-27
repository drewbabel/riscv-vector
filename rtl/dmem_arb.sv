`default_nettype none

module dmem_arb #(
    parameter  int XLEN   = 32,
    parameter  int DATA_W = XLEN,
    localparam int StrbW  = DATA_W / 8
) (
    input wire clk,
    input wire rst_n,
    input wire core_en,

    // Scalar side
    input  wire               s_req,
    input  wire  [  XLEN-1:0] s_addr,
    input  wire  [DATA_W-1:0] s_wdata,
    input  wire  [ StrbW-1:0] s_wstrb,
    output logic              s_ready,

    // Vector side
    input  wire               v_req,
    input  wire  [  XLEN-1:0] v_addr,
    input  wire  [DATA_W-1:0] v_wdata,
    input  wire  [ StrbW-1:0] v_wstrb,
    output logic              v_ready,

    // Shared port
    output logic              req,
    output logic [  XLEN-1:0] addr,
    output logic [DATA_W-1:0] wdata,
    output logic [ StrbW-1:0] wstrb,
    input  wire               ready
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
