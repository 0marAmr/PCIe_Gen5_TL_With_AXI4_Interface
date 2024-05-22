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
module tl_rx_error_check_receiver_overflow #(
        parameter PAYLOAD_LENGTH=10,
        HDR_FIELD_SIZE=8,
        DATA_FIELD_SIZE=12
) (
    input wire [PAYLOAD_LENGTH-1:0]   buffer_in_dw,
    input wire [DATA_FIELD_SIZE-1:0]  dll_data,
    input wire [HDR_FIELD_SIZE-1:0]   dll_hdr,
    input wire [HDR_FIELD_SIZE-1:0]   rcv_hdr,
    input wire [DATA_FIELD_SIZE-1:0]  rcv_data,
    input wire                        receiver_overflow_en,
    // input wire [1:0]                  hdr_scale,
    // input wire [1:0]                  data_scale,
    output wire receiver_overflow_error
);
    localparam BUFFER_IN_CREDS_WIDTH=9;

    reg [BUFFER_IN_CREDS_WIDTH-1:0] buffer_in_creds;
    reg [PAYLOAD_LENGTH-1:0]        shifted_num;
    reg                             reminder;

    wire [HDR_FIELD_SIZE-1:0]  rcv_hdr_total;
    wire [HDR_FIELD_SIZE-1:0]  rcv_hdr_total_compl;
    reg  [HDR_FIELD_SIZE-1:0]  rcv_hdr_total_compl_final;
    reg  [HDR_FIELD_SIZE-1:0]  result_hdr;
    reg  [HDR_FIELD_SIZE-1:0]  result_hdr_final;

    wire [DATA_FIELD_SIZE-1:0] rcv_data_total;
    wire [DATA_FIELD_SIZE-1:0] rcv_data_total_compl;
    reg  [DATA_FIELD_SIZE-1:0] rcv_data_total_compl_final;
    reg  [DATA_FIELD_SIZE-1:0] result_data;
    reg  [DATA_FIELD_SIZE-1:0] result_data_final;

    reg hdr_receiver_overflow_error;
    reg data_receiver_overflow_error;

    assign rcv_hdr_total = rcv_hdr + 1;
    assign rcv_hdr_total_compl = ~rcv_hdr_total + 1;

    assign rcv_data_total = rcv_data + buffer_in_creds;
    assign rcv_data_total_compl = ~rcv_data_total + 1;


    generate
        case (HDR_FIELD_SIZE)
            8 : begin
                always @(*) begin                    
                    rcv_hdr_total_compl_final = rcv_hdr_total_compl[7:0];
                    result_hdr = dll_hdr + rcv_hdr_total_compl_final;
                    result_hdr_final = result_hdr[7:0];
                    if (result_hdr_final>2**7) begin
                        hdr_receiver_overflow_error=1;
                    end
                    else
                        hdr_receiver_overflow_error=0;
                end
            end
            10: begin
                always @(*) begin
                    rcv_hdr_total_compl_final = rcv_hdr_total_compl[9:0];
                    result_hdr = dll_hdr + rcv_hdr_total_compl_final;
                    result_hdr_final = result_hdr[9:0];
                    if (result_hdr_final>2**9) begin
                        hdr_receiver_overflow_error=1;
                    end
                    else
                        hdr_receiver_overflow_error=0;
                end
            end
            12: begin
                always @(*) begin
                    rcv_hdr_total_compl_final = rcv_hdr_total_compl[11:0];
                    result_hdr = dll_hdr + rcv_hdr_total_compl_final;
                    result_hdr_final = result_hdr[11:0];
                    if (result_hdr_final>2**11) begin
                        hdr_receiver_overflow_error=1;
                    end
                    else
                        hdr_receiver_overflow_error=0;
                end
            end
        endcase
    endgenerate

    generate
        case (DATA_FIELD_SIZE)
        12: begin
            always @(*) begin
                /*Cred Conv*/
                shifted_num = buffer_in_dw >>2;
                reminder =|buffer_in_dw[1:0];
                buffer_in_creds = shifted_num + reminder;
                /*Evaluation*/
                rcv_data_total_compl_final = rcv_data_total_compl[11:0];
                result_data = dll_data + rcv_data_total_compl_final;
                result_data_final = result_data[11:0];
                if (result_data_final>2**11) begin
                    data_receiver_overflow_error=1;
                end
                else
                data_receiver_overflow_error=0;
                end
            end
        14: begin
            always @(*) begin
            /*Cred Conv*/
                shifted_num = buffer_in_dw >>4;
                reminder =|buffer_in_dw[3:0];
                buffer_in_creds = shifted_num + reminder + 1'b1;
                /*Evaluation*/
                rcv_data_total_compl_final = rcv_data_total_compl[13:0];
                result_data = dll_data + rcv_data_total_compl_final;
                result_data_final = result_data[13:0];
                if (result_data_final>2**13) begin
                    data_receiver_overflow_error=1;
                end
                else
                data_receiver_overflow_error=0;
            end
        end
        16: begin
            always @(*) begin
                /*Cred Conv*/
                shifted_num = buffer_in_dw >>6;
                reminder =|buffer_in_dw[5:0];
                buffer_in_creds = shifted_num + reminder + 1'b1;
                /*Evaluation*/
                rcv_data_total_compl_final = rcv_data_total_compl[15:0];
                result_data = dll_data + rcv_data_total_compl_final;
                result_data_final = result_data[15:0];
                if (result_data_final>2**15) begin
                    data_receiver_overflow_error=1;
                end
                else
                data_receiver_overflow_error=0;
            end
        end
    endcase
    endgenerate

    assign receiver_overflow_error = (hdr_receiver_overflow_error || data_receiver_overflow_error) && receiver_overflow_en;


endmodule
