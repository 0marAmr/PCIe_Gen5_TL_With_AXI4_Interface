/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_error_check_receiver_overflow_top
   DEPARTMENT :     Error Check -Wtire Handler
   AUTHOR :         Reem Mohamed - Omar Hafez
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com - eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-03-16              initial version
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
module tl_rx_error_check_receiver_overflow_top #(
        parameter PAYLOAD_LENGTH=10,
        HDR_FIELD_SIZE=8,
        DATA_FIELD_SIZE=12
) (
    input wire [PAYLOAD_LENGTH-1:0] i_buffer_in,
    input wire  i_receiver_overflow_en,
    // input wire [1:0] i_p_hdr_scale,
    // input wire [1:0] i_p_data_scale,
    // input wire [1:0] i_np_hdr_scale,
    // input wire [1:0] i_np_data_scale,   
    // input wire [1:0] i_cpl_hdr_scale,
    // input wire [1:0] i_cpl_data_scale,
    input wire [1:0] i_buffer_typ,

    input wire [HDR_FIELD_SIZE-1:0]  i_p_rcv_hdr,
    input wire [DATA_FIELD_SIZE-1:0] i_p_rcv_data,    
    input wire [HDR_FIELD_SIZE-1:0]  i_np_rcv_hdr,
    input wire [DATA_FIELD_SIZE-1:0] i_np_rcv_data,    
    input wire [HDR_FIELD_SIZE-1:0]  i_cpl_rcv_hdr,
    input wire [DATA_FIELD_SIZE-1:0] i_cpl_rcv_data,

    input wire [DATA_FIELD_SIZE-1:0] i_p_dll_data,
    input wire [HDR_FIELD_SIZE-1:0]  i_p_dll_hdr,    
    input wire [DATA_FIELD_SIZE-1:0] i_np_dll_data,
    input wire [HDR_FIELD_SIZE-1:0]  i_np_dll_hdr,    
    input wire [DATA_FIELD_SIZE-1:0] i_cpl_dll_data,
    input wire [HDR_FIELD_SIZE-1:0]  i_cpl_dll_hdr,

    output wire o_receiver_overflow_error 
);

    localparam [1:0]    POSTED = 2'b00,
                        NON_POSTED = 2'b01,
                        COMPLETION = 2'b10;

    reg [PAYLOAD_LENGTH-1:0] p_buffer_in;
    reg [PAYLOAD_LENGTH-1:0] np_buffer_in;
    reg [PAYLOAD_LENGTH-1:0] cpl_buffer_in;
    reg p_receiver_overflow_en;
    reg np_receiver_overflow_en;
    reg cpl_receiver_overflow_en;

    wire p_receiver_overflow_error;
    wire np_receiver_overflow_error;
    wire cpl_receiver_overflow_error;

    always @(*) begin
        case (i_buffer_typ)
            POSTED: begin
                p_buffer_in=i_buffer_in;
                np_buffer_in=0;
                cpl_buffer_in=0;
                p_receiver_overflow_en=i_receiver_overflow_en;
                np_receiver_overflow_en=0;
                cpl_receiver_overflow_en=0;
            end
            NON_POSTED: begin
                p_buffer_in=0;
                np_buffer_in=i_buffer_in;
                cpl_buffer_in=0;
                p_receiver_overflow_en=0;
                np_receiver_overflow_en=i_receiver_overflow_en;
                cpl_receiver_overflow_en=0;
            end
            COMPLETION: begin
                p_buffer_in=0;
                np_buffer_in=0;
                cpl_buffer_in=i_buffer_in;
                p_receiver_overflow_en=0;
                np_receiver_overflow_en=0;
                cpl_receiver_overflow_en=i_receiver_overflow_en;
            end
            2'b11: begin
                p_buffer_in=0;
                np_buffer_in=0;
                cpl_buffer_in=0;
                p_receiver_overflow_en=0;
                np_receiver_overflow_en=0;
                cpl_receiver_overflow_en=0;
            end 
        endcase
    end

    tl_rx_error_check_receiver_overflow #(
        .HDR_FIELD_SIZE(HDR_FIELD_SIZE),
        .DATA_FIELD_SIZE(DATA_FIELD_SIZE),
        /*FIXED*/
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH)
    )u_p(
        .buffer_in_dw(p_buffer_in),
        .dll_data(i_p_dll_data),
        .dll_hdr(i_p_dll_hdr),
        .rcv_hdr(i_p_rcv_hdr),
        .rcv_data(i_p_rcv_data),
        .receiver_overflow_en(p_receiver_overflow_en),
        // .hdr_scale(i_p_hdr_scale),
        // .data_scale(i_p_data_scale),
        .receiver_overflow_error(p_receiver_overflow_error)
    );

    tl_rx_error_check_receiver_overflow #(
        .HDR_FIELD_SIZE(HDR_FIELD_SIZE),
        .DATA_FIELD_SIZE(DATA_FIELD_SIZE),
        /*FIXED*/
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH)
    ) u_np (
        .buffer_in_dw(np_buffer_in),
        .dll_data(i_np_dll_data),
        .dll_hdr(i_np_dll_hdr),
        .rcv_hdr(i_np_rcv_hdr),
        .rcv_data(i_np_rcv_data),
        .receiver_overflow_en(np_receiver_overflow_en),
        // .hdr_scale(i_np_hdr_scale),
        // .data_scale(i_np_data_scale),
        .receiver_overflow_error(np_receiver_overflow_error)
    );

    tl_rx_error_check_receiver_overflow #(
        .HDR_FIELD_SIZE(HDR_FIELD_SIZE),
        .DATA_FIELD_SIZE(DATA_FIELD_SIZE),
        /*FIXED*/
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH)
    ) u_cpl (
        .buffer_in_dw(cpl_buffer_in),
        .dll_data(i_cpl_dll_data),
        .dll_hdr(i_cpl_dll_hdr),
        .rcv_hdr(i_cpl_rcv_hdr),
        .rcv_data(i_cpl_rcv_data),
        .receiver_overflow_en(cpl_receiver_overflow_en),
        // .hdr_scale(i_cpl_hdr_scale),
        // .data_scale(i_cpl_data_scale),
        .receiver_overflow_error(cpl_receiver_overflow_error)
    ); 

    assign o_receiver_overflow_error=p_receiver_overflow_error||np_receiver_overflow_error||cpl_receiver_overflow_error;
    
endmodule