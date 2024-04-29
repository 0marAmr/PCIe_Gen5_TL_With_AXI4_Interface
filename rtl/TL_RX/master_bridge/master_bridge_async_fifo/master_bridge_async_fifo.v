/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project under supervision of
   Dr. Hosam Fahmy and Si vision company
   -----------------------------------------------------------------------------
   FILE NAME :      PCIe_to_AXI_Map
   DEPARTMENT :     MASTER_BRIDGE
   AUTHOR :         Omar Hafez
   AUTHOR’S EMAIL : eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-04-03             initial version
   -----------------------------------------------------------------------------
   KEYWORDS : PCIe, General
   -----------------------------------------------------------------------------
   PURPOSE :
   -----------------------------------------------------------------------------
   PARAMETERS
   PARAM NAME               : RANGE  : DESCRIPTION                       : DEFAULT   : UNITS
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
`define DW 32
module master_bridge_async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter FIFO_DEPTH = 8,
    parameter ADDR_WIDTH  = 3,
    parameter PTR_WIDTH  = ADDR_WIDTH + 1
)(
    input   wire                    i_w_clk,
    input   wire                    i_w_n_rst,
    input   wire                    i_w_inc,
    input   wire                    i_r_clk,
    input   wire                    i_r_n_rst,
    input   wire                    i_r_inc,
    input   wire [DATA_WIDTH-1:0]   i_w_data,
    output  wire                    o_w_full_flag,
    output  wire                    o_r_empty_flag,
    output  wire [DATA_WIDTH-1:0]   o_r_data
);


    wire [ADDR_WIDTH:0]     gray_rd_ptr;
    wire [ADDR_WIDTH:0]     gray_sync_rd_ptr;
    wire [ADDR_WIDTH:0]     gray_wr_ptr;
    wire [ADDR_WIDTH:0]     gray_sync_wr_ptr;
    wire [ADDR_WIDTH-1:0]   rd_addr;
    wire [ADDR_WIDTH-1:0]   wr_addr;

    master_bridge_async_fifo_write #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) U0_WRITE_BLOCK (
        .W_CLK(i_w_clk),
        .W_RST(i_w_n_rst),
        .wr_inc(i_w_inc),
        .gray_rd_ptr(gray_sync_rd_ptr),
        .wr_addr(wr_addr),
        .gray_wr_ptr(gray_wr_ptr),
        .wr_full(o_w_full_flag)
    );
    
    master_bridge_async_fifo_read #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) U1_READ_BLOCK (
        .R_CLK(i_r_clk),
        .R_RST(i_r_n_rst),
        .rd_inc(i_r_inc),
        .gray_wr_ptr(gray_sync_wr_ptr),
        .rd_addr(rd_addr),
        .gray_rd_ptr(gray_rd_ptr),
        .rd_empty(o_r_empty_flag)
    );  

    master_bridge_async_fifo_storage #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) U2_MEMORY (
        .CLK(i_w_clk),
        .wclken((!o_w_full_flag && i_w_inc)),
        .wr_addr(wr_addr),
        .rd_addr(rd_addr),
        .wr_data(i_w_data),
        .rd_data(o_r_data)
    );

    master_bridge_async_fifo_bit_sync #(
        .NUM_STAGES(2),
        .BUS_WIDTH(PTR_WIDTH)
    ) U3_WR_RD_SYNC (
        .CLK(i_w_clk),
        .RST(i_w_n_rst),
        .ASYNC(gray_rd_ptr),
        .SYNC(gray_sync_rd_ptr)
    );

    master_bridge_async_fifo_bit_sync #(
        .NUM_STAGES(2),
        .BUS_WIDTH(PTR_WIDTH)
    ) U4_WR_RD_SYNC (
        .CLK(i_r_clk),
        .RST(i_r_n_rst),
        .ASYNC(gray_wr_ptr),
        .SYNC(gray_sync_wr_ptr)
    );
endmodule