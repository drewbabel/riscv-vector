`default_nettype none

module vec_fp_reduce
  import vec_pkg::*;
  import fp_pkg::Funct5Fminmax, fp_pkg::Funct3Fmin, fp_pkg::Funct3Fmax;
  import fp_pkg::FlagNv, fp_pkg::FlagW, fp_pkg::RmW, fp_pkg::fp_canon_nan;
#(
    parameter  int DLEN   = arch_pkg::VLEN,
    parameter  int ExpW   = fp_pkg::ExpW,
    parameter  int FracW  = fp_pkg::FracW,
    localparam int FpW    = 1 + ExpW + FracW,
    localparam int Elems  = DLEN / FpW,
    localparam int Levels = $clog2(Elems),
    localparam int Cut    = Levels / 2,
    localparam int Half   = Elems >> Cut,
    localparam int AddLat = fp_pkg::FpAddLatency
) (
    input wire clk,
    input wire rst_n,
    input wire core_en,

    input wire vec_fop_e             op,
    input wire                       first,
    input wire                       step,
    input wire           [ DLEN-1:0] vs2_data,
    input wire           [ DLEN-1:0] vs1_data,
    input wire           [Elems-1:0] elem_active,
    input wire           [  RmW-1:0] rm,

    output logic [ DLEN-1:0] result,
    output logic [  FpW-1:0] sum_result,
    output logic [FlagW-1:0] fflags
);

  localparam logic [FpW-1:0] CanonNan = FpW'(fp_canon_nan(ExpW, FracW));

  if ((Elems < 2) || (Elems != (1 << Levels))) begin : g_elems
    $error("DLEN must hold a power of two float elements, at least two");
  end

  if (AddLat < 2) begin : g_add_lat
    $error("ordered sum expects a pipelined adder");
  end

  if (DLEN > FpW) begin : g_unused_vs1
    logic unused_vs1;
    assign unused_vs1 = ^vs1_data[DLEN-1:FpW];
  end

  function automatic logic [opcode_pkg::Funct3W-1:0] pick(input vec_fop_e kind);
    pick = (kind == VEC_FMAX) ? Funct3Fmax : Funct3Fmin;
  endfunction

  logic [  FpW-1:0] lo_val [2*Elems];
  logic             lo_live[2*Elems];
  logic [FlagW-1:0] lo_flag[2*Elems];

  for (genvar n = 0; n < Half; n++) begin : g_lo_unused
    assign lo_val[n]  = '0;
    assign lo_live[n] = 1'b0;
    assign lo_flag[n] = '0;
  end

  for (genvar e = 0; e < Elems; e++) begin : g_leaf
    assign lo_val[Elems+e]  = vs2_data[e*FpW+:FpW];
    assign lo_live[Elems+e] = elem_active[e];
    assign lo_flag[Elems+e] = '0;
  end

  // Lower tree
  for (genvar n = Half; n < Elems; n++) begin : g_lo
    logic [  FpW-1:0] cmp_res;
    logic [FlagW-1:0] cmp_flags;
    logic             both;
    logic [  FpW-1:0] kept;

    fp_misc #(
        .ExpW (ExpW),
        .FracW(FracW)
    ) u_cmp (
        .funct5(Funct5Fminmax),
        .funct3(pick(op)),
        .a(lo_val[2*n]),
        .b(lo_val[2*n+1]),
        .result(cmp_res),
        .fflags(cmp_flags)
    );

    // Dead side copies
    assign both = lo_live[2*n] && lo_live[2*n+1];
    always_comb begin
      if (both) kept = cmp_res;
      else if (lo_live[2*n]) kept = lo_val[2*n];
      else kept = lo_val[2*n+1];
    end
    assign lo_val[n]  = kept;
    assign lo_live[n] = lo_live[2*n] || lo_live[2*n+1];
    assign lo_flag[n] = lo_flag[2*n] | lo_flag[2*n+1] | (both ? cmp_flags : '0);
  end

  // Mid tree cut
  logic     [  FpW-1:0] cut_val_q   [Half];
  logic                 cut_live_q  [Half];
  logic     [FlagW-1:0] cut_flag_q  [Half];
  logic     [  FpW-1:0] seed_q;
  vec_fop_e             op_q;
  logic                 first_q;
  logic                 step_q;
  logic                 sum_q;
  logic                 unord_q;
  logic     [  RmW-1:0] rm_q;
  logic     [  FpW-1:0] elem_q;
  logic                 elem_live_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      step_q <= 1'b0;
      sum_q  <= 1'b0;
    end else if (core_en) begin
      for (int n = 0; n < Half; n++) begin
        cut_val_q[n]  <= lo_val[Half+n];
        cut_live_q[n] <= lo_live[Half+n];
        cut_flag_q[n] <= lo_flag[Half+n];
      end
      seed_q  <= vs1_data[FpW-1:0];
      op_q    <= op;
      first_q <= first;
      step_q  <= step && !is_sum(op);
      sum_q   <= step && is_sum(op);
      unord_q <= op == VEC_FREDUSUM;
      rm_q    <= rm;
      elem_q  <= vs2_data[FpW-1:0];
      elem_live_q <= elem_active[0];
    end
  end

  logic [  FpW-1:0] hi_val [2*Half];
  logic             hi_live[2*Half];
  logic [FlagW-1:0] hi_flag[2*Half];

  assign hi_val[0]  = '0;
  assign hi_live[0] = 1'b0;
  assign hi_flag[0] = '0;

  for (genvar n = 0; n < Half; n++) begin : g_cut
    assign hi_val[Half+n]  = cut_val_q[n];
    assign hi_live[Half+n] = cut_live_q[n];
    assign hi_flag[Half+n] = cut_flag_q[n];
  end

  // Upper tree
  for (genvar n = 1; n < Half; n++) begin : g_hi
    logic [  FpW-1:0] cmp_res;
    logic [FlagW-1:0] cmp_flags;
    logic             both;
    logic [  FpW-1:0] kept;

    fp_misc #(
        .ExpW (ExpW),
        .FracW(FracW)
    ) u_cmp (
        .funct5(Funct5Fminmax),
        .funct3(pick(op_q)),
        .a(hi_val[2*n]),
        .b(hi_val[2*n+1]),
        .result(cmp_res),
        .fflags(cmp_flags)
    );

    assign both = hi_live[2*n] && hi_live[2*n+1];
    always_comb begin
      if (both) kept = cmp_res;
      else if (hi_live[2*n]) kept = hi_val[2*n];
      else kept = hi_val[2*n+1];
    end
    assign hi_val[n]  = kept;
    assign hi_live[n] = hi_live[2*n] || hi_live[2*n+1];
    assign hi_flag[n] = hi_flag[2*n] | hi_flag[2*n+1] | (both ? cmp_flags : '0);
  end

  // Carried accumulator
  logic [FlagW-1:0] sum_flags;
  logic [  FpW-1:0] acc_q;
  logic [  FpW-1:0] base;
  logic [  FpW-1:0] acc_res;
  logic [FlagW-1:0] acc_flags;
  logic [  FpW-1:0] acc_next;

  assign base = first_q ? seed_q : acc_q;

  fp_misc #(
      .ExpW (ExpW),
      .FracW(FracW)
  ) u_acc (
      .funct5(Funct5Fminmax),
      .funct3(pick(op_q)),
      .a(base),
      .b(hi_val[1]),
      .result(acc_res),
      .fflags(acc_flags)
  );

  // Scalar kept alone
  assign acc_next = hi_live[1] ? acc_res : base;

  always_ff @(posedge clk) begin
    if (!rst_n) acc_q <= '0;
    else if (core_en && step_q) acc_q <= acc_next;
  end

  assign result = DLEN'(acc_next);

  function automatic logic is_sum(input vec_fop_e kind);
    is_sum = (kind == VEC_FREDOSUM) || (kind == VEC_FREDUSUM);
  endfunction

  // Ordered sum
  logic [   FpW-1:0] sum_acc_q;
  logic [   FpW-1:0] sum_now;
  logic [   FpW-1:0] sum_base;
  logic              launch;
  logic [   FpW-1:0] add_res;
  logic [ FlagW-1:0] add_flags;
  logic              add_done;
  logic [AddLat-1:0] add_v_q;
  logic [AddLat-1:0] fin_v_q;
  logic [AddLat-1:0] fin_unord_q;

  assign add_done = add_v_q[AddLat-1];
  assign sum_now  = add_done ? add_res : sum_acc_q;
  assign sum_base = first_q ? seed_q : sum_now;
  assign launch   = sum_q && elem_live_q;

  fp_add #(
      .ExpW (ExpW),
      .FracW(FracW)
  ) u_add (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .sub(1'b0),
      .rm(rm_q),
      .a(sum_base),
      .b(elem_q),
      .result(add_res),
      .fflags(add_flags)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      sum_acc_q <= '0;
      add_v_q   <= '0;
      fin_v_q   <= '0;
    end else if (core_en) begin
      if (sum_q) begin
        sum_acc_q <= sum_base;
      end else if (add_done) begin
        sum_acc_q <= add_res;
      end
      add_v_q     <= {add_v_q[AddLat-2:0], launch};
      fin_v_q     <= {fin_v_q[AddLat-2:0], sum_q};
      fin_unord_q <= {fin_unord_q[AddLat-2:0], unord_q};
    end
  end

  // Unordered NaN rule
  logic fin_done;
  logic sum_nan;
  logic sum_snan;
  logic canon;

  assign fin_done = fin_v_q[AddLat-1];
  assign sum_nan = (&sum_now[FpW-2:FracW]) && (sum_now[FracW-1:0] != '0);
  assign sum_snan = sum_nan && !sum_now[FracW-1];
  assign canon = fin_done && fin_unord_q[AddLat-1] && sum_nan;

  assign sum_result = canon ? CanonNan : sum_now;
  assign sum_flags = (add_flags & {FlagW{add_done}}) | (FlagNv & {FlagW{canon && sum_snan}});

  assign fflags = ((hi_flag[1] | acc_flags) & {FlagW{step_q && hi_live[1]}}) | sum_flags;

endmodule

`default_nettype wire
