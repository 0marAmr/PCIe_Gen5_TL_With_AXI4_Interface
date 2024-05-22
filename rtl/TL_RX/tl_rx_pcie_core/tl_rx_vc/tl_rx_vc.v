/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project under supervision of
   Dr. Hosam Fahmy and Si vision company
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_vc
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
module tl_rx_vc #(
    parameter   DW = 32,
                W_CTRL_BUS_WIDTH = 6,
                R_CTRL_BUS_WIDTH = 6,  
                FLAGS_WIDTH = 6,            // Full Flags from VC Buffers
                HDR_FIFO_DEPTH = 2**7,
                P_DATA_FIFO_DEPTH = 2**10,
                NP_DATA_FIFO_DEPTH = 2**7,  // must be equal to headr depth
                CPL_DATA_FIFO_DEPTH = 2**10,
                BEAT_SIZE = 32*DW,
                REQ_HDR_SIZE = 4*DW,
                CPL_HDR_SIZE = 3*DW,
                P_DATA_IP_WIDTH = 8*DW,
                NP_DATA_IP_WIDTH = 1*DW,
                CPL_DATA_IP_WIDTH = 8*DW
)(
    //------ Global Signals ------//
    input   wire                            i_clk,
    input   wire                            i_n_rst,
    //------ Flags Output ------//
    output  wire  [FLAGS_WIDTH-1:0]         o_vc_w_full_flags,
    output  wire  [FLAGS_WIDTH-1:0]         o_vc_r_empty_flags,
    //------ Posted Buffers Interface ------//
    input   wire  [W_CTRL_BUS_WIDTH-1:0]    i_w_posted_ctrl,
    input   wire  [REQ_HDR_SIZE-1:0]        i_w_posted_hdr,
    input   wire  [CPL_DATA_IP_WIDTH-1:0]   i_w_posted_data,
    input   wire  [R_CTRL_BUS_WIDTH-1:0]    i_r_posted_ctrl,
    output  wire  [REQ_HDR_SIZE-1:0]        o_r_posted_hdr,
    output  wire  [BEAT_SIZE-1:0]           o_r_posted_data,
    //------ Non Posted Buffers Interface ------//
    input   wire  [W_CTRL_BUS_WIDTH-1:0]    i_w_non_posted_ctrl,
    input   wire  [REQ_HDR_SIZE-1:0]        i_w_non_posted_hdr,
    input   wire  [NP_DATA_IP_WIDTH-1:0]    i_w_non_posted_data,
    input   wire  [R_CTRL_BUS_WIDTH-1:0]    i_r_non_posted_ctrl,
    output  wire  [REQ_HDR_SIZE-1:0]        o_r_non_posted_hdr,
    output  wire  [BEAT_SIZE-1:0]           o_r_non_posted_data,
    //------ Completion Buffers Interface ------//
    input   wire  [W_CTRL_BUS_WIDTH-1:0]    i_w_completion_ctrl,
    input   wire  [CPL_HDR_SIZE-1:0]        i_w_completion_hdr,
    input   wire  [CPL_DATA_IP_WIDTH-1:0]   i_w_completion_data,
    input   wire  [R_CTRL_BUS_WIDTH-1:0]    i_r_completion_ctrl,
    output  wire  [CPL_HDR_SIZE-1:0]        o_r_completion_hdr,
    output  wire  [BEAT_SIZE-1:0]           o_r_completion_data
);    

    parameter P_BUFFER_TYPE = 0;
    parameter NP_BUFFER_TYPE = 1;
    parameter CPL_BUFFER_TYPE = 2;
    
    wire p_hdr_full_flag;
    wire p_data_full_flag;
    wire p_hdr_empty_flag;
    wire p_data_empty_flag;
    wire np_hdr_full_flag;
    wire np_data_full_flag;
    wire np_hdr_empty_flag;
    wire np_data_empty_flag;
    wire cpl_hdr_full_flag;
    wire cpl_data_full_flag;
    wire cpl_hdr_empty_flag;
    wire cpl_data_empty_flag;

    tl_rx_vc_buffer #(
        .BUFFER_TYPE("P"),
        .HDR_BUFFER_WIDTH(REQ_HDR_SIZE),
        .DATA_BUFFER_WIDTH(P_DATA_IP_WIDTH),
        .W_CTRL_BUS_WIDTH(W_CTRL_BUS_WIDTH),
        .R_CTRL_BUS_WIDTH(R_CTRL_BUS_WIDTH),
        .HDR_FIFO_DEPTH(HDR_FIFO_DEPTH),
        .DATA_FIFO_DEPTH(P_DATA_FIFO_DEPTH)
    ) posted_buffer (
        .i_clk(i_clk),
        .i_n_rst(i_n_rst),
        //------- Read Interface ------//
        .i_r_ctrl_bus(i_r_posted_ctrl),
        .o_r_tlp_hdr(o_r_posted_hdr),
        .o_r_tlp_data(o_r_posted_data),
        //------- Write Interface ------//
        .i_w_ctrl_bus(i_w_posted_ctrl),
        .i_w_tlp_hdr(i_w_posted_hdr),
        .i_w_tlp_data(i_w_posted_data),
        //------- Flags ------//
        .o_hdr_full_flag(p_hdr_full_flag),
        .o_data_full_flag(p_data_full_flag),
        .o_hdr_empty_flag(p_hdr_empty_flag),
        .o_data_empty_flag(p_data_empty_flag)
    );

   tl_rx_vc_buffer #(
       .BUFFER_TYPE("NP"),
       .HDR_BUFFER_WIDTH(REQ_HDR_SIZE),
       .DATA_BUFFER_WIDTH(NP_DATA_IP_WIDTH),
       .W_CTRL_BUS_WIDTH(W_CTRL_BUS_WIDTH),
       .R_CTRL_BUS_WIDTH(R_CTRL_BUS_WIDTH),
       .HDR_FIFO_DEPTH(HDR_FIFO_DEPTH),
       .DATA_FIFO_DEPTH(NP_DATA_FIFO_DEPTH)
   ) non_posted_buffer (
       .i_clk(i_clk),
       .i_n_rst(i_n_rst),
       //------- Read Interface ------//
       .i_r_ctrl_bus(i_r_non_posted_ctrl),
       .o_r_tlp_hdr(o_r_non_posted_hdr),
       .o_r_tlp_data(o_r_non_posted_data),
       //------- Write Interface ------//
       .i_w_ctrl_bus(i_w_non_posted_ctrl),
       .i_w_tlp_hdr(i_w_non_posted_hdr),
       .i_w_tlp_data(i_w_non_posted_data),
       //------- Flags ------//
       .o_hdr_full_flag(np_hdr_full_flag),
       .o_data_full_flag(np_data_full_flag),
       .o_hdr_empty_flag(np_hdr_empty_flag),
       .o_data_empty_flag(np_data_empty_flag)
   );
    
    tl_rx_vc_buffer #(
        .BUFFER_TYPE("CPL"),
        .HDR_BUFFER_WIDTH(CPL_HDR_SIZE),
        .DATA_BUFFER_WIDTH(CPL_DATA_IP_WIDTH),
        .W_CTRL_BUS_WIDTH(W_CTRL_BUS_WIDTH),
        .R_CTRL_BUS_WIDTH(R_CTRL_BUS_WIDTH),
        .HDR_FIFO_DEPTH(HDR_FIFO_DEPTH),
        .DATA_FIFO_DEPTH(CPL_DATA_FIFO_DEPTH)
    ) completion_buffer (
        .i_clk(i_clk),
        .i_n_rst(i_n_rst),
        //------- Read Interface ------//
        .i_r_ctrl_bus(i_r_completion_ctrl),
        .o_r_tlp_hdr(o_r_completion_hdr),
        .o_r_tlp_data(o_r_completion_data),
        //------- Write Interface ------//
        .i_w_ctrl_bus(i_w_completion_ctrl),
        .i_w_tlp_hdr(i_w_completion_hdr),
        .i_w_tlp_data(i_w_completion_data),
        //------- Flags ------//
        .o_hdr_full_flag(cpl_hdr_full_flag),
        .o_data_full_flag(cpl_data_full_flag),
        .o_hdr_empty_flag(cpl_hdr_empty_flag),
        .o_data_empty_flag(cpl_data_empty_flag)
    );

    assign o_vc_w_full_flags = {p_hdr_full_flag, p_data_full_flag, np_hdr_full_flag, np_data_full_flag, cpl_hdr_full_flag, cpl_data_full_flag};
    assign o_vc_r_empty_flags = {p_hdr_empty_flag, p_data_empty_flag, np_hdr_empty_flag, np_data_empty_flag, cpl_hdr_empty_flag, cpl_data_empty_flag};  
    
endmodule