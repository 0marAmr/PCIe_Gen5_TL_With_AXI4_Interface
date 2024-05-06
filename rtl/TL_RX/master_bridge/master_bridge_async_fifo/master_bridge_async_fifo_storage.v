module master_bridge_async_fifo_storage #(
    parameter   DATA_WIDTH  = 8,
                ADDR_WIDTH  = 4,
                FIFO_DEPTH  = 8
)(
    input   wire                        CLK,
    input   wire                        wclken,
    input   wire   [ADDR_WIDTH-1:0]     wr_addr,
    input   wire   [ADDR_WIDTH-1:0]     rd_addr,
    input   wire   [DATA_WIDTH-1:0]     wr_data,
    output  reg    [DATA_WIDTH-1:0]     rd_data
);

    reg [DATA_WIDTH-1:0] memory [0:FIFO_DEPTH-1];
    always @(posedge CLK) begin
        if (wclken) begin
            memory[wr_addr] <= wr_data;
        end
    end

    always @(*) begin
        rd_data = memory[rd_addr];
    end
    
endmodule