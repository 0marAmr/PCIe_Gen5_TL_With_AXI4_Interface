module master_bridge_async_fifo_bit_sync #(
    parameter   NUM_STAGES  = 2,
                BUS_WIDTH   = 1
)(
    input   wire                        CLK,
    input   wire                        RST,
    input   wire    [BUS_WIDTH-1:0]     ASYNC,
    output  reg     [BUS_WIDTH-1:0]     SYNC
);

    reg [NUM_STAGES-1:0] sync_chain [0:BUS_WIDTH-1];
    integer i;
    always @(posedge CLK or negedge RST) begin
        if (~RST) begin
            for (i = 0; i < BUS_WIDTH; i = i + 1) begin
                sync_chain[i] <= 'b0;
            end
        end
        else begin
            for (i = 0; i < BUS_WIDTH; i = i + 1) begin
                sync_chain[i] <= {ASYNC[i], sync_chain[i][NUM_STAGES-1:1]};
            end
        end
    end

    integer j;
    always @(*) begin
        for (j = 0; j < BUS_WIDTH; j = j + 1) begin
            SYNC[j] = sync_chain[j][0];
        end 
    end
endmodule