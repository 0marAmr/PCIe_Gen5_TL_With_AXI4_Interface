/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_w_handler
   DEPARTMENT :     Write Handler
   AUTHOR :         Reem Mohamed - Omar Hafez
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com - eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-03-09              initial version
   -----------------------------------------------------------------------------
   PURPOSE : Transaction Layer Receiver block write handler top module, this block
   manages writing the received TLP in the RX buffers after checking that there are
   no errors in the TLP
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
module tl_rx_write_handler #(
    parameter   DW = 32,
                TYPE_DEC_WIDTH = 2,         // Posted - Non-Posted - Completion
                RCV_BUS_WIDTH = 8*DW,
                P_DATA_IP_WIDTH = 8*DW,
                NP_DATA_IP_WIDTH = 1*DW,
                CPL_DATA_IP_WIDTH = 8*DW,
                FLAGS_WIDTH = 6,
                W_CTRL_BUS_WIDTH = 6,
                HDR_FIELD_SIZE = 8,
                DATA_FIELD_SIZE = 12,
                PAYLOAD_LENGTH = 10,
                ADDRESS_WIDTH = 64,
                REQUESTER_ID_WIDTH = 16,
                REQUESTER_TAG_WIDTH = 10,
                BARS_WIDTH = 32,
                REQ_HDR_SIZE = 4*DW,
                CPL_HDR_SIZE = 3*DW,
                SCALE_BUS_WIDTH = 6
) (
    //------ Global Signals ------//
    input   wire                            i_clk,
    input   wire                            i_n_rst,
    //------- RX FLow Control Interface -------//
    // input   wire    [5:0]                   i_rx_fc_hdr_scale_bus,
    // input   wire    [5:0]                   i_rx_fc_data_scale_bus,
    input   wire    [3*HDR_FIELD_SIZE-1:0]  i_rx_fc_hdr_credits_received_bus,
    input   wire    [3*DATA_FIELD_SIZE-1:0] i_rx_fc_data_credits_received_bus,
    input   wire    [3*HDR_FIELD_SIZE-1:0]  i_rx_fc_hdr_credits_allocated_bus,
    input   wire    [3*DATA_FIELD_SIZE-1:0] i_rx_fc_data_credits_allocated_bus,
    output  wire                            o_cr_hdr_inc,
    output  wire                            o_cr_data_inc,
    output  wire    [PAYLOAD_LENGTH-1:0]    o_payload_length,
    //------ Virtual Channels Interface -----//
    input   wire    [FLAGS_WIDTH-1:0]       i_vcs_w_full_flags,
    output  wire    [TYPE_DEC_WIDTH-1:0]    o_buffer_type,
    output  wire                            o_w_valid,
    /*POSTED*/
    output  wire    [REQ_HDR_SIZE-1:0]      o_w_posted_hdr,
    output  wire    [P_DATA_IP_WIDTH-1:0]   o_w_posted_data,
    output  wire    [W_CTRL_BUS_WIDTH-1:0]  o_w_posted_ctrl,
    /*NON_POSTED*/
    output  wire    [REQ_HDR_SIZE-1:0]      o_w_non_posted_hdr,
    output  wire    [NP_DATA_IP_WIDTH-1:0]  o_w_non_posted_data,
    output  wire    [W_CTRL_BUS_WIDTH-1:0]  o_w_non_posted_ctrl,
    /*COMPLETION*/
    output  wire    [CPL_HDR_SIZE-1:0]      o_w_completion_hdr,
    output  wire    [CPL_DATA_IP_WIDTH-1:0] o_w_completion_data,
    output  wire    [W_CTRL_BUS_WIDTH-1:0]  o_w_completion_ctrl,
    //------ Read Handler Interface ------//
    input   wire    [REQUESTER_ID_WIDTH-1:0]    i_device_id,
    //------ Config Space Interface ------//
    input   wire                                i_cfg_ecrc_chk_en,
    input   wire                                i_cfg_memory_space_en,
    input   wire                                i_cfg_io_space_en,
    input   wire    [2:0]                       i_cfg_max_payload_size,
    input   wire    [6*BARS_WIDTH-1:0]          i_cfg_BARs,
    //------ Error Handler Interface ------//
    output  wire    [2:0]                       o_error_type,
    //------ TL_TX interface ------//
    input   wire    [REQUESTER_TAG_WIDTH-1:0]   i_tx_last_req_tag,
    input   wire    [3*HDR_FIELD_SIZE-1:0]      i_tx_fc_hdr_credit_limit_bus,
    input   wire    [3*DATA_FIELD_SIZE-1:0]     i_tx_fc_data_credit_limit_bus,
    input   wire    [SCALE_BUS_WIDTH-1:0]       i_tx_fc_hdr_scale_bus,
    input   wire    [SCALE_BUS_WIDTH-1:0]       i_tx_fc_data_scale_bus,
    //------ DLL-RX TLP Interface ------//
    input   wire                                i_dll_rx_sop,
    input   wire    [RCV_BUS_WIDTH-1:0]         i_dll_rx_tlp,
    input   wire                                i_dll_rx_eop,
    input   wire    [2:0]                       i_dll_rx_last_dw,
    output  wire                                o_dll_rx_tlp_discard,
    //------ DLL-RX Flow Control Interface ------//
    input   wire    [1:0]                       i_dll_rx_fc_typ,
    input   wire    [HDR_FIELD_SIZE-1:0]        i_dll_rx_fc_hdr_creds,
    input   wire    [DATA_FIELD_SIZE-1:0]       i_dll_rx_fc_data_creds,
    input   wire    [1:0]                       i_dll_rx_fc_hdr_scale,
    input   wire    [1:0]                       i_dll_rx_fc_data_scale,
    input   wire                                i_dll_rx_fc_valid
);

    localparam  VALID_DATA      = 3;
    localparam  VCn_FLAGS_NUM   = 6;
    localparam  BUFFER_IN_DW_WIDTH=10;
    localparam  TRAS_TYPE_WIDTH = 3;
    localparam  HDR_FIELDS_WIDTH  = 118;

     // ----- TLP Processing <=> Error Check -----//
    wire                            error_check;
    wire    [TRAS_TYPE_WIDTH-1:0]   transaction_type;
    wire                            write_n_read;
    wire                            address_type;
    wire    [2:0]                   last_dw;
    wire                            rcv_done;
    wire    [HDR_FIELDS_WIDTH-1:0]  error_check_hdr_fields;
    wire                            error_check_en;
    // ----- TLP Processing <=> ECRC Check -----//
    wire                            ecrc_en;
    wire                            ecrc_done;
    wire                            ecrc_n_clr;
    wire                            hdr_write_flag;
    wire [VALID_DATA-1:0]           ecrc_input_length;
    // ----- Error Check <=> ECRC Check -----//
    wire                            ecrc_error;

    /*Virtual Channels Flags*/
    wire [VCn_FLAGS_NUM-1:0]    vc0_w_full_flags = i_vcs_w_full_flags[VCn_FLAGS_NUM-1:0];
    // wire [VCn_FLAGS_NUM-1:0] vc1_w_full_flags = i_vcs_w_full_flags[2*VCn_FLAGS_NUM-1:VCn_FLAGS_NUM];

    tl_rx_write_handler_tlp_processing #(
        .TYPE_DEC_WIDTH(TYPE_DEC_WIDTH),
        .FLAGS_WIDTH(FLAGS_WIDTH),
        .W_CTRL_BUS_WIDTH(W_CTRL_BUS_WIDTH),
        .RCV_BUS_WIDTH(RCV_BUS_WIDTH)
    ) u_tlp_processing (
        .i_clk(i_clk),
        .i_n_rst(i_n_rst),
        // ----- DLL Interface -----//
        .i_dll_rx_sop(i_dll_rx_sop),
        .i_dll_rx_tlp(i_dll_rx_tlp),
        // ----- Error Check Interface -----//
        .i_rcv_error(error_check),
        .o_transaction_type(transaction_type),
        .o_buffer_type(o_buffer_type),
        .o_write_n_read(write_n_read),
        .o_address_type(address_type),
        .o_last_dw(last_dw),
        .o_rcv_done(rcv_done),
        .o_error_check_hdr_fields(error_check_hdr_fields),
        .o_error_check_en(error_check_en),
        // ----- ECRC Check Interface -----//
        .o_ecrc_en(ecrc_en),
        .o_ecrc_done(ecrc_done),
        .o_ecrc_n_clr(ecrc_n_clr),
        .o_ecrc_input_length(ecrc_input_length),
        .o_hdr_write_flag(hdr_write_flag),
        // ----- Virtual Channels Interface-----//
        .i_vc0_w_full_flags(vc0_w_full_flags),
        .o_w_valid(o_w_valid),
        /*POSTED*/
        .o_w_posted_hdr(o_w_posted_hdr),
        .o_w_posted_data(o_w_posted_data),
        .o_w_posted_ctrl(o_w_posted_ctrl),
        /*NON_POSTED*/
        .o_w_non_posted_hdr(o_w_non_posted_hdr),
        .o_w_non_posted_data(o_w_non_posted_data),
        .o_w_non_posted_ctrl(o_w_non_posted_ctrl),
        /*COMPLETION*/
        .o_w_completion_hdr(o_w_completion_hdr),
        .o_w_completion_data(o_w_completion_data),
        .o_w_completion_ctrl(o_w_completion_ctrl),
        //-------- RX FLow Control Interface ------//
        .o_cr_hdr_inc(o_cr_hdr_inc),
		.o_cr_data_inc(o_cr_data_inc),
		.o_payload_length(o_payload_length)
    );

    tl_rx_write_handler_ecrc #(
        .DATA_WIDTH(RCV_BUS_WIDTH)  // Set appropriate value for DATA_WIDTH
    ) u_ecrc (
        .i_clk(i_clk),
        .i_n_rst(i_n_rst),
        // ----- TLP Processing Block Interface -----//
        .i_n_clr(ecrc_n_clr),
        .i_en(ecrc_en),
        .i_done(ecrc_done),
        .i_hdr_blk_EP(hdr_write_flag),
        .i_length(ecrc_input_length),
        // ----- Config Space Interface -----//
        .i_cfg_ecrc_chk_en(i_cfg_ecrc_chk_en),
        // ----- ERROR Block Interface -----//
        .o_ecrc_error(ecrc_error),
        // ----- DLL Interface -----//
        .i_data_in(i_dll_rx_tlp)
    );

     tl_rx_error_check #(
        .HDR_FIELD_SIZE(HDR_FIELD_SIZE),
        .DATA_FIELD_SIZE(DATA_FIELD_SIZE),
        .FC_HDR_CREDS_WIDTH(HDR_FIELD_SIZE),
        .FC_DATA_CREDS_WIDTH(DATA_FIELD_SIZE),
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH),
        .ADDRESS_WIDTH(ADDRESS_WIDTH),
        .REQUESTER_ID_WIDTH(REQUESTER_ID_WIDTH),
        .REQUESTER_TAG_WIDTH(REQUESTER_TAG_WIDTH)
    ) u_error_check (
        .i_clk(i_clk),
        .i_n_rst(i_n_rst),
        //-------- TLP Processing Interface ------//
        .i_transaction_type(transaction_type), /*MEMORY - IO - CONFIGURATION - COMPLETION - MESSAGE*/
        .i_buffer_type(o_buffer_type),
        .i_write_n_read(write_n_read),
        .i_address_type(address_type),
        .i_last_dw(last_dw),
        .i_rcv_done(rcv_done),
        .i_error_check_hdr_fields(error_check_hdr_fields),
        .i_error_check_en(error_check_en),
        .o_error_check(error_check),
        // ------ ECRC Interface ------//
        .i_ecrc_error_check(ecrc_error),
        //-------- RX FLow Control Interface ------//
        // .i_rx_fc_hdr_scale_bus(i_rx_fc_hdr_scale_bus),
        // .i_rx_fc_data_scale_bus(i_rx_fc_data_scale_bus),
        .i_rx_fc_hdr_credits_received_bus(i_rx_fc_hdr_credits_received_bus),
        .i_rx_fc_data_credits_received_bus(i_rx_fc_data_credits_received_bus),
        .i_rx_fc_hdr_credits_allocated_bus(i_rx_fc_hdr_credits_allocated_bus),
        .i_rx_fc_data_credits_allocated_bus(i_rx_fc_data_credits_allocated_bus),
        //-------- TL TX Interface ------//
        .i_tx_last_req_tag(i_tx_last_req_tag),
        .i_tx_fc_hdr_credit_limit_bus(i_tx_fc_hdr_credit_limit_bus),
        .i_tx_fc_data_credit_limit_bus(i_tx_fc_data_credit_limit_bus),
        .i_tx_fc_hdr_scale_bus(i_tx_fc_hdr_scale_bus),
        .i_tx_fc_data_scale_bus(i_tx_fc_data_scale_bus),
        //-------- DLL RX Interface ------//
        /*DLL-RX TLP*/
        .i_dll_rx_sop(i_dll_rx_sop),
        .i_dll_rx_eop(i_dll_rx_eop),
        .i_dll_rx_last_dw(i_dll_rx_last_dw),
        .o_dll_rx_tlp_discard(o_dll_rx_tlp_discard),
        /*DLL-RX FC*/
        .i_dll_rx_fc_typ(i_dll_rx_fc_typ),
        .i_dll_rx_fc_valid(i_dll_rx_fc_valid),
        .i_dll_rx_fc_hdr_scale(i_dll_rx_fc_hdr_scale),
        .i_dll_rx_fc_hdr_creds(i_dll_rx_fc_hdr_creds),
        .i_dll_rx_fc_data_scale(i_dll_rx_fc_data_scale),
        .i_dll_rx_fc_data_creds(i_dll_rx_fc_data_creds),
        // ------ Configuration Space Interface ------//
        .i_ecrc_check_en_config(i_cfg_ecrc_chk_en),
        .i_cfg_memory_space_en(i_cfg_memory_space_en),
        .i_cfg_io_space_en(i_cfg_io_space_en),
        .i_max_payload_config(i_cfg_max_payload_size),
        .i_BARSs(i_cfg_BARs),
        //------ Read Handler Interface ------//
        .i_device_id(i_device_id),
        //------ Error Handler Interface ------//
        .o_error_type(o_error_type)
    );

endmodule
