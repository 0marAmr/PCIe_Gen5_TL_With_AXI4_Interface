/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_write_handler_ecrc
   DEPARTMENT :     tl_rx_write_handler
   AUTHORS :        Omar Muhammed - Omar Hafez
   AUTHOR’S EMAIL : eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-03-09              initial version
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
//0000 0100 1100 0001 0001 1101 1011 0111 :: 04C11DB7
module tl_rx_write_handler_ecrc #(
    parameter   DW = 32,
                VALID_DATA_WIDTH = 3,
                DATA_WIDTH = 8*DW,
                ECRC_ON = 1
) (
    input   wire                            i_clk,
    input   wire                            i_n_rst,
    input   wire                            i_hdr_blk_EP,
    input   wire                            i_n_clr,
    input   wire  [DATA_WIDTH-1:0]          i_data_in,
    input   wire  [VALID_DATA_WIDTH-1:0]    i_length, /*the length of valid data on the bus for which ECRC is calculated*/
    input   wire                            i_en,
    input   wire                            i_done,
    input   wire                            i_cfg_ecrc_chk_en,
    output  wire                            o_ecrc_error,
    output  wire                            o_cfg_ecrc_chk_capable
);

    assign o_cfg_ecrc_chk_capable = ECRC_ON;
    wire ecrc_en = i_en && i_cfg_ecrc_chk_en;

    localparam DIGEST_WIDTH = 1*DW;
    localparam [DIGEST_WIDTH-1:0] DEFAULT_SEED = 32'hFFFF_FFFF;

    localparam [2:0]    DW_1 = 3'd0,
                        DW_2 = 3'd1,
                        DW_3 = 3'd2,
                        DW_4 = 3'd3,
                        DW_5 = 3'd4,
                        DW_6 = 3'd5,
                        DW_7 = 3'd6,
                        DW_8 = 3'd7;

    function [DIGEST_WIDTH-1:0] crc32_serial;
    input [DIGEST_WIDTH-1:0] crc;
    input data;
    begin
        crc32_serial[0] = crc[31] ^ data;
        crc32_serial[1] = crc[0] ^ crc[31] ^ data;
        crc32_serial[2] = crc[1] ^ crc[31] ^ data;
        crc32_serial[3] = crc[2];
        crc32_serial[4] = crc[3] ^ crc[31] ^ data;
        crc32_serial[5] = crc[4] ^ crc[31] ^ data;
        crc32_serial[6] = crc[5];
        crc32_serial[7] = crc[6]^ crc[31] ^ data;
        crc32_serial[8] = crc[7]^ crc[31] ^ data;
        crc32_serial[9] = crc[8];
        crc32_serial[10] = crc[9] ^ crc[31] ^ data;
        crc32_serial[11] = crc[10] ^ crc[31] ^ data ;
        crc32_serial[12] = crc[11] ^ crc[31] ^ data;
        crc32_serial[13] = crc[12];
        crc32_serial[14] = crc[13];
        crc32_serial[15] = crc[14];
        crc32_serial[16] = crc[15] ^ crc[31] ^ data;
        crc32_serial[17] = crc[16];
        crc32_serial[18] = crc[17];
        crc32_serial[19] = crc[18];
        crc32_serial[20] = crc[19];
        crc32_serial[21] = crc[20];
        crc32_serial[22] = crc[21] ^ crc[31] ^ data;
        crc32_serial[23] = crc[22] ^ crc[31] ^ data;
        crc32_serial[24] = crc[23];
        crc32_serial[25] = crc[24];
        crc32_serial[26] = crc[25] ^ crc[31] ^ data;
        crc32_serial[27] = crc[26];
        crc32_serial[28] = crc[27];
        crc32_serial[29] = crc[28];
        crc32_serial[30] = crc[29];
        crc32_serial[31] = crc[30];
    end
    endfunction

    function [DIGEST_WIDTH-1:0] crc_iteration;
    input [DIGEST_WIDTH-1:0] crc;
    input [DATA_WIDTH-1:0] data;
    input  [VALID_DATA_WIDTH-1:0] length;
    integer i;
    begin
        crc_iteration = crc;
        case (i_length)     
        DW_1:begin
            for(i=0; i<1*DW; i=i+1)begin
                crc_iteration = crc32_serial(crc_iteration, data[(1*DW-1) -i]);
            end
        end
        DW_2: begin
            for(i=0; i<2*DW; i=i+1)begin
                crc_iteration = crc32_serial(crc_iteration, data[(2*DW-1) -i]);
            end
        end
        DW_3: begin
            for(i=0; i<3*DW; i=i+1)begin
                crc_iteration = crc32_serial(crc_iteration, data[(3*DW-1) -i]);
            end
        end
        DW_4: begin
            for(i=0; i<4*DW; i=i+1)begin
                crc_iteration = crc32_serial(crc_iteration, data[(4*DW-1) -i]);
            end
        end
        DW_5: begin
            for(i=0; i<5*DW; i=i+1)begin
                crc_iteration = crc32_serial(crc_iteration, data[(5*DW-1) -i]);
            end
        end
        DW_6: begin
            for(i=0; i<6*DW; i=i+1)begin
                crc_iteration = crc32_serial(crc_iteration, data[(6*DW-1) -i]);
            end
        end
        DW_7: begin
            for(i=0; i<7*DW; i=i+1)begin
                crc_iteration = crc32_serial(crc_iteration, data[(7*DW-1) -i]);
            end
        end
        DW_8: begin
            for(i=0; i<8*DW; i=i+1)begin
                crc_iteration = crc32_serial(crc_iteration, data[(8*DW-1) -i]);
            end
        end
        endcase
    end
    endfunction


    reg [DIGEST_WIDTH-1:0] crc32;
    reg [DIGEST_WIDTH-1:0] rcv_ecrc_input;
    reg [DIGEST_WIDTH-1:0] rcv_ecrc;
    reg [DATA_WIDTH-1:0]   data_input;

    always @(*) begin
        if (i_hdr_blk_EP) begin
            data_input = {i_data_in[DATA_WIDTH-1:23],1'b0, i_data_in[21:0]};
        end
        else begin
            data_input = i_data_in;
        end
    end

    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            crc32 <= DEFAULT_SEED;
            rcv_ecrc<=0;
        end
        else  begin
            if(~i_n_clr)  begin    
                crc32 <= DEFAULT_SEED;
            end
            else if (ecrc_en) begin
                crc32 <= crc_iteration(crc32, data_input, i_length);
            end
            
            if (i_done) begin
                rcv_ecrc <= rcv_ecrc_input;
            end
        end

    end

    always @(*) begin
    case (i_length)
    DW_1:begin
        rcv_ecrc_input = i_data_in[8*DW-1:7*DW];
    end
    DW_2: begin
        rcv_ecrc_input = i_data_in[7*DW-1:6*DW];
    end
    DW_3: begin
        rcv_ecrc_input = i_data_in[6*DW-1:5*DW];
    end
    DW_4: begin
        rcv_ecrc_input = i_data_in[5*DW-1:4*DW];
    end
    DW_5: begin
        rcv_ecrc_input = i_data_in[4*DW-1:3*DW];
    end
    DW_6: begin
        rcv_ecrc_input = i_data_in[3*DW-1:2*DW];
    end
    DW_7: begin
        rcv_ecrc_input = i_data_in[2*DW-1:1*DW];
    end
    DW_8: begin
        rcv_ecrc_input = i_data_in[1*DW-1:0];
    end
    default: begin
        rcv_ecrc_input = 32'b0;
    end
    endcase 
    end

    /*Output*/
    assign o_ecrc_error = (rcv_ecrc != crc32) && i_done; 
    
endmodule
