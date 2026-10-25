`default_nettype none

module boot_loader #(
    parameter int XLEN      = arch_pkg::XLEN,
    parameter int DEPTH     = arch_pkg::MemWords,
    parameter int DATA_BITS = arch_pkg::UartDataBits
) (
    input  wire                  clk,
    input  wire                  core_en,
    input  wire                  rst_n,
    input  wire                  rx_valid,
    input  wire  [DATA_BITS-1:0] rx_data,
    output logic                 we,
    output logic [     XLEN-1:0] waddr,
    output logic [     XLEN-1:0] wdata,
    output logic                 loading
);

  typedef enum logic [1:0] {
    COUNT,
    LOAD,
    DONE
  } state_t;

  localparam logic [XLEN-1:0] CapWords = XLEN'(DEPTH);
  localparam int WordLsb = $clog2(XLEN / 8);
  localparam int Frames = XLEN / DATA_BITS;
  localparam int FrameW = (Frames > 1) ? $clog2(Frames) : 1;
  localparam logic [FrameW-1:0] LastFrame = FrameW'(Frames - 1);

  if ((Frames < 2) || (Frames * DATA_BITS != XLEN)) begin : g_frames
    $error("XLEN must hold at least two whole DATA_BITS frames");
  end

  state_t state, next_state;
  logic [FrameW-1:0] cnt_frame;
  logic [XLEN-1:0] cnt_word;
  logic [XLEN-1:0] max_word;
  logic [XLEN-1:0] limit;
  logic [XLEN-1:0] acc;
  logic [XLEN-1:0] acc_next;
  logic last_frame;

  assign acc_next = {rx_data, acc[XLEN-1:$bits(rx_data)]};
  assign last_frame = cnt_frame == LastFrame;

  // Memory bounds load
  assign limit = (max_word > CapWords) ? CapWords : max_word;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= COUNT;
      cnt_frame <= '0;
      cnt_word <= '0;
    end else if (core_en) begin
      state <= next_state;

      if (rx_valid) begin
        cnt_frame <= cnt_frame + FrameW'(1);
        acc <= acc_next;
        case (state)
          COUNT: if (last_frame) max_word <= acc_next;
          LOAD: if (last_frame) cnt_word <= cnt_word + 1'd1;
          default: ;
        endcase
      end
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      COUNT: if (rx_valid && last_frame) next_state = LOAD;
      LOAD: if (cnt_word == limit) next_state = DONE;
      DONE: ;  // Terminates
      default: ;
    endcase
  end

  assign we      = (state == LOAD) && rx_valid && last_frame;
  assign waddr   = cnt_word << WordLsb;
  assign wdata   = acc_next;
  assign loading = state != DONE;

endmodule

`default_nettype wire
