/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project 
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_vc_data_buffer
   DEPARTMENT :     VC
   AUTHOR :         Reem Mohamed - Omar Hafez
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com - eng.omar.amr@gmail.com
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
    parameter   BUFFER_TYPE = "P",
                DW = 32,
                DATA_FIFO_DEPTH = 2**8,
                DATA_PTR_SIZE = $clog2(DATA_FIFO_DEPTH) + 1,
                // DATA_PTR_SIZE = (BUFFER_TYPE == "NP")? DATA_PTR_SIZE : (DATA_PTR_SIZE -1),
                BUFFER_WIDTH = 8*DW,
                BEAT_SIZE = 32*DW
) (
    input   wire                            i_clk,
    input   wire                            i_n_rst,
    //------- Read Interface ------//
    input   wire  [2:0]                     i_r_data_inc_value,
    input   wire                            i_r_data_inc_en,
    input   wire                            i_r_data_allignment, // 0: Least 4DW, Most 4DW, 1: Least 5DW, Most 3DW
    output  reg  [BEAT_SIZE-1:0]            o_r_tlp_data,
    output  wire  [DATA_PTR_SIZE-1:0]       o_r_data_ptr,
    //------- Write Interface ------//
    input   wire                            i_w_data_cntr_ld,
    input   wire                            i_w_data_ptr_ld,
    input   wire                            i_digest_cycle_flag,
    input   wire                            i_w_data_en,
    input   wire  [BUFFER_WIDTH-1:0]        i_w_tlp_data,
    output  wire  [DATA_PTR_SIZE-1:0]       o_w_data_ptr

);
    
    localparam ADDRESS_SIZE = DATA_PTR_SIZE-1;

    reg [BUFFER_WIDTH-1:0]  data_fifo [0:DATA_FIFO_DEPTH-1];

    reg [DATA_PTR_SIZE-1:0] data_w_cntr;
    reg [DATA_PTR_SIZE-1:0] data_w_ptr_buffer;
    reg [DATA_PTR_SIZE-1:0] data_r_ptr;

    wire [ADDRESS_SIZE-1:0] write_address = data_w_cntr[DATA_PTR_SIZE-2:0]; // discard pointer extra bit
    wire [ADDRESS_SIZE-1:0] read_address  = data_r_ptr[DATA_PTR_SIZE-2:0]; // discard pointer extra 
    
    wire [ADDRESS_SIZE-1:0] read_address_plus_1 = read_address + 1;
    wire [ADDRESS_SIZE-1:0] read_address_plus_2 = read_address + 2;
    wire [ADDRESS_SIZE-1:0] read_address_plus_3 = read_address + 3;
    wire [ADDRESS_SIZE-1:0] read_address_plus_4 = read_address + 4;

    integer i;

    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            for (i = 0; i < DATA_FIFO_DEPTH; i = i + 1) begin
                data_fifo[i] <= 0;
            end
        end
        else if (i_w_data_en) begin
                data_fifo[write_address] <= i_w_tlp_data;
        end
    end

    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            data_w_cntr <=0;
            data_w_ptr_buffer <=0;
            data_r_ptr <=0;
        end
        else begin
            if (i_w_data_cntr_ld) begin
                data_w_cntr <= data_w_ptr_buffer;
            end
            else  if (i_w_data_en) begin
                data_w_cntr <= data_w_cntr + 1;
            end

             if (i_w_data_ptr_ld && i_digest_cycle_flag) begin
                data_w_ptr_buffer <= data_w_cntr; 
            end
            else if (i_w_data_ptr_ld && ~i_digest_cycle_flag) begin
                data_w_ptr_buffer <= data_w_cntr + 1; 
            end

            if (i_r_data_inc_en) begin
                data_r_ptr <= data_r_ptr + i_r_data_inc_value;
            end
        end
    end

    
    generate
        if (BUFFER_TYPE == "NP")
            always @(*) begin
                o_r_tlp_data = data_fifo[read_address];
            end
        else if ("CPL")begin
            always @(*) begin
                o_r_tlp_data = {data_fifo[read_address][5*DW-1:0], data_fifo[read_address_plus_1], data_fifo[read_address_plus_2], data_fifo[read_address_plus_3], data_fifo[read_address_plus_4][8*DW-1:5*DW]};
            end
        end
        else begin // Posted
            always @(*) begin
                if(i_r_data_allignment) begin
                    o_r_tlp_data = {data_fifo[read_address][4*DW-1:0], data_fifo[read_address_plus_1], data_fifo[read_address_plus_2], data_fifo[read_address_plus_3], data_fifo[read_address_plus_4][8*DW-1:4*DW]};
                end
                else begin
                    o_r_tlp_data = {data_fifo[read_address][5*DW-1:0], data_fifo[read_address_plus_1], data_fifo[read_address_plus_2], data_fifo[read_address_plus_3], data_fifo[read_address_plus_4][8*DW-1:5*DW]};
                end
            end
        end
    endgenerate

    assign o_w_data_ptr = data_w_ptr_buffer;
    assign o_r_data_ptr = data_r_ptr;

endmodule
