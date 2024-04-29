/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project under supervision of
   Dr. Hosam Fahmy and Si vision company
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_vc_buffer_control
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
module tl_rx_vc_buffer_control #(
    parameter   HDR_FIELD_SIZE = 8,
                DATA_FIELD_SIZE = 12
) (
    //------- Read Interface ------//
    input   wire [HDR_FIELD_SIZE-1:0]   i_r_hdr_ptr,
    input   wire [DATA_FIELD_SIZE-2:0]  i_r_data_ptr,
    input   wire                        i_r_hdr_inc,
    input   wire                        i_r_data_inc,
    output  wire                        o_r_hdr_inc, 
    output  wire                        o_r_data_inc, 
    //------- Write Interface ------//
    input   wire [HDR_FIELD_SIZE-1:0]   i_w_hdr_ptr,
    input   wire [DATA_FIELD_SIZE-2:0]  i_w_data_ptr,
    input   wire [1:0]                  i_w_status,
    input   wire                        i_w_data_transaction,
    input   wire                        i_w_valid,
    output  reg                         o_w_data_ptr_ld,
    output  reg                         o_w_data_cntr_ld,
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
                        DATA_RCV        = 2'b10,
                        ERROR_CHK       = 2'b11;

    assign o_hdr_empty_flag = (i_r_hdr_ptr == i_w_hdr_ptr);
    assign o_hdr_full_flag =(i_w_hdr_ptr[HDR_FIELD_SIZE-1] != i_r_hdr_ptr[HDR_FIELD_SIZE-1]) && (i_w_hdr_ptr[HDR_FIELD_SIZE-2:0] == i_w_hdr_ptr[HDR_FIELD_SIZE-2:0]);
    assign o_data_empty_flag = (i_r_data_ptr == i_w_data_ptr);
    assign o_data_full_flag =(i_w_data_ptr[DATA_FIELD_SIZE-2] != i_r_data_ptr[DATA_FIELD_SIZE-2]) && (i_w_data_ptr[DATA_FIELD_SIZE-3:0] == i_w_data_ptr[DATA_FIELD_SIZE-3:0]);

    assign o_w_hdr_en = (i_w_status == HDR_RCV) && ~o_hdr_full_flag;
    assign o_w_hdr_inc = (i_w_status == ERROR_EVALUATE) && i_w_valid;
    assign o_w_data_en = (^i_w_status) && ~o_data_full_flag && i_w_data_transaction;
    assign o_r_hdr_inc = i_r_hdr_inc && ~o_hdr_empty_flag;
    assign o_r_data_inc = i_r_data_inc && ~o_data_empty_flag; // must add increment value to the calculation, make it an output from this block also

    always @(*) begin
        if (i_w_status == ERROR_EVALUATE) begin
            if (i_w_valid) begin
				o_w_data_ptr_ld= 1;
                o_w_data_cntr_ld = 0;
            end
            else begin
                o_w_data_ptr_ld = 0;
                o_w_data_cntr_ld = 1;
            end
        end
        else begin
            o_w_data_ptr_ld = 0;
            o_w_data_cntr_ld = 0;
        end
    end

endmodule
