/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_write_handler_tlp_processing
   DEPARTMENT :     Write Handler
   AUTHOR :         Reem Mohamed - Omar Hafez
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com - eng.omar.amr@gmail.com
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

module tl_rx_write_handler_tlp_processing #(
    parameter   DW = 32,
                TYPE_DEC_WIDTH      = 2,            // POSTED - non-POSTED - COMPLETION
                FLAGS_WIDTH         = 6,            // full flags from vc buffers
                W_CTRL_BUS_WIDTH      = 6,
                RCV_BUS_WIDTH       = 8*DW,
                PAYLOAD_LENGTH      = 10,
                VALID_DATA          = 3,
                REQ_HDR_SIZE        = 4*DW,
                CPL_HDR_SIZE        = 3*DW,
                P_DATA_IP_WIDTH = 8*DW,
                NP_DATA_IP_WIDTH = 1*DW,
                CPL_DATA_IP_WIDTH = 8*DW,
                HDR_FIELDS_WIDTH    = 118,
                TRAS_TYPE_WIDTH = 3

) (
    //------ Global Signals ------//
    input   wire                            i_clk,
    input   wire                            i_n_rst,
    // ----- DLL Interface -----//
    input   wire                            i_dll_rx_sop,
    input   wire    [RCV_BUS_WIDTH-1:0]     i_dll_rx_tlp,
    // ----- Error Check Interface -----//
    input   wire                            i_rcv_error,
    output  reg     [TRAS_TYPE_WIDTH-1:0]   o_transaction_type,     /*MEMORY - IO - CONFIGURATION - COMPLETION - MESSAGE*/
    output  wire    [TYPE_DEC_WIDTH-1:0]    o_buffer_type,          /* (POSTED - NONPOSTED - COMPLETION) output for both Error Check and RX Flow Control */
    output  reg                             o_write_n_read,         /*read transaction -> 0 - write transaction -> 1*/
    output  reg                             o_address_type,         /*32-bit address -> 0 - 64-bit address -> 1*/
    output  wire    [2:0]                   o_last_dw,
    output  wire                            o_rcv_done,
    output  wire    [HDR_FIELDS_WIDTH-1:0]  o_error_check_hdr_fields,
    output  reg                             o_error_check_en,
    // ----- ECRC Check Interface -----//
    output  reg                             o_ecrc_en,
    output  reg                             o_ecrc_done,
    output  reg                             o_ecrc_n_clr,
    output  reg     [VALID_DATA-1:0]        o_ecrc_input_length,
    output  reg                             o_hdr_write_flag,   /* output for both VC and ECRC: A Flag that is raised when reciving a header */
    // ----- Virtual Channel Interface -----//
    input   wire    [FLAGS_WIDTH-1:0]       i_vc0_w_full_flags,
    output  reg                             o_w_valid,          /* A Signal indicating that the received TLP is error free*/ 
    /*POSTED*/
    output  reg     [REQ_HDR_SIZE-1:0]      o_w_posted_hdr,
    output  reg     [P_DATA_IP_WIDTH-1:0]   o_w_posted_data,
    output  reg     [W_CTRL_BUS_WIDTH-1:0]  o_w_posted_ctrl,
    /*NON_POSTED*/
    output  reg     [REQ_HDR_SIZE-1:0]      o_w_non_posted_hdr,
    output  reg     [NP_DATA_IP_WIDTH-1:0]  o_w_non_posted_data,
    output  reg     [W_CTRL_BUS_WIDTH-1:0]  o_w_non_posted_ctrl,
    /*COMPLETION*/
    output  reg     [CPL_HDR_SIZE-1:0]      o_w_completion_hdr,
    output  reg     [CPL_DATA_IP_WIDTH-1:0] o_w_completion_data,
    output  reg     [W_CTRL_BUS_WIDTH-1:0]  o_w_completion_ctrl,
    //------- RX FLow Control Interface -------//
    output  wire                            o_cr_hdr_inc,
    output  wire                            o_cr_data_inc,
    output  wire    [PAYLOAD_LENGTH-1:0]    o_payload_length
);

    /*type decoding*/
    localparam [1:0]    POSTED                  = 2'b00,
                        NON_POSTED              = 2'b01,
                        COMPLETION              = 2'b10;

    /*fmt and type Encodings*/
    localparam [7:0]    MRd_32      = 8'b0000_0000, // address width 32-bit
                        MRd_64      = 8'b0010_0000, // address width 64-bit
                        MRdLk_32    = 8'b0000_0001,
                        MRdLk_64    = 8'b0010_0001,
                        MWr_32      = 8'b0100_0000,
                        MWr_64      = 8'b0110_0000,
                        IORd        = 8'b0000_0010,
                        IOWr        = 8'b0100_0010,
                        CfgRd0      = 8'b0000_0100,
                        CfgWr0      = 8'b0100_0100,
                        CfgRd1      = 8'b0000_0101,
                        CfgWr1      = 8'b0100_0101,
                        msg         = 8'b0011_00??,
                        msgd        = 8'b0111_00??,
                        cpl         = 8'b0000_1010,
                        cpld        = 8'b0100_1010,
                        cpllk       = 8'b0000_1011,
                        cpldlk      = 8'b0100_1011,
                        fetchadd    = 8'b01?0_1100,
                        swap        = 8'b01?0_1101,
                        cas         = 8'b01?0_1110;
    /*Fmt Encoding*/
    localparam [1:0]    H3  = 2'b00,     /*Header 3DW - No Data*/
                        H4  = 2'b01,     /*Header 4DW - No Data*/
                        H3D = 2'b10,     /*Header 3DW - Wtih Data*/
                        H4D = 2'b11;     /*Header 4DW - With Data*/

    /*ECRC Length input Encoding*/
    localparam [2:0]    DW_1 = 3'd0,
                        DW_2 = 3'd1,
                        DW_3 = 3'd2,
                        DW_4 = 3'd3,
                        DW_5 = 3'd4,
                        DW_6 = 3'd5,
                        DW_7 = 3'd6,
                        DW_8 = 3'd7;


    localparam STATE_REG_WIDTH = 2;
    localparam [STATE_REG_WIDTH-1:0]    IDLE        = 2'b00,
                                        DATA_RCV    = 2'b01,
                                        DIGEST_RCV_CYCLE   = 2'b10;

    localparam  MEMORY = 3'b000,
                IO = 3'b001,
                CONFIGURATION = 3'b011,
                MESSAGE = 3'b100;

    localparam READ = 0, WRITE = 1;

    localparam  ADDRESS_WIDTH    = 64;
    localparam  REQ_CPL_ID_WIDTH = 16;
    localparam  TAG_WIDTH = 10;

    localparam  ADDR_32 = 0,
                ADDR_64 = 1;

    /****************************************************
    ************ Wires and Regs Declaration *************
    ****************************************************/

    /*regs*/
    reg [4*DW-1:0]              tlp_header_reg;             /*Register that stores the entire incoming TLP header for error handlig*/
    reg                         data_transaction_logic;
    reg                         data_transaction_reg;
    reg [TYPE_DEC_WIDTH-1:0]    buffer_type_logic;
    reg [TYPE_DEC_WIDTH-1:0]    buffer_type_reg;
    reg                         fsm_cycles_ld;              /*fsm signals the cycles calcualtion block to load the length value and hence calculating data cycles required*/
    reg                         fsm_cycles_n_clr;           /*fsm signal that clears the cycles counter synchronously in case of an error*/
    reg [STATE_REG_WIDTH-1:0]   present_state;              /*fsm present state register*/
    reg [STATE_REG_WIDTH-1:0]   next_state;                 /*fsm next state logic*/
    reg                         vcn_data_write_en;        /*Enables writing to VC data buffer when a transaction contains data*/
    reg                         digest_cycle;        
    reg                         data_w_ptr_ld;        

    /*wires*/
    wire                        data_transaction;
    wire [4*DW-1:0]             tlp_header_input        = i_dll_rx_tlp[8*DW-1:4*DW];                                       /*DIRECT INPUT TO BE REGISTERED */
    wire [2:0]                  fmt_input               = tlp_header_input[127:125];                                       /*DIRECT INPUT TO BE REGISTERED: format input field from dll rcv bus (valid only for 1 clk cycle after receiving sop)*/
    wire [4:0]                  type_input              = tlp_header_input[124:120];                                       /*DIRECT INPUT TO BE REGISTERED: type input field from dll rcv bus (valid only for 1 clk cycle after receiving sop)*/
    wire                        TD_input                = tlp_header_input[111];                                           /*DIRECT INPUT TO BE REGISTERED */
    wire [PAYLOAD_LENGTH-1:0]   payload_length_input    = tlp_header_input[105:96];                                        /*DIRECT INPUT TO BE REGISTERED */
    wire [1:0]                  w_status                = next_state;                                                       /*Ouput the next state of the FSM*/
    wire [W_CTRL_BUS_WIDTH-1:0] ctrl_bus                = {o_w_valid, w_status, vcn_data_write_en, o_hdr_write_flag, digest_cycle};    /*virtual channels buffers control bus*/

    /*Info Stored for error check*/
    wire [2:0]                   tlp_fmt_reg;
    wire [4:0]                   tlp_typ_reg;
    wire [2:0]                   TC_reg;
    wire                         TD_reg;
    wire                         EP_reg;
    wire [1:0]                   Attr_reg;
    wire [1:0]                   AT_reg;
    wire [PAYLOAD_LENGTH-1:0]    payload_length_reg;
    wire [2:0]                   completion_status_reg;
    wire [7:0]                   message_code_reg;
    /*Info Decoded for error check*/
    wire [REQ_CPL_ID_WIDTH-1:0] rcvd_cpl_requester_id_reg;
    wire [TAG_WIDTH-1:0] rcvd_cpl_requester_tag_reg;
    reg [ADDRESS_WIDTH-1:0]     address_reg;

    /*vc0 full flags*/
    assign {vc0_p_hdr_full_flag, vc0_p_data_full_flag, vc0_np_hdr_full_flag, vc0_np_data_full_flag, vc0_cpl_hdr_full_flag, vc0_cpl_data_full_flag} = i_vc0_w_full_flags;

    assign o_cr_hdr_inc = o_w_valid;
    assign o_cr_data_inc = o_w_valid && data_transaction;
    assign o_payload_length = payload_length_reg;

    /*************************************************
    ************** type and format decoder ***********
    *************************************************/
    always @(*) begin
        /*default output values*/
        buffer_type_logic = 0;
        data_transaction_logic = 0;
        casez ({fmt_input,type_input}) // direct input (valid for one cycle when dll_SOP signal is raised)
            MRd_32, MRd_64, MRdLk_32, MRdLk_64, IORd, CfgRd0, CfgRd1: begin
                buffer_type_logic = NON_POSTED;
                data_transaction_logic = 1'b0;
            end
            MWr_32, MWr_64: begin
                buffer_type_logic = POSTED;
                data_transaction_logic = 1'b1;
            end
            IOWr, CfgWr0, CfgWr1: begin
                buffer_type_logic = NON_POSTED;
                data_transaction_logic = 1'b1;
            end
            msg: begin
                buffer_type_logic = POSTED;
                data_transaction_logic = 1'b0;
            end
            msgd: begin
                buffer_type_logic = POSTED;
                data_transaction_logic = 1'b1;
            end
            cpl, cpllk: begin
                buffer_type_logic = COMPLETION;
                data_transaction_logic = 1'b0;
            end
            cpld, cpldlk: begin
                buffer_type_logic = COMPLETION;
                data_transaction_logic = 1'b1;
            end
            fetchadd, swap, cas: begin
                buffer_type_logic = NON_POSTED;
                data_transaction_logic = 1'b1;
            end
            default: begin
                buffer_type_logic = 0;
                data_transaction_logic = 0;
            end
        endcase
    end

    /*tlp decoder registered op*/
    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            buffer_type_reg <= 0;
            data_transaction_reg <= 0;
        end
        else if (o_hdr_write_flag) begin
            buffer_type_reg <= buffer_type_logic;
            data_transaction_reg <= data_transaction_logic;
        end
    end

    assign o_buffer_type = (o_hdr_write_flag)? buffer_type_logic : buffer_type_reg;
    assign data_transaction = (o_hdr_write_flag)? data_transaction_logic : data_transaction_reg;

    /********************************************
    ************ cycles calculation *************
    ********************************************/
    localparam CYCYLES_CNTR_WIDTH  = 8;             // 1029DW/8 = 129 cycles
    reg [CYCYLES_CNTR_WIDTH-1:0] cycles_counter;    /*Down counter that initially is loaded with the number of cycles required */
    reg [CYCYLES_CNTR_WIDTH-1:0] num_cycles_logic;
    reg [2:0] last_dw_location_logic;
    reg [2:0] last_dw_location_reg;
    reg [10:0] total_transcation_dw;      //1029 DW
    wire [CYCYLES_CNTR_WIDTH-1:0] num_cycles;
    wire digest_cycle_flag =  (((num_cycles == 'd2) && (present_state == DATA_RCV)) || (num_cycles == 'd1)) && TD_reg && (o_last_dw == 1'b1); // condition for receiving ECRC in a dedicated cycle (No data)

    assign o_last_dw = (fsm_cycles_ld)? last_dw_location_logic: last_dw_location_reg;
    assign num_cycles = (fsm_cycles_ld)? num_cycles_logic : cycles_counter; // instead of muxing num_cycles, multiplex o_rcv_done to reduce the no of muxes
    assign o_rcv_done = ((num_cycles == 'b0) && (i_dll_rx_sop) ) || ((num_cycles == 'b1) && ((present_state == DATA_RCV) || (present_state == DIGEST_RCV_CYCLE))); // asserted if if counter value is 1 to indicate that the data driven by the DLL at that moment is the last data
    // assign o_rcv_done = (num_cycles == 0)  && ( i_dll_rx_sop ||(present_state == DATA_RCV));
    

    always @(*) begin
        case (fmt_input[1:0])
        H3 : begin
            total_transcation_dw = 'd3 + TD_input;
        end
        H3D: begin
            if(payload_length_input != 0) begin // length encoding for 1024 DW
                total_transcation_dw = 'd3 + TD_input + payload_length_input;
            end
            else begin
                total_transcation_dw = 'd3 + TD_input + 'd1024;
            end
        end
        H4 : begin
            total_transcation_dw = 'd4 + TD_input;
        end
        H4D: begin
            if(payload_length_input != 0) begin
                total_transcation_dw = 'd4 + TD_input + payload_length_input;
            end
            else begin
                total_transcation_dw = 'd4 + TD_input + 'd1024;
            end
        end
        default: begin
            total_transcation_dw = 0;
        end
        endcase

        last_dw_location_logic = total_transcation_dw[2:0];
        if(~|last_dw_location_logic) begin // if no remainder
            num_cycles_logic = (total_transcation_dw >> 3) - 1'b1;
        end
        else begin
            num_cycles_logic = total_transcation_dw >> 3;   // notice that a ceil is not used since a clock cycle has already elapsed
        end
    end

    /*cycles_counter*/
    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            cycles_counter <= 0;
            last_dw_location_reg <= 0;
        end
        else if (~fsm_cycles_n_clr) begin
            cycles_counter <= 0;
        end
        else if (fsm_cycles_ld) begin
            cycles_counter <= num_cycles_logic;
            last_dw_location_reg <= last_dw_location_logic;
        end
        else if(cycles_counter != 'b0) begin
            cycles_counter = cycles_counter - 1'b1;
        end
    end

    /*ECRC valid data input calculation*/
    always @(*) begin
        if(!num_cycles) begin
            o_ecrc_input_length = DW_8;
        end
        else if (~o_last_dw) begin
            o_ecrc_input_length = DW_8;
        end
        else begin
            o_ecrc_input_length = o_last_dw - 1'b1;
        end
    end

    /**************************************
    ***************** FSM *****************
    ***************************************/

    /*state logic transition*/
    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            present_state <= IDLE;
        end
        else begin
            present_state <= next_state;
        end
    end

    /*next state and output transition*/
    always @(*) begin
        fsm_cycles_ld = 0;      // load cycles counter and last dw reg
        fsm_cycles_n_clr = 1;   // active low signal so it is high by default
        vcn_data_write_en = 0;  // enable writing to VC data buffer if the ongoing transcation contains payload
        o_hdr_write_flag = 0;   // a flag is raised to write header
        digest_cycle = 0;  
        data_w_ptr_ld = 0;  
        o_error_check_en = 0;   // enables error check block
        o_w_valid = 0;          // validates that the currently received TLP is error free
        o_ecrc_en = 0;          // enable ecrc calculation for check
        o_ecrc_done = 0;        // enables ecrc output
        o_ecrc_n_clr = 1;       // returning IDLE will always clear ECRC
        case (present_state)
            IDLE: begin
                if (i_dll_rx_sop && (num_cycles != 0)) begin
                    if (digest_cycle_flag) begin
                        next_state = DIGEST_RCV_CYCLE;
                    end
                    else begin
                        next_state = DATA_RCV;
                    end
                    fsm_cycles_ld = 1;
                    o_ecrc_en = TD_reg;
                    o_hdr_write_flag = 1'b1;
                    vcn_data_write_en = data_transaction;
                end
                else begin
                    next_state = IDLE;
                    if (i_dll_rx_sop) begin
                        vcn_data_write_en = data_transaction;
                        fsm_cycles_ld = 1; // load the cycles to get the bypassed combinational value (registering the input packet shall omit bypassing, will do after finals)
                        o_error_check_en = 1'b1; // enable error block
                        o_hdr_write_flag = 1'b1;
                        o_w_valid = ~i_rcv_error;
                    end
                end
            end
            DATA_RCV: begin
                vcn_data_write_en = 1; // if in this state then it is a data transaction
                if (digest_cycle_flag) begin
                    next_state = DIGEST_RCV_CYCLE;
                end
                else if (o_rcv_done || i_rcv_error) begin
                    next_state = IDLE;
                    fsm_cycles_n_clr = 0; // to clear last DW
                    o_w_valid = ~i_rcv_error;
                    data_w_ptr_ld = 1;
                end
                else begin
                    next_state = DATA_RCV;
                    o_ecrc_en = TD_reg;
                end
                o_error_check_en = 1'b1; // enable error block
            end
            DIGEST_RCV_CYCLE: begin
                next_state = IDLE;
                data_w_ptr_ld = 1;
                digest_cycle = 1;  
                o_w_valid = ~i_rcv_error;
                fsm_cycles_n_clr = 0;
                vcn_data_write_en = 1; // if in this state then it is a data transaction
            end
            default:begin
                next_state = IDLE;
            end
        endcase
    end

    /******************************************************
    ************  TLP Processing Output Logic *************
    *******************************************************/

    /******* Channel Buffers Demux *******/
    always @(*) begin
        o_w_posted_hdr = 0;
        o_w_posted_data = 0;
        o_w_posted_ctrl = 0;
        o_w_non_posted_hdr = 0;
        o_w_non_posted_data = 0;
        o_w_non_posted_ctrl = 0;
        o_w_completion_hdr = 0;
        o_w_completion_data = 0;
        o_w_completion_ctrl = 0;
        case (o_buffer_type)
            POSTED: begin
                o_w_posted_hdr = tlp_header_input;
                o_w_posted_data = i_dll_rx_tlp;
                o_w_posted_ctrl = ctrl_bus;
            end
            NON_POSTED: begin
                o_w_non_posted_hdr = tlp_header_input;
                // Notice that in case of Memory Read Request there is no data, so we dont need to check wheter address is 32 or 64 to determine the location of Data
                // The Non Posted data in case of memory write and configuration write will always be in the location 5DW-1:4DW as both these transactions has a header length of 3 DW
                o_w_non_posted_data = i_dll_rx_tlp[5*DW-1:4*DW];
                o_w_non_posted_ctrl = ctrl_bus;
            end
            COMPLETION: begin
                o_w_completion_hdr = tlp_header_input[4*DW-1:1*DW]; // the 3 MS DWs are the header in case of copmletion
                o_w_completion_data = i_dll_rx_tlp;
                o_w_completion_ctrl = ctrl_bus;
            end
        endcase
    end

    /********** Error Check Interface  **********/

    // reg storing header info
    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            tlp_header_reg <= 0;
        end
        else if (o_hdr_write_flag) begin
            tlp_header_reg <= tlp_header_input;
        end
    end

    always @(*) begin
        o_transaction_type = 0; /*MEMORY - IO - CONFIGURATION - COMPLETION - MESSAGE*/
        o_write_n_read = 0;     /*read transaction -> 0 - write transaction -> 1*/
        o_address_type = 0;      /*32-bit address -> 0 - 64-bit address -> 1*/
        case ({tlp_fmt_reg, tlp_typ_reg})   // registered
            MRd_32, MRdLk_32: begin
                o_transaction_type = MEMORY;
                o_write_n_read = READ;
                o_address_type = ADDR_32;
            end
            MRd_64, MRdLk_64: begin
                o_transaction_type = MEMORY;
                o_write_n_read = READ;
                o_address_type = ADDR_64;
            end
            IORd: begin
                o_transaction_type = IO;
                o_write_n_read = READ;
                o_address_type = ADDR_32;
            end
            CfgRd0, CfgRd1: begin
                o_transaction_type = CONFIGURATION;
                o_write_n_read = READ;
                o_address_type = ADDR_32;
            end
            MWr_32: begin
                o_transaction_type = MEMORY;
                o_write_n_read = WRITE;
                o_address_type = ADDR_32;
            end
            MWr_64: begin
                o_transaction_type = MEMORY;
                o_write_n_read = WRITE;
                o_address_type = ADDR_64;
            end
            IOWr: begin
                o_transaction_type = IO;
                o_write_n_read = WRITE;
                o_address_type = ADDR_32;
            end
            CfgWr0, CfgWr1: begin
                o_transaction_type = CONFIGURATION;
                o_write_n_read = WRITE;
                o_address_type = ADDR_32;
            end
            msg, msgd: begin
                o_transaction_type = MESSAGE;
            end
            cpl, cpllk, cpld, cpldlk: begin
                o_transaction_type = COMPLETION;
            end
        endcase
        
        if (o_address_type) begin
            address_reg = {tlp_header_reg[63:2], 2'b00};
        end
        else begin
            address_reg = {tlp_header_reg[63:34], 2'b00};
        end
    end

    assign tlp_fmt_reg = tlp_header_reg[127:125];
    assign tlp_typ_reg = tlp_header_reg[124:120];
    assign TC_reg = tlp_header_reg[118:116];
    assign TD_reg = tlp_header_reg[111];
    assign EP_reg = tlp_header_reg[110];
    assign Attr_reg = tlp_header_reg[109:108];
    assign AT_reg = tlp_header_reg[107:106];
    assign payload_length_reg = tlp_header_reg[105:96];
    assign completion_status_reg = tlp_header_reg[79:77];
    assign message_code_reg = tlp_header_reg[71:64];
    assign rcvd_cpl_requester_id_reg = tlp_header_reg[63:48];
    assign rcvd_cpl_requester_tag_reg = tlp_header_reg[47:38];
    assign o_error_check_hdr_fields = {TC_reg, TD_reg, EP_reg, Attr_reg, AT_reg, payload_length_reg, completion_status_reg, message_code_reg, rcvd_cpl_requester_id_reg, rcvd_cpl_requester_tag_reg, address_reg};

    /********** TLP Registering **********/
    // always @(posedge clk or negedge i_n_rst) begin
    //     if(~i_n_rst) begin
    //         tlp_header_reg <= 0;
    //     end
    // end

endmodule
