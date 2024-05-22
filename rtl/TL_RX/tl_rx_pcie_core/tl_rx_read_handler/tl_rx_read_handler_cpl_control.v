/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_read_handler_cpl_control
   DEPARTMENT :     Read Handler
   AUTHOR :         Reem Mohamed - Omar Hafez
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com - eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-04-07              initial version
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
module tl_rx_read_handler_cpl_control #(
    parameter   CPL_FLAGS_WIDTH = 2,
                PAYLOAD_LENGTH = 10,
                VALID_DATA_WIDTH = 5,
                R_CTRL_BUS_WIDTH = 6
) (     
    //------ Global Signals ------//
    input   wire                                i_clk,
    input   wire                                i_n_rst,
    //----- Virtual Channels Interface -----//
    input   wire                                i_cpl_fmt_data_bit,
    input   wire    [CPL_FLAGS_WIDTH-1:0]       i_vcn_cpl_r_empty_flags,
    input   wire    [PAYLOAD_LENGTH-1:0]        i_cpl_length_field,
    output  wire    [R_CTRL_BUS_WIDTH-1:0]      o_r_completion_ctrl,
    //------- RX FLow Control Interface -------//
    output  wire                                o_cpl_ca_hdr_inc,
    output  reg                                 o_cpl_ca_data_inc,
    //----- AXI Slave Interface -----//
    input   wire                                i_slave_ready,
    output  reg                                 o_slave_cpl_vaild,
    output  reg     [VALID_DATA_WIDTH-1:0]      o_slave_cpl_valid_data    /*indicates the valid data Double Words on the completion data bus- all ones means all the 32 DWs are valid*/
    // output  wire                                 o_slave_cpl_last,
);
    
    localparam  DATA =0, NO_DATA = 1;
    localparam DATA_INCR_MODE_WIDTH = 3;
    localparam CPL_HEADER_SIZE = 3;  
    localparam STATE_REG_WIDTH = 2;   

    localparam [STATE_REG_WIDTH-1:0]    IDLE            = 2'b00,
                                        HDR_TRANSFER    = 2'b01,
                                        DATA_TRANSFER   = 2'b11;

    localparam  [1:0]   INCR_BY_1 = 2'b00,
                        INCR_BY_2 = 2'b01,
                        INCR_BY_3 = 2'b10,
                        INCR_BY_4 = 2'b11;

    reg                                 vcn_read_hdr_inc_en;
    reg                                 vcn_read_data_inc_en;
    reg [DATA_INCR_MODE_WIDTH-1:0]      vcn_read_data_inc_value;
    reg counter_ld;
    reg counter_en;
    reg [STATE_REG_WIDTH-1:0]   present_state;              /*fsm present state register*/
    reg [STATE_REG_WIDTH-1:0]   next_state;                 /*fsm next state logic*/ 
    
    assign {vcn_cpl_hdr_empty_flag, vcn_cpl_data_empty_flag} = i_vcn_cpl_r_empty_flags;                    

    wire buffer_empty = vcn_cpl_hdr_empty_flag && vcn_cpl_data_empty_flag;
    wire [1:0] r_status = next_state;
    wire send_done;
   
    wire r_data_allignment = 0;  // 1: Least 4DW, Most 4DW, 0: Least 5DW, Most 3DW | in completion, it is hard-wired to 1, added just for completness

    assign o_r_completion_ctrl = {vcn_read_hdr_inc_en, vcn_read_data_inc_en, vcn_read_data_inc_value, r_data_allignment};
    assign {vcn_cpl_hdr_empty_flag, vcn_cpl_data_empty_flag} = i_vcn_cpl_r_empty_flags;
    assign o_cpl_ca_hdr_inc = 0; // increment rx fc header credits allocated counter when incrementing read header pointer of the VC buffer
    
   /************************************
    *********** Cycles Counter *********
    *************************************/
    localparam CYCYLES_CNTR_WIDTH  = 5;             // 1024DW/32 = 32 cycles
    
    reg [4:0] remainder;         
    reg [CYCYLES_CNTR_WIDTH-1:0] num_cycles_logic;
    reg [4:0] last_dw_location_logic;         
    reg [CYCYLES_CNTR_WIDTH-1:0] cycles_counter;      /*Down counter that initially is loaded with the number of cycles required */
    
    assign send_done = ~|cycles_counter;

    always @(*) begin
        remainder = i_cpl_length_field[4:0];
        if(~i_cpl_fmt_data_bit) begin   // if completion with no data
            num_cycles_logic = 0;
            last_dw_location_logic = 0;
        end
        else if (~|remainder) begin // if divisible by 32
            num_cycles_logic =  (i_cpl_length_field >> 5) - 1'b1;
            last_dw_location_logic = 5'b1_1111;     //all ones means all the 32 DWs are valid
        end
        else begin
            num_cycles_logic =  (i_cpl_length_field >> 5);
            last_dw_location_logic = remainder - 1'b1; // subract one to map the remainder to o_slave_cpl_valid_data (as 5'b00000 -> 1 DW Valid)
        end
    end

    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            cycles_counter <= 0;
        end
        else if (counter_ld) begin
            cycles_counter <= num_cycles_logic;
        end
        else if (counter_en) begin
            cycles_counter = cycles_counter - 1'b1; // decrement the counter 
        end
    end

   /*************************************
    ******* Data Increment logic ********
    *************************************/
    
    /*Virtal Channel Data read pointer Increment logic*/
    always @(*) begin
        vcn_read_data_inc_value = 0;
        if (buffer_empty || ~vcn_read_data_inc_en) begin
            vcn_read_data_inc_value = 0;
        end
        else if(~send_done) begin
            vcn_read_data_inc_value = 3'd4;
        end
        else if (o_slave_cpl_valid_data > 5'd28) begin
            vcn_read_data_inc_value = 3'd5;
        end
        else if (o_slave_cpl_valid_data > 5'd20) begin
            vcn_read_data_inc_value = 3'd4;
        end
        else if (o_slave_cpl_valid_data > 5'd12) begin
            vcn_read_data_inc_value = 3'd3;
        end
        else if (o_slave_cpl_valid_data > 5'd4) begin
            vcn_read_data_inc_value = 3'd2;
        end
        else begin
            vcn_read_data_inc_value = 3'd1;
        end
    end

    // always @(*) begin
    //     vcn_read_data_inc_value = 0;
    //     if (buffer_empty || ~vcn_read_data_inc_en) begin
    //         vcn_read_data_inc_value = 0;
    //     end
    //     else if(~send_done) begin
    //         vcn_read_data_inc_value = 3'd4;
    //     end
    //     else if (o_slave_cpl_valid_data > 5'd27) begin
    //         vcn_read_data_inc_value = 3'd5;
    //     end
    //     else if (o_slave_cpl_valid_data > 5'd19) begin
    //         vcn_read_data_inc_value = 3'd4;
    //     end
    //     else if (o_slave_cpl_valid_data > 5'd11) begin
    //         vcn_read_data_inc_value = 3'd3;
    //     end
    //     else if (o_slave_cpl_valid_data > 5'd3) begin
    //         vcn_read_data_inc_value = 3'd2;
    //     end
    //     else begin
    //         vcn_read_data_inc_value = 3'd1;
    //     end
    // end

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
        counter_ld = 0;
        counter_en = 0;
        o_slave_cpl_vaild = 0;
        vcn_read_hdr_inc_en = 0;
        vcn_read_data_inc_en = 0;
        // o_slave_cpl_last = 0;
        o_cpl_ca_data_inc = 0;
        o_slave_cpl_valid_data = 0;
        case (present_state)
            IDLE: begin
                if(buffer_empty) begin
                    next_state = IDLE;
                end
                else begin
                    next_state = HDR_TRANSFER;
                    o_slave_cpl_vaild = 1'b1; 
                    counter_ld = 1'b1; // check this condition
                    if (~num_cycles_logic) begin
                        o_slave_cpl_valid_data = 5'b1_1111; //all ones means all the 32 DWs are valid
                    end
                    else begin
                        o_slave_cpl_valid_data = last_dw_location_logic; 
                    end
                end
            end
            HDR_TRANSFER: begin
                if (~i_slave_ready) begin
                    next_state = HDR_TRANSFER;
                    o_slave_cpl_vaild = 1'b1; 
                    if (~num_cycles_logic) begin
                        o_slave_cpl_valid_data = 5'b1_1111; //all ones means all the 32 DWs are valid
                    end
                    else begin
                        o_slave_cpl_valid_data = last_dw_location_logic; //all ones means all the 32 DWs are valid
                    end
                end
                else if (~send_done) begin
                    next_state = DATA_TRANSFER;
                    counter_en = 1'b1;
                    vcn_read_data_inc_en =1'b1;
                    o_slave_cpl_valid_data = 5'b1_1111; //all ones means all the 32 DWs are valid
                end
                else begin
                    next_state = IDLE;
                    // o_slave_cpl_last = 1'b1;
                    vcn_read_hdr_inc_en = 1'b1;
                    o_slave_cpl_valid_data = last_dw_location_logic; //all ones means all the 32 DWs are valid
                    if (i_cpl_fmt_data_bit) begin
                        vcn_read_data_inc_en =1'b1;
                    end
                    else begin
                        vcn_read_data_inc_en =1'b0;
                    end
                end
            end
            DATA_TRANSFER: begin
                if (~send_done) begin
                    next_state = DATA_TRANSFER;
                    counter_en = 1'b1;
                    vcn_read_data_inc_en =1'b1;
                    o_slave_cpl_valid_data = 5'b1_1111; //all ones means all the 32 DWs are valid
                    end
                else begin
                    next_state = IDLE;
                    vcn_read_hdr_inc_en = 1'b1;
                    vcn_read_data_inc_en =1'b1;
                    // o_slave_cpl_last = 1'b1;
                    o_cpl_ca_data_inc = 1'b1;       // increment rx fc data credits allocated counter only after 
                    o_slave_cpl_valid_data = last_dw_location_logic; //all ones means all the 32 DWs are valid
                end
            end
            default: begin
                    next_state = IDLE;
            end
        endcase
    end
endmodule
