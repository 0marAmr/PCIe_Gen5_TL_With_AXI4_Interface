/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project 
   -----------------------------------------------------------------------------
   FILE NAME :      master_bridge
   DEPARTMENT :     AXI - PCIe Master Bridge
   AUTHOR :         Reem Mohamed - Omar Hafez
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com - eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-04-03             initial version
   -----------------------------------------------------------------------------
   PURPOSE : Receives PCIe request TLPs as a “Completer�? and converts them to AXI4 memory mapped transactions.
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
module master_bridge #(
    parameter   DW = 32,
                ADDR_WIDTH = 64,
                BEAT_SIZE = 32*DW,
                AW_CHANNEL_WIDTH = 103, // 16 (ID) + 4 (FBE) + 4 (LBE)+ 5 (addr least sig bits) + 5 (last dw) = 34
                AR_CHANNEL_WIDTH = 120, // 16 (ID) + 1 (req type MEM - IO) = 17             
                W_CHANNEL_WIDTH = BEAT_SIZE + 128,
                VALID_DATA_WIDTH = 5,
                REQUESTER_ID_WIDTH = 16,
                TAG_WIDTH = 10,
                TC_WIDTH = 3,
                PAYLOAD_LENGTH = 10,
                BYTE_ENABLES_WIDTH = 4,
                R_CHANNEL_WIDTH    = 56,
                B_CHANNEL_WIDTH    = 32,
                BYTE_COUNT_WIDTH = 12,
                LOWER_ADDR_FIELD = 7


   ) (
    //------- Global Signals -------//
    input   wire                            i_pcie_clk,
    input   wire                            i_pcie_n_rst,
    input   wire                            i_axi_clk,
    input   wire                            i_axi_n_rst,
    //------ Core: Read Handler Interface - Request Control ------//
    input   wire                            i_req_valid,            // indication for the beginning of transaction, asserted till the end of the transaction
    input   wire                            i_req_inc,              // increment the request info 
    input   wire                            i_req_data_write_inc,   // increment the request data (W CHANNEL)
    input   wire                            i_last,                 // indicates that the current beat is the last one in a transaction 
    input   wire    [VALID_DATA_WIDTH-1:0]  i_valid_data,           // encoding for valid Double Words of data driven on the bus (5'b00000 -> 1 DW valid, 5'b11111 32 DW valid) 
    output  wire                            o_AWREADY_fifo,         // de-asserted if the fifo is full
    output  wire                            o_WREADY_fifo,          // de-asserted if the fifo is full
    output  wire                            o_ARREADY_fifo,         // de-asserted if the fifo is full
    //------ Core: Read Handler Interface - Request Info | Data ------//
    input   wire   [REQUESTER_ID_WIDTH-1:0] i_requester_id,
    input   wire   [1:0]                    i_req_type,         /*Memory Read - Memory Write - IO Read - IO Write*/
    input   wire                            i_address_type,     // logic 1 in case of address 64-bit 
    input   wire   [TAG_WIDTH-1:0]          i_req_tag,
    input   wire   [TC_WIDTH-1:0]           i_TC,
    input   wire   [PAYLOAD_LENGTH-1:0]     i_req_length,
    input   wire   [BYTE_ENABLES_WIDTH-1:0] i_req_first_byte_enable,
    input   wire   [BYTE_ENABLES_WIDTH-1:0] i_req_last_byte_enable,
    input   wire   [ADDR_WIDTH-1:0]         i_req_address,
    input   wire   [BEAT_SIZE-1:0]          i_WDATA,            // data is multiplexed from POSTED/NON-POSTED buffers
    //------ Core: Completion Generator Interface - Completion Control ------//
    input  wire                             i_cpl_info_inc,
    input  wire                             i_cpl_data_inc,
    output wire                             o_cpl_valid,
    //------ Core: Completion Generator Interface - Completion Info | Data ------//
    output wire  [REQUESTER_ID_WIDTH-1:0]   o_cpl_requester_id,
    output wire                             o_cpl_type,
    output wire  [TAG_WIDTH-1:0]            o_cpl_tag,
    output wire  [TC_WIDTH-1:0]             o_cpl_traffic_class,
    output wire  [PAYLOAD_LENGTH-1:0]       o_cpl_length,
    output wire  [LOWER_ADDR_FIELD-1:0]     o_cpl_lower_address,
    output wire                             o_cpl_error_flag,
    output wire  [BYTE_COUNT_WIDTH-1:0]     o_cpl_initial_byte_count,
    output wire  [BEAT_SIZE-1:0]            o_cpl_data,
    //------ AXI Master Interface ------//
    /**AW Channel**/
    input   wire                            i_aw_ch_fifo_read_inc,
    output  wire                            o_AWVALID_fifo,
    output  wire    [AW_CHANNEL_WIDTH-1:0]  o_AW_CHANNEL_fifo,
    /**W Channel**/
    input   wire                            i_w_ch_fifo_read_inc,
    output  wire                            o_WVALID_fifo,
    /**B Channel**/
    input   wire                            i_b_ch_fifo_write_inc,
    input   wire    [B_CHANNEL_WIDTH-1:0]   i_B_CHANNEL,
    output  wire                            o_BREADY_fifo,
    /**AR Channel**/
    input   wire                            i_ar_ch_fifo_read_inc,
    output  wire                            o_ARVALID_fifo,
    output  wire    [AR_CHANNEL_WIDTH-1:0]  o_AR_CHANNEL_fifo,
    /**R Channel**/
    input   wire                            i_r_ch_fifo_write_info_inc,
    input   wire                            i_r_ch_fifo_write_data_inc,
    output  wire                            o_RREADY_fifo,
    input   wire    [R_CHANNEL_WIDTH-1:0]   i_R_CHANNEL_info,
    //------ AXI Slave (Application) Interface ------//
    /**R Channel**/
    input   wire    [BEAT_SIZE-1:0]         i_R_CHANNEL_data,
    /**W Channel**/
    output  wire    [W_CHANNEL_WIDTH-1:0]   o_W_CHANNEL_fifo
   );

    localparam  ID_WIDTH = 10;
    localparam  AxLEN_FIELD_WIDTH = 8;
    localparam  BURST_FIELD_WIDTH = 2;
    localparam  QOS_WIDTH = 4;
    localparam  READ_REQ_INFO = 34;     
    localparam  WRITE_REQ_INFO = 17;    
    localparam  STROBE_BUS_WIDTH = 128;
    localparam  RESP_WIDTH = 2;
    localparam  R_USER_SIG_WIDTH = 44;
    localparam  B_USER_SIG_WIDTH = REQUESTER_ID_WIDTH +  QOS_WIDTH;// 20

    localparam  AW_CH_FIFO_DEPTH    = 32;
    localparam  W_CH_FIFO_DEPTH     = 32;
    localparam  B_CH_FIFO_DEPTH     = 32;
    localparam  AR_CH_FIFO_DEPTH    = 32;
    localparam  R_CH_INFO_FIFO_DEPTH = 32;
    localparam  R_CH_DATA_FIFO_DEPTH = 32;
    localparam  FIFO_ADDR_WIDTH     = 5;

    //------- AW Channel -------//
    wire [ID_WIDTH-1:0]             AWID;
    wire [ADDR_WIDTH-1:0]           AWADDR;
    wire [AxLEN_FIELD_WIDTH-1:0]    AWLEN;
    wire [QOS_WIDTH-1:0]            AWQOS;
    wire [WRITE_REQ_INFO-1:0]       aw_request_info;
    wire [AW_CHANNEL_WIDTH-1:0]     AWCHANNEL;
    wire                            aw_ch_full_flag;
    wire                            aw_ch_empty_flag;
    //------- W Channel -------//
    wire [STROBE_BUS_WIDTH-1:0]     WSTRB;
    wire [W_CHANNEL_WIDTH-1:0]      WCHANNEL;
    wire                            w_ch_full_flag;
    wire                            w_ch_empty_flag;
    //------- AR Channel -------//
    wire [ID_WIDTH-1:0]             ARID;
    wire [ADDR_WIDTH-1:0]           ARADDR;
    wire [AxLEN_FIELD_WIDTH-1:0]    ARLEN;
    wire [QOS_WIDTH-1:0]            ARQOS;
    wire [READ_REQ_INFO-1:0]        ar_request_info;
    wire [AR_CHANNEL_WIDTH-1:0]     ARCHANNEL;
    wire                            ar_ch_full_flag;
    wire                            ar_ch_empty_flag;
    //------- B Channel -------//
    wire [B_CHANNEL_WIDTH-1:0]      b_ch_fifo;
    wire [ID_WIDTH-1:0]             BID;
    wire [RESP_WIDTH-1:0]           BRESP;
    wire [B_USER_SIG_WIDTH-1:0]     BUSER;
    wire                            b_ch_full_flag;
    wire                            b_ch_empty_flag;
    wire                            b_ch_read_inc;
    //------- R Channel -------//
    wire [R_CHANNEL_WIDTH-1:0]      r_ch_fifo_info;
    wire [ID_WIDTH-1:0]             RID;
    wire [RESP_WIDTH-1:0]           RRESP;
    wire [R_USER_SIG_WIDTH-1:0]     RUSER;
    wire                            r_ch_full_flag;
    wire                            r_ch_empty_flag;
    wire                            r_ch_read_info_inc;

    assign AWCHANNEL = {AWID, AWADDR, AWLEN, AWQOS, aw_request_info};
    assign WCHANNEL  = {WSTRB, i_WDATA};
    assign ARCHANNEL = {ARID, ARADDR, ARLEN, ARQOS, ar_request_info};
    assign {RID, RRESP, RUSER} = r_ch_fifo_info;
    assign {BID, BRESP, BUSER} = b_ch_fifo;

    assign o_AWREADY_fifo   = ~aw_ch_full_flag;
    assign o_AWVALID_fifo   = ~aw_ch_empty_flag;
    assign o_WREADY_fifo    = ~w_ch_full_flag;
    assign o_WVALID_fifo    = ~w_ch_empty_flag;
    assign o_ARREADY_fifo   = ~ar_ch_full_flag;
    assign o_ARVALID_fifo   = ~ar_ch_empty_flag;
    assign o_RREADY_fifo    = ~r_ch_full_flag;
    assign RVALID_fifo      = ~r_ch_empty_flag;
    assign o_BREADY_fifo    = ~b_ch_full_flag;
    assign BVALID_fifo      = ~b_ch_empty_flag;

    // --------- Mapping Blocks ---------//
    pcie_to_axi_map #(
        .ID_WIDTH(ID_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .AxLEN_FIELD_WIDTH(AxLEN_FIELD_WIDTH),
        .BURST_FIELD_WIDTH(BURST_FIELD_WIDTH),
        .QOS_WIDTH(QOS_WIDTH),
        .STROBE_BUS_WIDTH(STROBE_BUS_WIDTH)
   ) u_pcie_to_axi_map (
        //------- Request Interface -------//
        .i_req_type(i_req_type),
       .i_address_type(i_address_type),
        .i_req_address(i_req_address),
        .i_requester_id(i_requester_id),
        .i_req_tag(i_req_tag),
        .i_req_length(i_req_length),
        .i_req_first_byte_enable(i_req_first_byte_enable),
        .i_req_last_byte_enable(i_req_last_byte_enable),
        .i_req_traffic_class(i_TC),
        //------ Read Handler Interface -------//
        .i_req_inc(i_req_inc),
        .i_req_valid(i_req_valid),
        .i_last(i_last),
        .i_valid_data(i_valid_data),
        //------- AW Channel -------//
        .o_aw_write_inc(aw_write_inc),
        .o_AWID(AWID),
        .o_AWADDR(AWADDR),
        .o_AWLEN(AWLEN),
        .o_AWQOS(AWQOS),
        .o_aw_request_info(aw_request_info),
        //------- W Channel -------//
        .o_WSTRB(WSTRB),
        //------- AR Channel -------//
        .o_ar_write_inc(ar_ch_write_inc),
        .o_ARID(ARID),
        .o_ARADDR(ARADDR),
        .o_ARLEN(ARLEN),
        .o_ARQOS(ARQOS),
        .o_ar_request_info(ar_request_info)
    );
    
    axi_to_pcie_map #(
        .ID_WIDTH(ID_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .REQUESTER_ID_WIDTH(REQUESTER_ID_WIDTH),
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH),
        .TC_WIDTH(TC_WIDTH),
        .BYTE_ENABLES_WIDTH(BYTE_ENABLES_WIDTH)
    ) u_axi_to_pcie_map (
        //------- B Channel -------//
        .i_BID(BID),
        .i_BRESP(BRESP),
        .i_BUSER(BUSER),
        .i_BVALID_fifo(BVALID_fifo),
        .o_b_ch_read_inc(b_ch_read_inc),  
        //------- R Channel -------//
        .i_RID(RID),
        .i_RRESP(RRESP),
        .i_RUSER(RUSER),
        .i_RVALID_fifo(RVALID_fifo),  
        .o_r_ch_read_info_inc(r_ch_read_info_inc),  
        //------ Completion Generator Interface  ------//
        .i_cpl_info_inc(i_cpl_info_inc),
        .o_cpl_requester_id(o_cpl_requester_id),
        .o_cpl_type(o_cpl_type),
        .o_cpl_tag(o_cpl_tag),
        .o_cpl_traffic_class(o_cpl_traffic_class),
        .o_cpl_length(o_cpl_length),
        .o_cpl_lower_address(o_cpl_lower_address),
        .o_cpl_error_flag(o_cpl_error_flag),
        .o_cpl_initial_byte_count(o_cpl_initial_byte_count),
        .o_cpl_valid(o_cpl_valid)
    );

    master_bridge_async_fifo #(
        .DATA_WIDTH(AW_CHANNEL_WIDTH),
        .FIFO_DEPTH(AW_CH_FIFO_DEPTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .PTR_WIDTH(FIFO_ADDR_WIDTH+1)
    ) u_aw_req_channel_async_fifo (
        //------ Write Interface ------//
        .i_w_clk(i_pcie_clk),
        .i_w_n_rst(i_pcie_n_rst),
        .i_w_inc(aw_write_inc),
        .i_w_data(AWCHANNEL),
        //------ Read Interface ------//
        .i_r_clk(i_axi_clk),
        .i_r_n_rst(i_axi_n_rst),
        .i_r_inc(i_aw_ch_fifo_read_inc),
        .o_r_data(o_AW_CHANNEL_fifo),
        //------ Flags ------//
        .o_w_full_flag(aw_ch_full_flag),
        .o_r_empty_flag(aw_ch_empty_flag)
    );

    master_bridge_async_fifo #(
        .DATA_WIDTH(W_CHANNEL_WIDTH),
        .FIFO_DEPTH(W_CH_FIFO_DEPTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .PTR_WIDTH(FIFO_ADDR_WIDTH+1)
    ) u_w_req_channel_async_fifo (
        //------ Write Interface ------//
        .i_w_clk(i_pcie_clk),
        .i_w_n_rst(i_pcie_n_rst),
        .i_w_inc(i_req_data_write_inc),
        .i_w_data(WCHANNEL),
        //------ Read Interface ------//
        .i_r_clk(i_axi_clk),
        .i_r_n_rst(i_axi_n_rst),
        .i_r_inc(i_w_ch_fifo_read_inc),
        .o_r_data(o_W_CHANNEL_fifo),
        //------ Flags ------//
        .o_w_full_flag(w_ch_full_flag),
        .o_r_empty_flag(w_ch_empty_flag)
    );

    master_bridge_async_fifo #(
        .DATA_WIDTH(AR_CHANNEL_WIDTH),
        .FIFO_DEPTH(AR_CH_FIFO_DEPTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .PTR_WIDTH(FIFO_ADDR_WIDTH+1)
    ) u_ar_req_channel_async_fifo (
        //------ Write Interface ------//
        .i_w_clk(i_pcie_clk),
        .i_w_n_rst(i_pcie_n_rst),
        .i_w_inc(ar_ch_write_inc),
        .i_w_data(ARCHANNEL),
        //------ Read Interface ------//
        .i_r_clk(i_axi_clk),
        .i_r_n_rst(i_axi_n_rst),
        .i_r_inc(i_ar_ch_fifo_read_inc),
        .o_r_data(o_AR_CHANNEL_fifo),
        //------ Flags ------//
        .o_w_full_flag(ar_ch_full_flag),
        .o_r_empty_flag(ar_ch_empty_flag)
    );

    master_bridge_r_channel_async_fifo #(
        .BEAT_SIZE(BEAT_SIZE),
        .R_CH_INFO_WIDTH(R_CHANNEL_WIDTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .R_CH_INFO_FIFO_DEPTH(R_CH_INFO_FIFO_DEPTH),
        .R_CH_DATA_FIFO_DEPTH(R_CH_DATA_FIFO_DEPTH)
    ) u_r_resp_channel_async_fifo (
        //------ Write Interface ------//
        .i_w_clk(i_axi_clk),
        .i_w_n_rst(i_axi_n_rst),
        .i_w_data_inc(i_r_ch_fifo_write_data_inc),
        .i_w_info_inc(i_r_ch_fifo_write_info_inc),
        .i_w_data(i_R_CHANNEL_data),    
        .i_w_info(i_R_CHANNEL_info),    
        //------ Read Interface ------//
        .i_r_clk(i_pcie_clk),
        .i_r_n_rst(i_pcie_n_rst),
        .i_r_data_inc(i_cpl_data_inc),
        .o_r_data(o_cpl_data),    
        .i_r_info_inc(r_ch_read_info_inc),
        .o_r_info(r_ch_fifo_info),    
        //------ Flags ------//
        .o_w_full_flag(r_ch_full_flag),  
        .o_r_empty_flag(r_ch_empty_flag)  
   );

    master_bridge_async_fifo #(
        .DATA_WIDTH(B_CHANNEL_WIDTH),
        .FIFO_DEPTH(B_CH_FIFO_DEPTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .PTR_WIDTH(FIFO_ADDR_WIDTH+1)
    ) u_b_resp_channel_async_fifo (
        //------ Write Interface ------//
        .i_w_clk(i_axi_clk),
        .i_w_n_rst(i_axi_n_rst),
        .i_w_inc(i_b_ch_fifo_write_inc),
        .i_w_data(i_B_CHANNEL),
        //------ Read Interface ------//
        .i_r_clk(i_pcie_clk),
        .i_r_n_rst(i_pcie_n_rst),
        .i_r_inc(b_ch_read_inc),
        .o_r_data(b_ch_fifo),
        //------ Flags ------//
        .o_w_full_flag(b_ch_full_flag),
        .o_r_empty_flag(b_ch_empty_flag)
    );

endmodule
