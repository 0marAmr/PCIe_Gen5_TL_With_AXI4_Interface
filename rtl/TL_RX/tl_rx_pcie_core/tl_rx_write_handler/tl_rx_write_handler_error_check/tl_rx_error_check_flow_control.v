module tl_rx_error_check_flow_control #(
    parameter   FC_DATA_CREDS_WIDTH=16,
                FC_HDR_CREDS_WIDTH=12,
                DLL_DATA_CREDS_WIDTH=16,
                DLL_HDR_CREDS_WIDTH=12
) (
    input wire  [FC_DATA_CREDS_WIDTH-1:0]   data_creds_reg,
    input wire  [FC_HDR_CREDS_WIDTH-1:0]    hdr_creds_reg,
    input wire  [1:0]                       data_scale_reg,
    input wire  [1:0]                       hdr_scale_reg,
    input wire                              dll_valid,
    input wire                              flow_control_en,
    input wire  [DLL_DATA_CREDS_WIDTH-1:0]  dll_data_creds,
    input wire  [DLL_HDR_CREDS_WIDTH-1:0]   dll_hdr_creds,
    input wire  [1:0]                       dll_data_scale,
    input wire  [1:0]                       dll_hdr_scale,
    output reg                              flow_control_error
);

reg hdr_flow_control_error;
reg data_flow_control_error;

always @(*) begin
    if (flow_control_en==1 && dll_valid==1) begin
       case (dll_hdr_scale)
        2'b00: begin
            if (hdr_creds_reg==2'b00 && dll_hdr_creds != 2'b00) begin
                hdr_flow_control_error=1;
            end
            else if (hdr_creds_reg !=0 && dll_hdr_creds > 2**7) begin
                hdr_flow_control_error=1;
            end
            else if (hdr_scale_reg != 2'b00) begin
                hdr_flow_control_error=1;
            end
            else
            hdr_flow_control_error=0;
        end  
        2'b01: begin
            if (hdr_creds_reg==2'b00 && dll_hdr_creds != 2'b00) begin
                hdr_flow_control_error=1;
            end
            else if (hdr_creds_reg !=0 && dll_hdr_creds > 2**7) begin
                hdr_flow_control_error=1;
            end
            else if (hdr_scale_reg != 2'b01) begin
                hdr_flow_control_error=1;
            end
            else
            hdr_flow_control_error=0;
        end  
        2'b10: begin
            if (hdr_creds_reg==2'b00 && dll_hdr_creds != 2'b00) begin
                hdr_flow_control_error=1;
            end
            else if (hdr_creds_reg !=0 && dll_hdr_creds > 2**9) begin
                hdr_flow_control_error=1;
            end
            else if (hdr_scale_reg != 2'b10) begin
                hdr_flow_control_error=1;
            end
            else
            hdr_flow_control_error=0;
        end  
        2'b11: begin
            if (hdr_creds_reg==2'b00 && dll_hdr_creds != 2'b00) begin
                hdr_flow_control_error=1;
            end
            else if (hdr_creds_reg !=0 && dll_hdr_creds > 2**11) begin
                hdr_flow_control_error=1;
            end
            else if (hdr_scale_reg != 2'b11) begin
                hdr_flow_control_error=1;
            end
            else
            hdr_flow_control_error=0;
        end 
       endcase 
       case (dll_data_scale)
        2'b00: begin
            if ( data_creds_reg== 2'b00 && dll_data_creds != 2'b00) begin
                data_flow_control_error=1;
            end
            else if (data_creds_reg !=0 && dll_data_creds > 2**11 ) begin
                data_flow_control_error=1;
            end
            else if (data_creds_reg !=0 && dll_data_creds < 64) begin
                data_flow_control_error=1;
            end
            else if (data_scale_reg != 2'b00) begin
                data_flow_control_error=1;
            end
            else
            data_flow_control_error=0;
        end
        2'b01: begin
            if ( data_creds_reg== 2'b00 && dll_data_creds != 2'b00) begin
                data_flow_control_error=1;
            end
            else if (data_creds_reg !=0 && dll_data_creds > 2**11 ) begin
                data_flow_control_error=1;
            end
            else if (data_creds_reg !=0 && dll_data_creds < 64) begin
                data_flow_control_error=1;
            end
            else if (data_scale_reg != 2'b01) begin
                data_flow_control_error=1;
            end
            else
            data_flow_control_error=0;
        end
        2'b10: begin
            if ( data_creds_reg== 2'b00 && dll_data_creds != 2'b00) begin
                data_flow_control_error=1;
            end
            else if (data_creds_reg !=0 && dll_data_creds > 2**13 ) begin
                data_flow_control_error=1;
            end
            else if (data_creds_reg !=0 && dll_data_creds < 17) begin
                data_flow_control_error=1;
            end
            else if (data_scale_reg != 2'b10) begin
                data_flow_control_error=1;
            end
            else
            data_flow_control_error=0;
        end
        2'b11: begin
            if ( data_creds_reg== 2'b00 && dll_data_creds != 2'b00) begin
                data_flow_control_error=1;
            end
            else if (data_creds_reg !=0 && dll_data_creds > 2**15 ) begin
                data_flow_control_error=1;
            end
            else if (data_creds_reg !=0 && dll_data_creds < 5) begin
                data_flow_control_error=1;
            end
            else if (data_scale_reg != 2'b11) begin
                data_flow_control_error=1;
            end
            else
            data_flow_control_error=0;
        end
       endcase
       flow_control_error = hdr_flow_control_error || data_flow_control_error;
    end
    else
    flow_control_error = 0;
end   
endmodule