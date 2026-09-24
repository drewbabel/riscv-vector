`default_nettype none

module review_probe (
    input logic clk,
  input logic [7:0] a,
    output logic [3:0] y,
    output logic [7:0] z
);

  always @* begin
      z = a;   
  end

  assign y = a;


  logic [7:0] this_is_a_very_long_signal_name_that_keeps_going_to_break_the_line_length_limit_for_sure_ok;
	
endmodule

`default_nettype wire
