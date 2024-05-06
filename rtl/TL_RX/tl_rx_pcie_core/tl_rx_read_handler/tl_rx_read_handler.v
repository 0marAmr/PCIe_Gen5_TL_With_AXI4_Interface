/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      TL_RX_read_handler_cpl_control
   DEPARTMENT :     Read Handler
   AUTHOR :         Reem Mohamed - Omar Hafez
   AUTHOR’S EMAIL : eng.omar.amr@gmail.com
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
    parameter   FLAGS_WIDTH = 6,
                PAYLOAD_LENGTH = 10,
                VALID_DATA_WIDTH = 5,
                R_CTRL_BUS_WIDTH = 5

) (
    input   wire        i_clk,
    input   wire        i_n_rst,
    input   wire    [FLAGS_WIDTH-1:0]           i_vcn_r_empty_flags,
    //----- Request Interface -----//
    
    //----- Completion Interface -----//
    /**Channel Interface**/
    input   wire                                i_cpl_fmt_data_bit,
    input   wire    [PAYLOAD_LENGTH-1:0]        i_cpl_length_field,
    output  wire    [R_CTRL_BUS_WIDTH-1:0]      o_r_completion_ctrl,
    /**Slave Interface**/
    input   wire                                i_slave_ready,
    output  wire                                o_slave_cpl_vaild,
    output  wire    [VALID_DATA_WIDTH-1:0]      o_slave_cpl_valid_data
);
    
    TL_RX_read_handler_cpl_control #(
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH)
    ) u_TL_RX_read_handler_cpl_control (
        .i_clk(i_clk),
        .i_n_rst(i_n_rst),
        /**Channel Interface**/
        .i_cpl_fmt_data_bit(i_cpl_fmt_data_bit),
        .i_vcn_cpl_r_empty_flags(i_vcn_r_empty_flags[1:0]),
        .i_cpl_length_field(i_cpl_length_field),
        .o_r_completion_ctrl(o_r_completion_ctrl),
        /**Slave Interface**/
        .i_slave_ready(i_slave_ready),
        .o_slave_cpl_vaild(o_slave_cpl_vaild),
        .o_slave_cpl_valid_data(o_slave_cpl_valid_data)
    );

endmodule