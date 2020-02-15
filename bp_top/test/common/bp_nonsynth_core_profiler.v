
// The BlackParrot core pipeline is a mostly non-stalling pipeline, decoupled between the front-end
// and back-end.
module bp_nonsynth_core_profiler
  import bp_common_pkg::*;
  import bp_common_aviary_pkg::*;
  import bp_common_rv64_pkg::*;
  import bp_be_pkg::*;
  #(parameter bp_params_e bp_params_p = e_bp_inv_cfg
    `declare_bp_proc_params(bp_params_p)

    , localparam dispatch_pkt_width_lp = `bp_be_dispatch_pkt_width(vaddr_width_p)
    , localparam commit_pkt_width_lp = `bp_be_commit_pkt_width(vaddr_width_p)
    )
   (input                       clk_i
    , input                     reset_i

    // IF1 events
    , input icache_stall

    // IF2 events
    , input icache_miss
    , input branch_override
    
    // IF3 events
    , input cmd_fence

    // ISD events
    , input branch_mispredict
    , input dependency_stall

    // ALU events

    // MUL events

    // MEM events
    , input exception
    , input interrupt
    , input dcache_miss

    // Reservation packet
    , input [dispatch_pkt_width_lp-1:0] reservation

    // Commit packet
    , input [commit_pkt_width_lp-1:0] commit_pkt
    );

  `declare_bp_be_internal_if_structs(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p);

  typedef struct packed
  {
    logic unknown;
    logic icache_stall;
    logic icache_miss;
    logic branch_override;
    logic cmd_fence;
    logic branch_mispredict;
    logic dependency_stall;
    logic exception;
    logic interrupt;
    logic dcache_miss;
  }  bp_stall_reason_s;

  localparam num_stages_p = 8;
  bp_stall_reason_s [num_stages_p-1:0] stall_stage_n, stall_stage_r;
  bp_stall_reason_s stall_reason_r;
  bsg_dff_reset
   #(.width_p($bits(bp_stall_reason_s)*num_stages_p))
   stall_pipe
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.data_i(stall_stage_n)
     ,.data_o(stall_stage_r)
     );
  assign stall_reason_r = stall_stage_r[num_stages_p-1];

  bp_be_dispatch_pkt_s reservation_r;
  bsg_dff_chain
   #(.width_p($bits(bp_be_dispatch_pkt_s))
     ,.num_stages_p(4)
     )
   reservation_pipe
    (.clk_i(clk_i)
     ,.data_i(reservation)
     ,.data_o(reservation_r)
     );

  bp_be_commit_pkt_s commit_pkt_r;
  bsg_dff_reset
   #(.width_p($bits(bp_be_commit_pkt_s)))
   commit_pipe
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.data_i(commit_pkt)
     ,.data_o(commit_pkt_r)
     );

/*
  always_comb
    begin
      // By default, move down the pipe
      for (integer i = 0; i < num_stages_p; i++)
        stall_stage_n[i] = (i == '0) ? '0 : stall_stage_r[i-1];

      stall_stage_n[0].unknown = 1'b1;
      stall_stage_n[0].icache_stall = icache_stall;
      stall_stage_n[0].icache_miss = icache_miss;

      stall_stage_n[1].icache_miss = icache_miss;
    end

  always_ff @(negedge clk_i)
    begin
      if (commit_pkt_r.v)
        $display("Commit: %x", commit_pkt_r.pc);
      if (~commit_pkt_r.v)
        $display("Stall: %x %p", commit_pkt_r.pc, stall_reason_r);
    end
*/
/*
  always_ff @(negedge clk_i)
    begin
      if (~commit_pkt_r.v & ~|stall_reason_r)
        $display("No stall reason for invalid commit: %p stall: %p", commit_pkt_r, stall_reason_r);
    end
*/

endmodule

