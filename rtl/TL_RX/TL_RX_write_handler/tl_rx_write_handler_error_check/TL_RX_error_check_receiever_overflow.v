module TL_RX_error_check_receiver_overflow #(
        BUFFER_IN_CREDS_WIDTH=9,
        BUFFER_IN_DW_WIDTH=10,
        DLL_BUFFER_IN_CREDS_WIDTH=16,
        RCV_BUFFER_IN_CREDS_WIDTH=16,
        DLL_HDR_CREDS_WIDTH=12,
        RCV_HDR_CREDS_WIDTH=12
) (
    input wire [BUFFER_IN_DW_WIDTH-1:0]         buffer_in_dw,
    input wire [DLL_BUFFER_IN_CREDS_WIDTH-1:0]  dll_data,
    input wire [DLL_HDR_CREDS_WIDTH-1:0]        dll_hdr,
    input wire [RCV_HDR_CREDS_WIDTH-1:0]        rcv_hdr,
    input wire [RCV_BUFFER_IN_CREDS_WIDTH-1:0]  rcv_data,
    input wire                                  receiver_overflow_en,
    input wire [1:0]                            hdr_scale,
    input wire [1:0]                            data_scale,

    output reg receiver_overflow_error
);

    reg [BUFFER_IN_CREDS_WIDTH-1:0] buffer_in_creds;
    reg [2:0]                       shift_scale;
    reg [BUFFER_IN_DW_WIDTH-1:0]    shifted_num;
    reg                             reminder;

    wire [RCV_HDR_CREDS_WIDTH-1:0]       rcv_hdr_total;
    wire [RCV_HDR_CREDS_WIDTH-1:0]       rcv_hdr_total_compl;
    reg  [RCV_HDR_CREDS_WIDTH-1:0]       rcv_hdr_total_compl_final;
    reg  [RCV_HDR_CREDS_WIDTH-1:0]       result_hdr;
    reg  [RCV_HDR_CREDS_WIDTH-1:0]       result_hdr_final;

    wire [RCV_BUFFER_IN_CREDS_WIDTH-1:0] rcv_data_total;
    wire [RCV_BUFFER_IN_CREDS_WIDTH-1:0] rcv_data_total_compl;
    reg  [RCV_BUFFER_IN_CREDS_WIDTH-1:0] rcv_data_total_compl_final;
    reg  [RCV_BUFFER_IN_CREDS_WIDTH-1:0] result_data;
    reg  [RCV_BUFFER_IN_CREDS_WIDTH-1:0] result_data_final;

    reg hdr_receiver_overflow_error;
    reg data_receiver_overflow_error;

    assign rcv_hdr_total = rcv_hdr + 1;
    assign rcv_hdr_total_compl = ~rcv_hdr_total + 1;

    assign rcv_data_total = rcv_data + buffer_in_creds;
    assign rcv_data_total_compl = ~rcv_data_total + 1;

    always @(*) begin
        if (receiver_overflow_en==1) begin
            case (hdr_scale)
                2'b00: begin
                    rcv_hdr_total_compl_final = rcv_hdr_total_compl[7:0];
                    result_hdr = dll_hdr + rcv_hdr_total_compl_final;
                    result_hdr_final = result_hdr[7:0];
                    if (result_hdr_final>2**7) begin
                        hdr_receiver_overflow_error=1;
                    end
                    else
                    hdr_receiver_overflow_error=0;
                end
                2'b01: begin
                    rcv_hdr_total_compl_final = rcv_hdr_total_compl[7:0];
                    result_hdr = dll_hdr + rcv_hdr_total_compl_final;
                    result_hdr_final = result_hdr[7:0];
                    if (result_hdr_final>2**7) begin
                        hdr_receiver_overflow_error=1;
                    end
                    else
                    hdr_receiver_overflow_error=0;
                end
                2'b10: begin
                    rcv_hdr_total_compl_final = rcv_hdr_total_compl[9:0];
                    result_hdr = dll_hdr + rcv_hdr_total_compl_final;
                    result_hdr_final = result_hdr[9:0];
                    if (result_hdr_final>2**9) begin
                        hdr_receiver_overflow_error=1;
                    end
                    else
                    hdr_receiver_overflow_error=0;
                end
                2'b11: begin
                    rcv_hdr_total_compl_final = rcv_hdr_total_compl[11:0];
                    result_hdr = dll_hdr + rcv_hdr_total_compl_final;
                    result_hdr_final = result_hdr[11:0];
                    if (result_hdr_final>2**11) begin
                        hdr_receiver_overflow_error=1;
                    end
                    else
                    hdr_receiver_overflow_error=0;
                end
            endcase
            case (data_scale)
                2'b00: begin
                    rcv_data_total_compl_final = rcv_data_total_compl[11:0];
                    result_data = dll_data + rcv_data_total_compl_final;
                    result_data_final = result_data[11:0];
                    if (result_data_final>2**11) begin
                        data_receiver_overflow_error=1;
                    end
                    else
                    data_receiver_overflow_error=0;
                end
                2'b01: begin
                    rcv_data_total_compl_final = rcv_data_total_compl[11:0];
                    result_data = dll_data + rcv_data_total_compl_final;
                    result_data_final = result_data[11:0];
                    if (result_data_final>2**11) begin
                        data_receiver_overflow_error=1;
                    end
                    else
                    data_receiver_overflow_error=0;
                end
                2'b10: begin
                    rcv_data_total_compl_final = rcv_data_total_compl[13:0];
                    result_data = dll_data + rcv_data_total_compl_final;
                    result_data_final = result_data[13:0];
                    if (result_data_final>2**13) begin
                        data_receiver_overflow_error=1;
                    end
                    else
                    data_receiver_overflow_error=0;
                end
                2'b11: begin
                    rcv_data_total_compl_final = rcv_data_total_compl[15:0];
                    result_data = dll_data + rcv_data_total_compl_final;
                    result_data_final = result_data[15:0];
                    if (result_data_final>2**15) begin
                        data_receiver_overflow_error=1;
                    end
                    else
                    data_receiver_overflow_error=0;
                end
            endcase
                case (data_scale)
                2'b00 : begin
                    shift_scale=2;
                    shifted_num = buffer_in_dw >>2;
                    reminder =|buffer_in_dw[1:0];
                    buffer_in_creds = shifted_num + reminder + data_scale[1];
                end
                2'b01 : begin
                    shift_scale=2;
                    shifted_num = buffer_in_dw >>2;
                    reminder =|buffer_in_dw[1:0];
                    buffer_in_creds = shifted_num + reminder + data_scale[1];
                end
                2'b10 : begin
                    shift_scale=4;
                    shifted_num = buffer_in_dw >>4;
                    reminder =|buffer_in_dw[3:0];
                    buffer_in_creds = shifted_num + reminder + data_scale[1];
                end
                2'b11 : begin
                    shift_scale=6;
                    shifted_num = buffer_in_dw >>6;
                    reminder =|buffer_in_dw[5:0];
                    buffer_in_creds = shifted_num + reminder + data_scale[1];
                end
            endcase
            receiver_overflow_error = hdr_receiver_overflow_error || data_receiver_overflow_error;
        end
        else begin
            receiver_overflow_error=0;
        end
    end
endmodule
