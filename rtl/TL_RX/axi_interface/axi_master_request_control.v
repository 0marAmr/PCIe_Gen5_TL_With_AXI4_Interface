/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      axi_master_request_control
   DEPARTMENT :     AXI Master
   AUTHOR :         Omar Hafez
   AUTHOR’S EMAIL : eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-04-06             initial version
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
module axi_master_request_control #(
    parameter   DW = 32,
                ADDR_WIDTH = 64,
                BEAT_SIZE = 32*DW,
                Ax_CHANNEL_WIDTH = 100,
                Ax_SIZE_WIDTH = 3,
                Ax_BURST_WIDTH = 2,
                Ax_PROTECTION_WIDTH = 2,
                AxLEN_FIELD_WIDTH = 8,
                QOS_WIDTH = 4,
                ID_WIDTH = 10,
                STROBE_BUS_WIDTH = 128,
                W_CHANNEL_WIDTH = BEAT_SIZE + 128,
                USER_SIG_WIDTH = 12,
                VALID_DATA_WIDTH = 5
) (
    //------- Global Signals -------//
    input   wire                                i_clk,
    input   wire                                i_n_rst,
    //------ AW Channel FIFO Interface------//
    input   wire    [Ax_CHANNEL_WIDTH-1:0]      i_AW_CHANNEL_fifo,
    input   wire                                i_AWVALID_fifo, /*A transaction is written in the FIFO and yet to be read (i.e. info on FIFO output read bus is valid)*/
    output  reg                                 o_aw_fifo_read_inc,
    //------ Write Address Channel Slave Interface------//
    output  wire    [ID_WIDTH-1:0]              o_s_AWID,           /*Transaction Identifier: one-to-one mapping with PCIe tag field, 10-bit wide to suffort extended tag feature*/
    output  wire    [ADDR_WIDTH-1:0]            o_s_AWADDR,         /**/
    output  wire    [AxLEN_FIELD_WIDTH-1:0]     o_s_AWLEN,          /*The number of data transfers in a burst associated with the address of the write request transaction.*/
    output  wire    [Ax_SIZE_WIDTH-1:0]         o_s_AWSIZE,         /*Maximum number of bytes in each data transfer of the write request transaction (3'b000 -> 1 Byte 3'b111 -> 128 Byte)*/
    output  wire    [Ax_BURST_WIDTH-1:0]        o_s_AWBURST,        /*Burst type: FIXED - INCREMENTAL - WRAP*/
    output  wire    [Ax_PROTECTION_WIDTH-1:0]   o_s_AWPROT,
    output  wire    [QOS_WIDTH-1:0]             o_s_AWQOS,
    output  wire    [USER_SIG_WIDTH-1:0]        o_s_AWUSER,         /*req_type, requester_id*/
    output  reg                                 o_s_AWVALID,
    input   wire                                i_s_AWREADY,
    //------ W Channel FIFO Interface------//
    input   wire                                i_WVALID_fifo,      /*A transaction is written in the FIFO and yet to be read (i.e. info on FIFO output read bus is valid)*/
    output  reg                                 o_w_fifo_read_inc,
    //------ Write Data Channel Slave Interface------//
    output  wire    [BEAT_SIZE-1:0]             o_WDATA,
    output  wire    [STROBE_BUS_WIDTH-1:0]      o_s_WSTRB,
    output  reg                                 o_s_WLAST,
    output  reg                                 o_s_WVALID,
    input   wire                                i_s_WREADY,
    //------ AR Channel FIFO Interface------//
    input   wire    [Ax_CHANNEL_WIDTH-1:0]      i_AR_CHANNEL_fifo,
    input   wire                                i_ARVALID_fifo,     /*A transaction is written in the FIFO and yet to be read (i.e. info on FIFO output read bus is valid)*/
    output  reg                                 o_ar_fifo_read_inc,
    //------ Read Address Channel Slave Interface------//
    output  wire    [ID_WIDTH-1:0]              o_s_ARID,
    output  wire    [ADDR_WIDTH-1:0]            o_s_ARADDR,
    output  wire    [AxLEN_FIELD_WIDTH-1:0]     o_s_ARLEN,       /*The number of data transfers in a burst associated with the address of the read responce transaction.*/
    output  wire    [Ax_SIZE_WIDTH-1:0]         o_s_ARSIZE,     /*Maximum number of bytes in each data transfer of the read responce transaction (3'b000 -> 1 Byte 3'b111 -> 128 Byte)*/
    output  wire    [Ax_BURST_WIDTH-1:0]        o_s_ARBURST,    
    output  wire    [Ax_PROTECTION_WIDTH-1:0]   o_s_ARPROT,
    output  wire    [QOS_WIDTH-1:0]             o_s_ARQOS,
    output  wire    [USER_SIG_WIDTH-1:0]        o_s_ARUSER,
    output  reg                                 o_s_ARVALID,
    input   wire                                i_s_ARREADY
);

    localparam STATE_REG_WIDTH = 2;
    
    // AW Request FSM States
    localparam [STATE_REG_WIDTH-1:0]        W_IDLE = 2'b00,                 // No FIFO data valid (FIFOs are empty as no write requests are demanded).
                                            W_INIT_HS_CHECK = 2'b01,        // Initial Handshake Check: Address or data Handshake check.
                                            W_PENDING_HS = 2'b10,           // Write Handshake Pending: when slave WREADY was deasserted during transaction.
                                            W_DATA_TRANSFER = 2'b11;        // Adress handshake was established and data handshake is maintained: data is transfered.
    
    localparam  R_IDLE = 1'b0,                 // No FIFO data valid (FIFOs are empty as no read requests are demanded).
                R_HS_PENDING = 1'b1;           // Handshake Pending: data is valid, waiting for slave to assert ready signal

    // Burst Type
    localparam [1:0]    FIXED       = 2'b00, 
                        INCREMENT   = 2'b01,
                        WRAP        = 2'b10;
    assign {
        o_s_AWID, 
        o_s_AWADDR, 
        o_s_AWLEN, 
        o_s_AWBURST, 
        o_s_AWQOS, 
        o_s_AWUSER
            } = i_AW_CHANNEL_fifo;


    reg [STATE_REG_WIDTH-1:0] w_present_state;
    reg [STATE_REG_WIDTH-1:0] w_next_state;
    reg [AxLEN_FIELD_WIDTH:0] aw_burst_length_counter;
    reg counter_ld;
    reg counter_en;

    wire write_transaction_empty = ~(i_AWVALID_fifo || i_WVALID_fifo);
    wire aw_handshake =  o_s_AWVALID && i_s_AWREADY;
    wire w_handshake =  o_s_WVALID && i_s_WREADY;
    wire w_send_done;

    reg r_present_state;
    reg r_next_state;
    wire read_transaction_empty = ~i_ARVALID_fifo;
    wire ar_handshake =  o_s_ARVALID && i_s_ARREADY;

    assign w_send_done = ~|aw_burst_length_counter;
