/**
 *  bp_core.v
 *
 *  icache is connected to 0.
 *  dcache is connected to 1.
 */

module bp_core
 import bp_common_pkg::*;
 import bp_common_aviary_pkg::*;
 import bp_be_pkg::*;
 import bp_be_dcache_pkg::*;
 import bp_common_rv64_pkg::*;
 import bp_common_cfg_link_pkg::*;
  #(parameter bp_params_e bp_params_p = e_bp_inv_cfg
    `declare_bp_proc_params(bp_params_p)
    `declare_bp_fe_be_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p)
    `declare_bp_lce_cce_if_widths(cce_id_width_p, lce_id_width_p, paddr_width_p, lce_assoc_p, dword_width_p, cce_block_width_p)
    `declare_bp_cache_miss_widths(cce_block_width_p, lce_assoc_p, paddr_width_p)

    , localparam cfg_bus_width_lp = `bp_cfg_bus_width(vaddr_width_p, core_id_width_p, cce_id_width_p, lce_id_width_p, cce_pc_width_p, cce_instr_width_p)
    , localparam way_id_width_lp = `BSG_SAFE_CLOG2(lce_assoc_p)

    , localparam dcache_lce_data_mem_pkt_width_lp=
      `bp_cache_data_mem_pkt_width(lce_sets_p, lce_assoc_p, cce_block_width_p)
    , localparam dcache_lce_tag_mem_pkt_width_lp=
      `bp_cache_tag_mem_pkt_width(lce_sets_p, lce_assoc_p, ptag_width_p)
    , localparam dcache_lce_stat_mem_pkt_width_lp=
      `bp_cache_stat_mem_pkt_width(lce_sets_p, lce_assoc_p)
    )
   (
    input                                          clk_i
    , input                                        reset_i

    , input [cfg_bus_width_lp-1:0]                 cfg_bus_i
    , output [vaddr_width_p-1:0]                   cfg_npc_data_o
    , output [dword_width_p-1:0]                   cfg_irf_data_o
    , output [dword_width_p-1:0]                   cfg_csr_data_o
    , output [1:0]                                 cfg_priv_data_o

    // LCE-CCE interface
    , output [1:0][lce_cce_req_width_lp-1:0]       lce_req_o
    , output [1:0]                                 lce_req_v_o
    , input [1:0]                                  lce_req_ready_i

    , output [1:0][lce_cce_resp_width_lp-1:0]      lce_resp_o
    , output [1:0]                                 lce_resp_v_o
    , input [1:0]                                  lce_resp_ready_i

    // CCE-LCE interface
    , input [1:0][lce_cmd_width_lp-1:0]            lce_cmd_i
    , input [1:0]                                  lce_cmd_v_i
    , output [1:0]                                 lce_cmd_yumi_o

    , output [1:0][lce_cmd_width_lp-1:0]           lce_cmd_o
    , output [1:0]                                 lce_cmd_v_o
    , input [1:0]                                  lce_cmd_ready_i

    , input                                        timer_irq_i
    , input                                        software_irq_i
    , input                                        external_irq_i
    );

  `declare_bp_cfg_bus_s(vaddr_width_p, core_id_width_p, cce_id_width_p, lce_id_width_p, cce_pc_width_p, cce_instr_width_p);

  bp_cfg_bus_s cfg_bus_cast_i;
  assign cfg_bus_cast_i = cfg_bus_i;

  `declare_bp_cache_miss_s(cce_block_width_p, lce_assoc_p, paddr_width_p);

  logic [1:0][bp_cache_miss_width_lp-1:0] cache_miss_cast_lo;

  logic cache_miss_dcache_v_lo, cache_miss_icache_v_lo, cache_miss_dcache_ready_li, cache_miss_icache_ready_li;

  logic [1:0] lce_ready_lo;
  logic credits_full_lo, credits_empty_lo;

  logic [1:0] lr_hit_lo;
  logic [1:0] cache_v_lo;

  logic [1:0][cce_block_width_p-1:0] data_mem_data_lo;
  logic [1:0] store_lo;

  // response side - Interface from LCE
  logic [1:0][dcache_lce_data_mem_pkt_width_lp-1:0] data_mem_pkt_li;
  logic [1:0] data_mem_pkt_v_li;
  logic [1:0] data_mem_pkt_yumi_lo;

  logic [1:0][dcache_lce_tag_mem_pkt_width_lp-1:0] tag_mem_pkt_li;
  logic [1:0] tag_mem_pkt_v_li;
  logic [1:0] tag_mem_pkt_yumi_lo;

  logic [1:0][dcache_lce_stat_mem_pkt_width_lp-1:0] stat_mem_pkt_li;
  logic [1:0] stat_mem_pkt_v_li;
  logic [1:0] stat_mem_pkt_yumi_lo;

  bp_core_minimal
    #(.bp_params_p(bp_params_p))
  core_minimal
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     // Config info
     ,.cfg_bus_i(cfg_bus_i)
     ,.cfg_npc_data_o(cfg_npc_data_o)
     ,.cfg_irf_data_o(cfg_irf_data_o)
     ,.cfg_csr_data_o(cfg_csr_data_o)
     ,.cfg_priv_data_o(cfg_priv_data_o)

     // BP request side - Interface to LCE
     ,.lce_ready_i(lce_ready_lo)
     ,.credits_full_i(credits_full_lo)
     ,.credits_empty_i(credits_empty_lo)

     ,.lr_hit_o(lr_hit_lo)
     ,.cache_v_o(cache_v_lo)

     ,.data_mem_data_o(data_mem_data_lo)
     ,.store_o(store_lo)

     ,.cache_miss_o(cache_miss_cast_lo)
     ,.cache_miss_v_o({cache_miss_dcache_v_lo, cache_miss_icache_v_lo})
     ,.cache_miss_ready_i({cache_miss_dcache_ready_li, cache_miss_icache_ready_li})

     // response side - Interface from LCE
     ,.data_mem_pkt_i(data_mem_pkt_li)
     ,.data_mem_pkt_v_i(data_mem_pkt_v_li)
     ,.data_mem_pkt_yumi_o(data_mem_pkt_yumi_lo)

     ,.tag_mem_pkt_i(tag_mem_pkt_li)
     ,.tag_mem_pkt_v_i(tag_mem_pkt_v_li)
     ,.tag_mem_pkt_yumi_o(tag_mem_pkt_yumi_lo)

     ,.stat_mem_pkt_i(stat_mem_pkt_li)
     ,.stat_mem_pkt_v_i(stat_mem_pkt_v_li)
     ,.stat_mem_pkt_yumi_o(stat_mem_pkt_yumi_lo)

     ,.timer_irq_i(timer_irq_i)
     ,.software_irq_i(software_irq_i)
     ,.external_irq_i(external_irq_i)

     );

  bp_fe_lce
    #(.bp_params_p(bp_params_p))
  fe_lce
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.cfg_bus_i(cfg_bus_i)

     ,.ready_o(lce_ready_lo[0])
     ,.cache_miss_i(cache_miss_cast_lo[0])
     ,.cache_miss_v_i(cache_miss_icache_v_lo)
     ,.cache_miss_ready_o(cache_miss_icache_ready_li)

     ,.data_mem_data_i(data_mem_data_lo[0])
     ,.data_mem_pkt_o(data_mem_pkt_li[0])
     ,.data_mem_pkt_v_o(data_mem_pkt_v_li[0])
     ,.data_mem_pkt_yumi_i(data_mem_pkt_yumi_lo[0])

     ,.tag_mem_pkt_o(tag_mem_pkt_li[0])
     ,.tag_mem_pkt_v_o(tag_mem_pkt_v_li[0])
     ,.tag_mem_pkt_yumi_i(tag_mem_pkt_yumi_lo[0])

     ,.stat_mem_pkt_v_o(stat_mem_pkt_v_li[0])
     ,.stat_mem_pkt_o(stat_mem_pkt_li[0])
     ,.stat_mem_pkt_yumi_i(stat_mem_pkt_yumi_lo[0])

     ,.lce_req_o(lce_req_o[0])
     ,.lce_req_v_o(lce_req_v_o[0])
     ,.lce_req_ready_i(lce_req_ready_i[0])

     ,.lce_resp_o(lce_resp_o[0])
     ,.lce_resp_v_o(lce_resp_v_o[0])
     ,.lce_resp_ready_i(lce_resp_ready_i[0])

     ,.lce_cmd_i(lce_cmd_i[0])
     ,.lce_cmd_v_i(lce_cmd_v_i[0])
     ,.lce_cmd_yumi_o(lce_cmd_yumi_o[0])

     ,.lce_cmd_o(lce_cmd_o[0])
     ,.lce_cmd_v_o(lce_cmd_v_o[0])
     ,.lce_cmd_ready_i(lce_cmd_ready_i[0])
     );

  bp_be_dcache_lce
    #(.bp_params_p(bp_params_p))
  be_lce
    (.clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.lce_id_i(cfg_bus_cast_i.dcache_id)

    ,.ready_o(lce_ready_lo[1])
    ,.cache_miss_i(cache_miss_cast_lo[1])
    ,.cache_miss_v_i(cache_miss_dcache_v_lo)
    ,.cache_miss_ready_o(cache_miss_dcache_ready_li)

    // locking logic
    ,.lr_hit_tv_i(lr_hit_lo[1])
    ,.cache_v_o_i(cache_v_lo[1])

    ,.data_mem_data_i(data_mem_data_lo[1])
    ,.data_mem_pkt_o(data_mem_pkt_li[1])
    ,.data_mem_pkt_v_o(data_mem_pkt_v_li[1])
    ,.data_mem_pkt_yumi_i(data_mem_pkt_yumi_lo[1])

    ,.tag_mem_pkt_o(tag_mem_pkt_li[1])
    ,.tag_mem_pkt_v_o(tag_mem_pkt_v_li[1])
    ,.tag_mem_pkt_yumi_i(tag_mem_pkt_yumi_lo[1])

    ,.stat_mem_pkt_v_o(stat_mem_pkt_v_li[1])
    ,.stat_mem_pkt_o(stat_mem_pkt_li[1])
    ,.stat_mem_pkt_yumi_i(stat_mem_pkt_yumi_lo[1])

    ,.lce_req_o(lce_req_o[1])
    ,.lce_req_v_o(lce_req_v_o[1])
    ,.lce_req_ready_i(lce_req_ready_i[1])

    ,.lce_resp_o(lce_resp_o[1])
    ,.lce_resp_v_o(lce_resp_v_o[1])
    ,.lce_resp_ready_i(lce_resp_ready_i[1])

    ,.lce_cmd_i(lce_cmd_i[1])
    ,.lce_cmd_v_i(lce_cmd_v_i[1])
    ,.lce_cmd_yumi_o(lce_cmd_yumi_o[1])

    ,.lce_cmd_o(lce_cmd_o[1])
    ,.lce_cmd_v_o(lce_cmd_v_o[1])
    ,.lce_cmd_ready_i(lce_cmd_ready_i[1])

    ,.credits_full_o(credits_full_lo)
    ,.credits_empty_o(credits_empty_lo)
    );

endmodule

