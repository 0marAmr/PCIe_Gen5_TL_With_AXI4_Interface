/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project under supervision of
   Dr. Hosam Fahmy and Si vision company
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_w_handler
   DEPARTMENT :     W_HANDLER
   AUTHOR :         Omar Hafez
   AUTHOR’S EMAIL : eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-03-09              initial version
   -----------------------------------------------------------------------------
   KEYWORDS : PCIe, Transaction_Layer,
   -----------------------------------------------------------------------------
   PURPOSE : Transaction Layer Receiver block write handler top module, this block
   manages writing the received TLP in the RX buffers after checking that there are
   no errors in the TLP
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
`include "macros.vh"
module tl_rx_write_handler #(
    parameter   TYPE_DEC_WIDTH = 2,         // Posted - Non-Posted - Completion
                RCV_BUS_WIDTH = 8*`DW,
                FLAGS_WIDTH = 6,
                CTRL_BUS_WIDTH = 5,
                HDR_CREDS_WIDTH = 12,
                DATA_CREDS_WIDTH = 16,
                DATA_WIDTH = 10,
                ADDRESS_WIDTH = 64,
                REQUESTER_ID_WIDTH = 16,
                REQUESTER_TAG_WIDTH = 10,
                BARS_WIDTH = 32
) (
    //------ Global Signals ------//
    input   wire                                    i_clk,
    input   wire                                    i_n_rst,
    //------- RX FLow Control Interface -------//
    input   wire    [5:0]                           i_rx_fc_hdr_scale_bus,
    input   wire    [5:0]                           i_rx_fc_data_scale_bus,
    input   wire    [3*HDR_CREDS_WIDTH-1:0]         i_rx_fc_hdr_credits_received_bus,
    input   wire    [3*DATA_CREDS_WIDTH-1:0]        i_rx_fc_data_credits_received_bus,
    input   wire    [3*HDR_CREDS_WIDTH-1:0]         i_rx_fc_hdr_credits_allocated_bus,
    input   wire    [3*DATA_CREDS_WIDTH-1:0]        i_rx_fc_data_credits_allocated_bus,
    //------ Virtual Channels Interface -----//
    input   wire    [FLAGS_WIDTH-1:0]               i_vcs_w_full_flags,
    output  wire    [TYPE_DEC_WIDTH-1:0]            o_buffer_type,
    output  wire                                    o_w_valid,
    /*POSTED*/
    output  wire    [4*`DW-1:0]                     o_w_posted_hdr,
    output  wire    [RCV_BUS_WIDTH-1:0]             o_w_posted_data,
    output  wire    [CTRL_BUS_WIDTH-1:0]            o_w_posted_ctrl,
    /*NON_POSTED*/
    output  wire    [4*`DW-1:0]                     o_w_non_posted_hdr,
    output  wire    [RCV_BUS_WIDTH-1:0]             o_w_non_posted_data,
    output  wire    [CTRL_BUS_WIDTH-1:0]            o_w_non_posted_ctrl,
    /*COMPLETION*/
    output  wire    [4*`DW-1:0]                     o_w_completion_hdr,
    output  wire    [RCV_BUS_WIDTH-1:0]             o_w_completion_data,
    output  wire    [CTRL_BUS_WIDTH-1:0]            o_w_completion_ctrl,
    //------ Read Handler Interface ------//
    input   wire    [REQUESTER_ID_WIDTH-1:0]        i_device_requester_id,
    //------ Config Space Interface ------//
    input   wire                                    i_cfg_ecrc_chk_en,
    input   wire    [2:0]                           i_cfg_max_payload_size,
    input   wire    [6*BARS_WIDTH-1:0]              i_cfg_BARs,
    //------ TL_TX interface ------//
    input   wire    [REQUESTER_TAG_WIDTH-1:0]       i_tx_last_req_tag,
    input   wire    [3*HDR_CREDS_WIDTH-1:0]         i_tx_fc_hdr_credit_limit_bus,
    input   wire    [3*DATA_CREDS_WIDTH-1:0]        i_tx_fc_data_credit_limit_bus,
    input   wire    [5:0]                           i_tx_fc_hdr_scale_bus,
    input   wire    [5:0]                           i_tx_fc_data_scale_bus,
    //------ DLL-RX TLP Interface ------//
    input   wire                                    i_dll_rcv_sop,
    input   wire    [RCV_BUS_WIDTH-1:0]             i_dll_rcv_tlp,
    input   wire                                    i_dll_rcv_eop,
    input   wire    [2:0]                           i_dll_last_byte,
    output  wire                                    o_tl_tlp_rcv_blk,
    //------ DLL-RX Flow Control Interface ------//
    input   wire    [1:0]                           i_dll_typ,
    input   wire    [HDR_CREDS_WIDTH-1:0]           i_dll_hdr_creds,
    input   wire    [DATA_CREDS_WIDTH-1:0]          i_dll_data_creds,
    input   wire    [1:0]                           i_dll_hdr_scale,
    input   wire    [1:0]                           i_dll_data_scale,
    input   wire                                    i_dll_valid
);

    localparam  VALID_DATA      = 3;
    localparam  VCn_FLAGS_NUM   = 6;
    localparam  BUFFER_IN_DW_WIDTH=10;
    localparam  TRAS_TYPE_WIDTH = 3;
    localparam  HDR_FIELDS_WIDTH  = 118;

     // ----- TLP Processing <=> Error Check -----//
    wire                            rcv_error;
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
        .CTRL_BUS_WIDTH(CTRL_BUS_WIDTH),
        .RCV_BUS_WIDTH(RCV_BUS_WIDTH)
    ) u_tlp_processing (
        .i_clk(i_clk),
        .i_n_rst(i_n_rst),
        // ----- DLL Interface -----//
        .i_dll_rcv_sop(i_dll_rcv_sop),
        .i_dll_rcv_tlp(i_dll_rcv_tlp),
        .o_tlp_rcv_blk(o_tl_tlp_rcv_blk),
        // ----- Error Check Interface -----//
        .i_rcv_error(0), // rcv_error
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
        .o_w_completion_ctrl(o_w_completion_ctrl)
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
        .i_data_in(i_dll_rcv_tlp)
    );

     tl_rx_error_check #(
        .DLL_HDR_CREDS_WIDTH(HDR_CREDS_WIDTH),
        .DLL_DATA_CREDS_WIDTH(DATA_CREDS_WIDTH),
        .RCV_HDR_CREDS_WIDTH(HDR_CREDS_WIDTH),
        .RCV_DATA_CREDS_WIDTH(DATA_CREDS_WIDTH),
        .FC_HDR_CREDS_WIDTH(HDR_CREDS_WIDTH),
        .FC_DATA_CREDS_WIDTH(DATA_CREDS_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDRESS_WIDTH(ADDRESS_WIDTH),
        .REQUESTER_ID_WIDTH(REQUESTER_ID_WIDTH),
        .REQUESTER_TAG_WIDTH(REQUESTER_TAG_WIDTH)
    ) u_error_check (
        .clk(i_clk),
        .rst(i_n_rst),
        //-------- TLP Processing Interface ------//
        .i_transaction_type(transaction_type), /*MEMORY - IO - CONFIGURATION - COMPLETION - MESSAGE*/
        .i_buffer_type(o_buffer_type),
        .i_write_n_read(write_n_read),
        .i_address_type(address_type),
        .i_last_dw(last_dw),
        .i_rcv_done(rcv_done),
        .i_error_check_hdr_fields(error_check_hdr_fields),
        .i_error_check_en(error_check_en),
        .o_error_check(rcv_error),
        // ------ ECRC Interface ------//
        .i_ecrc_error_check(ecrc_error),
        //-------- RX FLow Control Interface ------//
        .i_rx_fc_hdr_scale_bus(i_rx_fc_hdr_scale_bus),
        .i_rx_fc_data_scale_bus(i_rx_fc_data_scale_bus),
        .i_rx_fc_hdr_credits_received_bus(i_rx_fc_hdr_credits_received_bus),
        .i_rx_fc_data_credits_received_bus(i_rx_fc_data_credits_received_bus),
        .i_rx_fc_hdr_credits_allocated_bus(i_rx_fc_hdr_credits_allocated_bus),
        .i_rx_fc_data_credits_allocated_bus(i_rx_fc_data_credits_allocated_bus),
        //-------- TL TX Interface ------//
        .tx_last_req_tag(i_tx_last_req_tag),
        .i_tx_fc_hdr_credit_limit_bus(i_tx_fc_hdr_credit_limit_bus),
        .i_tx_fc_data_credit_limit_bus(i_tx_fc_data_credit_limit_bus),
        .i_tx_fc_hdr_scale_bus(i_tx_fc_hdr_scale_bus),
        .i_tx_fc_data_scale_bus(i_tx_fc_data_scale_bus),
        //-------- Data Link Layer Interface ------//
        .i_dll_data_creds(i_dll_data_creds),
        .i_dll_hdr_creds(i_dll_hdr_creds),
        .i_dll_data_scale(i_dll_data_scale),
        .i_dll_hdr_scale(i_dll_hdr_scale),
        .i_dll_valid(i_dll_valid),
        .i_dll_typ(i_dll_typ),
        .i_dll_eop(i_dll_rcv_eop),
        .i_dll_last_byte(i_dll_last_byte),
        // ------ Configuration Space Interface ------//
        .i_max_payload_config(i_cfg_max_payload_size),
        .i_ecrc_check_en_config(i_cfg_ecrc_chk_en),
        .i_BARSs(i_cfg_BARs),
        //------ Read Handler Interface ------//
        .i_device_requester_id(i_device_requester_id)
    );

endmodule
