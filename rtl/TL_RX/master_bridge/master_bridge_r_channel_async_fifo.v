/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project 
   -----------------------------------------------------------------------------
   FILE NAME :      master_bridge_r_channel_async_fifo
   DEPARTMENT :     PCIe-AXI Bridge Side of inbound
   AUTHOR :         Omar Hafez
   AUTHOR’S EMAIL : eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-04-20              initial version
   -----------------------------------------------------------------------------
   PURPOSE : 
   -----------------------------------------------------------------------------
   REUSE ISSUES
   Clock Domains    : n/a
   Critical Timing  : n/a
   Test Features    :
   Asynchronous I/F : n/a
   Scan Methodology : n/a
   Instantiations   :
   Synthesizable    : Y
   Other            :
   -FHDR------------------------------------------------------------------------*/
module master_bridge_r_channel_async_fifo #(
   parameter   DW = 32,
               BEAT_SIZE = 32*DW,
               R_CH_INFO_WIDTH = 30,
               ADDR_WIDTH = 5,
               R_CH_INFO_FIFO_DEPTH = 32,
               R_CH_DATA_FIFO_DEPTH = 32
) (
   //------ Global Signals ------//
   input wire i_w_clk,
   input wire i_w_n_rst,
   input wire i_r_clk,
   input wire i_r_n_rst,
   //------ Data FIFO------//
   input  wire                 i_w_data_inc,
   input  wire [BEAT_SIZE-1:0] i_w_data,
   input  wire                 i_r_data_inc,
   output wire [BEAT_SIZE-1:0] o_r_data,
   //------ Info FIFO------//
   input  wire                         i_w_info_inc,
   input  wire [R_CH_INFO_WIDTH-1:0]   i_w_info,
   input  wire                         i_r_info_inc,
   output wire [R_CH_INFO_WIDTH-1:0]   o_r_info,
   //------ Flags ------//
   output wire o_w_full_flag,
   output wire o_r_empty_flag
);

   wire r_data_full_flag;
   wire r_data_empty_flag;
   wire r_info_full_flag;
   wire r_info_empty_flag;
   
   master_bridge_async_fifo #(
      .DATA_WIDTH(R_CH_INFO_WIDTH),
      .FIFO_DEPTH(R_CH_INFO_FIFO_DEPTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .PTR_WIDTH(ADDR_WIDTH+1)
   ) u_r_channel_info_async_fifo (
      //------ Write Interface ------//
      .i_w_clk(i_w_clk),
      .i_w_n_rst(i_w_n_rst),
      .i_w_inc(i_w_info_inc),
      .i_w_data(i_w_info),
      //------ Read Interface ------//
      .i_r_clk(i_r_clk),
      .i_r_n_rst(i_r_n_rst),
      .i_r_inc(i_r_info_inc),
      .o_r_data(i_r_info),
      //------ Flags ------//
      .o_w_full_flag(r_info_full_flag),
      .o_r_empty_flag(r_info_empty_flag)
    );

   master_bridge_async_fifo #(
      .DATA_WIDTH(BEAT_SIZE),
      .FIFO_DEPTH(R_CH_DATA_FIFO_DEPTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .PTR_WIDTH(ADDR_WIDTH+1)
   ) u_r_channel_data_async_fifo (
      //------ Write Interface ------//
      .i_w_clk(i_w_clk),
      .i_w_n_rst(i_w_n_rst),
      .i_w_inc(i_w_data_inc),
      .i_w_data(ARCHANNEL),
      //------ Read Interface ------//
      .i_r_clk(i_r_clk),
      .i_r_n_rst(i_r_n_rst),
      .i_r_inc(i_r_data_inc),
      .o_r_data(o_r_data),
      //------ Flags ------//
      .o_w_full_flag(r_data_full_flag),
      .o_r_empty_flag(r_data_empty_flag)
    );

      
   assign o_w_full_flag = r_info_full_flag || r_data_full_flag;
   assign o_r_empty_flag = r_info_empty_flag || r_data_empty_flag;
   
endmodule
