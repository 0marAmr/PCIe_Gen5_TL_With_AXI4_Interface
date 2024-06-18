module tl_rx_error_handler_config #(
    parameter UC_ERROR_REG_WIDTH=14
    
) (
    input wire                                error_sig,
    input wire [2:0]                          error_typ,
    input wire [2:0]                          tlp_typ,
    input wire [2:0]                          cpl_status,
    input wire                                p_np_req,
    input wire [UC_ERROR_REG_WIDTH-1:0]       i_uc_status_reg,       // uncorrectable error status regiter [25:12]
    input wire [UC_ERROR_REG_WIDTH-1:0]       uc_severity_reg,    // uncorrectable error severity regiter [25:12]
    input wire [UC_ERROR_REG_WIDTH-1:0]       uc_mask_reg,       // uncorrectable error mask regiter [25:12]
    input wire                                command_reg_serr_en,                              // command register[8]
    input wire                                command_reg_parity_err_resp,                     //parity error respons  command register[6]
    input wire [3:0]                          device_ctrl_reg,                              // device control register [3:0]
    input wire                                advisory_nf_err_mask,                              // correctable error mask register [13] 
    input wire [4:0]                          i_first_err_ptr,


    // outputs to the configURation space
    // these outputs represent enable signals to config space as when they are 1 the config space is enables and set these 1 for these bits                  
    output reg [3:0] status_reg,                                // status reg [15:12]
    output reg master_data_parity_err,                         // status reg [8]
    output reg [3:0] device_status_reg,                        // device status register [3:0]
    output reg advisory_nf_err_status,                         // correctable error status register [13]
    output reg [UC_ERROR_REG_WIDTH-1:0] o_uc_status_reg,          // uncorrectable error status regiter [25:12]
    output reg multiple_hdr_capable,                            //Advanced Error Capability and Control Register [9]
    output reg [4:0] o_first_err_ptr,                               //Advanced Error Capability and Control Register[4:0]
    output reg hdr_log_en,
    // outputs to msg and cpl fifo
    output reg write_ptr_incr,
    output reg [1:0] msg_decode,
    output reg cpl_en
    
);

// reg receiver_overflow_err;
// reg flowcontrol_err;
// reg malformed_err;
// reg ecrc_err;
// reg unsupported_req_err;
// reg unexpected_cpl_err;
// reg poisoned_err;


localparam MEMORY = 3'b000,
           IO = 3'b001,
           CONFIGURATION = 3'b010,
           COMPLETION= 3'b011,
           MESSAGE = 3'b100;

localparam CORRECTABLE =2'b00,
           FATAL=2'b11,
           NON_FATAL=2'b01;

localparam SC=3'b000,
           UR=3'b001,
           CRS=3'b010,
           CA=3'b100;
localparam     
receiver_overflow_err=3'b001,
flowcontrol_err=3'b010,
malformed_err=3'b011,
ecrc_err=3'b100,
unsupported_req_err=3'b101,
unexpected_cpl_err=3'b110,
poisoned_err=3'b111;
    
