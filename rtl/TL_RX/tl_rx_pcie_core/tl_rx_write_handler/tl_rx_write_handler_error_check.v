/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_write_handler_error_check
   DEPARTMENT :     Wtire Handler
   AUTHOR :         Reem Mohamed - Omar Hafez
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com - eng.omar.amr@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-03-16              initial version
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
module tl_rx_error_check #(
    parameter   PAYLOAD_LENGTH=10,
                HDR_FIELD_SIZE=8,
                DATA_FIELD_SIZE=12,
                FC_HDR_CREDS_WIDTH=8,
                FC_DATA_CREDS_WIDTH=12,
                ADDRESS_WIDTH=64,
                REQUESTER_ID_WIDTH=16,
                REQUESTER_TAG_WIDTH=10,
                HDR_FIELDS_WIDTH= 118,
                BARS_WIDTH = 32,
                SCALE_BUS_WIDTH = 6
) (
    //------ Global Signals ------//
    input wire                          i_clk,
    input wire                          i_n_rst,
    //------- TLP Processing Interface -------//
    input wire                          i_error_check_en,
    input wire  [2:0]                   i_transaction_type,
    input wire  [1:0]                   i_buffer_type,
    input wire                          i_write_n_read,
    input wire                          i_address_type,
    input wire  [2:0]                   i_last_dw,
    input wire                          i_rcv_done,
    input wire  [HDR_FIELDS_WIDTH-1:0]  i_error_check_hdr_fields,
    //------- receiver overflow error check block -------//
    /**RX Flow Control Credits Received Counter**/
    input wire  [3*HDR_FIELD_SIZE-1:0]      i_rx_fc_hdr_credits_received_bus,
    input wire  [3*DATA_FIELD_SIZE-1:0]     i_rx_fc_data_credits_received_bus,
    /**RX Flow Control Credits Allocated Counter **/
    input wire  [3*HDR_FIELD_SIZE-1:0]      i_rx_fc_hdr_credits_allocated_bus,
    input wire  [3*DATA_FIELD_SIZE-1:0]     i_rx_fc_data_credits_allocated_bus,
    //------- flow control error check block -------//
    /**TX Flow Control Interface**/
    input wire  [3*FC_HDR_CREDS_WIDTH-1:0]  i_tx_fc_hdr_credit_limit_bus,
    input wire  [3*FC_DATA_CREDS_WIDTH-1:0] i_tx_fc_data_credit_limit_bus,
    input wire  [SCALE_BUS_WIDTH-1:0]       i_tx_fc_hdr_scale_bus,
    input wire  [SCALE_BUS_WIDTH-1:0]       i_tx_fc_data_scale_bus,
    /**DLL Flow Control Interface**/
    input wire  [DATA_FIELD_SIZE-1:0]       i_dll_rx_fc_data_creds,
    input wire  [HDR_FIELD_SIZE-1:0]        i_dll_rx_fc_hdr_creds,
    input wire  [1:0]                       i_dll_rx_fc_data_scale,
    input wire  [1:0]                       i_dll_rx_fc_hdr_scale,
    input wire                              i_dll_rx_fc_valid,
    input wire  [1:0]                       i_dll_rx_fc_typ,
    /**malformed error check block**/
    input wire                              i_dll_rx_sop,
    input wire [2:0]                        i_dll_rx_last_dw,
    input wire                              i_dll_rx_eop,
    input wire[2:0]                         i_max_payload_config,
    /**ECRC error check block**/
    input wire                              i_ecrc_error_check,
    input wire                              i_ecrc_check_en_config,
    /** UR error check block **/
    input wire                              i_cfg_memory_space_en,
    input wire                              i_cfg_io_space_en,
    input wire [6*BARS_WIDTH-1:0]           i_BARSs,
    /** unexpected completion error check block**/
    input wire [REQUESTER_ID_WIDTH-1:0]     i_device_id,
    input wire [REQUESTER_TAG_WIDTH-1:0]    i_tx_last_req_tag,
    /** ouput **/
    output wire                             o_error_check,
    output reg [2:0]                        o_error_type,
    output wire                             o_dll_rx_tlp_discard // output to datalink layer to discard tlp
);

    reg [2:0] dll_last_dw_reg;

    wire receiver_overflow_error_top;
    wire flow_control_error_top;
    wire malformed_error_top;
    wire ecrc_error_top;
    wire ur_error_top;
    wire uc_error_top;
    wire poisoned_error_top;

    wire [2:0]                            TC;
    wire                                  TD;
    wire                                  EP;
    wire [1:0]                            Attr;
    wire [1:0]                            AT;
    wire [PAYLOAD_LENGTH-1:0]             Length;
    wire [2:0]                            compl_status;
    wire [7:0]                            msg_code;
    wire [REQUESTER_ID_WIDTH-1:0]         rx_req_id;
    wire [REQUESTER_TAG_WIDTH-1:0]        rx_req_tag;
    wire [ADDRESS_WIDTH-1:0]              address;


    /*Info Decoded for error check*/
    assign {TC, TD, EP, Attr, AT, Length, compl_status, msg_code, rx_req_id, rx_req_tag, address} = i_error_check_hdr_fields;

    wire  [1:0]                           p_hdr_scale;
    wire  [1:0]                           np_hdr_scale;
    wire  [1:0]                           cpl_hdr_scale;
    wire  [1:0]                           p_data_scale;
    wire  [1:0]                           np_data_scale;
    wire  [1:0]                           cpl_data_scale;

    // assign {p_hdr_scale, np_hdr_scale, cpl_hdr_scale} = i_rx_fc_hdr_scale_bus;
    // assign {p_data_scale, np_data_scale,cpl_data_scale} = i_rx_fc_data_scale_bus;

    wire  [HDR_FIELD_SIZE-1:0]       p_rcv_hdr;
    wire  [HDR_FIELD_SIZE-1:0]       np_rcv_hdr;
    wire  [HDR_FIELD_SIZE-1:0]       cpl_rcv_hdr;
    wire  [DATA_FIELD_SIZE-1:0]      p_rcv_data;
    wire  [DATA_FIELD_SIZE-1:0]      np_rcv_data;
    wire  [DATA_FIELD_SIZE-1:0]      cpl_rcv_data;

    assign {p_rcv_hdr, np_rcv_hdr, cpl_rcv_hdr} = i_rx_fc_hdr_credits_received_bus;    
    assign {p_rcv_data, np_rcv_data, cpl_rcv_data} = i_rx_fc_data_credits_received_bus;

    wire  [HDR_FIELD_SIZE-1:0]       p_dll_hdr;
    wire  [HDR_FIELD_SIZE-1:0]       np_dll_hdr;
    wire  [HDR_FIELD_SIZE-1:0]       cpl_dll_hdr;
    wire  [DATA_FIELD_SIZE-1:0]      p_dll_data;
    wire  [DATA_FIELD_SIZE-1:0]      np_dll_data;
    wire  [DATA_FIELD_SIZE-1:0]      cpl_dll_data;

    assign {p_dll_hdr, np_dll_hdr, cpl_dll_hdr} = i_rx_fc_hdr_credits_allocated_bus;
    assign {p_dll_data, np_dll_data, cpl_dll_data} = i_rx_fc_data_credits_allocated_bus;

    wire  [FC_HDR_CREDS_WIDTH-1:0]        p_hdr_creds_reg;
    wire  [FC_HDR_CREDS_WIDTH-1:0]        np_hdr_creds_reg;
    wire  [FC_HDR_CREDS_WIDTH-1:0]        cpl_hdr_creds_reg;
    wire  [FC_DATA_CREDS_WIDTH-1:0]       p_data_creds_reg;
    wire  [FC_DATA_CREDS_WIDTH-1:0]       np_data_creds_reg;
    wire  [FC_DATA_CREDS_WIDTH-1:0]       cpl_data_creds_reg;

    assign {p_hdr_creds_reg, np_hdr_creds_reg, cpl_hdr_creds_reg} = i_tx_fc_hdr_credit_limit_bus;
    assign {p_data_creds_reg, np_data_creds_reg, cpl_data_creds_reg} = i_tx_fc_data_credit_limit_bus;
     
    wire  [1:0]                           p_hdr_scale_reg;
    wire  [1:0]                           np_hdr_scale_reg;
    wire  [1:0]                           cpl_hdr_scale_reg;
    wire  [1:0]                           p_data_scale_reg;
    wire  [1:0]                           np_data_scale_reg;
    wire  [1:0]                           cpl_data_scale_reg;

    assign {p_hdr_scale_reg, np_hdr_scale_reg, cpl_hdr_scale_reg} = i_tx_fc_hdr_scale_bus;
    assign {p_data_scale_reg, np_data_scale_reg, cpl_data_scale_reg} = i_tx_fc_data_scale_bus;
    
    wire [BARS_WIDTH-1:0]                           bar0;
    wire [BARS_WIDTH-1:0]                           bar1;
    wire [BARS_WIDTH-1:0]                           bar2;
    wire [BARS_WIDTH-1:0]                           bar3;
    wire [BARS_WIDTH-1:0]                           bar4;
    wire [BARS_WIDTH-1:0]                           bar5;

    assign {bar0, bar1, bar2, bar3, bar4, bar5} = i_BARSs;

    tl_rx_error_check_receiver_overflow_top #(
        .HDR_FIELD_SIZE(HDR_FIELD_SIZE),
        .DATA_FIELD_SIZE(DATA_FIELD_SIZE),
        /*FIXED*/
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH)
    ) u_error_check_receiver_overflow (
        //------- TLP Processing Interface -------//
        .i_receiver_overflow_en(i_error_check_en),
        .i_buffer_typ(i_buffer_type),
        .i_buffer_in(Length),
        //------- RX FC Interface -------//
        /*i_rx_fc_hdr_credits_received_bus*/
        .i_p_rcv_hdr(p_rcv_hdr),
        .i_np_rcv_hdr(np_rcv_hdr),
        .i_cpl_rcv_hdr(cpl_rcv_hdr),
        /*i_rx_fc_data_credits_received_bus*/
        .i_p_rcv_data(p_rcv_data),
        .i_np_rcv_data(np_rcv_data),
        .i_cpl_rcv_data(cpl_rcv_data),
        /*i_rx_fc_hdr_credits_allocated_bus*/
        .i_p_dll_hdr(p_dll_hdr),
        .i_np_dll_hdr(np_dll_hdr),
        .i_cpl_dll_hdr(cpl_dll_hdr),
        /*i_rx_fc_data_credits_allocated_bus*/
        .i_p_dll_data(p_dll_data),
        .i_np_dll_data(np_dll_data),
        .i_cpl_dll_data(cpl_dll_data),
        /*output error signal*/
        .o_receiver_overflow_error(receiver_overflow_error_top)
    );

    tl_rx_error_check_flow_control_top #(
        .FC_DATA_CREDS_WIDTH(FC_DATA_CREDS_WIDTH),
        .FC_HDR_CREDS_WIDTH(FC_HDR_CREDS_WIDTH),
        .DLL_DATA_CREDS_WIDTH(DATA_FIELD_SIZE),
        .DLL_HDR_CREDS_WIDTH(HDR_FIELD_SIZE)
    ) u_error_check_flow_control (
        .flow_control_en(i_error_check_en),
        .p_hdr_creds_reg(p_hdr_creds_reg),
        .np_hdr_creds_reg(np_hdr_creds_reg),
        .cpl_hdr_creds_reg(cpl_hdr_creds_reg),
        .p_data_creds_reg(p_data_creds_reg),
        .np_data_creds_reg(np_data_creds_reg),
        .cpl_data_creds_reg(cpl_data_creds_reg),
        .p_data_scale_reg(p_data_scale_reg),
        .p_hdr_scale_reg(p_hdr_scale_reg),
        .np_data_scale_reg(np_data_scale_reg),
        .np_hdr_scale_reg(np_hdr_scale_reg),
        .cpl_data_scale_reg(cpl_data_scale_reg),
        .cpl_hdr_scale_reg(cpl_hdr_scale_reg),
        .dll_typ(i_dll_rx_fc_typ),
        .dll_valid(i_dll_rx_fc_valid),
        .dll_hdr_creds(i_dll_rx_fc_hdr_creds),
        .dll_data_creds(i_dll_rx_fc_data_creds),
        .dll_hdr_scale(i_dll_rx_fc_hdr_scale),
        .dll_data_scale(i_dll_rx_fc_data_scale),
        .flow_control_error(flow_control_error_top)
    );

    tl_rx_error_check_malformed #(
        .DATA_WIDTH(PAYLOAD_LENGTH)
    ) u_error_check_malformed (
        .last_dw(dll_last_dw_reg),
        .last_rcv_data(i_last_dw),
        .eop(i_dll_rx_eop),
        .i_rcv_done(i_rcv_done),
        .Length(Length),
        .typ(i_transaction_type),
        .Attr(Attr),
        .AT(AT),
        .TC(TC),
        .max_payload_config(i_max_payload_config),
        .malformed_en(i_error_check_en),
        .malformed_error(malformed_error_top)
    );

    tl_rx_error_check_ecrc u_tl_rx_error_check_ecrc(
        .ecrc_en(i_error_check_en),
        .ecrc_error_check(i_ecrc_error_check),
        .TD(TD),
        .ecrc_check_en_config(i_ecrc_check_en_config),
        .ecrc_error(ecrc_error_top)
    );

    tl_rx_error_check_unsupported_req #(
        .ADDRESS_WIDTH(ADDRESS_WIDTH)
    ) u_error_check_unsupported_req (
        .address(address),
        .msg_code(msg_code),
        .EP(EP),
        .ur_en(i_error_check_en),
        .typ(i_transaction_type),
        .read_write(i_write_n_read),
        .address_typ(i_address_type),
        .bar0(bar0),
        .bar1(bar1),
        .bar2(bar2),
        .bar3(bar3),
        .bar4(bar4),
        .bar5(bar5),
        .memory_space_en_config(i_cfg_io_space_en),
        .io_space_en_config(i_cfg_memory_space_en),
        .ur_error(ur_error_top)
    );

    tl_rx_error_check_unexpected_cpl #(
        .REQUESTER_ID_WIDTH(REQUESTER_ID_WIDTH),
        .REQUESTER_TAG_WIDTH(REQUESTER_TAG_WIDTH)
    ) u_error_check_unexpected_cpl (
        .rx_req_id(rx_req_id),
        .tx_req_id(i_device_id),
        .rx_req_tag(rx_req_tag),
        .tx_last_req_tag(i_tx_last_req_tag),
        .typ(i_transaction_type),
        .uc_en(i_error_check_en),
        .clk(i_clk),
        .rst(i_n_rst),
        .uc_error(uc_error_top)
    );

    tl_rx_error_check_poisoned u_error_check_poisoned(
        .EP(EP),
        .poisoned_en(i_error_check_en),
        .poisoned_error(poisoned_error_top)
    );

    wire [6:0] error_sig = {receiver_overflow_error_top, flow_control_error_top, malformed_error_top, ecrc_error_top, ur_error_top, uc_error_top, poisoned_error_top};

    localparam [7:0]    OVERFLOW_ERROR = 7'b1??????,
                        FLOW_CONTROL_ERROR = 7'b01?????,
                        MALFORMED_ERROR = 7'b001????;

    /**Priority Encoder**/
    always @(*) begin
       casez (error_sig)
        7'b1??????: begin
            o_error_type=3'b001;        // Over Flow Error
        end  
        7'b01?????: begin
            o_error_type=3'b010;        // Flow Control Error
        end 
        7'b001????: begin
            o_error_type=3'b011;        // Malformed Error
        end 
        7'b0001???: begin
            o_error_type=3'b100;        // ECRC Error
        end 
        7'b00001??: begin
            o_error_type=3'b101;        // Unsupported Request Error
        end
        7'b000001?: begin
            o_error_type=3'b110;        // Unexpected Completion Error
        end
        7'b0000001: begin
            o_error_type=3'b111;        // Poisoned TLP Error
        end
        default: begin
            o_error_type=3'b000;        // No Error
        end
       endcase 
    end

    always @(posedge i_clk or negedge i_n_rst) begin
        if (~i_n_rst) begin
            dll_last_dw_reg <= 0;
        end
        else if (i_dll_rx_sop) begin
            dll_last_dw_reg <= i_dll_rx_last_dw;
        end
    end

    assign o_error_check = receiver_overflow_error_top || flow_control_error_top || malformed_error_top || ecrc_error_top || ur_error_top || uc_error_top|| poisoned_error_top;
    assign o_dll_rx_tlp_discard = o_error_check && (~i_dll_rx_eop);

endmodule
