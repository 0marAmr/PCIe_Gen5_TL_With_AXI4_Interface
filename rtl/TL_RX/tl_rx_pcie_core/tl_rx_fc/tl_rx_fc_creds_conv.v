/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_fc_creds_conv
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
module tl_rx_fc_creds_conv #(
    parameter PAYLOAD_LENGTH=10,  
    PAYLOAD_IN_CREDS=9
) (
   input wire [PAYLOAD_LENGTH-1:0] buffer_dw,
   input wire [1:0] data_scale,
   output reg[PAYLOAD_IN_CREDS-1:0] buffer_creds
);
reg [2:0]shift_scale;
reg [PAYLOAD_LENGTH-1:0]shifted_num;
reg reminder;


always @(*) begin
        case (data_scale)
            2'b00 :
            begin shift_scale=2;
            shifted_num = buffer_dw >>2;
            reminder =|buffer_dw[1:0];
            buffer_creds = shifted_num + reminder + data_scale[1];
            end 
             2'b01 :
            begin shift_scale=2;
            shifted_num = buffer_dw >>2;
            reminder =|buffer_dw[1:0];
            buffer_creds = shifted_num + reminder + data_scale[1];
            end  
            2'b10 :
            begin shift_scale=4;
            shifted_num = buffer_dw >>4;
            reminder =|buffer_dw[3:0];
            buffer_creds = shifted_num + reminder + data_scale[1];
            end  
            2'b11 :
            begin shift_scale=6;
            shifted_num = buffer_dw >>6;
            reminder =|buffer_dw[5:0];
            buffer_creds = shifted_num + reminder + data_scale[1];
            end  
        endcase
end
endmodule


