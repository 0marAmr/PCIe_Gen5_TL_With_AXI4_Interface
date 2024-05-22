/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      VC_BUFFER_CONTROL
   DEPARTMENT :     VC
   AUTHOR :         Reem Mohamed - Omar Hafez
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com - eng.omar.amr@gmail.com
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
module tl_rx_pcie_core #(
   parameter   DW = 32,
               RCV_BUS_WIDTH  = 8*DW,
               BEAT_SIZE = 32*DW,
               REQ_HDR_SIZE = 4*DW,
               CPL_HDR_SIZE = 3*DW,
               BARS_WIDTH = 32,
               REQUESTER_ID_WIDTH = 16,
               TAG_WIDTH = 10,
               TC_WIDTH = 3,
               PAYLOAD_LENGTH = 10,
               BYTE_ENABLES_WIDTH = 4,
               ADDR_WIDTH = 64,
               BYTE_COUNT_WIDTH = 4,
               VALID_DATA_WIDTH = 5,
               LOWER_ADDR_FIELD = 7,
               P_DATA_IP_WIDTH = 8*DW,
               NP_DATA_IP_WIDTH = 1*DW,
               CPL_DATA_IP_WIDTH = 8*DW,
               TYPE_DEC_WIDTH = 2,
               /** Flow Control **/
               HDR_FIELD_SIZE = 8,
               DATA_FIELD_SIZE = 12,
               RX_MAX_HDR_BUFFER_SIZE_WIDTH = 8,
               RX_MAX_DATA_BUFFER_SIZE_WIDTH = 12,
               SCALE_BUS_WIDTH = 6,
               /**Virtual Channel**/
               HDR_FIFO_DEPTH = 2**(HDR_FIELD_SIZE-1),
               P_DATA_FIFO_DEPTH = 2**(DATA_FIELD_SIZE-2),
               NP_DATA_FIFO_DEPTH = 2**(HDR_FIELD_SIZE-1),
               CPL_DATA_FIFO_DEPTH = 2**(DATA_FIELD_SIZE-2),
               W_CTRL_BUS_WIDTH = 6,
               R_CTRL_BUS_WIDTH = 6,
               FLAGS_WIDTH = 6
) (
	//------ Global Signals ------//
	input	wire                             i_clk,
	input	wire                             i_n_rst,
	//------ Config Space Interface ------//
	input	wire                             i_cfg_ecrc_chk_en,
	input	wire                             i_cfg_memory_space_en,
	input	wire                             i_cfg_io_space_en,
	input	wire    [2:0]                    i_cfg_max_payload_size,
	input	wire    [6*BARS_WIDTH-1:0]       i_cfg_BARs,
	//------ Master Bridge Interface - Request Control ------//
	output  wire                             o_req_valid,            // indication for the beginning of transaction, asserted till
    output  wire                             o_req_inc,    
    output  wire                             o_req_data_write_inc,    
    output  wire                             o_req_last,                 // indicates that the current beat is the last one in a transaction 
    output  wire    [VALID_DATA_WIDTH-1:0]   o_req_valid_data,           // encoding for valid Double Words of data driven on the bus (5'b00000 -> 1 DW valid, 5'b11111 32 DW valid) 
    input   wire                             i_AWREADY_fifo,
    input   wire                             i_WREADY_fifo,
    input   wire							 i_ARREADY_fifo,
	//------ Master Bridge Interface - Request Info | Data ------//
    output  wire   	[REQUESTER_ID_WIDTH-1:0] o_requester_id,
	output  wire   	[1:0]                    o_req_type,   /*Memory Read - Memory Write - IO Read - IO Write*/
    output  wire                             o_req_address_type,
    output  wire   	[TAG_WIDTH-1:0]          o_req_tag,
    output  wire   	[TC_WIDTH-1:0]           o_req_TC,
    output  wire   	[PAYLOAD_LENGTH-1:0]	 o_req_length,
    output  wire   	[BYTE_ENABLES_WIDTH-1:0] o_req_first_byte_enable,
    output  wire   	[BYTE_ENABLES_WIDTH-1:0] o_req_last_byte_enable,
    output  wire   	[ADDR_WIDTH-1:0]         o_req_address,
    output  wire   	[BEAT_SIZE-1:0]          o_req_data,
	//------ Master Bridge Interface - Completion Control ------//
    output wire                             o_cpl_info_inc,
    output wire                             o_cpl_data_inc,
    input  wire                             i_cpl_valid,
    //------ Master Bridge Interface  - Completion Info | Data ------//
    input  wire  [REQUESTER_ID_WIDTH-1:0]   i_cpl_requester_id,
    input  wire                             i_cpl_type,
    input  wire  [TAG_WIDTH-1:0]            i_cpl_tag,
    input  wire  [TC_WIDTH-1:0]             i_cpl_traffic_class,
    input  wire  [PAYLOAD_LENGTH-1:0]      	i_cpl_length,
    input  wire  [LOWER_ADDR_FIELD-1:0]     i_cpl_lower_address,
    input  wire                             i_cpl_error_flag,
    input  wire  [BYTE_COUNT_WIDTH-1:0]     i_cpl_initial_byte_count,
    input  wire  [BEAT_SIZE-1:0]			i_cpl_data,
	//------ TL_TX Interface ------//
	input	wire	[TAG_WIDTH-1:0]			i_tx_last_req_tag,
	input	wire    [3*HDR_FIELD_SIZE-1:0]  i_tx_fc_hdr_credit_limit_bus,
	input	wire    [3*DATA_FIELD_SIZE-1:0] i_tx_fc_data_credit_limit_bus,
	input	wire    [SCALE_BUS_WIDTH-1:0]   i_tx_fc_hdr_scale_bus,
	input	wire    [SCALE_BUS_WIDTH-1:0]   i_tx_fc_data_scale_bus,
	//------- DLL-RX TLP Interface -------//
	input	wire                            i_dll_rx_sop,
	input	wire    [RCV_BUS_WIDTH-1:0]     i_dll_rx_tlp,
	input	wire                            i_dll_rx_eop,
	input	wire    [2:0]                   i_dll_rx_last_dw,
	output	wire                            o_dll_rx_tlp_discard,
	//------ DLL-RX Flow Control Interface ------//
	input	wire    [1:0]                   i_dll_rx_fc_typ,
	input	wire    [HDR_FIELD_SIZE-1:0]    i_dll_rx_fc_hdr_creds,
	input	wire    [DATA_FIELD_SIZE-1:0]   i_dll_rx_fc_data_creds,
	input	wire    [1:0]                   i_dll_rx_fc_hdr_scale,
	input	wire    [1:0]                   i_dll_rx_fc_data_scale,
	input	wire                            i_dll_rx_fc_valid,
	//------ DLL-TX Flow Control Interface ------//
	input	wire                            i_dll_ctrl_fc_init,
	output	wire 	[HDR_FIELD_SIZE-1:0]    o_dll_tx_fc_hdr_creds,
	output	wire 	[DATA_FIELD_SIZE-1:0]   o_dll_tx_fc_data_creds,
	output	wire 	[1:0]                   o_dll_tx_fc_hdr_scale,
	output	wire 	[1:0]                   o_dll_tx_fc_data_scale,
	output	wire 	[1:0]                   o_dll_tx_fc_fc_type,
	output	wire							o_dll_tx_fc_fc_creds_valid,
	//------- AXI Slave (TX) Interface -------//
	input  wire                            	i_slave_ready,
	output wire    [BEAT_SIZE-1:0]         	o_vc_cpl_data,
	output wire    [CPL_HDR_SIZE-1:0]      	o_vc_cpl_hdr,
	output wire                            	o_slave_cpl_vaild,
	output wire    [4:0]                   	o_slave_cpl_valid_data

);
     
    localparam N_VCS = 1;

    //------- VC0 Interface ------//
    wire	[FLAGS_WIDTH-1:0]             vc0_w_full_flags;
    wire	[FLAGS_WIDTH-1:0]             vc0_r_empty_flags;
    wire	[N_VCS*FLAGS_WIDTH-1:0]       vcs_w_full_flags = vc0_w_full_flags; // add more VCs
    /*POSTED*/         
    wire	[W_CTRL_BUS_WIDTH-1:0]        vc0_w_posted_ctrl;
    wire	[REQ_HDR_SIZE-1:0]            vc0_w_posted_hdr;
    wire	[P_DATA_IP_WIDTH-1:0]         vc0_w_posted_data;
    // wire     [R_CTRL_BUS_WIDTH-1:0] vc0_r_posted_ctrl;
    wire	[REQ_HDR_SIZE-1:0]            vc0_r_posted_hdr;
    wire	[BEAT_SIZE-1:0]               vc0_r_posted_data;
    /*NON_POSTED*/
    wire	[W_CTRL_BUS_WIDTH-1:0]        vc0_w_non_posted_ctrl;
    wire	[REQ_HDR_SIZE-1:0]            vc0_w_non_posted_hdr;
    wire	[NP_DATA_IP_WIDTH-1:0]        vc0_w_non_posted_data;
    // wire	  [R_CTRL_BUS_WIDTH-1:0] vc0_r_non_posted_ctrl;
    wire	[REQ_HDR_SIZE-1:0]            vc0_r_non_posted_hdr;
    wire	[BEAT_SIZE-1:0]               vc0_r_non_posted_data;
    /*COMPLETION*/      
    wire	[W_CTRL_BUS_WIDTH-1:0]        vc0_w_completion_ctrl;
    wire	[CPL_HDR_SIZE-1:0]            vc0_w_completion_hdr;
    wire	[CPL_DATA_IP_WIDTH-1:0]       vc0_w_completion_data;
    wire	[R_CTRL_BUS_WIDTH-1:0]        vc0_r_completion_ctrl;
    wire	[CPL_HDR_SIZE-1:0]            vc0_r_completion_hdr;
    wire	[BEAT_SIZE-1:0]               vc0_r_completion_data;
    //------ TC/VC Mapping Interface ------//
    // [TYPE_DEC_WIDTH-1:0]          write_buffer_type;
    //                               w_valid;
    //------ Arbiter Interface ------//
    wire	[R_CTRL_BUS_WIDTH-1:0]      vcn_r_completion_ctrl;
    wire	[FLAGS_WIDTH-1:0]           vcn_r_empty_flags;
    wire	                            vcn_cpl_fmt_data_bit;
    wire	[PAYLOAD_LENGTH-1:0]        vcn_cpl_length_field;
    //------- RX Flow Control <=> Write Handler ------//
    wire	[TYPE_DEC_WIDTH-1:0]     	write_buffer_type;
    wire                          	 	cr_hdr_inc;
    wire                          	 	cr_data_inc;
    wire	[PAYLOAD_LENGTH-1:0]     	write_payload_length;
    // wire	[SCALE_BUS_WIDTH-1:0]    	rx_fc_hdr_scale_bus;    
    // wire	[SCALE_BUS_WIDTH-1:0]    	rx_fc_data_scale_bus;
    wire	[3*HDR_FIELD_SIZE-1:0]  	rx_fc_hdr_credits_allocated_bus;
    wire	[3*DATA_FIELD_SIZE-1:0] 	rx_fc_data_credits_allocated_bus;
    wire	[3*HDR_FIELD_SIZE-1:0]  	rx_fc_hdr_credits_received_bus;
    wire	[3*DATA_FIELD_SIZE-1:0] 	rx_fc_data_credits_received_bus;
    //------- RX Flow Control <=> Read Handler ------//
    // wire								req_read_buffer_type; // 0 -> POSTED, 1 -> NONPOSTED
    // wire	[PAYLOAD_LENGTH-1:0]	    req_payload_length;
    // wire								req_ca_hdr_inc;
    // wire								req_ca_data_inc;
	wire 								cpl_ca_hdr_inc;
	wire 								cpl_ca_data_inc;
    //------ Read Handler Interface ------//
