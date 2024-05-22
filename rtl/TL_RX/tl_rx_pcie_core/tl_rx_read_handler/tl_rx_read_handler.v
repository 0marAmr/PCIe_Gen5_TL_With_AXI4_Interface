/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_read_handler
   DEPARTMENT :     Read Handler
   AUTHOR :         Reem Mohamed - Omar Hafez
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com - eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-04-07              initial version
   -----------------------------------------------------------------------------
   PURPOSE :
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
module tl_rx_read_handler #(
    parameter   DW = 32,
                FLAGS_WIDTH = 6,
                PAYLOAD_LENGTH = 10,
                VALID_DATA_WIDTH = 5,
                R_CTRL_BUS_WIDTH = 6,
                REQUESTER_ID_WIDTH = 16,
				TAG_WIDTH = 10,
                TC_WIDTH = 3,
                BYTE_ENABLES_WIDTH = 4,
                ADDR_WIDTH = 64,
                BEAT_SIZE = 32 * DW
) (
    //------ Global Signals ------//
    input   wire        i_clk,
    input   wire        i_n_rst,
    //----- Virtual Channels Interface -----//
    input   wire    [FLAGS_WIDTH-1:0]       i_vcn_r_empty_flags,
    input   wire                            i_cpl_fmt_data_bit,
    input   wire    [PAYLOAD_LENGTH-1:0]    i_cpl_length_field,
    output  wire    [R_CTRL_BUS_WIDTH-1:0]  o_r_completion_ctrl,
    //------ Master Bridge Interface - Request Control ------//
	output  wire                            o_req_valid,            // indication for the beginning of transaction, asserted till
    output  wire                            o_req_inc,    
    output  wire                            o_req_data_write_inc,    
    output  wire                            o_req_last,                 // indicates that the current beat is the last one in a transaction 
    output  wire    [VALID_DATA_WIDTH-1:0]  o_req_valid_data,           // encoding for valid Double Words of data driven on the bus (5'b00000 -> 1 DW valid, 5'b11111 32 DW valid) 
    input   wire                            i_AWREADY_fifo,
    input   wire                            i_WREADY_fifo,
    input   wire                            i_ARREADY_fifo,
	//------ Master Bridge Interface - Request Info | Data ------//
	output  wire   [1:0]                    o_req_type,   /*Memory Read - Memory Write - IO Read - IO Write*/
    output  wire                            o_req_address_type,
    output  wire   [REQUESTER_ID_WIDTH-1:0] o_requester_id,
    output  wire   [TAG_WIDTH-1:0]          o_req_tag,
    output  wire   [TC_WIDTH-1:0]           o_req_TC,
    output  wire   [PAYLOAD_LENGTH-1:0]    	o_req_length,
    output  wire   [BYTE_ENABLES_WIDTH-1:0] o_req_first_byte_enable,
    output  wire   [BYTE_ENABLES_WIDTH-1:0] o_req_last_byte_enable,
    output  wire   [ADDR_WIDTH-1:0]         o_req_address,
    output  wire   [BEAT_SIZE-1:0]          o_req_data,
	//------- RX FLow Control Interface -------//
    output  wire                            o_cpl_ca_hdr_inc,
    output  wire                            o_cpl_ca_data_inc,
    //----- AXI Slave Interface -----//
    input   wire                            i_slave_ready,
    output  wire                            o_slave_cpl_vaild,
    output  wire    [VALID_DATA_WIDTH-1:0]  o_slave_cpl_valid_data
);
    
    tl_rx_read_handler_cpl_control #(
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH)
    ) u_cpl_control (
        .i_clk(i_clk),
        .i_n_rst(i_n_rst),
        //----- Virtual Channels Interface -----//
        .i_cpl_fmt_data_bit(i_cpl_fmt_data_bit),
        .i_vcn_cpl_r_empty_flags(i_vcn_r_empty_flags[1:0]),
        .i_cpl_length_field(i_cpl_length_field),
        .o_r_completion_ctrl(o_r_completion_ctrl),
        //------- RX FLow Control Interface -------//
        .o_cpl_ca_hdr_inc(o_cpl_ca_hdr_inc),
        .o_cpl_ca_data_inc(o_cpl_ca_data_inc),
        //----- AXI Slave Interface -----//
        .i_slave_ready(i_slave_ready),
        .o_slave_cpl_vaild(o_slave_cpl_vaild),
        .o_slave_cpl_valid_data(o_slave_cpl_valid_data)
    );

    assign o_req_valid = 'b0;
    assign o_req_inc = 'b0;
    assign o_req_data_write_inc = 'b0;
    assign o_req_last = 'b0;
    assign o_valid_data = 'b0;
    assign o_req_type = 'b0;
    assign o_req_address_type = 'b0;
    assign o_requester_id = 'b0;
    assign o_req_tag = 'b0;
    assign o_req_TC = 'b0;
    assign o_req_length = 'b0;
    assign o_req_first_byte_enable = 'b0;
    assign o_req_last_byte_enable = 'b0;
    assign o_req_address = 'b0;
    assign o_req_data = 'b0;
    assign o_req_address_type = 'b0;
    assign o_req_valid_data = 'b0;
    
endmodule