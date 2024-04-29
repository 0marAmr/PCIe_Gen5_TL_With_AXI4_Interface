/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project under supervision
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_vc_buffer
   DEPARTMENT :     VC
   AUTHOR :         Omar Hafez
   AUTHOR’S EMAIL : eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-03-10              initial version
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
   -----------------------------------------------------------------------------*/
module tl_rx_vc_buffer #(
        parameter   DW = 32,
                    HDR_FIELD_SIZE = 8,
                    DATA_FIELD_SIZE = 12,
                    W_CTRL_BUS_WIDTH = 5,
                    R_CTRL_BUS_WIDTH = 4,
                    DATA_BUFFER_WIDTH = 8*DW,      
                    HDR_BUFFER_WIDTH = 4*DW,
                    BEAT_SIZE = 32*DW
) (
    input   wire                            i_clk,
    input   wire                            i_n_rst,
    //------- Read Interface ------//
    input   wire  [R_CTRL_BUS_WIDTH-1:0]    i_r_ctrl_bus,
    output  wire  [4*DW-1:0]               o_r_tlp_hdr,
    output  wire  [32*DW-1:0]              o_r_tlp_data,
    //------- Write Interface ------//
    input   wire  [W_CTRL_BUS_WIDTH-1:0]    i_w_ctrl_bus,
    input   wire  [4*DW-1:0]               i_w_tlp_hdr,
    input   wire  [DATA_BUFFER_WIDTH-1:0]   i_w_tlp_data,
    //------- Flags ------//
    output  wire                            o_hdr_full_flag,
    output  wire                            o_data_full_flag,
    output  wire                            o_hdr_empty_flag,
    output  wire                            o_data_empty_flag

);

    wire                        w_data_transaction;
    wire [1:0]                  w_status;
    wire                        w_valid;
    wire [HDR_FIELD_SIZE-1:0]   r_hdr_ptr;
    wire [HDR_FIELD_SIZE-1:0]   w_hdr_ptr;
    wire [DATA_FIELD_SIZE-2:0]  r_data_ptr;
    wire [DATA_FIELD_SIZE-2:0]  w_data_ptr;
    wire                        w_data_ptr_ld;
    wire                        w_data_cntr_ld;
    wire                        w_hdr_en;
    wire                        w_data_en;
    wire                        r_hdr_inc;
    wire                        r_data_inc;
    wire                        r_hdr_inc_en;
    wire                        r_data_inc_en;
    wire [2:0]                  r_data_inc_value;

    assign {w_valid, hdr_write_flag, w_status, w_data_transaction} = i_w_ctrl_bus;
    assign {r_hdr_inc_en, r_data_inc_en, r_data_inc_value} = i_r_ctrl_bus;

    tl_rx_vc_buffer_control #(
        .HDR_FIELD_SIZE(HDR_FIELD_SIZE),
        .DATA_FIELD_SIZE(DATA_FIELD_SIZE)
    ) u_buffer_ctrl (
        //------- Read Interface ------//
        .i_r_hdr_ptr(r_hdr_ptr),
        .i_r_data_ptr(r_data_ptr),
        .i_r_hdr_inc(r_hdr_inc_en),
        .i_r_data_inc(r_data_inc_en),
        .o_r_hdr_inc(r_hdr_inc),
        .o_r_data_inc(r_data_inc),
        //------- Write Interface ------//
        .i_w_hdr_ptr(w_hdr_ptr),
        .i_w_data_ptr(w_data_ptr),
        .i_w_status(w_status),
        .i_w_data_transaction(w_data_transaction),
        .i_w_valid(w_valid),
        .o_w_data_ptr_ld(w_data_ptr_ld),
        .o_w_data_cntr_ld(w_data_cntr_ld),
        .o_w_hdr_en(w_hdr_en),
        .o_w_data_en(w_data_en),
        .o_w_hdr_inc(w_hdr_inc),
         //------- Flags ------//
        .o_hdr_empty_flag(o_hdr_empty_flag),
        .o_data_empty_flag(o_data_empty_flag),
        .o_hdr_full_flag(o_hdr_full_flag),
        .o_data_full_flag(o_data_full_flag)
    );

    tl_rx_vc_data_buffer #(
        .DATA_FIELD_SIZE(DATA_FIELD_SIZE),
        .BUFFER_WIDTH(DATA_BUFFER_WIDTH)
    ) u_data_buffer (
        .i_clk(i_clk),
        .i_n_rst(i_n_rst),
        //------- Read Interface ------//
        .i_r_data_inc_value(r_data_inc_value), 
        .i_r_data_inc_en(r_data_inc), 
        .o_r_tlp_data(o_r_tlp_data),
        .o_r_data_ptr(r_data_ptr),
        //------- Write Interface ------//
        .i_w_data_ptr_ld(w_data_ptr_ld),
        .i_w_data_cntr_ld(w_data_cntr_ld),
        .i_hdr_write_flag(hdr_write_flag),
        .i_w_data_en(w_data_en),
        .i_w_tlp_data(i_w_tlp_data),
        .o_w_data_ptr(w_data_ptr)
    );

    tl_rx_vc_hdr_buffer #(
        .HDR_FIELD_SIZE(HDR_FIELD_SIZE),
        .BUFFER_WIDTH(HDR_BUFFER_WIDTH)
    ) u_hdr_buffer (
        .i_clk(i_clk),
        .i_n_rst(i_n_rst),
        //------- Read Interface ------//
        .i_r_hdr_inc(r_hdr_inc),
        .o_r_tlp_hdr(o_r_tlp_hdr),
        .o_r_hdr_ptr(r_hdr_ptr),
        //------- Write Interface ------//
        .i_w_hdr_inc(w_hdr_inc),
        .i_w_hdr_en(w_hdr_en),
        .i_w_tlp_hdr(i_w_tlp_hdr),
        .o_w_hdr_ptr(w_hdr_ptr)
    );

endmodule