/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_vc_buffer_control
   DEPARTMENT :     VC
   AUTHOR :         Reem Mohamed - Omar Hafez
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com - eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
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
   -FHDR------------------------------------------------------------------------*/
module tl_rx_vc_buffer_control #(
    parameter   HDR_PTR_SIZE = 8,
                DATA_PTR_SIZE = 11
) (
    //------- Read Interface ------//
    input   wire [HDR_PTR_SIZE-1:0]     i_r_hdr_ptr,
    input   wire [DATA_PTR_SIZE-1:0]    i_r_data_ptr,
    input   wire                        i_r_hdr_inc,
    input   wire                        i_r_data_inc,
    output  wire                        o_r_hdr_inc,
    output  wire                        o_r_data_inc,
    //------- Write Interface ------//
    input   wire [HDR_PTR_SIZE-1:0]     i_w_hdr_ptr,
    input   wire [DATA_PTR_SIZE-1:0]    i_w_data_ptr,
    input   wire [1:0]                  i_w_status,
    input   wire                        i_w_data_transaction,
    input   wire                        i_w_valid,
    input   wire                        i_hdr_write_flag, // signal to enable writing header, it is written only when dll_sop is raised
    input   wire                        i_digest_cycle_flag,
    output  wire                        o_w_data_ptr_ld,  // data pointer load: in case no error (w valid = 1) the pointer loads the new counter value 
    output  wire                        o_w_data_cntr_ld, // data counter load: in case of an error (w valid = 0) the counter loads the initial write pointer value
    output  wire                        o_w_hdr_en, 
    output  wire                        o_w_data_en, 
    output  wire                        o_w_hdr_inc,
    //------- Flags ------//
    output  wire                        o_hdr_empty_flag, 
    output  wire                        o_data_empty_flag, 
    output  wire                        o_hdr_full_flag, 
    output  wire                        o_data_full_flag
);

    localparam [1:0]    ERROR_EVALUATE  = 2'b00,
                        HDR_RCV         = 2'b01,
                        ERROR_CHK       = 2'b11;
    
    /*******Flags Logic *******/
    assign o_hdr_empty_flag = ( i_w_hdr_ptr == i_r_hdr_ptr);
    assign o_hdr_full_flag =(i_w_hdr_ptr[HDR_PTR_SIZE-1] != i_r_hdr_ptr[HDR_PTR_SIZE-1]) && (i_w_hdr_ptr[HDR_PTR_SIZE-2:0] == i_r_hdr_ptr[HDR_PTR_SIZE-2:0]);
    assign o_data_empty_flag = (i_w_data_ptr == i_r_data_ptr);
    assign o_data_full_flag =(i_w_data_ptr[DATA_PTR_SIZE-1] != i_r_data_ptr[DATA_PTR_SIZE-1]) && (i_w_data_ptr[DATA_PTR_SIZE-2:0] == i_r_data_ptr[DATA_PTR_SIZE-2:0]);

    /******* Control Signals *******/
    // 
    assign o_w_hdr_en = i_hdr_write_flag && ~o_hdr_full_flag;    // enable signal is mandatory here so that header is not overwritten in data recieve cycles
    assign o_w_hdr_inc = (i_w_status == ERROR_EVALUATE) && i_w_valid;   // only increment after evaluating that there is no error
    assign o_w_data_en = ~o_data_full_flag && i_w_data_transaction && ~i_digest_cycle_flag;
    assign o_r_hdr_inc = i_r_hdr_inc && ~o_hdr_empty_flag;
    assign o_r_data_inc = i_r_data_inc && ~o_data_empty_flag; // must add increment value to the calculation, make it an output from this block also

    /* both are activeted during data transactions only */
    assign o_w_data_ptr_ld = (i_w_status == ERROR_EVALUATE) && (i_w_valid) && i_w_data_transaction;
    // assign o_w_data_cntr_ld = ((i_w_status == ERROR_EVALUATE) && (~i_w_valid) && i_w_data_transaction);
    assign o_w_data_cntr_ld = 0;

endmodule
