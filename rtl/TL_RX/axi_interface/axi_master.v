/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      axi_master
   DEPARTMENT :     AXI Master
   AUTHOR :         Reem Mohamed - Omar Hafez
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com - eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-04-06             initial version
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
   ------------------------------------------------------------------------------*/
module axi_master #(
    parameter   DW = 32,
                BEAT_SIZE = 32 * DW,
                ID_WIDTH = 10,
                ADDR_WIDTH = 64,
                AxLEN_FIELD_WIDTH = 8,
                ADDR_LSBS_PORTION = 5,
                Ax_SIZE_WIDTH = 3,
                REQUESTER_ID_WIDTH = 16,
                Ax_BURST_WIDTH = 2,
                AW_CHANNEL_WIDTH = 103,             
                AR_CHANNEL_WIDTH = 120,             
                Ax_PROTECTION_WIDTH = 2,
                QOS_WIDTH = 4,
                Ax_USER_SIG_WIDTH = 17, // requester_id + type (MEM - IO)
                RESP_WIDTH = 2,
                W_CHANNEL_WIDTH = BEAT_SIZE + 128,
                R_USER_SIG_WIDTH = 44,  //  16  (reqester_id) + 4 (QOS) + 4 * 2 (BE) + 5 (Lsig addr bits) + 6 (r data counter) + 5 (last_dw) 
                B_USER_SIG_WIDTH = 20, // 16  (reqester_id) + 4 (QOS) 
                B_CHANNEL_WIDTH = ID_WIDTH + RESP_WIDTH + B_USER_SIG_WIDTH, // 10 + 2 + 20 = 32
                STROBE_BUS_WIDTH = 128,
                R_CHANNEL_INFO_WIDTH = ID_WIDTH + RESP_WIDTH + R_USER_SIG_WIDTH, // 10 + 2 + 44 = 56
                VALID_DATA_WIDTH = 5
) (
    //------- Global Signals -------//
    input   wire                                i_clk,
    input   wire                                i_n_rst,
    //------ AW Channel FIFO Interface------//
    input   wire                                i_AWVALID_fifo,     /*A transaction is written in the FIFO and yet to be read (i.e. info on FIFO output read bus is valid)*/
    input   wire    [AW_CHANNEL_WIDTH-1:0]      i_AW_CHANNEL_fifo,
    output  wire                                o_aw_ch_fifo_read_inc,
    //------ W Channel FIFO Interface------//
    input   wire                                i_WVALID_fifo,      /*A transaction is written in the FIFO and yet to be read (i.e. info on FIFO output read bus is valid)*/
    output  wire                                o_w_ch_fifo_read_inc,
    //------ B Channel FIFO Interface------//
    output  wire                                o_b_ch_fifo_write_inc,
    output  wire    [B_CHANNEL_WIDTH-1:0]       o_B_CHANNEL,
    input   wire                                i_BREADY_fifo,      /*A transaction is need to be written in the FIFO, hence we shall know if the FIFO is EMPTY*/
    //------ AR Channel FIFO Interface------//
    input   wire                                i_ARVALID_fifo,     /*A transaction is written in the FIFO and yet to be read (i.e. info on FIFO output read bus is valid)*/
    input   wire    [AR_CHANNEL_WIDTH-1:0]      i_AR_CHANNEL_fifo,
    output  wire                                o_ar_ch_fifo_read_inc,
    //------ R Channel FIFO Interface------//
    output  wire                                o_r_ch_fifo_write_info_inc,
    output  wire                                o_r_ch_fifo_write_data_inc,
    input   wire                                i_RREADY_fifo,      /*A transaction is need to be written in the FIFO, hence we shall know if the FIFO is EMPTY*/
    output  wire    [R_CHANNEL_INFO_WIDTH-1:0]  o_R_CHANNEL_info,
    //------ Slave (Application) Interface------//
    /**AW Channel**/
    output  wire    [ID_WIDTH-1:0]              o_s_AWID,
    output  wire    [ADDR_WIDTH-1:0]            o_s_AWADDR,
    output  wire    [AxLEN_FIELD_WIDTH-1:0]     o_s_AWLEN,       /*Burst length: gives the exact number of data transfers in a burst associated with the address.*/
    output  wire    [Ax_SIZE_WIDTH-1:0]         o_s_AWSIZE,
    output  wire    [Ax_BURST_WIDTH-1:0]        o_s_AWBURST,
    output  wire    [Ax_PROTECTION_WIDTH-1:0]   o_s_AWPROT,
    output  wire                                o_s_AWVALID,
    input   wire                                i_s_AWREADY,
    /**W Channel**/
    input   wire                                i_s_WREADY,
    output  wire                                o_s_WVALID,
    output  wire                                o_s_WLAST,
    // output  wire    [STROBE_BUS_WIDTH-1:0]      o_s_WSTRB,
    /**B Channel**/
    input   wire    [ID_WIDTH-1:0]              i_s_BID,
    input   wire                                i_s_BVALID,
    // input   wire    [B_USER_SIG_WIDTH-1:0]      i_s_BUSER,
    input   wire    [RESP_WIDTH-1:0]            i_s_BRESP,
    output  wire                                o_s_BREADY,
    /**AR Channel**/
    output  wire    [ID_WIDTH-1:0]              o_s_ARID,
    output  wire    [ADDR_WIDTH-1:0]            o_s_ARADDR,
    output  wire    [AxLEN_FIELD_WIDTH-1:0]     o_s_ARLEN,       /*Burst length: gives the exact number of data transfers in a burst associated with the address.*/
    output  wire    [Ax_SIZE_WIDTH-1:0]         o_s_ARSIZE,
    output  wire    [Ax_BURST_WIDTH-1:0]        o_s_ARBURST,
    output  wire    [Ax_PROTECTION_WIDTH-1:0]   o_s_ARPROT,
    output  wire                                o_s_ARVALID,
    input   wire                                i_s_ARREADY,
    /**R Channel**/
    input   wire    [ID_WIDTH-1:0]              i_s_RID,
    input   wire    [RESP_WIDTH-1:0]            i_s_RRESP,
    input   wire                                i_s_RLAST,
    input   wire                                i_s_RVALID,
    output  wire                                o_s_RREADY
);
    localparam  READ_REQ_INFO = 34;     // 16 (ID) + 4 (FBE) + 4 (LBE)+ 5 (addr least sig bits) + 6 (r_push_counter) + 5 (last dw) = 34
    localparam  WRITE_REQ_INFO = 17;    // 16 (ID) + 1 (req type MEM - IO) = 17
    localparam  BE_WIDTH = 4;
    localparam CNTR_WIDTH = 6;

     /*Consider putting this info in a sync fifo in the bridge*/
     wire [QOS_WIDTH-1:0] AWQOS;
    wire [WRITE_REQ_INFO-1:0] aw_request_info;
    wire [REQUESTER_ID_WIDTH-1:0] write_requester_id;
    wire    write_reqest_type; // (req type MEM: 0 - IO: 1)

    wire [QOS_WIDTH-1:0] ARQOS;
    wire [READ_REQ_INFO-1:0] ar_request_info;
    wire [REQUESTER_ID_WIDTH-1:0] read_requester_id;
    wire [BE_WIDTH-1:0] read_req_first_byte_enable;
    wire [BE_WIDTH-1:0] read_req_last_byte_enable;
    wire [ADDR_LSBS_PORTION-1:0] read_address_lsbs; // 5 least significant bit of the address
    wire [CNTR_WIDTH-1:0] r_ch_pushed_data_cntr;

    wire [4:0] read_last_dw; 


    wire [B_USER_SIG_WIDTH-1:0] BUSER;
    wire [R_USER_SIG_WIDTH-1:0] RUSER;

    assign o_s_AWID = i_AW_CHANNEL_fifo[102:93];
    assign o_s_AWADDR = i_AW_CHANNEL_fifo[92:29];
    assign o_s_AWLEN = i_AW_CHANNEL_fifo[28:21];
    assign AWQOS = i_AW_CHANNEL_fifo[20:17];
    assign aw_request_info = i_AW_CHANNEL_fifo[16:0];
    assign write_requester_id = aw_request_info[16:1];
    assign write_reqest_type = aw_request_info[0];

    assign o_s_ARID = i_AR_CHANNEL_fifo[119:110];
    assign o_s_ARADDR = i_AR_CHANNEL_fifo[109:46];
    assign o_s_ARLEN = i_AR_CHANNEL_fifo[45:38];
    assign ARQOS = i_AR_CHANNEL_fifo[37:34];
    assign ar_request_info = i_AR_CHANNEL_fifo[33:0];
    assign read_requester_id = ar_request_info[33:18];
    assign read_req_first_byte_enable = ar_request_info[17:14];
    assign read_req_last_byte_enable = ar_request_info[13:10];
    assign read_address_lsbs = ar_request_info[9:5];
    assign read_last_dw = ar_request_info[4:0];
    
    assign BUSER = {write_requester_id, AWQOS};
    assign o_B_CHANNEL = {i_s_BID, i_s_BRESP, BUSER};
    
    assign RUSER = {read_requester_id, ARQOS, read_req_first_byte_enable, read_req_last_byte_enable, read_address_lsbs, r_ch_pushed_data_cntr, read_last_dw};
    assign o_R_CHANNEL_info = {i_s_RID, i_s_RRESP, RUSER};

    axi_master_request_control #(
        .DW(DW),
        .ADDR_WIDTH(ADDR_WIDTH),
        .BEAT_SIZE(BEAT_SIZE),
        .Ax_SIZE_WIDTH(Ax_SIZE_WIDTH),
        .Ax_BURST_WIDTH(Ax_BURST_WIDTH),
        .Ax_PROTECTION_WIDTH(Ax_PROTECTION_WIDTH),
        .AxLEN_FIELD_WIDTH(AxLEN_FIELD_WIDTH),
        .QOS_WIDTH(QOS_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .STROBE_BUS_WIDTH(STROBE_BUS_WIDTH),
        .W_CHANNEL_WIDTH(W_CHANNEL_WIDTH),
        .Ax_USER_SIG_WIDTH(Ax_USER_SIG_WIDTH),
        .VALID_DATA_WIDTH(VALID_DATA_WIDTH)
    ) u_request_control (
        .i_clk(i_clk),
        .i_n_rst(i_n_rst),
        //------ AW Channel FIFO Interface------//
        // .i_AW_CHANNEL_fifo(i_AW_CHANNEL_fifo),
        .i_AWLEN(o_s_AWLEN),
        .i_AWVALID_fifo(i_AWVALID_fifo),
        .o_aw_ch_fifo_read_inc(o_aw_ch_fifo_read_inc),
        //------ Write Address Channel Slave Interface------//
        .o_s_AWSIZE(o_s_AWSIZE),
        .o_s_AWBURST(o_s_AWBURST),
        .o_s_AWPROT(o_s_AWPROT),
        .o_s_AWVALID(o_s_AWVALID),
        .i_s_AWREADY(i_s_AWREADY),
        //------ W Channel FIFO Interface------//
        .i_WVALID_fifo(i_WVALID_fifo),
        .o_w_ch_fifo_read_inc(o_w_ch_fifo_read_inc),
        //------ Write Data Channel Slave Interface------//
//        .o_WDATA(o_WDATA),
        .o_s_WLAST(o_s_WLAST),
        .o_s_WVALID(o_s_WVALID),
        .i_s_WREADY(i_s_WREADY),
        //------ AR Channel FIFO Interface------//
        .i_ARVALID_fifo(i_ARVALID_fifo),
        .o_ar_ch_fifo_read_inc(o_ar_ch_fifo_read_inc),
        //------ Read Address Channel Slave Interface------//
        .o_s_ARSIZE(o_s_ARSIZE),
        .o_s_ARBURST(o_s_ARBURST),
        .o_s_ARPROT(o_s_ARPROT),
        .o_s_ARVALID(o_s_ARVALID),
        .i_s_ARREADY(i_s_ARREADY)
    );

    axi_master_response_control u_response_control (
        .i_clk(i_clk),
        .i_n_rst(i_n_rst),
        .i_write_reqest_type(write_reqest_type),
        //------ B Channel FIFO Interface------//
        .o_b_ch_fifo_write_inc(o_b_ch_fifo_write_inc),
        .i_BREADY_fifo(i_BREADY_fifo),
        //------ Write Responce Channel Slave Interface------//
        .i_s_BVALID(i_s_BVALID),
        .o_s_BREADY(o_s_BREADY),
        //------ R Channel FIFO Interface------//
        .o_r_ch_fifo_write_info_inc(o_r_ch_fifo_write_info_inc),
        .o_r_ch_fifo_write_data_inc(o_r_ch_fifo_write_data_inc),
        .i_RREADY_fifo(i_RREADY_fifo),
        //------ R Channel Slave Interface------//
        .o_r_ch_pushed_data_cntr(r_ch_pushed_data_cntr),
        .i_s_RRESP(i_s_RRESP),
        .i_s_RLAST(i_s_RLAST),
        .i_s_RVALID(i_s_RVALID),
        .o_s_RREADY(o_s_RREADY)
    );
                        
endmodule
