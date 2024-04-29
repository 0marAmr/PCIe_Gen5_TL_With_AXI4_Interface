module master_bridge_async_fifo_read #(
    parameter   ADDR_WIDTH  = 3
)(
    input   wire                    R_CLK,
    input   wire                    R_RST,
    input   wire                    rd_inc,
    input   wire [ADDR_WIDTH:0]     gray_wr_ptr,
    output  wire [ADDR_WIDTH-1:0]   rd_addr,
    output  wire [ADDR_WIDTH:0]     gray_rd_ptr,
    output  wire                    rd_empty


);
    reg [ADDR_WIDTH:0]      read_pointer;
    
    always @(posedge R_CLK or negedge R_RST) begin
        if(~R_RST) begin
            read_pointer <= 'b0;
        end
        else if (~rd_empty && rd_inc) begin
            read_pointer <= read_pointer + 1;
        end
    end
    
    genvar i;
    generate
         for (i = 0; i < ADDR_WIDTH; i = i +1) begin
            assign gray_rd_ptr[i] = read_pointer[i] ^ read_pointer[i+1];
         end
    endgenerate
    assign gray_rd_ptr[ADDR_WIDTH] = read_pointer[ADDR_WIDTH];

    assign rd_addr = read_pointer[ADDR_WIDTH-1:0];
    assign rd_empty = (gray_wr_ptr == gray_rd_ptr);
endmodule