module master_bridge_async_fifo_write #(
    parameter   ADDR_WIDTH  = 3
)(
    input   wire                    W_CLK,
    input   wire                    W_RST,
    input   wire                    wr_inc,
    input   wire [ADDR_WIDTH:0]     gray_rd_ptr,
    output  wire [ADDR_WIDTH-1:0]   wr_addr,
    output  wire [ADDR_WIDTH:0]     gray_wr_ptr,
    output  wire                    wr_full


);
    reg [ADDR_WIDTH:0]      write_pointer;
    
    always @(posedge W_CLK or negedge W_RST) begin
        if(~W_RST) begin
            write_pointer <= 'b0;
        end
        else if (~wr_full && wr_inc) begin
            write_pointer <= write_pointer + 1;
        end
    end

    genvar i;
    generate
         for (i = 0; i < ADDR_WIDTH; i = i +1) begin
            assign gray_wr_ptr[i] = write_pointer[i] ^ write_pointer[i+1];
         end
    endgenerate
    assign gray_wr_ptr[ADDR_WIDTH] = write_pointer[ADDR_WIDTH];

    assign wr_addr = write_pointer[ADDR_WIDTH-1:0];
    assign wr_full = (gray_wr_ptr[ADDR_WIDTH] != gray_rd_ptr[ADDR_WIDTH]) && (gray_wr_ptr[ADDR_WIDTH-1] != gray_rd_ptr[ADDR_WIDTH-1]) && ((gray_wr_ptr[ADDR_WIDTH-2:0] == gray_rd_ptr[ADDR_WIDTH-2:0]));
endmodule