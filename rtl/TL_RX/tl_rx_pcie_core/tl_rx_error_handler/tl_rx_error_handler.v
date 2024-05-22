module tl_rx_error_handler #(
    parameter UC_ERROR_REG_WIDTH=14,
              REQ_WIDTH=16,
              TAG_WIDTH=8,
              FIFO_DEPTH=8,
              FIFO_DATA_WIDTH=27,
              MSG_WIDTH=128
) (
    input wire                                i_clk,
    input wire                                i_rst,
    input wire [REQ_WIDTH-1:0]                i_req_id,
    input wire [TAG_WIDTH-1:0]                i_tag,
    input wire                                i_msg_trans_en,
    input wire                                i_read_ptr_incr,
    input wire                                i_error_sig,
    input wire [2:0]                          i_error_typ,
    input wire [2:0]                          i_tlp_typ,
    input wire [2:0]                          i_cpl_status,
    input wire                                i_p_np_req,
    input wire [UC_ERROR_REG_WIDTH-1:0]       i_uc_status_reg,       // uncorrectable error status regiter [25:12]
    input wire [UC_ERROR_REG_WIDTH-1:0]       i_uc_severity_reg,    // uncorrectable error severity regiter [25:12]
    input wire [UC_ERROR_REG_WIDTH-1:0]       i_uc_mask_reg,       // uncorrectable error mask regiter [25:12]
    input wire                                i_command_reg_serr_en,                              // command register[8]
    input wire                                i_command_reg_parity_err_resp,                     //parity error respons  command register[6]
    input wire [3:0]                          i_device_ctrl_reg,                              // device control register [3:0]
    input wire                                i_advisory_nf_err_mask,                              // correctable error mask register [13] 
    input wire [4:0]                          i_first_err_ptr,
    // error handling config interface
    // outputs to the configURation space
    // these outputs represent enable signals to config space as when they are 1 the config space is enables and set these 1 for these bits                  
    output reg [3:0]                          o_status_reg,                                // status reg [15:12]
    output reg                                o_master_data_parity_err,                         // status reg [8]
    output reg [3:0]                          o_device_status_reg,                        // device status register [3:0]
    output reg                                o_advisory_nf_err_status,                         // correctable error status register [13]
    output reg [UC_ERROR_REG_WIDTH-1:0]       o_uc_status_reg,          // uncorrectable error status regiter [25:12]
    output reg                                o_multiple_hdr_capable,                            //Advanced Error Capability and Control Register [9]
    output reg [4:0]                          o_first_err_ptr,                               //Advanced Error Capability and Control Register[4:0]
    output reg                                o_hdr_log_en,
    // error handling fifo
    output reg [MSG_WIDTH-1:0]                o_tlp_msg,
    output reg                                o_ur_cpl_valid,
    output reg                                o_empty_flag
);
wire write_ptr_incr_top;
wire [1:0] msg_decode_top;
wire cpl_en_top;

tl_rx_error_handler_config u_cfg_interface(
    .error_sig(i_error_sig),
    .error_typ(i_error_typ),
    .tlp_typ(i_tlp_typ),
    .cpl_status(i_cpl_status),
    .p_np_req(i_p_np_req),
    .i_uc_status_reg(i_uc_status_reg),       
    .uc_severity_reg(i_uc_severity_reg),    
    .uc_mask_reg(i_uc_mask_reg),       
    .command_reg_serr_en(i_command_reg_serr_en),                             
    .command_reg_parity_err_resp(i_command_reg_parity_err_resp),                    
    .device_ctrl_reg(i_device_ctrl_reg),                              
    .advisory_nf_err_mask(i_advisory_nf_err_mask),                              
    .i_first_err_ptr(i_first_err_ptr),
    .status_reg(o_status_reg),                            
    .master_data_parity_err(o_master_data_parity_err),                        
    .device_status_reg(o_device_status_reg),                        
    .advisory_nf_err_status(o_advisory_nf_err_status),                         
    .o_uc_status_reg(o_uc_status_reg),          
    .multiple_hdr_capable(o_multiple_hdr_capable),                            
    .o_first_err_ptr(o_first_err_ptr),                               
    .hdr_log_en(o_hdr_log_en),
    .write_ptr_incr(write_ptr_incr_top),
    .msg_decode(msg_decode_top),
    .cpl_en(cpl_en_top)
);

tl_rx_error_handler_fifo u_fifo (
    .clk(i_clk),
    .rst(i_rst),
    .req_id(i_req_id),
    .tag(i_tag),
    .msg_decode(msg_decode_top),
    .cpl_en(cpl_en_top),
    .write_ptr_incr(write_ptr_incr_top),  // write msg info to report this error by sending it to tx 
    .msg_trans_en(i_msg_trans_en),
    .read_ptr_incr(i_read_ptr_incr),
    .tlp_msg(o_tlp_msg),
    .ur_cpl_valid(o_ur_cpl_valid),
    .empty_flag(o_empty_flag)
);  
endmodule
