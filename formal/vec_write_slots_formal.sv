`default_nettype none

module vec_write_slots_formal ();

  localparam int DEPTH  = vec_pkg::VecFpLatency + 1;
  localparam int DepthW = $clog2(DEPTH + 1);
  localparam int Slots  = 1 << DepthW;

  logic              clk;

  (* anyseq *)logic              core_en;
  (* anyseq *)logic              start;
  (* anyseq *)logic [DepthW-1:0] depth;

  logic              free;

  logic              rst_n;
  logic [       1:0] t = 2'd0;
  logic              f_past_valid = 1'b0;

  initial assume (t == 2'd0);
  always @(posedge clk) begin
    t <= (t == 2'd3) ? 2'd3 : t + 2'd1;
    f_past_valid <= 1'b1;
  end
  assign rst_n = (t != 2'd0);

  vec_write_slots #(
      .DEPTH(DEPTH)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(start),
      .depth(depth),
      .free(free)
  );

  // Issuer contract
  always @(posedge clk)
    if (rst_n && start) begin
      assume (free);
      assume (depth >= DepthW'(1) && depth <= DepthW'(DEPTH));
    end

  // Writes due
  logic [1:0] f_due[Slots];

  always @(posedge clk) begin
    for (int k = 0; k < Slots; k++) begin
      if (!rst_n) f_due[k] <= 2'd0;
      else if (core_en) begin
        f_due[k] <= ((k == Slots - 1) ? 2'd0 : f_due[(k+1)%Slots]) +
            2'(start && (int'(depth) == k + 1));
      end
    end
  end

  always @(posedge clk) if (rst_n) assert (f_due[0] <= 2'd1);

  // Covers
  always @(posedge clk)
    if (rst_n && core_en) begin
      cover (f_due[0] == 2'd1 && $past(f_due[0] == 2'd1) && $past(f_due[0] == 2'd1, 2));
      cover (!free && depth == DepthW'(DEPTH - 2) && $past(
          core_en && start && depth == DepthW'(DEPTH - 1)
      ));
      cover (f_due[0] == 2'd1 && f_due[1] == 2'd1 && f_due[DEPTH-1] == 2'd1);
      cover (f_due[0] == 2'd1 && $past(f_due[0] == 2'd1 && !core_en));
    end

endmodule

`default_nettype wire