//     wire      [REQUESTER_ID_WIDTH-1:0]      device_id; 
    //------ Error Handler Interface ------//
    wire [2:0] error_type;

     tl_rx_vc #(
        .W_CTRL_BUS_WIDTH(W_CTRL_BUS_WIDTH),
        .R_CTRL_BUS_WIDTH(R_CTRL_BUS_WIDTH),
        .HDR_FIFO_DEPTH(HDR_FIFO_DEPTH),
        .P_DATA_FIFO_DEPTH(P_DATA_FIFO_DEPTH),
        .NP_DATA_FIFO_DEPTH(NP_DATA_FIFO_DEPTH),
        .CPL_DATA_FIFO_DEPTH(CPL_DATA_FIFO_DEPTH)
     ) u_vc0 (
          //------ Global Signals ------//
          .i_clk(i_clk),
          .i_n_rst(i_n_rst),
          //------ Flags Output ------//
          .o_vc_w_full_flags(vc0_w_full_flags),
          .o_vc_r_empty_flags(vc0_r_empty_flags),
          //------ Posted Buffers Interface ------//
          .i_w_posted_ctrl(vc0_w_posted_ctrl),
          .i_w_posted_hdr(vc0_w_posted_hdr),
          .i_w_posted_data(vc0_w_posted_data),
          .i_r_posted_ctrl(6'b0), // vc0_r_posted_ctrl
          .o_r_posted_hdr(vc0_r_posted_hdr),
          .o_r_posted_data(vc0_r_posted_data),
          //------ Non Posted Buffers Interface ------//
          .i_w_non_posted_ctrl(vc0_w_non_posted_ctrl),
          .i_w_non_posted_hdr(vc0_w_non_posted_hdr),
          .i_w_non_posted_data(vc0_w_non_posted_data),
          .i_r_non_posted_ctrl(6'b0), //vc0_r_non_posted_ctrl
          .o_r_non_posted_hdr(vc0_r_non_posted_hdr),
          .o_r_non_posted_data(vc0_r_non_posted_data),
          //------ Completion Buffers Interface ------//
          .i_w_completion_ctrl(vc0_w_completion_ctrl),
          .i_w_completion_hdr(vc0_w_completion_hdr),
          .i_w_completion_data(vc0_w_completion_data),
          .i_r_completion_ctrl(vc0_r_completion_ctrl),
          .o_r_completion_hdr(vc0_r_completion_hdr),
          .o_r_completion_data(vc0_r_completion_data)
     );

     tl_rx_fc #(
        .PAYLOAD_LENGTH(PAYLOAD_LENGTH),
        .HDR_FIELD_SIZE(HDR_FIELD_SIZE),
        .DATA_FIELD_SIZE(DATA_FIELD_SIZE),
        .SCALE_BUS_WIDTH(SCALE_BUS_WIDTH),
        .HDR_FIFO_DEPTH(HDR_FIFO_DEPTH),
        .P_DATA_FIFO_DEPTH(P_DATA_FIFO_DEPTH),
        .NP_DATA_FIFO_DEPTH(NP_DATA_FIFO_DEPTH),
        .CPL_DATA_FIFO_DEPTH(CPL_DATA_FIFO_DEPTH)
     ) u_tl_rx_fc (
     // Module ports
          //------ Global Signals ------//
        .i_clk(i_clk),
        .i_n_rst(i_n_rst),
        //------ Write Handler Interface ------//
        .i_write_buffer_type(write_buffer_type),
        .i_cr_hdr_inc(cr_hdr_inc),
        .i_cr_data_inc(cr_data_inc),
        .i_buffer_in_dw(write_payload_length),
        // .o_rx_fc_hdr_scale_bus(rx_fc_hdr_scale_bus),
        // .o_rx_fc_data_scale_bus(rx_fc_data_scale_bus),
        .o_rx_fc_hdr_credits_allocated_bus(rx_fc_hdr_credits_allocated_bus),
        .o_rx_fc_data_credits_allocated_bus(rx_fc_data_credits_allocated_bus),
        .o_rx_fc_hdr_credits_received_bus(rx_fc_hdr_credits_received_bus),
        .o_rx_fc_data_credits_received_bus(rx_fc_data_credits_received_bus),
        //------ Read Handler Interface ------//
        .i_req_read_buffer_type(1'b0), // req_read_buffer_type
        .i_req_buffer_out_dw(10'b0), // req_payload_length
        .i_cpl_buffer_out_dw(vcn_cpl_length_field),
        .i_req_ca_hdr_inc(1'b0), // req_ca_hdr_inc
        .i_req_ca_data_inc(1'b0), // req_ca_data_inc
        .i_cpl_ca_hdr_inc(cpl_ca_hdr_inc),
        .i_cpl_ca_data_inc(cpl_ca_data_inc),
		//------ Config Space Interface ------//
        .i_cfg_max_payload(i_cfg_max_payload_size),
        //------ DLL-TX Flow Control Interface ------//
        .i_dll_ctrl_fc_init(i_dll_ctrl_fc_init),
        .o_dll_tx_fc_hdr_creds(o_dll_tx_fc_hdr_creds),
        .o_dll_tx_fc_data_creds(o_dll_tx_fc_data_creds),
        .o_dll_tx_fc_hdr_scale(o_dll_tx_fc_hdr_scale),
        .o_dll_tx_fc_data_scale(o_dll_tx_fc_data_scale),
        .o_dll_tx_fc_fc_type(o_dll_tx_fc_fc_type),
        .o_dll_tx_fc_fc_creds_valid(o_dll_tx_fc_fc_creds_valid)
     );

	tl_rx_write_handler #(
		.TYPE_DEC_WIDTH(TYPE_DEC_WIDTH),
		.RCV_BUS_WIDTH(RCV_BUS_WIDTH),
        .HDR_FIELD_SIZE(HDR_FIELD_SIZE),
        .DATA_FIELD_SIZE(DATA_FIELD_SIZE),
		.FLAGS_WIDTH(FLAGS_WIDTH)
	) u_write_handler (
		.i_clk(i_clk),
		.i_n_rst(i_n_rst),
		//------- RX FLow Control Interface -------//
		.o_cr_hdr_inc(cr_hdr_inc),
		.o_cr_data_inc(cr_data_inc),
		.o_payload_length(write_payload_length),
		// .i_rx_fc_hdr_scale_bus(rx_fc_hdr_scale_bus),
		// .i_rx_fc_data_scale_bus(rx_fc_data_scale_bus),
		.i_rx_fc_hdr_credits_allocated_bus(rx_fc_hdr_credits_allocated_bus),
		.i_rx_fc_data_credits_allocated_bus(rx_fc_data_credits_allocated_bus),
		.i_rx_fc_hdr_credits_received_bus(rx_fc_hdr_credits_received_bus),
		.i_rx_fc_data_credits_received_bus(rx_fc_data_credits_received_bus),
		//------ Virtual Channels Interface -----//
		.i_vcs_w_full_flags(vcs_w_full_flags),
		.o_buffer_type(write_buffer_type),
		.o_w_valid(w_valid),
		/*POSTED*/
		.o_w_posted_hdr(vc0_w_posted_hdr),
		.o_w_posted_data(vc0_w_posted_data),
		.o_w_posted_ctrl(vc0_w_posted_ctrl),
		/*NON_POSTED*/
		.o_w_non_posted_hdr(vc0_w_non_posted_hdr),
		.o_w_non_posted_data(vc0_w_non_posted_data),
		.o_w_non_posted_ctrl(vc0_w_non_posted_ctrl),
		/*COMPLETION*/
		.o_w_completion_hdr(vc0_w_completion_hdr),
		.o_w_completion_data(vc0_w_completion_data),
		.o_w_completion_ctrl(vc0_w_completion_ctrl),
		//------ Read Handler Interface ------//
		.i_device_id(16'b0),	//device_id	// Requester BDF: error check block to identify wheter a cpl is expected or not.
		//------ Error Handler Interface ------//
        .o_error_type(error_type),
		//------ Config Space Interface ------//
		.i_cfg_ecrc_chk_en(i_cfg_ecrc_chk_en),
        .i_cfg_memory_space_en(i_cfg_memory_space_en),
        .i_cfg_io_space_en(i_cfg_io_space_en),
		.i_cfg_max_payload_size(i_cfg_max_payload_size),
		.i_cfg_BARs(i_cfg_BARs),
		//------ TL_TX interface ------//
		.i_tx_last_req_tag(i_tx_last_req_tag),
		.i_tx_fc_hdr_credit_limit_bus(i_tx_fc_hdr_credit_limit_bus),
		.i_tx_fc_data_credit_limit_bus(i_tx_fc_data_credit_limit_bus),
		.i_tx_fc_hdr_scale_bus(i_tx_fc_hdr_scale_bus),
		.i_tx_fc_data_scale_bus(i_tx_fc_data_scale_bus),
		//------ DLL-RX TLP Interface ------//
		.i_dll_rx_sop(i_dll_rx_sop),
		.i_dll_rx_tlp(i_dll_rx_tlp),
		.i_dll_rx_eop(i_dll_rx_eop),
		.i_dll_rx_last_dw(i_dll_rx_last_dw),
		.o_dll_rx_tlp_discard(o_dll_rx_tlp_discard),
		//------ DLL-RX Flow Control Interface ------//
		.i_dll_rx_fc_typ(i_dll_rx_fc_typ),
		.i_dll_rx_fc_hdr_creds(i_dll_rx_fc_hdr_creds),
		.i_dll_rx_fc_data_creds(i_dll_rx_fc_data_creds),
		.i_dll_rx_fc_hdr_scale(i_dll_rx_fc_hdr_scale),
		.i_dll_rx_fc_data_scale(i_dll_rx_fc_data_scale),
		.i_dll_rx_fc_valid(i_dll_rx_fc_valid)
	);

	tl_rx_read_handler #(
		.R_CTRL_BUS_WIDTH(R_CTRL_BUS_WIDTH)
	) u_read_handler (
		.i_clk(i_clk),
		.i_n_rst(i_n_rst),
		//------- RX FLow Control Interface -------//
        .o_cpl_ca_hdr_inc(cpl_ca_hdr_inc),
        .o_cpl_ca_data_inc(cpl_ca_data_inc),
		//------ Virtual Channels Interface -----//
		.i_vcn_r_empty_flags(vcn_r_empty_flags),
		.i_cpl_fmt_data_bit(vcn_cpl_fmt_data_bit),
		.i_cpl_length_field(vcn_cpl_length_field),
		.o_r_completion_ctrl(vcn_r_completion_ctrl),
		//------ Master Bridge Interface - Request Control ------//
		.o_req_valid(o_req_valid),
		.o_req_inc(o_req_inc),
		.o_req_data_write_inc(o_req_data_write_inc),
		.o_req_last(o_req_last),
		.o_req_valid_data(o_req_valid_data),
		.i_AWREADY_fifo(i_AWREADY_fifo),
		.i_WREADY_fifo(i_WREADY_fifo),
		.i_ARREADY_fifo(i_ARREADY_fifo),
		//------ Master Bridge Interface - Request Info | Data ------//
		.o_req_type(o_req_type),
		.o_req_address_type(o_req_address_type),
		.o_requester_id(o_requester_id),
		.o_req_tag(o_req_tag),
		.o_req_TC(o_req_TC),
		.o_req_length(o_req_length),
		.o_req_first_byte_enable(o_req_first_byte_enable),
		.o_req_last_byte_enable(o_req_last_byte_enable),
		.o_req_address(o_req_address),
		.o_req_data(o_req_data),
		//------ AXI Salve Completion Interface ------//
		.i_slave_ready(i_slave_ready),
		.o_slave_cpl_vaild(o_slave_cpl_vaild),
		.o_slave_cpl_valid_data(o_slave_cpl_valid_data)
	);



    assign o_cpl_info_inc = 0;
    assign o_cpl_data_inc = 0;


     /*RX VC Arbiter (Future work)*/
     assign o_vc_cpl_hdr = vc0_r_completion_hdr;
     assign o_vc_cpl_data = vc0_r_completion_data ;
     assign vc0_r_completion_ctrl = vcn_r_completion_ctrl;
     assign vcn_r_empty_flags = vc0_r_empty_flags;
     assign vcn_cpl_fmt_data_bit = vc0_r_completion_hdr[94];
     assign vcn_cpl_length_field = vc0_r_completion_hdr[73:64];
    
endmodule
       