module tl_rx_error_check_unexpected_cpl #(
    REQUESTER_ID_WIDTH=16,
    REQUESTER_TAG_WIDTH=10
) (
    input wire clk,
    input wire rst,
    input wire [REQUESTER_ID_WIDTH-1:0]  rx_req_id,  //cpl_rx_side
    input wire [REQUESTER_ID_WIDTH-1:0]  tx_req_id, //req_tx_side(or from rx_side_from config write tlp received)
    input wire [REQUESTER_TAG_WIDTH-1:0] rx_req_tag, //cpl_rx_side
    input wire [REQUESTER_TAG_WIDTH-1:0] tx_last_req_tag, //req_tx_side
    input wire [2:0]                     typ,
    input wire                           uc_en,
    output reg                           uc_error
);

    reg tx_last_req_tag_reg;

    localparam  MEMORY = 3'b000,
                IO = 3'b001,
                COMPLETION= 3'b010,
                CONFIGURATION = 3'b011,
                MESSAGE = 3'b100;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            tx_last_req_tag_reg<=0;
        end
        else begin
            tx_last_req_tag_reg<=tx_last_req_tag;
        end
    end

    always @(*) begin
        if (uc_en==1 && typ==COMPLETION) begin
            if ((rx_req_id==tx_req_id)&&(rx_req_tag<=tx_last_req_tag_reg)) begin
                uc_error=0;
            end
            else begin
                uc_error=1;
            end
        end
        else  begin
            uc_error=0;
        end
    end
    
endmodule
