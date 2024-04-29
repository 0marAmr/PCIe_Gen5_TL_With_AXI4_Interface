/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project under supervision of
   Dr. Hosam Fahmy and Si vision company
   -----------------------------------------------------------------------------
   FILE NAME :      VC_HDR_BUFFER
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
module tl_rx_vc_hdr_buffer #(
    parameter   DW = 32, 
                HDR_FIELD_SIZE = 8,
                BUFFER_WIDTH = 4*DW
) (
    input   wire                       i_clk,
    input   wire                       i_n_rst,
    //------- Read Interface ------//
    input   wire                       i_r_hdr_inc,
    output  wire  [BUFFER_WIDTH-1:0]   o_r_tlp_hdr,
    output  wire  [HDR_FIELD_SIZE-1:0] o_r_hdr_ptr,
    //------- Write Interface ------//
    input   wire                       i_w_hdr_inc,
    input   wire                       i_w_hdr_en,
    input   wire  [BUFFER_WIDTH-1:0]   i_w_tlp_hdr,
    output  wire  [HDR_FIELD_SIZE-1:0] o_w_hdr_ptr
);
 
    localparam DEPTH        = 2**(HDR_FIELD_SIZE-1);
    localparam ADDRESS_SIZE = HDR_FIELD_SIZE - 1;

    reg [BUFFER_WIDTH-1:0] header_fifo [0:DEPTH-1];
    reg [HDR_FIELD_SIZE-1:0] w_hdr_ptr;
    reg [HDR_FIELD_SIZE-1:0] r_hdr_ptr;
    
    wire [ADDRESS_SIZE-1:0] write_address   = w_hdr_ptr[HDR_FIELD_SIZE-2:0]; // discard pointer extra bit
    wire [ADDRESS_SIZE-1:0] read_address    = r_hdr_ptr[HDR_FIELD_SIZE-2:0]; // discard pointer extra bit

    integer i;
    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            w_hdr_ptr <=0;
            r_hdr_ptr <=0;
        end
        else begin
            if (i_w_hdr_en) begin
                header_fifo[write_address] <= i_w_tlp_hdr;
            end
            else if(i_w_hdr_inc)begin
                w_hdr_ptr = w_hdr_ptr + 1;
            end
            if (i_r_hdr_inc) begin
                r_hdr_ptr = r_hdr_ptr + 1;
            end
        end
    end
    
    assign o_r_tlp_hdr = header_fifo[read_address];
    assign o_w_hdr_ptr = w_hdr_ptr;
    assign o_r_hdr_ptr = r_hdr_ptr;

endmodule