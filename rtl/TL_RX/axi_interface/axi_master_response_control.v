/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      axi_master_responce_control
   DEPARTMENT :     AXI Master
   AUTHOR :         Reem Mohamed - Omar Hafez
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com - eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-04-25             initial version
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
module axi_master_response_control #(
    parameter   RESP_WIDTH = 2,
                CNTR_WIDTH = 6
   ) (
    //------- Global Signals -------//
    input   wire                                i_clk,
    input   wire                                i_n_rst,
    input   wire                                i_write_reqest_type,
    //------ B Channel FIFO Interface------//
    output  reg                                 o_b_ch_fifo_write_inc,
    input   wire                                i_BREADY_fifo,      /*A transaction is need to be written in the FIFO, hence we shall know if the FIFO is EMPTY*/
    //------ Write Responce Channel Slave Interface------//
    input   wire                                i_s_BVALID,
    output  reg                                 o_s_BREADY,
    //------ R Channel FIFO Interface------//
    output  reg [CNTR_WIDTH-1:0]                o_r_ch_pushed_data_cntr,
    output  reg                                 o_r_ch_fifo_write_info_inc,
    output  reg                                 o_r_ch_fifo_write_data_inc,
    input   wire                                i_RREADY_fifo,      /*A transaction is need to be written in the FIFO, hence we shall know if the FIFO is EMPTY*/
    //------ Read Data Channel Slave Interface------//
    input   wire    [RESP_WIDTH-1:0]            i_s_RRESP,
    input   wire                                i_s_RLAST,
    input   wire                                i_s_RVALID,
    output  reg                                 o_s_RREADY
   );
     
    localparam MEMORY = 0;
    localparam IO = 1;
    // Burst Type
    localparam [1:0]    FIXED       = 2'b00, 
                        INCREMENT   = 2'b01,
                        WRAP        = 2'b10;

    localparam  [RESP_WIDTH-1:0]    OKAY = 2'b00,
                                    EXOKAY = 2'b01,
                                    SLVERR = 2'b10,
                                    DECERR  = 2'b11;

    localparam  B_IDLE = 1'b0,               // No Valid Data asserted by slave - FIFOs are full and cannot receive data
                B_RCV_RESP = 1'b1;           // Handshake Pending: FIFOs are ready to accept data, waiting for slave to assert valid

    localparam STATE_REG_WIDTH = 3;

    localparam [STATE_REG_WIDTH-1:0]    R_IDLE = 3'b000,               // No Valid Data asserted by slave - FIFOs are full and cannot receive data
                                        R_HANDSHAKE = 3'b001,          // Performs Handshake - Initially or if it was broken during reception
                                        R_HS_PENDING = 3'b010,
                                        R_DATA_RECEIVE = 3'b011,
                                        R_DISCARD = 3'b100;            // Discard the info being recieved



    reg b_present_state;
    reg b_next_state;
    reg r_error_status;

    reg [STATE_REG_WIDTH-1:0] r_present_state;
    reg [STATE_REG_WIDTH-1:0] r_next_state;
    reg r_cntr_n_clr;
    reg r_cntr_en;
    wire r_handshake_init;

    assign r_handshake_init = i_s_RVALID && i_RREADY_fifo;

    //------------ B Responce Control -----------//
    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            b_present_state <= B_IDLE;
        end    
        else begin  
            b_present_state <= b_next_state;
        end
    end
    always @(*) begin
        o_s_BREADY = 1'b0;
        o_b_ch_fifo_write_inc = 1'b0;
        case (b_present_state)
            B_IDLE: begin
                if (i_BREADY_fifo && i_s_BVALID) begin
                    b_next_state = B_RCV_RESP;
                end
            end
            B_RCV_RESP: begin
                if (i_s_BVALID) begin
                    o_s_BREADY = 1'b1;
                    if (i_write_reqest_type == IO) begin // b response is only for IO write
                        o_b_ch_fifo_write_inc = 1'b1;
                    end
                end
                b_next_state = B_IDLE;
            end
            default: begin
                b_next_state = B_IDLE;
            end
        endcase
    end
    
    //------------ R Responce Control -----------//
    /*
    6-bit contuer to count up to 32 to count the number of pushes done to r-ch fifo. 
    used with last_dw to retrieve payload length or to discard info from r-dada fifo in case of an error.
    */
    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            o_r_ch_pushed_data_cntr <= 0; 
        end    
        else if(~r_cntr_n_clr) begin  
            o_r_ch_pushed_data_cntr <= 0;
        end
        else if (r_cntr_en) begin
            o_r_ch_pushed_data_cntr <= o_r_ch_pushed_data_cntr + 1;
        end
    end

    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            r_present_state <= R_IDLE;
        end    
        else begin  
            r_present_state <= r_next_state;
        end
    end

    always @(*) begin
        o_s_RREADY = 0;
        o_r_ch_fifo_write_info_inc = 0;
        o_r_ch_fifo_write_data_inc = 0;
        r_error_status = 0;
        r_cntr_n_clr = 1;
        r_cntr_en = 0;
        case (r_present_state)
            R_IDLE: begin
                if (i_s_RVALID) begin
                    r_next_state = R_HANDSHAKE;
                    r_cntr_n_clr = 0;
                end
                else begin
                    r_next_state = R_IDLE;
                end
            end
            R_HANDSHAKE: begin
                if (r_handshake_init) begin
                    r_next_state = R_DATA_RECEIVE;
                    o_s_RREADY  = 1'b1;
                    o_r_ch_fifo_write_data_inc = 1'b1;
                    r_cntr_en = 1;
                end
                else begin
                    r_next_state = R_HANDSHAKE;
                end
            end
            R_DATA_RECEIVE: begin
                if (~r_handshake_init) begin
                    r_next_state = R_HANDSHAKE;
                    o_s_RREADY = i_RREADY_fifo;
                end
                else if (i_s_RLAST) begin
                    r_next_state = R_IDLE;
                    if (i_s_RRESP != OKAY) begin
                        r_error_status = 1;
                    end
                    else begin
                        o_r_ch_fifo_write_data_inc = 1'b1;
                        r_cntr_en = 1;
                    end
                    o_r_ch_fifo_write_info_inc = 1'b1;
                    o_s_RREADY = 1;
                end
                else if (i_s_RRESP != OKAY) begin
                    r_next_state = R_DISCARD;
                    r_error_status = 1;
                    o_s_RREADY = 1;
                end
                else begin
                    r_next_state = R_DATA_RECEIVE;
                    o_s_RREADY = 1;
                    o_r_ch_fifo_write_data_inc = 1'b1;
                    r_cntr_en = 1;
                end
            end
            R_DISCARD: begin
                if(~i_s_RLAST) begin
                    r_next_state = R_DISCARD;
                    o_s_RREADY = 1;
                end
                else begin
                    r_next_state = R_IDLE;
                    o_r_ch_fifo_write_info_inc = 1'b1;
                end
                r_error_status = 1;
            end
            default: begin
                r_next_state = R_IDLE;
            end
        endcase
    end

endmodule
