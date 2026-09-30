`default_nettype none

module boot_loader #(
    parameter int XLEN  = arch_pkg::XLEN,
    parameter int DEPTH = 16384
) (
    input  wire             clk,
    input  wire             core_en,
    input  wire             rst_n,
    input  wire             rx_valid,
    input  wire  [     7:0] rx_data,
    output logic            we,
    output logic [XLEN-1:0] waddr,
    output logic [XLEN-1:0] wdata,
    output logic            loading
);

  typedef enum logic [1:0] {
    COUNT,
    LOAD,
    DONE
  } state_t;

  localparam logic [XLEN-1:0] CapWords = XLEN'(DEPTH);
  localparam int WordBytes = XLEN / 8;
  localparam int WordLsb = $clog2(WordBytes);
  localparam logic [WordLsb-1:0] LastByte = WordLsb'(WordBytes - 1);

  state_t state, next_state;
  logic [WordLsb-1:0] cnt_byte;
  logic [XLEN-1:0] cnt_word;
  logic [XLEN-1:0] max_word;
  logic [XLEN-1:0] limit;
  logic [XLEN-1:0] acc;

  // Memory bounds load
  assign limit = (max_word > CapWords) ? CapWords : max_word;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= COUNT;
      cnt_byte <= '0;
      cnt_word <= '0;
    end else if (core_en) begin
      state <= next_state;

      if (rx_valid) begin
        cnt_byte <= cnt_byte + WordLsb'(1);
        acc <= {rx_data, acc[XLEN-1:$bits(rx_data)]};
        case (state)
          COUNT: if (cnt_byte == LastByte) max_word <= {rx_data, acc[XLEN-1:$bits(rx_data)]};
          LOAD: if (cnt_byte == LastByte) cnt_word <= cnt_word + 1'd1;
          default: ;
        endcase
      end
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      COUNT: if (rx_valid && cnt_byte == LastByte) next_state = LOAD;
      LOAD: if (cnt_word == limit) next_state = DONE;
      DONE: ;  // Terminates
      default: ;
    endcase
  end

  assign we      = (state == LOAD) && rx_valid && (cnt_byte == LastByte);
  assign waddr   = cnt_word << WordLsb;
  assign wdata   = {rx_data, acc[XLEN-1:$bits(rx_data)]};
  assign loading = state != DONE;

endmodule

`default_nettype wire
