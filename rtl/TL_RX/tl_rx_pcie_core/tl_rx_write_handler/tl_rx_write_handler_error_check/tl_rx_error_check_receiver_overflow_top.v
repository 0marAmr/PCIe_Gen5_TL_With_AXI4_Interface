module tl_rx_error_check_receiver_overflow_top #(
        parameter BUFFER_IN_DW_WIDTH=10,
        DLL_DATA_CREDS_WIDTH=16,
        RCV_DATA_CREDS_WIDTH=16,
        DLL_HDR_CREDS_WIDTH=12,
        RCV_HDR_CREDS_WIDTH=12
) (
    input wire [BUFFER_IN_DW_WIDTH-1:0]buffer_in,
    input wire  receiver_overflow_en,
    input wire [1:0] p_hdr_scale,
    input wire [1:0] p_data_scale,
    input wire [1:0] np_hdr_scale,
    input wire [1:0] np_data_scale,   
    input wire [1:0] cpl_hdr_scale,
    input wire [1:0] cpl_data_scale,
    input wire [1:0] buffer_typ,

    input wire [RCV_HDR_CREDS_WIDTH-1:0]  p_rcv_hdr,
    input wire [RCV_DATA_CREDS_WIDTH-1:0] p_rcv_data,    
    input wire [RCV_HDR_CREDS_WIDTH-1:0]  np_rcv_hdr,
    input wire [RCV_DATA_CREDS_WIDTH-1:0] np_rcv_data,    
    input wire [RCV_HDR_CREDS_WIDTH-1:0]  cpl_rcv_hdr,
    input wire [RCV_DATA_CREDS_WIDTH-1:0] cpl_rcv_data,

    input wire [DLL_DATA_CREDS_WIDTH-1:0] p_dll_data,
    input wire [DLL_HDR_CREDS_WIDTH-1:0]  p_dll_hdr,    
    input wire [DLL_DATA_CREDS_WIDTH-1:0] np_dll_data,
    input wire [DLL_HDR_CREDS_WIDTH-1:0]  np_dll_hdr,    
    input wire [DLL_DATA_CREDS_WIDTH-1:0] cpl_dll_data,
    input wire [DLL_HDR_CREDS_WIDTH-1:0]  cpl_dll_hdr,

    output wire receiver_overflow_error 
);

    reg [BUFFER_IN_DW_WIDTH-1:0] p_buffer_in;
    reg [BUFFER_IN_DW_WIDTH-1:0] np_buffer_in;
    reg [BUFFER_IN_DW_WIDTH-1:0] cpl_buffer_in;
    reg p_receiver_overflow_en;
    reg np_receiver_overflow_en;
    reg cpl_receiver_overflow_en;

    wire p_receiver_overflow_error;
    wire np_receiver_overflow_error;
    wire cpl_receiver_overflow_error;

    always @(*) begin
        case (buffer_typ)
            2'b00: begin
                p_buffer_in=buffer_in;
                np_buffer_in=0;
                cpl_buffer_in=0;
                p_receiver_overflow_en=receiver_overflow_en;
                np_receiver_overflow_en=0;
                cpl_receiver_overflow_en=0;
            end
            2'b01: begin
                p_buffer_in=0;
                np_buffer_in=buffer_in;
                cpl_buffer_in=0;
                p_receiver_overflow_en=0;
                np_receiver_overflow_en=receiver_overflow_en;
                cpl_receiver_overflow_en=0;
            end
            2'b10: begin
                p_buffer_in=0;
                np_buffer_in=0;
                cpl_buffer_in=buffer_in;
                p_receiver_overflow_en=0;
                np_receiver_overflow_en=0;
                cpl_receiver_overflow_en=receiver_overflow_en;
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

    tl_rx_error_check_receiver_overflow u_p(
        .buffer_in_dw(p_buffer_in),
        .dll_data(p_dll_data),
        .dll_hdr(p_dll_hdr),
        .rcv_hdr(p_rcv_hdr),
        .rcv_data(p_rcv_data),
        .receiver_overflow_en(p_receiver_overflow_en),
        .hdr_scale(p_hdr_scale),
        .data_scale(p_data_scale),
        .receiver_overflow_error(p_receiver_overflow_error)
    );

    tl_rx_error_check_receiver_overflow u_np(
        .buffer_in_dw(np_buffer_in),
        .dll_data(np_dll_data),
        .dll_hdr(np_dll_hdr),
        .rcv_hdr(np_rcv_hdr),
        .rcv_data(np_rcv_data),
        .receiver_overflow_en(np_receiver_overflow_en),
        .hdr_scale(np_hdr_scale),
        .data_scale(np_data_scale),
        .receiver_overflow_error(np_receiver_overflow_error)
    );

    tl_rx_error_check_receiver_overflow u_cpl(
        .buffer_in_dw(cpl_buffer_in),
        .dll_data(cpl_dll_data),
        .dll_hdr(cpl_dll_hdr),
        .rcv_hdr(cpl_rcv_hdr),
        .rcv_data(cpl_rcv_data),
        .receiver_overflow_en(cpl_receiver_overflow_en),
        .hdr_scale(cpl_hdr_scale),
        .data_scale(cpl_data_scale),
        .receiver_overflow_error(cpl_receiver_overflow_error)
    ); 

    assign receiver_overflow_error=p_receiver_overflow_error||np_receiver_overflow_error||cpl_receiver_overflow_error;
endmodule