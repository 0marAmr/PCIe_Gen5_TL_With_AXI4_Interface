/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      pcie_to_axi_map
   DEPARTMENT :     AXI - PCIe Master Bridge
   AUTHOR :         Reem Mohamed - Omar Hafez
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com - eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-04-03             initial version
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
   module pcie_to_axi_map #(
    parameter   DW =32,
                ID_WIDTH = 10,
                ADDR_WIDTH = 62,
                AxLEN_FIELD_WIDTH = 8,
                BURST_FIELD_WIDTH = 2,
                QOS_WIDTH = 4,
                VALID_DATA_WIDTH = 5,
                STROBE_BUS_WIDTH = 128,
                BEAT_SIZE = 32*DW,
                REQ_BUS_WIDTH = 112,
                REQUESTER_ID_WIDTH = 16,
                // Ax_USER_SIG_WIDTH = REQUESTER_ID_WIDTH + 1,
                TAG_WIDTH = 10,
                LEN_FIELD_WIDTH = 10,
                TC_WIDTH = 3,
                ADDR_LSBS_PORTION = 5,
                BYTE_ENABLES_WIDTH = 4,
                READ_REQ_INFO = 34, // 16 (ID) + 4 (FBE) + 4 (LBE)+ 5 (addr least sig bits) + 5 (last dw) = 34
                WRITE_REQ_INFO = 17 // 16 (ID) + 1 (req type MEM - IO) = 17
   ) (
    //------ Request Input ------//
    // input   wire [REQ_BUS_WIDTH-1:0]        i_request,
    input   wire [1:0]                      i_req_type,   /*Memory Read - Memory Write - IO Read - IO Write*/
    input   wire                            i_address_type, // address type Logic High: 64-bit, used to get the least significant 5 bits 
    input   wire [TC_WIDTH-1:0]             i_req_traffic_class,
    input   wire [REQUESTER_ID_WIDTH-1:0]   i_requester_id,
    input   wire [TAG_WIDTH-1:0]            i_req_tag,
    input   wire [LEN_FIELD_WIDTH-1:0]      i_req_length,
    input   wire [BYTE_ENABLES_WIDTH-1:0]   i_req_first_byte_enable,
    input   wire [BYTE_ENABLES_WIDTH-1:0]   i_req_last_byte_enable,
    input   wire [ADDR_WIDTH-1:0]           i_req_address,
    //------ Read Handler Control Signals  ------//
    input   wire                            i_req_inc,    
    input   wire                            i_req_valid,    
    input   wire                            i_last,         // indicates that the current beat is the last one in a transaction 
    input   wire  [VALID_DATA_WIDTH-1:0]    i_valid_data,   // encoding for valid Double Words of data driven on the bus (5'b00000 -> 1 DW valid, 5'b11111 32 DW valid) 
    //------ AW Channel ------//
    output  reg                             o_aw_write_inc,
    output  reg  [ID_WIDTH-1:0]             o_AWID,        
    output  reg  [ADDR_WIDTH-1:0]           o_AWADDR,
    output  reg  [AxLEN_FIELD_WIDTH-1:0]    o_AWLEN,    /*Burst length: gives the exact number of data transfers in a burst associated with the address.*/     
    output  reg  [QOS_WIDTH-1:0]            o_AWQOS,
    output  reg  [WRITE_REQ_INFO-1:0]       o_aw_request_info,   /*requester_id - req_type[1] (MEM - IO)*/
    //------ W Channel ------//
    output  reg  [STROBE_BUS_WIDTH-1:0]     o_WSTRB,
    //------ AR Channel ------//
    output  reg                             o_ar_write_inc,
    output  reg  [ID_WIDTH-1:0]             o_ARID,        
    output  reg  [ADDR_WIDTH-1:0]           o_ARADDR,
    output  reg  [AxLEN_FIELD_WIDTH-1:0]    o_ARLEN,       /*Burst length: gives the exact number of data transfers in a burst associated with the address.*/     
    output  reg  [3:0]                      o_ARQOS,
    output  reg  [READ_REQ_INFO-1:0]        o_ar_request_info
);

    localparam  [1:0]   MEMORY_READ     = 2'b00,
                        MEMORY_WRITE    = 2'b01,
                        IO_READ         = 2'b10,
                        IO_WRITE        = 2'b11;
    
    localparam  READ = 0,
                WRITE = 1;
    
    localparam  ADDR_32 = 0,
                ADDR_64 = 1;
            
    localparam [4:0]    DW_1    = 5'b0_0000,
                        DW_2    = 5'b0_0001,
                        DW_3    = 5'b0_0010,
                        DW_4    = 5'b0_0011,
                        DW_5    = 5'b0_0100,
                        DW_6    = 5'b0_0101,
                        DW_7    = 5'b0_0110,
                        DW_8    = 5'b0_0111,
                        DW_9    = 5'b0_1000,
                        DW_10   = 5'b0_1001,
                        DW_11   = 5'b0_1010,
                        DW_12   = 5'b0_1011,
                        DW_13   = 5'b0_1100,
                        DW_14   = 5'b0_1101,
                        DW_15   = 5'b0_1110,
                        DW_16   = 5'b0_1111,
                        DW_17   = 5'b1_0000,
                        DW_18   = 5'b1_0001,
                        DW_19   = 5'b1_0010,
                        DW_20   = 5'b1_0011,
                        DW_21   = 5'b1_0100,
                        DW_22   = 5'b1_0101,
                        DW_23   = 5'b1_0110,
                        DW_24   = 5'b1_0111,
                        DW_25   = 5'b1_1000,
                        DW_26   = 5'b1_1001,
                        DW_27   = 5'b1_1010,
                        DW_28   = 5'b1_1011,
                        DW_29   = 5'b1_1100,
                        DW_30   = 5'b1_1101,
                        DW_31   = 5'b1_1110,
                        DW_32   = 5'b1_1111;

    localparam STATE_REG_WIDTH = 2;

    localparam STROBE_DEFAULT_VALUE = 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;

    reg [ADDR_LSBS_PORTION-1:0] address_lsbs; // 5 least significant bit of the address
    reg [STROBE_BUS_WIDTH-1:0] byte_strobe;
    reg [4:0] ar_last_dw;

    wire transaction_type = i_req_type[0]; /*Read -> 0, Write -> 1*/


    always @(*) begin
        /*AW Channel*/
        o_aw_write_inc =0 ;
        o_AWID = 0;
        o_AWADDR = 0;
        o_AWLEN = 0;
        o_AWQOS = 0;
        o_aw_request_info = 0;
        /*AR Channel*/
        o_ar_write_inc = 0;
        o_ARID = 0;
        o_ARADDR = 0;
        o_ARLEN = 0;
        o_ARQOS = 0;
        ar_last_dw = 0;
        o_ar_request_info = 0;
        /*W Channel*/
        o_WSTRB = STROBE_DEFAULT_VALUE;
        if (transaction_type == READ) begin
            o_ar_write_inc = i_req_inc;
            o_ARID = i_req_tag;
            o_ARADDR = i_req_address;
            o_ARLEN = i_req_length >> 5;
            o_ARQOS = {1'b0, i_req_traffic_class};
            ar_last_dw = i_req_length[4:0];
            o_ar_request_info = {i_requester_id, i_req_first_byte_enable, i_req_last_byte_enable, address_lsbs, ar_last_dw, i_req_type[1]};
        end
        else if(transaction_type == WRITE) begin
            o_aw_write_inc = i_req_inc;
            o_AWID = i_req_tag;
            o_AWADDR = i_req_address;
            o_AWLEN = i_req_length >> 5;
            o_AWQOS = {1'b0, i_req_traffic_class};
            o_aw_request_info = {i_requester_id, i_req_type[1]};
            o_WSTRB = byte_strobe;
        end

        if (i_address_type == ADDR_64) begin
            address_lsbs = i_req_address[4:0];
        end
        else begin
            address_lsbs = i_req_address[38:34];
        end
    end

/*
Byte Enable rules:
    - Length =  1 DW: FBE non-contiguous byte enables is accepted - LBE is 4'b0000 
    - Length =  2 DW: FBE & LBE non-contiguous byte enables are accepted
    - Length >= 3 DW: Contiguous byte enables is a must
*/
/* Note: byte strobes are generated by the master, its a good idea to consider sending FBE & LBE via AW & AR USER signals and hence decode the strobe in the AXI master 
    Also we won't need to store the strobe with the data (BONUS Pt :))
*/
    always @(*) begin
        byte_strobe = 0;
        if (i_req_length < 3) begin 
            byte_strobe = {i_req_first_byte_enable, i_req_last_byte_enable , {(STROBE_BUS_WIDTH-8){1'b0}}};
        end
        else if(i_req_valid) begin
            byte_strobe = {i_req_first_byte_enable, {31{4'hF}}};
        end
        else if(i_last) begin
            case (i_valid_data)
                DW_1:   byte_strobe = {             i_req_last_byte_enable, {124{1'b0}}};
                DW_2:   byte_strobe = {{4'hF},      i_req_last_byte_enable, {120{1'b0}}};
                DW_3:   byte_strobe = {{2{4'hF}},   i_req_last_byte_enable, {116{1'b0}}};
                DW_4:   byte_strobe = {{3{4'hF}},   i_req_last_byte_enable, {112{1'b0}}};
                DW_5:   byte_strobe = {{4{4'hF}},   i_req_last_byte_enable, {108{1'b0}}};
                DW_6:   byte_strobe = {{5{4'hF}},   i_req_last_byte_enable, {104{1'b0}}};
                DW_7:   byte_strobe = {{6{4'hF}},   i_req_last_byte_enable, {100{1'b0}}};
                DW_8:   byte_strobe = {{7{4'hF}},   i_req_last_byte_enable, {96{1'b0}}};
                DW_9:   byte_strobe = {{8{4'hF}},   i_req_last_byte_enable, {92{1'b0}}};
                DW_10:  byte_strobe = {{9{4'hF}},   i_req_last_byte_enable, {88{1'b0}}};
                DW_11:  byte_strobe = {{10{4'hF}},  i_req_last_byte_enable, {84{1'b0}}};
                DW_12:  byte_strobe = {{11{4'hF}},  i_req_last_byte_enable, {80{1'b0}}};
                DW_13:  byte_strobe = {{12{4'hF}},  i_req_last_byte_enable, {76{1'b0}}};
                DW_14:  byte_strobe = {{13{4'hF}},  i_req_last_byte_enable, {72{1'b0}}};
                DW_15:  byte_strobe = {{14{4'hF}},  i_req_last_byte_enable, {68{1'b0}}};
                DW_16:  byte_strobe = {{15{4'hF}},  i_req_last_byte_enable, {64{1'b0}}};
                DW_17:  byte_strobe = {{16{4'hF}},  i_req_last_byte_enable, {60{1'b0}}};
                DW_18:  byte_strobe = {{17{4'hF}},  i_req_last_byte_enable, {56{1'b0}}};
                DW_19:  byte_strobe = {{18{4'hF}},  i_req_last_byte_enable, {52{1'b0}}};
                DW_20:  byte_strobe = {{19{4'hF}},  i_req_last_byte_enable, {48{1'b0}}};
                DW_21:  byte_strobe = {{20{4'hF}},  i_req_last_byte_enable, {44{1'b0}}};
                DW_22:  byte_strobe = {{21{4'hF}},  i_req_last_byte_enable, {40{1'b0}}};
                DW_23:  byte_strobe = {{22{4'hF}},  i_req_last_byte_enable, {36{1'b0}}};
                DW_24:  byte_strobe = {{23{4'hF}},  i_req_last_byte_enable, {32{1'b0}}};
                DW_25:  byte_strobe = {{24{4'hF}},  i_req_last_byte_enable, {28{1'b0}}};
                DW_26:  byte_strobe = {{25{4'hF}},  i_req_last_byte_enable, {24{1'b0}}};
                DW_27:  byte_strobe = {{26{4'hF}},  i_req_last_byte_enable, {20{1'b0}}};
                DW_28:  byte_strobe = {{27{4'hF}},  i_req_last_byte_enable, {16{1'b0}}};
                DW_29:  byte_strobe = {{28{4'hF}},  i_req_last_byte_enable, {12{1'b0}}};
                DW_30:  byte_strobe = {{29{4'hF}},  i_req_last_byte_enable, {8{1'b0}}};
                DW_31:  byte_strobe = {{30{4'hF}},  i_req_last_byte_enable, {4{1'b0}}};
                DW_32:  byte_strobe = {{31{4'hF}},  i_req_last_byte_enable, {0{1'b0}}};
                default: byte_strobe = {STROBE_BUS_WIDTH{1'b1}};
            endcase
        end
        else if (i_req_length <= BEAT_SIZE) begin
            case (i_valid_data)
                // DW 1 & DW 2 are covered by the previous case
                DW_3:   byte_strobe = {i_req_first_byte_enable, {4'hF},     i_req_last_byte_enable, {(STROBE_BUS_WIDTH-12){1'b0}}};
                DW_4:   byte_strobe = {i_req_first_byte_enable, {2{4'hF}},  i_req_last_byte_enable, {(STROBE_BUS_WIDTH-16){1'b0}}};
                DW_5:   byte_strobe = {i_req_first_byte_enable, {3{4'hF}},  i_req_last_byte_enable, {(STROBE_BUS_WIDTH-20){1'b0}}};
                DW_6:   byte_strobe = {i_req_first_byte_enable, {4{4'hF}},  i_req_last_byte_enable, {(STROBE_BUS_WIDTH-24){1'b0}}};
                DW_7:   byte_strobe = {i_req_first_byte_enable, {5{4'hF}},  i_req_last_byte_enable, {(STROBE_BUS_WIDTH-28){1'b0}}};
                DW_8:   byte_strobe = {i_req_first_byte_enable, {6{4'hF}},  i_req_last_byte_enable, {(STROBE_BUS_WIDTH-32){1'b0}}};
                DW_9:   byte_strobe = {i_req_first_byte_enable, {7{4'hF}},  i_req_last_byte_enable, {(STROBE_BUS_WIDTH-36){1'b0}}};
                DW_10:  byte_strobe = {i_req_first_byte_enable, {8{4'hF}},  i_req_last_byte_enable, {(STROBE_BUS_WIDTH-40){1'b0}}};
                DW_11:  byte_strobe = {i_req_first_byte_enable, {9{4'hF}},  i_req_last_byte_enable, {(STROBE_BUS_WIDTH-44){1'b0}}};
                DW_12:  byte_strobe = {i_req_first_byte_enable, {10{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-48){1'b0}}};
                DW_13:  byte_strobe = {i_req_first_byte_enable, {11{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-52){1'b0}}};
                DW_14:  byte_strobe = {i_req_first_byte_enable, {12{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-56){1'b0}}};
                DW_15:  byte_strobe = {i_req_first_byte_enable, {13{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-60){1'b0}}};
                DW_16:  byte_strobe = {i_req_first_byte_enable, {14{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-64){1'b0}}};
                DW_17:  byte_strobe = {i_req_first_byte_enable, {15{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-68){1'b0}}};
                DW_18:  byte_strobe = {i_req_first_byte_enable, {16{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-72){1'b0}}};
                DW_19:  byte_strobe = {i_req_first_byte_enable, {17{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-76){1'b0}}};
                DW_20:  byte_strobe = {i_req_first_byte_enable, {18{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-80){1'b0}}};
                DW_21:  byte_strobe = {i_req_first_byte_enable, {19{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-84){1'b0}}};
                DW_22:  byte_strobe = {i_req_first_byte_enable, {20{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-88){1'b0}}};
                DW_23:  byte_strobe = {i_req_first_byte_enable, {21{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-92){1'b0}}};
                DW_24:  byte_strobe = {i_req_first_byte_enable, {22{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-96){1'b0}}};
                DW_25:  byte_strobe = {i_req_first_byte_enable, {23{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-100){1'b0}}};
                DW_26:  byte_strobe = {i_req_first_byte_enable, {24{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-104){1'b0}}};
                DW_27:  byte_strobe = {i_req_first_byte_enable, {25{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-108){1'b0}}};
                DW_28:  byte_strobe = {i_req_first_byte_enable, {26{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-112){1'b0}}};
                DW_29:  byte_strobe = {i_req_first_byte_enable, {27{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-116){1'b0}}};
                DW_30:  byte_strobe = {i_req_first_byte_enable, {28{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-120){1'b0}}};
                DW_31:  byte_strobe = {i_req_first_byte_enable, {29{4'hF}}, i_req_last_byte_enable, {(STROBE_BUS_WIDTH-124){1'b0}}};
                DW_32:  byte_strobe = {i_req_first_byte_enable, {30{4'hF}}, i_req_last_byte_enable};
                default: byte_strobe = {STROBE_BUS_WIDTH{1'b1}};
            endcase
        end
        else begin
            byte_strobe = STROBE_DEFAULT_VALUE;
        end
    end

endmodule
