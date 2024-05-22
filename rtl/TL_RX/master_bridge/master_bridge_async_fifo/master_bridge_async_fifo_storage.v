/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      master_bridge_async_fifo_storage
   DEPARTMENT :     async_fifo
   AUTHOR :         Omar Hafez
   AUTHOR’S EMAIL : eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-04-03             initial version
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
module master_bridge_async_fifo_storage #(
    parameter   DATA_WIDTH  = 8,
                ADDR_WIDTH  = 4,
                FIFO_DEPTH  = 8
)(
    input   wire                        CLK,
    input   wire                        i_w_n_rst,
    input   wire                        full_flag,
    input   wire   [ADDR_WIDTH-1:0]     wr_addr,
    input   wire   [ADDR_WIDTH-1:0]     rd_addr,
    input   wire   [DATA_WIDTH-1:0]     wr_data,
    output  reg    [DATA_WIDTH-1:0]     rd_data
);

    reg [DATA_WIDTH-1:0] memory [0:FIFO_DEPTH-1];

    integer i;
    always @(posedge CLK or negedge i_w_n_rst) begin
        if(~i_w_n_rst) begin
            for (i = 0; i < FIFO_DEPTH; i=i+1) begin
                memory[i] <= 0;
            end
        end 
        else if (~full_flag) begin
            memory[wr_addr] <= wr_data;
        end
    end

    always @(*) begin
        rd_data = memory[rd_addr];
    end
    
endmodule