`default_nettype none

module BUFG (
    input  wire I,
    output wire O
);
  assign O = I;
endmodule

module PLLE2_BASE #(
    parameter real CLKIN1_PERIOD  = 10.0,
    parameter int  CLKFBOUT_MULT  = 10,
    parameter int  CLKOUT0_DIVIDE = 10,
    parameter int  CLKOUT1_DIVIDE = 5
) (
    input  wire CLKIN1,
    input  wire CLKFBIN,
    output wire CLKFBOUT,
    output wire CLKOUT0,
    output wire CLKOUT1,
    output wire CLKOUT2,
    output wire CLKOUT3,
    output wire CLKOUT4,
    output wire CLKOUT5,
    output wire LOCKED,
    input  wire PWRDWN,
    input  wire RST
);
  assign CLKFBOUT = CLKIN1;
  assign CLKOUT0  = CLKIN1;
  assign CLKOUT1  = CLKIN1;
  assign CLKOUT2  = 1'b0;
  assign CLKOUT3  = 1'b0;
  assign CLKOUT4  = 1'b0;
  assign CLKOUT5  = 1'b0;
  assign LOCKED   = 1'b1;
endmodule

// Behavioral memory controller
module mig_7series_0 #(
    parameter int ReadLat = 20
) (
    output logic [ 14:0] ddr3_addr,
    output logic [  2:0] ddr3_ba,
    output logic         ddr3_ras_n,
    output logic         ddr3_cas_n,
    output logic         ddr3_we_n,
    output logic         ddr3_reset_n,
    output logic [  0:0] ddr3_ck_p,
    output logic [  0:0] ddr3_ck_n,
    output logic [  0:0] ddr3_cke,
    output logic [  0:0] ddr3_odt,
    output logic [  1:0] ddr3_dm,
    inout  wire  [ 15:0] ddr3_dq,
    inout  wire  [  1:0] ddr3_dqs_p,
    inout  wire  [  1:0] ddr3_dqs_n,
    input  wire          sys_clk_i,
    input  wire          clk_ref_i,
    input  wire          sys_rst,
    input  wire  [ 28:0] app_addr,
    input  wire  [  2:0] app_cmd,
    input  wire          app_en,
    output logic         app_rdy,
    input  wire  [127:0] app_wdf_data,
    input  wire  [ 15:0] app_wdf_mask,
    input  wire          app_wdf_wren,
    input  wire          app_wdf_end,
    output logic         app_wdf_rdy,
    output logic [127:0] app_rd_data,
    output logic         app_rd_data_valid,
    output logic         app_rd_data_end,
    input  wire          app_sr_req,
    input  wire          app_ref_req,
    input  wire          app_zq_req,
    output logic         app_sr_active,
    output logic         app_ref_ack,
    output logic         app_zq_ack,
    output logic         ui_clk,
    output logic         ui_clk_sync_rst,
    output logic         init_calib_complete,
    output logic [ 11:0] device_temp
);

  localparam int Lines = 4194304;

  logic [127:0] mem[Lines];
  int cyc = 0;
  int calib_ctr = 0;
  int rd_due[$];
  int rd_line[$];
  int wr_line[$];
  logic [127:0] wd_data[$];
  logic [15:0] wd_mask[$];

  assign ui_clk = sys_clk_i;
  assign {ddr3_addr, ddr3_ba, ddr3_ras_n, ddr3_cas_n, ddr3_we_n, ddr3_reset_n} = '0;
  assign {ddr3_ck_p, ddr3_ck_n, ddr3_cke, ddr3_odt, ddr3_dm} = '0;
  assign {app_sr_active, app_ref_ack, app_zq_ack, device_temp} = '0;
  assign ui_clk_sync_rst = !sys_rst || (calib_ctr < 16);
  assign init_calib_complete = (calib_ctr >= 64);
  assign app_rdy = init_calib_complete;
  assign app_wdf_rdy = init_calib_complete;
  assign app_rd_data_end = app_rd_data_valid;

  always @(posedge ui_clk) begin
    cyc <= cyc + 1;
    if (!sys_rst) calib_ctr <= 0;
    else if (calib_ctr < 64) calib_ctr <= calib_ctr + 1;
    app_rd_data_valid <= 1'b0;
    if (app_en && app_rdy) begin
      if (app_cmd == 3'b001) begin
        rd_due.push_back(cyc + ReadLat);
        rd_line.push_back(int'(app_addr[28:4]));
      end else begin
        wr_line.push_back(int'(app_addr[28:4]));
      end
    end
    if (app_wdf_wren && app_wdf_rdy) begin
      wd_data.push_back(app_wdf_data);
      wd_mask.push_back(app_wdf_mask);
    end
    if (wr_line.size() > 0 && wd_data.size() > 0) begin
      logic [127:0] line;
      logic [127:0] data;
      logic [ 15:0] mask;
      line = mem[wr_line[0]];
      data = wd_data[0];
      mask = wd_mask[0];
      for (int b = 0; b < 16; b++) if (!mask[b]) line[b*8+:8] = data[b*8+:8];
      mem[wr_line[0]] = line;
      void'(wr_line.pop_front());
      void'(wd_data.pop_front());
      void'(wd_mask.pop_front());
    end
    if (rd_due.size() > 0 && rd_due[0] <= cyc) begin
      app_rd_data_valid <= 1'b1;
      app_rd_data <= mem[rd_line[0]];
      void'(rd_due.pop_front());
      void'(rd_line.pop_front());
    end
  end

endmodule

`default_nettype wire
