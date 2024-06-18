/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_fc
   DEPARTMENT :     tl_rx_fc
   AUTHOR :         Reem Mohamed
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-04-15              initial version
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
module tl_rx_fc #(
    parameter   PAYLOAD_LENGTH = 10,
                HDR_FIELD_SIZE=8,
                DATA_FIELD_SIZE=12,
                SCALE_BUS_WIDTH = 6,
                HDR_FIFO_DEPTH = 2**7,
                P_DATA_FIFO_DEPTH = 2**10,
                NP_DATA_FIFO_DEPTH = 2**7,
                CPL_DATA_FIFO_DEPTH = 2**10
) (
    //------ Global Signals ------//
    input wire                              i_clk,
    input wire                              i_n_rst,
    //------ Write Handler Interface ------//
    input wire [1:0]                        i_write_buffer_type,   // buffer selected by TLP Write Handler (P - NP - CPL)
    input wire                              i_cr_hdr_inc,
    input wire                              i_cr_data_inc,
    input wire [PAYLOAD_LENGTH-1:0]         i_buffer_in_dw,    // payload lendth of the data written into the VC buffer in DW
    /* overflow_error */
    // output wire [SCALE_BUS_WIDTH-1:0]       o_rx_fc_hdr_scale_bus,
    // output wire [SCALE_BUS_WIDTH-1:0]       o_rx_fc_data_scale_bus,
    output wire [3*HDR_FIELD_SIZE-1:0]      o_rx_fc_hdr_credits_allocated_bus,
    output wire [3*DATA_FIELD_SIZE-1:0]     o_rx_fc_data_credits_allocated_bus,
    output wire [3*HDR_FIELD_SIZE-1:0]      o_rx_fc_hdr_credits_received_bus,
    output wire [3*DATA_FIELD_SIZE-1:0]     o_rx_fc_data_credits_received_bus,
    //------ Read Handler Interface ------//
    input wire                              i_req_read_buffer_type,   // 0 posted request and 1 non posted request
    input wire                              i_req_ca_hdr_inc,
    input wire                              i_req_ca_data_inc,
    input wire                              i_cpl_ca_hdr_inc,
    input wire                              i_cpl_ca_data_inc,
    //------ Virtual Channels Interface ----//
    input wire [PAYLOAD_LENGTH-1:0]         i_req_buffer_out_dw,   // payload lendth of the data read from the VC buffer in DW
    input wire [PAYLOAD_LENGTH-1:0]         i_cpl_buffer_out_dw,   // payload lendth of the data read from the VC buffer in DW
    //------ Config Space Interface ------//
    input wire [2:0]                        i_cfg_max_payload,
    //------ DLL Interface ------//
    input wire                              i_dll_ctrl_fc_init,
    output reg [HDR_FIELD_SIZE-1:0]         o_dll_tx_fc_hdr_creds,
    output reg [DATA_FIELD_SIZE-1:0]        o_dll_tx_fc_data_creds,
    output reg [1:0]                        o_dll_tx_fc_hdr_scale,
    output reg [1:0]                        o_dll_tx_fc_data_scale,
    output reg [1:0]                        o_dll_tx_fc_fc_type,
    output reg                              o_dll_tx_fc_fc_creds_valid
);

    localparam [1:0]    POSTED = 2'b00,
                        NON_POSTED = 2'b01,
                        COMPLETION = 2'b10;
    
    localparam  PAYLOAD_IN_CREDS = 9;

    wire p_update;
    wire np_update;
    wire cpl_update;

    wire [1:0]  p_hdr_scale;
    wire [1:0]  np_hdr_scale;
    wire [1:0]  cpl_hdr_scale;
    wire [1:0]  p_data_scale;
    wire [1:0]  np_data_scale;
    wire [1:0]  cpl_data_scale;

    wire [HDR_FIELD_SIZE-1:0]    p_creds_alloc_hdr;
    wire [HDR_FIELD_SIZE-1:0]    np_creds_alloc_hdr;
    wire [HDR_FIELD_SIZE-1:0]    cpl_creds_alloc_hdr;
    wire [DATA_FIELD_SIZE-1:0]   p_creds_alloc_data;
    wire [DATA_FIELD_SIZE-1:0]   np_creds_alloc_data;
    wire [DATA_FIELD_SIZE-1:0]   cpl_creds_alloc_data;

    wire [HDR_FIELD_SIZE-1:0]    p_creds_rcv_hdr;
    wire [HDR_FIELD_SIZE-1:0]    np_creds_rcv_hdr;
    wire [HDR_FIELD_SIZE-1:0]    cpl_creds_rcv_hdr;
    wire [DATA_FIELD_SIZE-1:0]   p_creds_rcv_data;
    wire [DATA_FIELD_SIZE-1:0]   np_creds_rcv_data;
    wire [DATA_FIELD_SIZE-1:0]   cpl_creds_rcv_data;

    reg p_cr_hdr_inc;
    reg p_cr_data_inc;
    reg np_cr_hdr_inc;
    reg np_cr_data_inc;
    reg cpl_cr_hdr_inc;
    reg cpl_cr_data_inc;
    reg p_ca_data_inc;
    reg p_ca_hdr_inc;
    reg np_ca_data_inc;
    reg np_ca_hdr_inc;

    // assign o_rx_fc_hdr_scale_bus = {p_hdr_scale, np_hdr_scale, cpl_hdr_scale};
    // assign o_rx_fc_data_scale_bus = {p_data_scale, np_data_scale, cpl_data_scale};

    assign o_rx_fc_hdr_credits_allocated_bus = {p_creds_alloc_hdr, np_creds_alloc_hdr, cpl_creds_alloc_hdr};
    assign o_rx_fc_data_credits_allocated_bus = {p_creds_alloc_data, np_creds_alloc_data, cpl_creds_alloc_data};

    assign o_rx_fc_hdr_credits_received_bus = {p_creds_rcv_hdr, np_creds_rcv_hdr, cpl_creds_rcv_hdr};
    assign o_rx_fc_data_credits_received_bus = {p_creds_rcv_data, np_creds_rcv_data, cpl_creds_rcv_data};

    tl_rx_fc_counters #(
        .HDR_FIELD_SIZE(HDR_FIELD_SIZE),
        .DATA_FIELD_SIZE(DATA_FIELD_SIZE),
        .HDR_FIFO_DEPTH(HDR_FIFO_DEPTH),
        .DATA_FIFO_DEPTH(P_DATA_FIFO_DEPTH),
        /*FIXED*/
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH),
        .PAYLOAD_IN_CREDS(PAYLOAD_IN_CREDS)
    ) u_p (
        .clk(i_clk),
        .rst(i_n_rst),
        .dll_init(i_dll_ctrl_fc_init),
        .cr_hdr_inc(p_cr_hdr_inc),
        .cr_data_inc(p_cr_data_inc),
        .ca_hdr_inc(p_ca_hdr_inc),
        .ca_data_inc(p_ca_data_inc),
        .buffer_in_dw(i_buffer_in_dw),
        .buffer_out_dw(i_req_buffer_out_dw),
        .typ(2'b00),
        .max_payload(i_cfg_max_payload),
        .creds_alloc_data(p_creds_alloc_data),
        .creds_alloc_hdr(p_creds_alloc_hdr),
        .creds_rcv_data(p_creds_rcv_data),
        .creds_rcv_hdr(p_creds_rcv_hdr),
        .dll_data_scale(p_data_scale),
        .dll_hdr_scale(p_hdr_scale),
        .update(p_update)
    );

    tl_rx_fc_counters #(
        .HDR_FIELD_SIZE(HDR_FIELD_SIZE),
        .DATA_FIELD_SIZE(DATA_FIELD_SIZE),
        /*FIXED*/
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH),
        .PAYLOAD_IN_CREDS(PAYLOAD_IN_CREDS)
    ) u_np (
        .clk(i_clk),
        .rst(i_n_rst),
        .dll_init(i_dll_ctrl_fc_init),
        .cr_hdr_inc(np_cr_hdr_inc),
        .cr_data_inc(np_cr_data_inc),
        .ca_hdr_inc(np_ca_hdr_inc),
        .ca_data_inc(np_ca_data_inc),
        .buffer_in_dw(i_buffer_in_dw),
        .buffer_out_dw(i_req_buffer_out_dw),
        .typ(2'b01),
        .max_payload(i_cfg_max_payload),
        .creds_alloc_data(np_creds_alloc_data),
        .creds_alloc_hdr(np_creds_alloc_hdr),
        .creds_rcv_data(np_creds_rcv_data),
        .creds_rcv_hdr(np_creds_rcv_hdr),
        .dll_data_scale(np_data_scale),
        .dll_hdr_scale(np_hdr_scale),
        .update(np_update)
    );

    tl_rx_fc_counters #(
        .HDR_FIELD_SIZE(HDR_FIELD_SIZE),
        .DATA_FIELD_SIZE(DATA_FIELD_SIZE),
        /*FIXED*/
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH),
        .PAYLOAD_IN_CREDS(PAYLOAD_IN_CREDS)
    ) u_cpl (
        .clk(i_clk),
        .rst(i_n_rst),
        .dll_init(i_dll_ctrl_fc_init),
        .cr_hdr_inc(cpl_cr_hdr_inc),
        .cr_data_inc(cpl_cr_data_inc),
        .ca_hdr_inc(i_cpl_ca_hdr_inc),
        .ca_data_inc(i_cpl_ca_data_inc),
        .buffer_in_dw(i_buffer_in_dw),
        .buffer_out_dw(i_cpl_buffer_out_dw),
        .typ(2'b10),
        .max_payload(i_cfg_max_payload),
        .creds_alloc_data(cpl_creds_alloc_data),
        .creds_alloc_hdr(cpl_creds_alloc_hdr),
        .creds_rcv_data(cpl_creds_rcv_data),
        .creds_rcv_hdr(cpl_creds_rcv_hdr),
        .dll_data_scale(cpl_data_scale),
        .dll_hdr_scale(cpl_hdr_scale),
        .update(cpl_update)
    );

    reg [2:0] current_state;
    reg [2:0] next_state;
    
    localparam idle =3'b000,
            p_init =3'b001,
            np_init =3'b010,
            cpl_init =3'b011,
            p_upd =3'b100,
            np_upd =3'b101,
            cpl_upd =3'b110;

    always @(posedge i_clk or negedge i_n_rst) begin
        if (!i_n_rst) begin
            current_state<=idle;
        end
        else
        current_state<=next_state;
    end

    always @(*) begin
        o_dll_tx_fc_data_creds=0;
        o_dll_tx_fc_hdr_creds=0;
        o_dll_tx_fc_data_scale=0;
        o_dll_tx_fc_hdr_scale=0;
        o_dll_tx_fc_fc_type=0;
        o_dll_tx_fc_fc_creds_valid=0;
        case (current_state)
            idle: 
            begin
                if (i_dll_ctrl_fc_init==1) begin
                    next_state=p_init;
                end
                else if (p_update==1) begin
                    next_state=p_upd;
                end
                else if (np_update==1) begin
                    next_state=np_upd;
                end
                else if (cpl_update==1) begin
                    next_state=cpl_upd;
                end
                else 
                next_state=idle;
            end 
            p_init: 
            begin
                next_state=np_init;
                //output
                o_dll_tx_fc_data_creds=p_creds_alloc_data;
                o_dll_tx_fc_hdr_creds=p_creds_alloc_hdr;
                o_dll_tx_fc_data_scale=p_data_scale;
                o_dll_tx_fc_hdr_scale=p_hdr_scale;
                o_dll_tx_fc_fc_type=2'b00;
                o_dll_tx_fc_fc_creds_valid=1;
            end
            np_init: 
            begin
                next_state=cpl_init;
                //output
                o_dll_tx_fc_data_creds=np_creds_alloc_data;
                o_dll_tx_fc_hdr_creds=np_creds_alloc_hdr;
                o_dll_tx_fc_data_scale=np_data_scale;
                o_dll_tx_fc_hdr_scale=np_hdr_scale;
                o_dll_tx_fc_fc_type=2'b01;
                o_dll_tx_fc_fc_creds_valid=1;
            end
            cpl_init: 
            begin
                if (i_dll_ctrl_fc_init==1) begin
                    next_state=p_init;
                end
                else if (p_update==1) begin
                    next_state=p_upd;
                end
                else if (np_update==1) begin
                    next_state=np_upd;
                end
                else if (cpl_update==1) begin
                    next_state=cpl_upd;
                end
                else
                next_state=idle;
                //output 
                o_dll_tx_fc_data_creds=cpl_creds_alloc_data;
                o_dll_tx_fc_hdr_creds=cpl_creds_alloc_hdr;
                o_dll_tx_fc_data_scale=cpl_data_scale;
                o_dll_tx_fc_hdr_scale=cpl_hdr_scale;
                o_dll_tx_fc_fc_type=2'b10;
                o_dll_tx_fc_fc_creds_valid=1;
            end
            p_upd:
            begin
                if (i_dll_ctrl_fc_init==1) begin
                    next_state=p_init;
                end
                else if (p_update==1) begin
                    next_state=p_upd;
                end
                else if (np_update==1) begin
                    next_state=np_upd;
                end
                else if (cpl_update==1) begin
                    next_state=cpl_upd;
                end
                else
                next_state=idle;
                //output
                o_dll_tx_fc_data_creds=p_creds_alloc_data;
                o_dll_tx_fc_hdr_creds=p_creds_alloc_hdr;
                o_dll_tx_fc_data_scale=p_data_scale;
                o_dll_tx_fc_hdr_scale=p_hdr_scale;
                o_dll_tx_fc_fc_type=2'b00;
                o_dll_tx_fc_fc_creds_valid=1; 
            end
            np_upd:
            begin
                if (i_dll_ctrl_fc_init==1) begin
                    next_state=p_init;
                end
                else if (p_update==1) begin
                    next_state=p_upd;
                end
                else if (np_update==1) begin
                    next_state=np_upd;
                end
                else if (cpl_update==1) begin
                    next_state=cpl_upd;
                end
                else
                next_state=idle;
                //output
                o_dll_tx_fc_data_creds=np_creds_alloc_data;
                o_dll_tx_fc_hdr_creds=np_creds_alloc_hdr;
                o_dll_tx_fc_data_scale=np_data_scale;
                o_dll_tx_fc_hdr_scale=np_hdr_scale;
                o_dll_tx_fc_fc_type=2'b01;
                o_dll_tx_fc_fc_creds_valid=1; 
            end
            cpl_upd:
            begin
                if (i_dll_ctrl_fc_init==1) begin
                    next_state=p_init;
                end
                else if (p_update==1) begin
                    next_state=p_upd;
                end
                else if (np_update==1) begin
                    next_state=np_upd;
                end
                else if (cpl_update==1) begin
                    next_state=cpl_upd;
                end
                else
                next_state=idle;
                //output
                o_dll_tx_fc_data_creds=cpl_creds_alloc_data;
                o_dll_tx_fc_hdr_creds=cpl_creds_alloc_hdr;
                o_dll_tx_fc_data_scale=cpl_data_scale;
                o_dll_tx_fc_hdr_scale=cpl_hdr_scale;
                o_dll_tx_fc_fc_type=2'b10;
                o_dll_tx_fc_fc_creds_valid=1; 
            end
            default: next_state=idle; 
        endcase
    end

    always @(*) begin
        case (i_write_buffer_type)
            2'b00:
            begin
                p_cr_hdr_inc=i_cr_hdr_inc;
                p_cr_data_inc=i_cr_data_inc;
                np_cr_hdr_inc=0;
                np_cr_data_inc=0;
                cpl_cr_hdr_inc=0;
                cpl_cr_data_inc=0;

            end
            2'b01:
            begin
                np_cr_hdr_inc=i_cr_hdr_inc;
                np_cr_data_inc=i_cr_data_inc;
                p_cr_hdr_inc=0;
                p_cr_data_inc=0;
                cpl_cr_hdr_inc=0;
                cpl_cr_data_inc=0;
            end
            2'b10:
            begin
                cpl_cr_hdr_inc=i_cr_hdr_inc;
                cpl_cr_data_inc=i_cr_data_inc;
                np_cr_hdr_inc=0;
                np_cr_data_inc=0;
                p_cr_hdr_inc=0;
                p_cr_data_inc=0;
            end 
            default:
            begin
                p_cr_hdr_inc=0;
                p_cr_data_inc=0;
                np_cr_hdr_inc=0;
                np_cr_data_inc=0;
                cpl_cr_hdr_inc=0;
                cpl_cr_data_inc=0;
            end 
        endcase

        if (i_req_read_buffer_type==0) begin
            p_ca_hdr_inc=i_req_ca_hdr_inc;
            p_ca_data_inc=i_req_ca_data_inc;
            np_ca_data_inc=0;
            np_ca_hdr_inc=0;
        end
        else
        begin
            np_ca_data_inc=i_req_ca_data_inc;
            np_ca_hdr_inc=i_req_ca_hdr_inc;
            p_ca_hdr_inc=0;
            p_ca_data_inc=0;
        end
    end

endmodule