assign first_err_ptr_valid= (i_uc_status_reg[i_first_err_ptr-12]==1) ? 1 : 0;
assign error_handling_en= error_sig || (tlp_typ==COMPLETION && (cpl_status==UR || cpl_status==CA));
always @(*) begin
    // initialization as default value for case statemet in default and for case of errorhandlingen=0
    status_reg=0;                              
    master_data_parity_err=0;                         
    device_status_reg=0;                       
    advisory_nf_err_status=0;                         
    o_uc_status_reg=0;       
    multiple_hdr_capable=0;                           
    o_first_err_ptr=0;                              
    hdr_log_en=0;
    write_ptr_incr=0;
    msg_decode=0;
    cpl_en=0;
        if (error_handling_en==1) begin
            if (tlp_typ==COMPLETION && cpl_status==UR)  begin
                status_reg=4'b0010;
            end
            else if (tlp_typ==COMPLETION && cpl_status==CA) begin
                status_reg=4'b0001;
            end
            else
            begin
                // for advisory error
                if ((error_typ==unexpected_cpl_err && uc_severity_reg[4]==0) || (error_typ==unsupported_req_err && p_np_req==0 && uc_severity_reg[8]==0)) begin
                    if (error_typ==unsupported_req_err) begin
                        device_status_reg=4'b1001;
                    end
                    else
                    device_status_reg=4'b0001;

                    advisory_nf_err_status=1;
                    if (advisory_nf_err_mask==0) begin
                        if (error_typ==unexpected_cpl_err) begin
                            o_uc_status_reg=14'b0000_0000_0100_00;
                            if (uc_mask_reg[4]==0 && first_err_ptr_valid==0) begin
                                hdr_log_en=1;
                                o_first_err_ptr=16; 
                            end
                            else
                            hdr_log_en=0;
                        end
                        else
                        begin
                            o_uc_status_reg=14'b0000_0100_0000_00;
                            if (uc_mask_reg[8]==0 && first_err_ptr_valid==0) begin
                                hdr_log_en=1;
                                o_first_err_ptr=20;
                            end
                            else
                            hdr_log_en=0;
                        end
                        if (error_typ==unsupported_req_err && device_ctrl_reg==4'b1001) begin
                            write_ptr_incr=1;
                            msg_decode=CORRECTABLE;
                            cpl_en=1;
                        end
                        else if (error_typ==unexpected_cpl_err && device_ctrl_reg==4'b0001) begin
                            write_ptr_incr=1;
                            msg_decode=CORRECTABLE;
                        end
                        else
                        write_ptr_incr=0;
                    end
                    else
                    write_ptr_incr=0;
                end
                // for non-advisory errors (means uncorrectable errors)
                else 
                begin
                    case (error_typ)
                        receiver_overflow_err: begin
                            if (uc_severity_reg[5]==1) begin
                               device_status_reg=4'b0100; 
                            end
                            else
                            device_status_reg=4'b0010;
                            o_uc_status_reg=14'b0000_0000_1000_00;
                            if (uc_mask_reg[5]==0) begin
                                if (first_err_ptr_valid==0) begin
                                    hdr_log_en=1;
                                    o_first_err_ptr=17;
                                end
                                else
                                hdr_log_en=0;
                                if (uc_severity_reg[5]==1) begin
                                    if (command_reg_serr_en==1|| device_ctrl_reg[2]==1) begin
                                        write_ptr_incr=1;
                                        msg_decode=FATAL;
                                    end
                                    else
                                    write_ptr_incr=0;
                                end
                                else 
                                if (command_reg_serr_en==1|| device_ctrl_reg[1]==1) begin
                                        write_ptr_incr=1;
                                        msg_decode=NON_FATAL;
                                    end
                                    else
                                    write_ptr_incr=0;
                                    if (command_reg_serr_en==1) begin
                                       status_reg=4'b0100; 
                                    end
                                    else
                                    status_reg=0;
                            end
                            else
                            write_ptr_incr=0;
                        end               
                        flowcontrol_err: begin
                            if (uc_severity_reg[1]==1) begin
                               device_status_reg=4'b0100; 
                            end
                            else
                            device_status_reg=4'b0010;
                            o_uc_status_reg=14'b0000_0000_0000_10;
                            if (uc_mask_reg[1]==0) begin
                                if (first_err_ptr_valid==0) begin
                                    hdr_log_en=1;
                                    o_first_err_ptr=13;
                                end
                                else
                                hdr_log_en=0;
                                if (uc_severity_reg[1]==1) begin
                                    if (command_reg_serr_en==1|| device_ctrl_reg[2]==1) begin
                                        write_ptr_incr=1;
                                        msg_decode=FATAL;
                                    end
                                    else
                                    write_ptr_incr=0;
                                end
                                else 
                                if (command_reg_serr_en==1|| device_ctrl_reg[1]==1) begin
                                        write_ptr_incr=1;
                                        msg_decode=NON_FATAL;
                                    end
                                    else
                                    write_ptr_incr=0;
                                    if (command_reg_serr_en==1) begin
                                       status_reg=4'b0100; 
                                    end
                                    else
                                    status_reg=0;
                            end
                            else
                            write_ptr_incr=0;
                        end
                        malformed_err: begin
                            if (uc_severity_reg[6]==1) begin
                               device_status_reg=4'b0100; 
                            end
                            else
                            device_status_reg=4'b0010;
                            o_uc_status_reg=14'b0000_0001_0000_00;
                            if (uc_mask_reg[6]==0) begin
                                if (first_err_ptr_valid==0) begin
                                    hdr_log_en=1;
                                    o_first_err_ptr=18;
                                end
                                else
                                hdr_log_en=0;
                                if (uc_severity_reg[6]==1) begin
                                    if (command_reg_serr_en==1|| device_ctrl_reg[2]==1) begin
                                        write_ptr_incr=1;
                                        msg_decode=FATAL;
                                    end
                                    else
                                    write_ptr_incr=0;
                                end
                                else 
                                if (command_reg_serr_en==1|| device_ctrl_reg[1]==1) begin
                                        write_ptr_incr=1;
                                        msg_decode=NON_FATAL;
                                    end
                                    else
                                    write_ptr_incr=0;
                                    if (command_reg_serr_en==1) begin
                                       status_reg=4'b0100; 
                                    end
                                    else
                                    status_reg=0;
                            end
                            else
                            write_ptr_incr=0;
                        end
                        ecrc_err: begin
                            if (uc_severity_reg[7]==1) begin
                               device_status_reg=4'b0100; 
                            end
                            else
                            device_status_reg=4'b0010;
                            o_uc_status_reg=14'b0000_0010_0000_00;
                            if (uc_mask_reg[7]==0) begin
                                if (first_err_ptr_valid==0) begin
                                    hdr_log_en=1;
                                    o_first_err_ptr=19;
                                end
                                else
                                hdr_log_en=0;
                                if (uc_severity_reg[7]==1) begin
                                    if (command_reg_serr_en==1|| device_ctrl_reg[2]==1) begin
                                        write_ptr_incr=1;
                                        msg_decode=FATAL;
                                    end
                                    else
                                    write_ptr_incr=0;
                                end
                                else 
                                if (command_reg_serr_en==1|| device_ctrl_reg[1]==1) begin
                                        write_ptr_incr=1;
                                        msg_decode=NON_FATAL;
                                    end
                                    else
                                    write_ptr_incr=0;
                                    if (command_reg_serr_en==1) begin
                                       status_reg=4'b0100; 
                                    end
                                    else
                                    status_reg=0;
                            end
                            else
                            write_ptr_incr=0;
                        end
                        unsupported_req_err: begin
                            if (uc_severity_reg[8]==1) begin
                               device_status_reg=4'b1100; 
                            end
                            else
                            device_status_reg=4'b1010;
                            o_uc_status_reg=14'b0000_0100_0000_00;
                            if (uc_mask_reg[8]==0) begin
                                if (first_err_ptr_valid==0) begin
                                    hdr_log_en=1;
                                    o_first_err_ptr=20;
                                end
                                else
                                hdr_log_en=0;
                                if (uc_severity_reg[8]==1) begin
                                    if ((device_ctrl_reg[3]==1)&&(command_reg_serr_en==1|| device_ctrl_reg[2]==1)) begin
                                        write_ptr_incr=1;
                                        msg_decode=FATAL;
                                    end
                                    else
                                    write_ptr_incr=0;
                                end
                                else 
                                if ((device_ctrl_reg[3]==1)&&(command_reg_serr_en==1|| device_ctrl_reg[1]==1)) begin
                                        write_ptr_incr=1;
                                        msg_decode=NON_FATAL;
                                    end
                                    else
                                    write_ptr_incr=0;
                                    if (command_reg_serr_en==1) begin
                                       status_reg=4'b0100; 
                                    end
                                    else
                                    status_reg=0;
                            end
                            else
                            write_ptr_incr=0;
                        end
                        unexpected_cpl_err: begin
                            if (uc_severity_reg[4]==1) begin
                               device_status_reg=4'b0100; 
                            end
                            else
                            device_status_reg=4'b0010;
                            o_uc_status_reg=14'b0000_0000_0100_00;
                            if (uc_mask_reg[4]==0) begin
                                if (first_err_ptr_valid==0) begin
                                    hdr_log_en=1;
                                    o_first_err_ptr=16;
                                end
                                else
                                hdr_log_en=0;
                                if (uc_severity_reg[4]==1) begin
                                    if (command_reg_serr_en==1|| device_ctrl_reg[2]==1) begin
                                        write_ptr_incr=1;
                                        msg_decode=FATAL;
                                    end
                                    else
                                    write_ptr_incr=0;
                                end
                                else 
                                if (command_reg_serr_en==1|| device_ctrl_reg[1]==1) begin
                                        write_ptr_incr=1;
                                        msg_decode=NON_FATAL;
                                    end
                                    else
                                    write_ptr_incr=0;
                                    if (command_reg_serr_en==1) begin
                                       status_reg=4'b0100; 
                                    end
                                    else
                                    status_reg=0;
                            end
                            else
                            write_ptr_incr=0;
                        end
                        poisoned_err: begin
                            status_reg=4'b1000;
                            if (command_reg_parity_err_resp==1) begin
                                master_data_parity_err=1;
                            end
                            else
                            master_data_parity_err=0;
                            if (uc_severity_reg[0]==1) begin
                               device_status_reg=4'b0100; 
                            end
                            else
                            device_status_reg=4'b0010;
                            o_uc_status_reg=14'b0000_0000_0000_01;
                            if (uc_mask_reg[0]==0) begin
                                if (first_err_ptr_valid==0) begin
                                    hdr_log_en=1;
                                    o_first_err_ptr=12;
                                end
                                else
                                hdr_log_en=0;
                                if (uc_severity_reg[0]==1) begin
                                    if (command_reg_serr_en==1|| device_ctrl_reg[2]==1) begin
                                        write_ptr_incr=1;
                                        msg_decode=FATAL;
                                        if (p_np_req==0) begin
                                            cpl_en=1;
                                        end
                                        else
                                        cpl_en=0;
                                    end
                                    else
                                    write_ptr_incr=0;
                                end
                                else 
                                if (command_reg_serr_en==1|| device_ctrl_reg[1]==1) begin
                                        write_ptr_incr=1;
                                        msg_decode=NON_FATAL;
                                    end
                                    else
                                    write_ptr_incr=0;
                                    if (command_reg_serr_en==1) begin
                                       status_reg=4'b0100; 
                                    end
                                    else
                                    status_reg=0;
                            end
                            else
                            write_ptr_incr=0;
                        end
                    endcase
                end
            end      
    end
end  
endmodule