/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_fc_counters
   DEPARTMENT :     tl_rx_fc
   AUTHOR :         Reem Mohamed
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-04-15              initial version
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
module tl_rx_fc_counters #(
    parameter PAYLOAD_LENGTH=10,
    PAYLOAD_IN_CREDS=9,
    HDR_FIELD_SIZE=8,
    DATA_FIELD_SIZE=12,
    HDR_FIFO_DEPTH = 2**7,
    DATA_FIFO_DEPTH = 2**10
) (
    input wire clk,
    input wire rst,
    input wire [PAYLOAD_LENGTH-1:0] buffer_in_dw,
    input wire [PAYLOAD_LENGTH-1:0] buffer_out_dw,
    input wire dll_init,
    input wire cr_hdr_inc,
    input wire ca_hdr_inc,
    input wire cr_data_inc,
    input wire ca_data_inc,
    input wire [1:0] typ,
    input wire [2:0] max_payload,
    output wire [HDR_FIELD_SIZE-1:0] creds_alloc_hdr,
    output wire [HDR_FIELD_SIZE-1:0] creds_rcv_hdr,
    output wire [DATA_FIELD_SIZE-1:0] creds_alloc_data,
    output wire [DATA_FIELD_SIZE-1:0] creds_rcv_data,
    output wire [1:0] dll_hdr_scale,
    output wire [1:0] dll_data_scale,
    output wire update
);

    wire hdr_update_top;
    wire data_update_top;
    wire [PAYLOAD_IN_CREDS-1:0] buffer_in_creds;
    wire [PAYLOAD_IN_CREDS-1:0] buffer_out_creds;

    tl_rx_fc_hdr #(
        .HDR_FIELD_SIZE(HDR_FIELD_SIZE),
        .HDR_FIFO_DEPTH(HDR_FIFO_DEPTH)
    )u_hdr_fc(
        .clk(clk),
        .rst(rst),
        .dll_init(dll_init),
        .cr_hdr_inc(cr_hdr_inc),
        .ca_hdr_inc(ca_hdr_inc),
        .creds_alloc_hdr(creds_alloc_hdr),
        .creds_rcv_hdr(creds_rcv_hdr),
        .dll_hdr_scale(dll_hdr_scale),
        .hdr_update(hdr_update_top)
    );

    tl_rx_fc_data #(
        .DATA_FIELD_SIZE(DATA_FIELD_SIZE),
        .DATA_FIFO_DEPTH(DATA_FIFO_DEPTH),
        /*FIXED*/
        .PAYLOAD_IN_CREDS(PAYLOAD_IN_CREDS)
    ) u_data_fc(
        .clk(clk),
        .rst(rst),
        .dll_init(dll_init),
        .typ(typ),
        .max_payload(max_payload),
        .cr_data_inc(cr_data_inc),
        .ca_data_inc(ca_data_inc),
        .data_buffer_in(buffer_in_creds),
        .data_buffer_out(buffer_out_creds),
        .creds_alloc_data(creds_alloc_data),
        .creds_rcv_data(creds_rcv_data),
        .dll_data_scale(dll_data_scale),
        .data_update(data_update_top)
    );

    tl_rx_fc_creds_conv #(
        /*FIXED*/
        .PAYLOAD_IN_CREDS(PAYLOAD_IN_CREDS),
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH)
    ) u_buffer_in_conv (
        .buffer_dw(buffer_in_dw),
        .data_scale(dll_data_scale),
        .buffer_creds(buffer_in_creds)
    );

    tl_rx_fc_creds_conv #(
        /*FIXED*/
        .PAYLOAD_IN_CREDS(PAYLOAD_IN_CREDS),
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH)
    ) u_buffer_out_conv (
        .buffer_dw(buffer_out_dw),
        .data_scale(dll_data_scale),
        .buffer_creds(buffer_out_creds)
    );

    assign update= hdr_update_top || data_update_top;

endmodule