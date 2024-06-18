/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_vc_sequence_buffer
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
module tl_rx_vc_sequence_buffer #(
    parameter   P_HDR_FIFO_DEPTH,
                NP_HDR_FIFO_DEPTH
) (
     input   wire                   i_clk,
     input   wire                   i_n_rst,
     input   wire                   i_r_inc,
     input   wire                   i_w_inc,
     input   wire                   i_w_buffer_type, // 0: POSTED     1: NONPOSTED
     output  wire                   o_r_buffer_type,  // 0: POSTED     1: NONPOSTED
    //  output  wire                   o_full_flag,
     output  wire                   o_empty_flag
);
 
    localparam DEPTH = P_HDR_FIFO_DEPTH + NP_HDR_FIFO_DEPTH;
    localparam BUFFER_WIDTH = 1;
    localparam PTR_SIZE = $clog2(DEPTH) + 1;
    localparam ADDRESS_SIZE = PTR_SIZE - 1;

    // To Do: Ordering Pointers
    reg [BUFFER_WIDTH-1:0] sequence_buffer [0:DEPTH-1];
    reg [PTR_SIZE-1:0] w_ptr;
    reg [PTR_SIZE-1:0] r_ptr;

    wire [ADDRESS_SIZE-1:0] write_address   = w_ptr[PTR_SIZE-2:0]; // discard pointer extra bit
    wire [ADDRESS_SIZE-1:0] read_address    = r_ptr[PTR_SIZE-2:0]; // discard pointer extra bit
    
    integer i;
    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                sequence_buffer[i] <= 0;
            end
        end
        else if (i_w_inc) begin
                sequence_buffer[write_address] <= i_w_buffer_type;
        end
    end

    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            w_ptr <=0;
            r_ptr <=0;
        end
        else begin
            if(i_w_inc)begin
                if (write_address == (DEPTH-1)) begin
                    w_ptr  <= {~w_ptr[PTR_SIZE-1], {(PTR_SIZE - 1){1'b0}}};
                end
                else begin
                    w_ptr <= w_ptr + 1;
                end
            end
            if (i_r_inc) begin
                if (read_address == (DEPTH-1)) begin
                    r_ptr  <= {~r_ptr[PTR_SIZE-1], {(PTR_SIZE - 1){1'b0}}};
                end
                else begin
                    r_ptr <= r_ptr + 1;
                end
            end
        end
    end

    assign o_r_buffer_type = sequence_buffer[read_address];
    // assign o_full_flag = ((w_ptr[PTR_SIZE-1] == r_ptr[PTR_SIZE-1]) && (write_address == read_address));
    assign o_empty_flag = (w_ptr == r_ptr);

endmodule