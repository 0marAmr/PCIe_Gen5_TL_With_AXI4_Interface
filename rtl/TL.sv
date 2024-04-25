module TL #(
     parameter DW = 32,
               BEAT_SIZE = 32*DW,
               REQ_HDR_SIZE = 4*DW,
               CPL_HDR_SIZE = 3*DW,
               RCV_BUS_WIDTH  = 8*DW,
               HDR_CREDS_WIDTH = 12,
               DATA_CREDS_WIDTH = 16,
               VALID_DATA_WIDTH = 5,
               ADDR_WIDTH = 62,
               BARS_WIDTH = 32
) (
     //------ Global Signals ------//
     input  logic                         i_clk,
     input  logic                         i_n_rst,
     //------ Config Space Interface ------//
     input  logic                         i_cfg_ecrc_chk_en,
     input  logic [2:0]                   i_cfg_max_payload_size,
     input  logic [6*BARS_WIDTH-1:0]      i_cfg_BARs,
     //------- Data Link Layer Interface -------//
     input  logic                         i_dll_rcv_sop,
     input  logic [RCV_BUS_WIDTH-1:0]     i_dll_rcv_tlp,
     input  logic                         i_dll_rcv_eop,
     input  logic [2:0]                   i_dll_last_dw,
     output logic                         o_tl_tlp_rcv_blk,
     //------ DLL-RX Flow Control Interface ------//
     input  logic [1:0]                   i_dll_typ,
     input  logic [HDR_CREDS_WIDTH-1:0]   i_dll_hdr_creds,
     input  logic [DATA_CREDS_WIDTH-1:0]  i_dll_data_creds,
     input  logic [1:0]                   i_dll_hdr_scale,
     input  logic [1:0]                   i_dll_data_scale,
     input  logic                         i_dll_valid,
     //------- AXI Master Bridge Interface -------//
     output logic [1:0]                   o_master_req_type,   /*Memory Read - Memory Write - IO Read - IO Write*/
     output logic                         o_master_address_type,
     output logic [2:0]                   o_master_req_traffic_class,
     output logic [15:0]                  o_master_requester_id,
     output logic [9:0]                   o_master_req_tag,
     output logic [9:0]                   o_master_req_length,
     output logic [3:0]                   o_master_req_first_byte_enable,
     output logic [3:0]                   o_master_req_last_byte_enable,
     output logic [ADDR_WIDTH-1:0]        o_master_req_address,
     output logic                         o_master_req_increment,    
     output logic                         o_master_req_valid,    
     output logic                         o_master_last,         // indicates that the current beat is the last one in a transaction 
     output logic [VALID_DATA_WIDTH-1:0]  o_master_valid_data,   // encoding for valid Double Words of data driven on the bus (5'b00000 -> 1 DW valid, 5'b11111 32 DW valid) 
     //------- AXI Slave Bridge Interface -------//
     input  logic                         i_slave_ready,
     output logic [BEAT_SIZE-1:0]         o_vc_cpl_data,
     output logic [CPL_HDR_SIZE-1:0]      o_vc_cpl_hdr,
     output logic                         o_slave_cpl_vaild,
     output logic [4:0]                   o_slave_cpl_valid_data
);

localparam     REQUESTER_TAG_WIDTH = 8;

//------- TX Flow Control <=> RX Error Check ------//
logic [REQUESTER_TAG_WIDTH-1:0] tx_last_req_tag;
logic [3*HDR_CREDS_WIDTH-1:0]   tx_fc_hdr_credit_limit_bus;
logic [3*DATA_CREDS_WIDTH-1:0]  tx_fc_data_credit_limit_bus;
logic [5:0]                     tx_fc_hdr_scale_bus;
logic [5:0]                     tx_fc_data_scale_bus;
//------- RX Flow Control <=> TX Arbiter  ------//
logic [CPL_HDR_SIZE-1:0] tx_cpl_hdr;
logic [CPL_HDR_SIZE-1:0] tx_cpl_data;
logic [4*DW-1:0]         tx_error_msg;
logic [1:0]              tx_transfer_ctrl;
logic                    tx_cpl_type;        // With or without data
logic                    tx_transfer_ack;

