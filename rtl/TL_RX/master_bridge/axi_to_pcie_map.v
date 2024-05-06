/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project.
   -----------------------------------------------------------------------------
   FILE NAME :      axi_to_pcie_map
   DEPARTMENT :     master_bridge
   AUTHOR :         Omar Hafez
   AUTHOR’S EMAIL : eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-04-03              initial version
   -----------------------------------------------------------------------------
   KEYWORDS : PCIe, General
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
    module axi_to_pcie_map #(
        parameter   ID_WIDTH = 10,
                    TAG_WIDTH =10,
                    REQUESTER_ID_WIDTH = 16,
                    LEN_FIELD_WIDTH = 10,
                    TC_WIDTH = 3,
                    LOWER_ADDR_FIELD = 7,
                    BYTE_ENABLES_WIDTH = 4,
                    ADDR_LSBS_PORTION = 5,
                    R_USER_SIG_WIDTH = REQUESTER_ID_WIDTH + 2*BYTE_ENABLES_WIDTH + ADDR_LSBS_PORTION + TC_WIDTH + LEN_FIELD_WIDTH + 1, // 43
                    B_USER_SIG_WIDTH = REQUESTER_ID_WIDTH +  TC_WIDTH, // 19
                    BYTE_COUNT_WIDTH = 12,
                    RESP_WIDTH = 2
   ) (
    //------- B Channel -------//
    input  wire [ID_WIDTH-1:0]          i_BID,        
    input  wire [RESP_WIDTH-1:0]        i_BRESP,
    input  wire [B_USER_SIG_WIDTH-1:0]  i_BUSER,
    input  wire                         i_BVALID_fifo,
    output reg                         o_b_ch_read_inc,  
    //------- R Channel -------//
    input  wire [ID_WIDTH-1:0]          i_RID,        
    input  wire [RESP_WIDTH-1:0]        i_RRESP,
    input  wire [R_USER_SIG_WIDTH-1:0]  i_RUSER,
    input  wire                         i_RVALID_fifo,  
    output reg                          o_r_ch_read_info_inc,
    //------ Completion Generator Interface  ------//
    input  wire                              i_cpl_info_inc,
    output reg  [REQUESTER_ID_WIDTH-1:0]     o_requester_id,
    output reg                               o_cpl_type,
    output reg  [TAG_WIDTH-1:0]              o_cpl_tag,
    output reg  [TC_WIDTH-1:0]               o_cpl_traffic_class,
    output reg  [LEN_FIELD_WIDTH-1:0]        o_cpl_length,
    output reg  [LOWER_ADDR_FIELD-1:0]       o_cpl_lower_address,
    output reg                               o_cpl_error_flag,
    output reg  [BYTE_COUNT_WIDTH-1:0]       o_cpl_initial_byte_count,
    output reg                               o_cpl_valid
);
     
    localparam  READ_RESP = 1'b0,
                WRITE_RESP = 1'b1;

    localparam  IO = 1'b0,
                MEMORY = 1'b1; 

     localparam NODATA = 1'b0,
                DATA = 1'b1; 
    
    localparam  [RESP_WIDTH-1:0]    OKAY = 2'b00,
                                    EXOKAY = 2'b01,
                                    SLVERR = 2'b10,
                                    DECERR  = 2'b11;

    localparam [BYTE_ENABLES_WIDTH-1:0] NO_BYTES_VALID  = 4'b0000,
                                        ALL_BYTES_VALID = 4'b???1,
                                        BYTES_VALID_3   = 4'b??10,
                                        BYTES_VALID_2   = 4'b?100,
                                        BYTES_VALID_1   = 4'b1000;

    reg channel_selection;
    reg [1:0] byte_level_address; // least significant two bits of the lower address

    wire [REQUESTER_ID_WIDTH-1:0] r_requester_id;
    wire [BYTE_ENABLES_WIDTH-1:0] r_first_dw_byte_enable;
    wire [ADDR_LSBS_PORTION-1:0]  r_address_lsbs;
    wire [TC_WIDTH-1:0]           r_traffic_class;
    wire [LEN_FIELD_WIDTH-1:0]    r_payload_length;
    wire                          r_responce_type; // MEMORY - IO

    wire [TC_WIDTH-1:0]           b_traffic_class;
    wire [REQUESTER_ID_WIDTH-1:0] b_requester_id;

    assign {r_requester_id, r_first_dw_byte_enable, r_last_dw_byte_enable, r_address_lsbs, r_traffic_class, r_payload_length, r_responce_type} = i_RUSER;
    assign {b_requester_id, b_traffic_class} = i_BUSER;

    //------- R-B Channels Arbitration -------//
    always @(*) begin
        if (i_RVALID_fifo) begin
            channel_selection = READ_RESP;
        end 
        else begin
            channel_selection = WRITE_RESP;
        end
    end

    always @(*) begin // add round robin via in case both valid
        o_r_ch_read_info_inc = 0;
        o_b_ch_read_inc = 0;
        if(channel_selection == READ_RESP) begin
            o_requester_id = r_requester_id;
            o_cpl_tag = i_RID;           
            o_cpl_traffic_class = r_traffic_class;
            o_cpl_length = r_payload_length;
            o_cpl_lower_address = {r_address_lsbs, byte_level_address};
            if (r_responce_type ==MEMORY) begin
                o_cpl_type = DATA;
            end
            else begin
                o_cpl_type = NODATA;
            end
            if (i_RRESP == OKAY) begin
                o_cpl_error_flag = 1'b0;
            end 
            else begin
                o_cpl_error_flag = 1'b1;
            end
            o_r_ch_read_info_inc = i_cpl_info_inc;
            o_cpl_valid = i_RVALID_fifo;
        end
        else if(channel_selection == WRITE_RESP) begin
            o_requester_id = b_requester_id;
            o_cpl_tag = i_BID;           
            o_cpl_traffic_class = b_traffic_class;
            o_cpl_length = 1'b1;
            o_cpl_lower_address = 7'b0;
            o_cpl_type = NODATA;
            if (i_BRESP == OKAY) begin
                o_cpl_error_flag = 1'b0;
            end 
            else begin
                o_cpl_error_flag = 1'b1;
            end
            o_b_ch_read_inc = i_cpl_info_inc;
            o_cpl_valid = i_BVALID_fifo;
        end
    end
    
    //------- Lower Address Calculation -------//
    /*
        Lower Address field is generated from the least significant 5 bits of the address of the Request concatenated with 2 bits of byte-level address.
        Lower Address field is set to all 0's for all completions except for memory read completions.
    */
    always @(*) begin
        casez (r_first_dw_byte_enable)
            NO_BYTES_VALID: begin
                byte_level_address = 2'b00;
            end
            ALL_BYTES_VALID: begin
                byte_level_address = 2'b00;
            end
            BYTES_VALID_3: begin
                byte_level_address = 2'b01;
            end
            BYTES_VALID_2: begin
                byte_level_address = 2'b10;
            end
            BYTES_VALID_1: begin
                byte_level_address = 2'b11;
            end
            default: begin
                byte_level_address = 2'b00;
            end
        endcase
    end
    
    //------- Initial Byte Count Calculation -------//
    always @(*) begin
        if ((channel_selection == READ_RESP)&&(r_responce_type == MEMORY)) begin
            casez ({r_first_dw_byte_enable, r_last_dw_byte_enable})
                /****** Length is less than or equal 1 DW ******/
                8'b1??1_0000: begin
                    o_cpl_initial_byte_count = 8'd4;
                end
                8'b01?1_0000: begin
                    o_cpl_initial_byte_count = 8'd3;
                end
                8'b1?10_0000: begin
                    o_cpl_initial_byte_count = 8'd3;
                end
                8'b0011_0000, 8'b1100_0000, 8'b0110_0000: begin
                    o_cpl_initial_byte_count = 8'd2;
                end
                8'b0001_0000, 8'b0010_0000, 8'b0100_0000, 8'b1000_0000, 8'b0000_0000: begin
                    o_cpl_initial_byte_count = 8'd1;
                end
                /****** Length is greater than 1 DW ******/
                8'b???1_1???: begin
                    o_cpl_initial_byte_count = r_payload_length<<2; //  multipliying the length in double words by 4
                end
                8'b???1_01??, 8'b??10_1???: begin
                    o_cpl_initial_byte_count = (r_payload_length<<2) - 1'd1;
                end
                8'b???1_001?, 8'b??10_01??, 8'b?100_1???, 8'b?100_1???: begin
                    o_cpl_initial_byte_count = (r_payload_length<<2) - 12'd2;
                end
                8'b??10_001?, 8'b?100_01??, 8'b1000_1???: begin
                    o_cpl_initial_byte_count = (r_payload_length<<2) - 12'd3;
                end
                8'b??10_0001, 8'b?100_001?, 8'b1000_01??: begin
                    o_cpl_initial_byte_count = (r_payload_length<<2) - 12'd4;
                end
                8'b?100_0001, 8'b1000_001?: begin
                    o_cpl_initial_byte_count = (r_payload_length<<2) - 12'd5;
                end
                8'b1000_0001: begin
                    o_cpl_initial_byte_count = (r_payload_length<<2) - 12'd6;
                end
                default: begin
                    o_cpl_initial_byte_count = 0;
                end
            endcase
        end 
        else begin
            o_cpl_initial_byte_count = 8'd4;
        end
    end
    
endmodule
