module TL_RX_error_check_flow_control_top #(
    parameter FC_DATA_CREDS_WIDTH=16,
    FC_HDR_CREDS_WIDTH=12,
    DLL_DATA_CREDS_WIDTH=16,
    DLL_HDR_CREDS_WIDTH=12
) (
    input   wire[FC_DATA_CREDS_WIDTH-1:0]   p_data_creds_reg,
    input   wire[FC_HDR_CREDS_WIDTH-1:0]    p_hdr_creds_reg,    
    input   wire[FC_DATA_CREDS_WIDTH-1:0]   np_data_creds_reg,
    input   wire[FC_HDR_CREDS_WIDTH-1:0]    np_hdr_creds_reg,  
    input   wire[FC_DATA_CREDS_WIDTH-1:0]   cpl_data_creds_reg,
    input   wire[FC_HDR_CREDS_WIDTH-1:0]    cpl_hdr_creds_reg,
    input   wire[1:0]                       p_data_scale_reg,
    input   wire[1:0]                       p_hdr_scale_reg,    
    input   wire[1:0]                       np_data_scale_reg,
    input   wire[1:0]                       np_hdr_scale_reg,    
    input   wire[1:0]                       cpl_data_scale_reg,
    input   wire[1:0]                       cpl_hdr_scale_reg,
    input   wire[DLL_DATA_CREDS_WIDTH-1:0]  dll_data_creds,
    input   wire[DLL_HDR_CREDS_WIDTH-1:0]   dll_hdr_creds,
    input   wire[1:0]                       dll_data_scale,
    input   wire[1:0]                       dll_hdr_scale,
    input   wire                            dll_valid,
    input   wire                            flow_control_en,
    input   wire [1:0]                      dll_typ,
    output  wire                            flow_control_error
);

    reg p_dll_valid;
    reg np_dll_valid;
    reg cpl_dll_valid;
    reg p_flow_control_en;
    reg np_flow_control_en;
    reg cpl_flow_control_en;

    wire p_flow_control_error;
    wire np_flow_control_error;
    wire cpl_flow_control_error;

    always @(*) begin
        case (dll_typ)
            2'b00: begin
                p_dll_valid=dll_valid;
                np_dll_valid=0;
                cpl_dll_valid=0;
                p_flow_control_en=flow_control_en;
                np_flow_control_en=0;
                cpl_flow_control_en=0;
            end  
             2'b01: begin
                p_dll_valid=0;
                np_dll_valid=dll_valid;
                cpl_dll_valid=0;
                p_flow_control_en=0;
                np_flow_control_en=flow_control_en;
                cpl_flow_control_en=0;
            end 
            2'b10: begin
                p_dll_valid=0;
                np_dll_valid=0;
                cpl_dll_valid=dll_valid;
                p_flow_control_en=0;
                np_flow_control_en=0;
                cpl_flow_control_en=flow_control_en;
            end  
            2'b11: begin
                p_dll_valid=0;
                np_dll_valid=0;
                cpl_dll_valid=0;
                p_flow_control_en=0;
                np_flow_control_en=0;
                cpl_flow_control_en=0;
            end  
        endcase
    end

    TL_RX_error_check_flow_control u_p(
        .data_creds_reg(p_data_creds_reg),
        .hdr_creds_reg(p_hdr_creds_reg),
        .data_scale_reg(p_data_scale_reg),
        .hdr_scale_reg(p_hdr_scale_reg),
        .dll_valid(p_dll_valid),
        .flow_control_en(p_flow_control_en),
        .dll_data_creds(dll_data_creds),
        .dll_hdr_creds(dll_hdr_creds),
        .dll_data_scale(dll_data_scale),
        .dll_hdr_scale(dll_hdr_scale),
        .flow_control_error(p_flow_control_error)
    );

    TL_RX_error_check_flow_control u_np(
        .data_creds_reg(np_data_creds_reg),
        .hdr_creds_reg(np_hdr_creds_reg),
        .data_scale_reg(np_data_scale_reg),
        .hdr_scale_reg(np_hdr_scale_reg),
        .dll_valid(np_dll_valid),
        .flow_control_en(np_flow_control_en),
        .dll_data_creds(dll_data_creds),
        .dll_hdr_creds(dll_hdr_creds),
        .dll_data_scale(dll_data_scale),
        .dll_hdr_scale(dll_hdr_scale),
        .flow_control_error(np_flow_control_error)
    );

    TL_RX_error_check_flow_control u_cpl(
        .data_creds_reg(cpl_data_creds_reg),
        .hdr_creds_reg(cpl_hdr_creds_reg),
        .data_scale_reg(cpl_data_scale_reg),
        .hdr_scale_reg(cpl_hdr_scale_reg),
        .dll_valid(cpl_dll_valid),
        .flow_control_en(cpl_flow_control_en),
        .dll_data_creds(dll_data_creds),
        .dll_hdr_creds(dll_hdr_creds),
        .dll_data_scale(dll_data_scale),
        .dll_hdr_scale(dll_hdr_scale),
        .flow_control_error(cpl_flow_control_error)
    );

    assign flow_control_error=p_flow_control_error||np_flow_control_error||cpl_flow_control_error;
endmodule