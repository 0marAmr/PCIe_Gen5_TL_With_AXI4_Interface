/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project 
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_vc_data_buffer
   DEPARTMENT :     VC
   AUTHOR :         Omar Hafez
   AUTHOR’S EMAIL : eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-03-10              initial version
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
module tl_rx_vc_data_buffer #(
    parameter   DW = 32,  
                DATA_FIELD_SIZE = 12,
                BUFFER_WIDTH = 8*DW,
                BEAT_SIZE = 32*DW
) (
    input   wire                           i_clk,
    input   wire                           i_n_rst,
    //------- Read Interface ------//
    input   wire  [2:0]                    i_r_data_inc_value,
    input   wire                           i_r_data_inc_en,
    output  wire   [BEAT_SIZE-1:0]         o_r_tlp_data,
    output  wire  [DATA_FIELD_SIZE-2:0]    o_r_data_ptr,
    //------- Write Interface ------//
    input   wire                           i_hdr_write_flag,     /*indicates whether the entry (8DW) is half filled ()or completly filled (normal case)*/
    input   wire                           i_w_data_cntr_ld,
    input   wire                           i_w_data_ptr_ld,
    input   wire                           i_w_data_en,
    input   wire  [BUFFER_WIDTH-1:0]       i_w_tlp_data,
    output  wire  [DATA_FIELD_SIZE-2:0]    o_w_data_ptr

);
    
    localparam DEPTH = 2**(DATA_FIELD_SIZE-2);
    localparam ADDRESS_SIZE = DATA_FIELD_SIZE-2;
    localparam  [1:0]   INCR_BY_1 = 2'b00,
                        INCR_BY_2 = 2'b01,
                        INCR_BY_3 = 2'b10,
                        INCR_BY_4 = 2'b11;

    reg [BUFFER_WIDTH-1:0]  data_fifo [0:DEPTH-1];
    reg [DATA_FIELD_SIZE-2:0] data_w_cntr;
    reg [DATA_FIELD_SIZE-2:0] data_w_ptr_buffer;
    reg [DATA_FIELD_SIZE-2:0] data_r_ptr;
    integer i;

    wire [ADDRESS_SIZE-1:0] write_address   = data_w_cntr[DATA_FIELD_SIZE-3:0]; // discard pointer extra bit
    wire [ADDRESS_SIZE-1:0] read_address    = data_r_ptr[DATA_FIELD_SIZE-3:0]; // discard pointer extra bit

    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            data_w_cntr <=0;
            data_w_ptr_buffer <=0;
            data_r_ptr <=0;
        end
        else begin
            if (i_w_data_en) begin
                data_fifo[write_address] <= i_w_tlp_data;
                data_w_cntr <= data_w_cntr + 1;
            end
            if (i_w_data_cntr_ld) begin
                data_w_cntr <= data_w_ptr_buffer;
            end
            if (i_w_data_ptr_ld) begin
                data_w_ptr_buffer <= data_w_cntr;
            end
            if (i_r_data_inc_en) begin
                data_r_ptr <= data_r_ptr + i_r_data_inc_value;
            end
        end
    end
    // always @(*) begin
    //     if() begin
    //         o_r_tlp_data = {data_fifo[read_address][4*DW-1:0], data_fifo[read_address+1], data_fifo[read_address+2], data_fifo[read_address+3], data_fifo[read_address+4][8*DW-1:4*DW]};
    //     end
    //     else begin
                
    //         o_r_tlp_data = {data_fifo[read_address][5*DW-1:0], data_fifo[read_address+1], data_fifo[read_address+2], data_fifo[read_address+3], data_fifo[read_address+4][8*DW-1:5*DW]};
    //     end
        
    // end
    
    assign o_r_tlp_data = {data_fifo[read_address][5*DW-1:0], data_fifo[read_address+1], data_fifo[read_address+2], data_fifo[read_address+3], data_fifo[read_address+4][8*DW-1:5*DW]};

    assign o_w_data_ptr = data_w_ptr_buffer;
    assign o_r_data_ptr = data_r_ptr;

endmodule