TL_RX #(
     .BEAT_SIZE(BEAT_SIZE),
     .REQ_HDR_SIZE(REQ_HDR_SIZE),
     .CPL_HDR_SIZE(CPL_HDR_SIZE),
     .RCV_BUS_WIDTH(RCV_BUS_WIDTH),
     .HDR_CREDS_WIDTH(HDR_CREDS_WIDTH),
     .DATA_CREDS_WIDTH(DATA_CREDS_WIDTH),
     .BARS_WIDTH(BARS_WIDTH)
) TL_RX (
     //------- Global Signals -------//
     .i_clk(i_clk),
     .i_n_rst(i_n_rst),
     //------- Config Space Interface -------//
     .i_cfg_ecrc_chk_en(i_cfg_ecrc_chk_en),
     .i_cfg_max_payload_size(i_cfg_max_payload_size),
     .i_cfg_BARs(i_cfg_BARs),
     //------- TL_TX General Interface -------//
     .i_tx_last_req_tag(tx_last_req_tag),
     //------- TL_TX FC Interface -------//
     .i_tx_fc_hdr_credit_limit_bus(tx_fc_hdr_credit_limit_bus),
     .i_tx_fc_data_credit_limit_bus(tx_fc_data_credit_limit_bus),
     .i_tx_fc_hdr_scale_bus(tx_fc_hdr_scale_bus),
     .i_tx_fc_data_scale_bus(tx_fc_data_scale_bus),
     //------- TL_TX Arbiter Interface -------//
     .o_tx_cpl_hdr(tx_cpl_hdr),
     .o_tx_cpl_data(tx_cpl_data),
     .o_tx_error_msg(tx_error_msg),
     .o_tx_cpl_type(tx_cpl_type),
     .o_tx_transfer_ctrl(tx_transfer_ctrl),
     .i_tx_transfer_ack(tx_transfer_ack),
     //------- Data Link Layer Interface -------//
     .i_dll_rcv_sop(i_dll_rcv_sop),
     .i_dll_rcv_tlp(i_dll_rcv_tlp),
     .i_dll_rcv_eop(i_dll_rcv_eop),
     .i_dll_last_dw(i_dll_last_dw),
     .o_tl_tlp_rcv_blk(o_tl_tlp_rcv_blk),
     //------- DLL-RX Flow Control Interface -------//
     .i_dll_typ(i_dll_typ),
     .i_dll_hdr_creds(i_dll_hdr_creds),
     .i_dll_data_creds(i_dll_data_creds),
     .i_dll_hdr_scale(i_dll_hdr_scale),
     .i_dll_data_scale(i_dll_data_scale),
     .i_dll_valid(i_dll_valid),
     //------- AXI Master Bridge Interface -------//
          /*Request Info Signals*/
     .o_master_req_type(o_req_type),
     .o_master_address_type(o_address_type),
     .o_master_req_traffic_class(o_req_traffic_class),
     .o_master_requester_id(o_requester_id),
     .o_master_req_tag(o_req_tag),
     .o_master_req_length(o_req_length),
     .o_master_req_first_byte_enable(o_req_first_byte_enable),
     .o_master_req_last_byte_enable(o_req_last_byte_enable),
     .o_master_req_address(o_req_address),
          /*Control Signals*/
     .o_master_req_increment(o_req_increment),
     .o_master_req_valid(o_req_valid),
     .o_master_last(o_last),
     .o_master_valid_data(o_valid_data),
     //------- AXI SlaveBridge Interface -------//
     .i_slave_ready(i_slave_ready),
     .o_vc_cpl_data(o_vc_cpl_data),
     .o_vc_cpl_hdr(o_vc_cpl_hdr),
     .o_slave_cpl_vaild(o_slave_cpl_vaild),
     .o_slave_cpl_valid_data(o_slave_cpl_valid_data)
);

endmodule