//------------ AW Request Control -----------//
/*
    Expected Master Behaviour at Request (AWVALID, WVALID):
        - Write data can appear at an interface before or in the same cycle as the write address for the transaction.
        - It follows that WVALID can be asserted before or in the same cycle or after AWVALID. Hence, no dependency whatsoever between AWVALID and WVALID.
    Expected Slave Behaviour at Request (AWREADY, WREADY): 
        - Slave can assert AWREADY before both AWVALID and WVALID are asserted
        - Slave can assert WREADY before both AWVALID and WVALID are asserted
    Slave Responce Dependency:
        - Slave must wait for WLAST to be asserted before asserting BVALID.
        - Slave must wait for WVALID, and WREADY to be asserted before asserting BVALID.
        - Slave must wait for AWVALID, AWREADYto be asserted before asserting BVALID. (Dependency introduced in AXI4)
        - Hence, the FSM designed gurantees that WLAST won't be sent except when 

    Design Approach:
        - Even if W Handshake occoured first, the adress is yet to be provided (and V.V), so as a starting point let wait for AW handshake first.
*/
    always @(posedge i_clk or negedge i_n_rst) begin
        if (~i_n_rst) begin
            aw_burst_length_counter <= 0;
        end
        else if(counter_en) begin
            aw_burst_length_counter = aw_burst_length_counter - 1'b1;
        end
        else if (counter_ld) begin
            aw_burst_length_counter <= o_s_AWLEN + 1'b1;
        end
    end

    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            w_present_state <= W_IDLE;
        end    
        else begin
            w_present_state <= w_next_state;
        end
    end

    always @(*) begin
        o_s_AWVALID = 0;
        o_s_WVALID = 0;
        counter_ld = 0;
        counter_en = 0;
        o_w_fifo_read_inc = 0;
        o_aw_fifo_read_inc = 0;
        case (w_present_state)
            W_IDLE: begin
                // Next State Logic
                if (~write_transaction_empty) begin
                    w_next_state = W_INIT_HS_CHECK;
                    counter_ld = 1;
                    o_s_AWVALID = i_AWVALID_fifo;
                    o_s_WVALID  = i_WVALID_fifo;
                end
                else begin
                    w_next_state = W_IDLE;
                end
            end
            W_INIT_HS_CHECK: begin
                // Next State Logic
                if (~aw_handshake) begin
                    w_next_state = W_INIT_HS_CHECK;
                end 
                else if (w_handshake) begin
                    w_next_state = W_DATA_TRANSFER;
                    o_w_fifo_read_inc = 1;
                    counter_en = 1;
                end 
                else begin
                    w_next_state = W_PENDING_HS;
                end
                // Output Logic
                o_s_AWVALID = i_AWVALID_fifo;
                o_s_WVALID  = i_WVALID_fifo;
            end
            W_PENDING_HS: begin
            // Next State Logic
            if (~w_handshake) begin
                w_next_state = W_PENDING_HS;
            end
            else begin
                w_next_state = W_DATA_TRANSFER;
                o_w_fifo_read_inc = 1;
                counter_en = 1;
            end
            // Output Logic
            o_s_WVALID  = i_WVALID_fifo;
            end
            W_DATA_TRANSFER: begin
                if (~w_handshake) begin
                    w_next_state = W_PENDING_HS;
                end
                else if (~w_send_done) begin
                    w_next_state = W_IDLE;
                    // Output Logic
                    o_w_fifo_read_inc = 1;
                    o_aw_fifo_read_inc = 1;
                    o_s_WLAST = 1'b1;
                end
                else begin
                    w_next_state = W_DATA_TRANSFER;
                    o_w_fifo_read_inc = 1;
                    counter_en = 1;
                end
                // Output Logic
                o_s_WVALID  = i_WVALID_fifo;
            end
            default: begin
                w_next_state = 0;
            end
        endcase
    end

    //------------ AR Request Control -----------//
    always @(posedge i_clk or negedge i_n_rst) begin
        if(~i_n_rst) begin
            r_present_state <= R_IDLE;
        end    
        else begin
            r_present_state <= r_next_state;
        end
    end

    always @(*) begin
        o_ar_fifo_read_inc = 0;
        o_s_ARVALID = 0;
        case (r_present_state)
            R_IDLE: begin
                if (read_transaction_empty) begin
                    r_next_state = R_IDLE;
                end
                else begin
                    r_next_state = R_HS_PENDING;
                    o_s_ARVALID = 1;
                end
            end
            R_HS_PENDING: begin
                if (ar_handshake) begin
                    r_next_state = R_IDLE;
                    o_ar_fifo_read_inc = 1;
                end
                else begin
                    r_next_state = R_HS_PENDING;
                end
                o_s_ARVALID = 1;
            end
            default: begin
                r_next_state = 0;
            end
        endcase
    end

endmodule
