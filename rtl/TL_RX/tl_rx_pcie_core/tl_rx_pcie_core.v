/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project under supervision of
   Dr. Hosam Fahmy and Si vision company
   -----------------------------------------------------------------------------
   FILE NAME :      VC_BUFFER_CONTROL
   DEPARTMENT :     VC
   AUTHOR :         Omar Hafez
   AUTHOR’S EMAIL : eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-03-10              initial version
   -----------------------------------------------------------------------------
   KEYWORDS : PCIe, Transaction_Layer,
   -----------------------------------------------------------------------------
   PURPOSE :
   -----------------------------------------------------------------------------
   PARAMETERS
   PARAM NAME               : RANGE  : DESCRIPTION                       : DEFAULT   : UNITS
   DECODING_OUTPUT_WIDTH    :   2    : Posted - Nonposted - Completion   :   2       :   n/a
   -----------------------------------------------------------------------------
   REUSE ISSUES
   Reset Strategy   : n/a
   Clock Domains    : n/a
   Critical Timing  : n/a
   Test Features    :
   Asynchronous I/F : n/a
   Scan Methodology : n/a
   Instantiations   :
   Synthesizable    : Y
   Other            :
   -FHDR------------------------------------------------------------------------*/
module tl_rx_pcie_core #(
     parameter      DW = 32,
                    BEAT_SIZE = 32*DW,
                    REQ_HDR_SIZE = 4*DW,
                    CPL_HDR_SIZE = 4*DW,
                    RCV_BUS_WIDTH  = 8*DW,
                    FLAGS_WIDTH    = 6,
                    TYPE_DEC_WIDTH = 2,
                    W_CTRL_BUS_WIDTH = 5,
                    R_CTRL_BUS_WIDTH = 5,
                    HDR_CREDS_WIDTH = 12,
                    DATA_CREDS_WIDTH = 16,
                    BARS_WIDTH = 32,
                    REQUESTER_TAG_WIDTH = 10
) (
     //------ Global Signals ------//
     input     wire                               i_clk,
     input     wire                               i_n_rst,
     //------ Config Space Interface ------//
     input   wire                                 i_cfg_ecrc_chk_en,
     input   wire    [2:0]                        i_cfg_max_payload_size,
     input   wire    [6*BARS_WIDTH-1:0]           i_cfg_BARs,
     //------ TL_TX interface ------//
     input   wire    [REQUESTER_TAG_WIDTH-1:0]    i_tx_last_req_tag,
     input   wire    [3*HDR_CREDS_WIDTH-1:0]      i_tx_fc_hdr_credit_limit_bus,
     input   wire    [3*DATA_CREDS_WIDTH-1:0]     i_tx_fc_data_credit_limit_bus,
     input   wire    [5:0]                        i_tx_fc_hdr_scale_bus,
     input   wire    [5:0]                        i_tx_fc_data_scale_bus,
     //------- Data Link Layer Interface -------//
     input   wire                                 i_dll_rcv_sop,
     input   wire    [RCV_BUS_WIDTH-1:0]          i_dll_rcv_tlp,
     input   wire                                 i_dll_rcv_eop,
     input   wire    [2:0]                        i_dll_last_byte,
     output  wire                                 o_tl_tlp_rcv_blk,
     //------ DLL-RX Flow Control Interface ------//
     input   wire    [1:0]                        i_dll_typ,
     input   wire    [HDR_CREDS_WIDTH-1:0]        i_dll_hdr_creds,
     input   wire    [DATA_CREDS_WIDTH-1:0]       i_dll_data_creds,
     input   wire    [1:0]                        i_dll_hdr_scale,
     input   wire    [1:0]                        i_dll_data_scale,
     input   wire                                 i_dll_valid,
     //------- AXI Slave Interface -------//
     input     wire                               i_slave_ready,
     output    wire    [BEAT_SIZE-1:0]            o_vc_cpl_data,
     output    wire    [CPL_HDR_SIZE-1:0]         o_vc_cpl_hdr,
     output    wire                               o_slave_cpl_vaild,
     output    wire    [4:0]                      o_slave_cpl_valid_data

);
     
     localparam PAYLOAD_LENGTH = 10;
     localparam REQUESTER_ID_WIDTH = 16;

     //------- VC0 Interface ------//
     wire      [FLAGS_WIDTH-1:0]             vc0_w_full_flags;
     wire      [FLAGS_WIDTH-1:0]             vc0_r_empty_flags;
     /*POSTED*/         
     wire      [W_CTRL_BUS_WIDTH-1:0]        vc0_w_posted_ctrl;
     wire      [REQ_HDR_SIZE-1:0]            vc0_w_posted_hdr;
     wire      [RCV_BUS_WIDTH-1:0]           vc0_w_posted_data;
     // wire     [R_CTRL_BUS_WIDTH-1:0] vc0_r_posted_ctrl;
     wire      [REQ_HDR_SIZE-1:0]            vc0_r_posted_hdr;
     wire      [BEAT_SIZE-1:0]               vc0_r_posted_data;
     /*NON_POSTED*/
     wire      [W_CTRL_BUS_WIDTH-1:0]        vc0_w_non_posted_ctrl;
     wire      [REQ_HDR_SIZE-1:0]            vc0_w_non_posted_hdr;
     wire      [RCV_BUS_WIDTH-1:0]           vc0_w_non_posted_data;
     // wire     [R_CTRL_BUS_WIDTH-1:0] vc0_r_non_posted_ctrl;
     wire      [REQ_HDR_SIZE-1:0]            vc0_r_non_posted_hdr;
     wire      [BEAT_SIZE-1:0]               vc0_r_non_posted_data;
     /*COMPLETION*/      
     wire      [W_CTRL_BUS_WIDTH-1:0]        vc0_w_completion_ctrl;
     wire      [REQ_HDR_SIZE-1:0]            vc0_w_completion_hdr;
     wire      [RCV_BUS_WIDTH-1:0]           vc0_w_completion_data;
     wire      [R_CTRL_BUS_WIDTH-1:0]        vc0_r_completion_ctrl;
     wire      [REQ_HDR_SIZE-1:0]            vc0_r_completion_hdr;
     wire      [BEAT_SIZE-1:0]               vc0_r_completion_data;
     //------ TC/VC Mapping Interface ------//
     wire      [TYPE_DEC_WIDTH-1:0]          buffer_type;
     wire                                    w_valid;
     //------ Arbiter Interface ------//
     wire      [R_CTRL_BUS_WIDTH-1:0]        vcn_r_completion_ctrl;
     wire      [FLAGS_WIDTH-1:0]             vcn_r_empty_flags;
     wire                                    vcn_cpl_fmt_data_bit;
     wire      [PAYLOAD_LENGTH-1:0]          vcn_cpl_length_field;
     //------- RX Flow Control <=> Write Handler ------//
     wire      [5:0]                         rx_fc_hdr_scale_bus;    
     wire      [5:0]                         rx_fc_data_scale_bus;
     wire      [3*HDR_CREDS_WIDTH-1:0]       rx_fc_hdr_credits_received_bus;
     wire      [3*DATA_CREDS_WIDTH-1:0]      rx_fc_data_credits_received_bus;
     wire      [3*HDR_CREDS_WIDTH-1:0]       rx_fc_hdr_credits_allocated_bus;
     wire      [3*DATA_CREDS_WIDTH-1:0]      rx_fc_data_credits_allocated_bus;
     //------ Read Handler Interface ------//
     wire      [REQUESTER_ID_WIDTH-1:0]      device_requester_id; 


     tl_rx_vc #(
        .W_CTRL_BUS_WIDTH(W_CTRL_BUS_WIDTH),
        .R_CTRL_BUS_WIDTH(R_CTRL_BUS_WIDTH)
     ) u_vc0 (
          //------ Global Signals ------//
          .i_clk(i_clk),
          .i_n_rst(i_n_rst),
          //------ Flags Output ------//
          .o_vc_w_full_flags(vc0_w_full_flags),
          .o_vc_r_empty_flags(vc0_r_empty_flags),
          //------ Posted Buffers Interface ------//
          .i_w_posted_ctrl(vc0_w_posted_ctrl),
          .i_w_posted_hdr(vc0_w_posted_hdr),
          .i_w_posted_data(vc0_w_posted_data),
          .i_r_posted_ctrl(0), // vc0_r_posted_ctrl
          .o_r_posted_hdr(vc0_r_posted_hdr),
          .o_r_posted_data(vc0_r_posted_data),
          //------ Non Posted Buffers Interface ------//
          .i_w_non_posted_ctrl(vc0_w_non_posted_ctrl),
          .i_w_non_posted_hdr(vc0_w_non_posted_hdr),
          .i_w_non_posted_data(vc0_w_non_posted_data),
          .i_r_non_posted_ctrl(0), //vc0_r_non_posted_ctrl
          .o_r_non_posted_hdr(vc0_r_non_posted_hdr),
          .o_r_non_posted_data(vc0_r_non_posted_data),
          //------ Completion Buffers Interface ------//
          .i_w_completion_ctrl(vc0_w_completion_ctrl),
          .i_w_completion_hdr(vc0_w_completion_hdr),
          .i_w_completion_data(vc0_w_completion_data),
          .i_r_completion_ctrl(vc0_r_completion_ctrl),
          .o_r_completion_hdr(vc0_r_completion_hdr),
          .o_r_completion_data(vc0_r_completion_data)
     );

     wire [FLAGS_WIDTH-1:0] vcs_w_full_flags = vc0_w_full_flags; // add more VCs

     tl_rx_write_handler #(
          .TYPE_DEC_WIDTH(TYPE_DEC_WIDTH),
          .RCV_BUS_WIDTH(RCV_BUS_WIDTH),
          .FLAGS_WIDTH(FLAGS_WIDTH)
     ) u_write_handler (
          .i_clk(i_clk),
          .i_n_rst(i_n_rst),
          //------- RX FLow Control Interface -------//
          .i_rx_fc_hdr_scale_bus(rx_fc_hdr_scale_bus),
          .i_rx_fc_data_scale_bus(rx_fc_data_scale_bus),
          .i_rx_fc_hdr_credits_received_bus(rx_fc_hdr_credits_received_bus),
          .i_rx_fc_data_credits_received_bus(rx_fc_data_credits_received_bus),
          .i_rx_fc_hdr_credits_allocated_bus(rx_fc_hdr_credits_allocated_bus),
          .i_rx_fc_data_credits_allocated_bus(rx_fc_data_credits_allocated_bus),
          //------ Virtual Channels Interface -----//
          .i_vcs_w_full_flags(vcs_w_full_flags),
          .o_buffer_type(buffer_type),
          .o_w_valid(w_valid),
          /*POSTED*/
          .o_w_posted_hdr(vc0_w_posted_hdr),
          .o_w_posted_data(vc0_w_posted_data),
          .o_w_posted_ctrl(vc0_w_posted_ctrl),
          /*NON_POSTED*/
          .o_w_non_posted_hdr(vc0_w_non_posted_hdr),
          .o_w_non_posted_data(vc0_w_non_posted_data),
          .o_w_non_posted_ctrl(vc0_w_non_posted_ctrl),
          /*COMPLETION*/
          .o_w_completion_hdr(vc0_w_completion_hdr),
          .o_w_completion_data(vc0_w_completion_data),
          .o_w_completion_ctrl(vc0_w_completion_ctrl),
          //------ Read Handler Interface ------//
          .i_device_requester_id(device_requester_id),
          //------ Config Space Interface ------//
          .i_cfg_ecrc_chk_en(i_cfg_ecrc_chk_en),
          .i_cfg_max_payload_size(i_cfg_max_payload_size),
          .i_cfg_BARs(i_cfg_BARs),
          //------ TL_TX interface ------//
          .i_tx_last_req_tag(i_tx_last_req_tag),
          .i_tx_fc_hdr_credit_limit_bus(i_tx_fc_hdr_credit_limit_bus),
          .i_tx_fc_data_credit_limit_bus(i_tx_fc_data_credit_limit_bus),
          .i_tx_fc_hdr_scale_bus(i_tx_fc_hdr_scale_bus),
          .i_tx_fc_data_scale_bus(i_tx_fc_data_scale_bus),
          //------ DLL-RX TLP Interface ------//
          .i_dll_rcv_sop(i_dll_rcv_sop),
          .i_dll_rcv_tlp(i_dll_rcv_tlp),
          .i_dll_rcv_eop(i_dll_rcv_eop),
          .i_dll_last_byte(i_dll_last_byte),
          .o_tl_tlp_rcv_blk(o_tl_tlp_rcv_blk),
          //------ DLL-RX Flow Control Interface ------//
          .i_dll_typ(i_dll_typ),
          .i_dll_hdr_creds(i_dll_hdr_creds),
          .i_dll_data_creds(i_dll_data_creds),
          .i_dll_hdr_scale(i_dll_hdr_scale),
          .i_dll_data_scale(i_dll_data_scale),
          .i_dll_valid(i_dll_valid)
     );

     tl_rx_read_handler #(
        .R_CTRL_BUS_WIDTH(R_CTRL_BUS_WIDTH)
     ) u_read_handler (
          .i_clk(i_clk),
          .i_n_rst(i_n_rst),
          .i_vcn_r_empty_flags(vcn_r_empty_flags),
          //------ Completion Buffers Interface ------//
          .i_cpl_fmt_data_bit(vcn_cpl_fmt_data_bit),
          .i_cpl_length_field(vcn_cpl_length_field),
          .o_r_completion_ctrl(vcn_r_completion_ctrl),
          //------ AXI Salve Completion Interface ------//
          .i_slave_ready(i_slave_ready),
          .o_slave_cpl_vaild(o_slave_cpl_vaild),
          .o_slave_cpl_valid_data(o_slave_cpl_valid_data)
     );


     /*RX VC Arbiter (Future work)*/
     assign o_vc_cpl_hdr = vc0_r_completion_hdr;
     assign o_vc_cpl_data = vc0_r_completion_data ;
     assign vc0_r_completion_ctrl = vcn_r_completion_ctrl;
     assign vcn_r_empty_flags = vc0_r_empty_flags;
     assign vcn_cpl_fmt_data_bit = vc0_r_completion_hdr[126];
     assign vcn_cpl_length_field = vc0_r_completion_hdr[105:97];

endmodule
       