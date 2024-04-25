/* Module Name	: Tx_FC         	            */
/* Written By	: Ahmady                     	*/
/* Date			: 9-04-2024 					*/
/* Version		: V_1							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: -							    */
/* Future Work  :                               */
module Tx_FC # (
    parameter   FC_HDR_WIDTH    = 12,
                FC_DATA_WIDTH   = 16                
)(
    input bit clk,
    input bit arst,
    // Interface with Tx Arbiter
    Tx_FC_Interface.FC_ARBITER  _fc_arbiter,
    // Interface with DLL
    Tx_FC_Interface.FC_DLL      _fc_dll
);

/* Packages */

/* Parameters */
import Tx_Arbiter_Package::*;

/* Internal Signals */
logic [FC_HDR_WIDTH  - 1 : 0] CC_Posted_Hdr; 
logic [FC_DATA_WIDTH - 1 : 0] CC_Posted_Data; 
logic [FC_HDR_WIDTH  - 1 : 0] CC_NonPosted_Hdr; 
logic [FC_DATA_WIDTH - 1 : 0] CC_NonPosted_Data; 
logic [FC_HDR_WIDTH  - 1 : 0] CC_Completion_Hdr; 
logic [FC_DATA_WIDTH - 1 : 0] CC_Completion_Data; 

logic [FC_HDR_WIDTH  - 1 : 0] CL_Posted_Hdr; 
logic [FC_DATA_WIDTH - 1 : 0] CL_Posted_Data; 
logic [FC_HDR_WIDTH  - 1 : 0] CL_NonPosted_Hdr; 
logic [FC_DATA_WIDTH - 1 : 0] CL_NonPosted_Data; 
logic [FC_HDR_WIDTH  - 1 : 0] CL_Completion_Hdr; 
logic [FC_DATA_WIDTH - 1 : 0] CL_Completion_Data; 

/* Useful Functions */
// 1st: Check Hdr
function FC_result_t FC_Hdr_Check_Update (
    input logic [FC_HDR_WIDTH - 1 : 0] CL_1, 
    inout logic [FC_HDR_WIDTH - 1 : 0] CC_1
);
    FC_result_t Result;
    if ((CL_1 >= (CC_1 + 1))) begin
        Result  = FC_SUCCESS_1;
        CC_1    = (CC_1 + 1);
        $display("Iam here");
    end
    else begin
        Result  = FC_FAILED;        
    end
    return Result;
endfunction


// 1st: Check Hdr
// 2nd: Check Hdr
function FC_result_t FC_Hdr_Hdr_Check_Update (
    input logic [FC_HDR_WIDTH - 1 : 0] CL_1, 
    inout logic [FC_HDR_WIDTH - 1 : 0] CC_1, 
    input logic [FC_HDR_WIDTH - 1 : 0] CL_2, 
    inout logic [FC_HDR_WIDTH - 1 : 0] CC_2
);
    FC_result_t Result;
    if ((CL_1 >= (CC_1 + 1))) begin
        Result  = FC_SUCCESS_1;
        CC_1    = (CC_1 + 1);
        $display("Iam here");
    end
    else if ((CL_2 >= (CC_2 + 1))) begin
        Result  = FC_SUCCESS_2;
        CC_2    = CC_2 + 1;        
    end
    else begin
        Result  = FC_FAILED;        
    end
    return Result;
endfunction


// 1st: Check Data
function FC_result_t FC_Data_Check_Update (  
    input logic [FC_HDR_WIDTH   - 1 : 0]        CL_H_1,
    input logic [FC_DATA_WIDTH  - 1 : 0]        CL_D_1,
    inout logic [FC_HDR_WIDTH   - 1 : 0]        CC_H_1,
    inout logic [FC_DATA_WIDTH  - 1 : 0]        CC_D_1,
    input logic [9:0]                           PTLP_1
);
    FC_result_t Result;
    if ((CL_H_1 >= (CC_H_1 + 1))) begin
        if ((CL_D_1 >= (CC_D_1 + FC_PTLP_Conv(PTLP_1)))) begin
            CC_H_1      = (CC_H_1 + 1);
            CC_D_1      = (CC_D_1 + FC_PTLP_Conv(PTLP_1));
            Result      = FC_SUCCESS_1;
        end
        else begin
            Result      = FC_FAILED;                                    
        end
    end
    else begin
        Result      = FC_FAILED;
    end                                    

    return Result;
endfunction


// 1st: Check Data
// 2nd: Check Data
function FC_result_t FC_Data_Data_Check_Update (  
    input logic [FC_HDR_WIDTH   - 1 : 0]        CL_H_1,
    input logic [FC_DATA_WIDTH  - 1 : 0]        CL_D_1,
    inout logic [FC_HDR_WIDTH   - 1 : 0]        CC_H_1,
    inout logic [FC_DATA_WIDTH  - 1 : 0]        CC_D_1,
    input logic [9:0]                           PTLP_1,

    input logic [FC_HDR_WIDTH   - 1 : 0]        CL_H_2,
    input logic [FC_DATA_WIDTH  - 1 : 0]        CL_D_2,
    inout logic [FC_HDR_WIDTH   - 1 : 0]        CC_H_2,
    inout logic [FC_DATA_WIDTH  - 1 : 0]        CC_D_2,
    input logic [9:0]                           PTLP_2
);
    FC_result_t Result;
    if ((CL_H_1 >= (CC_H_1 + 1))) begin
        if ((CL_D_1 >= (CC_D_1 + FC_PTLP_Conv(PTLP_1)))) begin
            CC_H_1      = (CC_H_1 + 1);
            CC_D_1      = (CC_D_1 + FC_PTLP_Conv(PTLP_1));
            Result      = FC_SUCCESS_1;
        end
        else begin
            if ((CL_H_2 >= (CC_H_2 + 1))) begin
                if ((CL_D_2 >= (CC_D_2 + FC_PTLP_Conv(PTLP_2)))) begin
                    CC_H_2      = (CC_H_2 + 1);
                    CC_D_2      = (CC_D_2 + FC_PTLP_Conv(PTLP_2));
                    Result      = FC_SUCCESS_2;
                end
                else begin
                    Result      = FC_FAILED;                                    
                end
            end
            else begin
                    Result      = FC_FAILED;                                                    
            end
        end
    end
    else if ((CL_H_2 >= (CC_H_2 + 1))) begin
        if ((CL_D_2 >= (CC_D_2 + FC_PTLP_Conv(PTLP_2)))) begin
            CC_H_2      = (CC_H_2 + 1);
            CC_D_2      = (CC_D_2 + FC_PTLP_Conv(PTLP_2));
            Result      = FC_SUCCESS_2;
        end
        else begin
            Result      = FC_FAILED;                                    
        end
    end
    else begin
       Result           = FC_FAILED; 
    end

    return Result;
endfunction


// 1st: Check Hdr
// 2nd: Check Data
function FC_result_t FC_Hdr_Data_Check_Update (  
    input logic [FC_HDR_WIDTH   - 1 : 0]        CL_H_1,
    // input logic [FC_DATA_WIDTH  - 1 : 0]        CL_D_1,
    inout logic [FC_HDR_WIDTH   - 1 : 0]        CC_H_1,
    // inout logic [FC_DATA_WIDTH  - 1 : 0]        CC_D_1,
    // input logic [9:0]                           PTLP_1

    input logic [FC_HDR_WIDTH   - 1 : 0]        CL_H_2,
    input logic [FC_DATA_WIDTH  - 1 : 0]        CL_D_2,
    inout logic [FC_HDR_WIDTH   - 1 : 0]        CC_H_2,
    inout logic [FC_DATA_WIDTH  - 1 : 0]        CC_D_2,
    input logic [9:0]                           PTLP_2
);
    FC_result_t Result;
    if ((CL_H_1 >= (CC_H_1 + 1))) begin
        CC_H_1      = (CC_H_1 + 1);
        Result      = FC_SUCCESS_1;
    end
    else begin
        if ((CL_H_2 >= (CC_H_2 + 1))) begin
            if ((CL_D_2 >= (CC_D_2 + FC_PTLP_Conv(PTLP_2)))) begin
                CC_H_2      = (CC_H_2 + 1);
                CC_D_2      = (CC_D_2 + FC_PTLP_Conv(PTLP_2));
                Result      = FC_SUCCESS_2;
            end
            else begin
                Result      = FC_FAILED;                                    
            end
        end
        else begin
                Result      = FC_FAILED;                                                    
        end
    end

    return Result;
endfunction


// 1st: Check Data
// 2nd: Check Hdr
function FC_result_t FC_Data_Hdr_Check_Update (  
    input logic [FC_HDR_WIDTH   - 1 : 0]        CL_H_1,
    input logic [FC_DATA_WIDTH  - 1 : 0]        CL_D_1,
    inout logic [FC_HDR_WIDTH   - 1 : 0]        CC_H_1,
    inout logic [FC_DATA_WIDTH  - 1 : 0]        CC_D_1,
    input logic [9:0]                           PTLP_1,

    input logic [FC_HDR_WIDTH   - 1 : 0]        CL_H_2,
    // input logic [FC_DATA_WIDTH  - 1 : 0]        CL_D_2,
    inout logic [FC_HDR_WIDTH   - 1 : 0]        CC_H_2
    // inout logic [FC_DATA_WIDTH  - 1 : 0]        CC_D_2,
    // input logic [9:0]                           PTLP_2
);
    FC_result_t Result;
    if ((CL_H_1 >= (CC_H_1 + 1))) begin
        if ((CL_D_1 >= (CC_D_1 + FC_PTLP_Conv(PTLP_1)))) begin
            CC_H_1      = (CC_H_1 + 1);
            CC_D_1      = (CC_D_1 + FC_PTLP_Conv(PTLP_1));
            Result      = FC_SUCCESS_1;
        end
        else begin
            if ((CL_H_2 >= (CC_H_2 + 1))) begin
                CC_H_2      = (CC_H_2 + 1);
                Result      = FC_SUCCESS_2;
            end
            else begin
                Result      = FC_FAILED;                                    
            end
        end
    end
    else if ((CL_H_2 >= (CC_H_2 + 1))) begin
        CC_H_2      = (CC_H_2 + 1);
        Result      = FC_SUCCESS_2;
    end
    else begin
        Result      = FC_FAILED;                                    
    end

    return Result;
endfunction



function logic [9 : 0] FC_PTLP_Conv (input logic [9 : 0] PTLP);
    // if PTLP % 4 == 0 (devisable by 4) then result = (PTLP / 4)
    // else result = (PTLP / 4) + 1
    if ((PTLP & 10'b00_0000_0011) == 10'b00_0000_0000) begin
        // xx_xxxx_xx00
        return PTLP >> 2;
    end
    else begin
        return (PTLP >> 2) + 1;        
    end
endfunction

/* Assign Statements */

/* Always Blocks */
always_ff @(posedge clk or negedge arst) begin : FC_DLL_Update
    if (!arst) begin
        CL_Posted_Hdr       <= '0;
        CL_Posted_Data      <= '0;
        CL_NonPosted_Hdr    <= '0;
        CL_NonPosted_Data   <= '0;
        CL_Completion_Hdr   <= '0;
        CL_Completion_Data  <= '0;
    end    
    else begin
        case (_fc_dll.TypeFC)
            FC_P   : begin
                CL_Posted_Hdr       <= _fc_dll.HdrFC;
                CL_Posted_Data      <= _fc_dll.DataFC; 
            end
            FC_NP  : begin
                CL_NonPosted_Hdr    <= _fc_dll.HdrFC; 
                CL_NonPosted_Data   <= _fc_dll.DataFC; 
            end
            FC_CPL : begin
                CL_Completion_Hdr   <= _fc_dll.HdrFC; 
                CL_Completion_Data  <= _fc_dll.DataFC; 
            end
            default: begin
            end
        endcase
    end
end

always_ff @(posedge clk or negedge arst) begin : FC_Arbiter_Command
    if (!arst) begin
        _fc_arbiter.Result <= FC_INVALID;
        CC_Posted_Hdr       <= '0;
        CC_Posted_Data      <= '0;
        CC_NonPosted_Hdr    <= '0;
        CC_NonPosted_Data   <= '0;
        CC_Completion_Hdr   <= '0;
        CC_Completion_Data  <= '0; 
    end    
    else begin
        case (_fc_arbiter.Command_1)
            FC_P_H   : begin
                case (_fc_arbiter.Command_2)
                    FC_P_H : begin
                        _fc_arbiter.Result <= FC_Hdr_Check_Update(CL_Posted_Hdr, CC_Posted_Hdr);
                    end 
                    FC_P_D : begin
                        _fc_arbiter.Result <= FC_Hdr_Data_Check_Update(CL_Posted_Hdr, CC_Posted_Hdr, CL_Posted_Hdr, CL_Posted_Data, CC_Posted_Hdr, CC_Posted_Data, _fc_arbiter.PTLP_2);
                    end 
                    FC_NP_H : begin
                        _fc_arbiter.Result <= FC_Hdr_Hdr_Check_Update(CL_Posted_Hdr, CC_Posted_Hdr, CL_NonPosted_Hdr, CC_NonPosted_Hdr);
                    end 
                    FC_NP_D : begin
                        _fc_arbiter.Result <= FC_Hdr_Data_Check_Update(CL_Posted_Hdr, CC_Posted_Hdr, CL_NonPosted_Hdr, CL_NonPosted_Data, CC_NonPosted_Hdr, CC_NonPosted_Data, _fc_arbiter.PTLP_2);
                    end 
                    FC_CPL_H : begin
                        _fc_arbiter.Result <= FC_Hdr_Hdr_Check_Update(CL_Posted_Hdr, CC_Posted_Hdr, CL_Completion_Hdr, CC_Completion_Hdr);
                    end 
                    FC_CPL_D : begin
                        _fc_arbiter.Result <= FC_Hdr_Data_Check_Update(CL_Posted_Hdr, CC_Posted_Hdr, CL_Completion_Hdr, CL_Completion_Data, CC_Completion_Hdr, CC_Completion_Data, _fc_arbiter.PTLP_2);
                    end 
                    default: begin
                        _fc_arbiter.Result <= FC_Hdr_Check_Update(CL_Posted_Hdr, CC_Posted_Hdr);
                    end
                endcase
            end
            FC_P_D   : begin
                case (_fc_arbiter.Command_2)
                    FC_P_H : begin
                        _fc_arbiter.Result <= FC_Data_Hdr_Check_Update(CL_Posted_Hdr, CL_Posted_Data, CC_Posted_Hdr, CC_Posted_Data, _fc_arbiter.PTLP_1, CL_Posted_Hdr, CC_Posted_Hdr);
                    end 
                    FC_P_D : begin
                        _fc_arbiter.Result <= FC_Data_Check_Update(CL_Posted_Hdr, CL_Posted_Data, CC_Posted_Hdr, CC_Posted_Data, _fc_arbiter.PTLP_1);
                    end 
                    FC_NP_H : begin
                        _fc_arbiter.Result <= FC_Data_Hdr_Check_Update(CL_Posted_Hdr, CL_Posted_Data, CC_Posted_Hdr, CC_Posted_Data, _fc_arbiter.PTLP_1, CL_NonPosted_Hdr, CC_NonPosted_Hdr);
                    end 
                    FC_NP_D : begin
                        _fc_arbiter.Result <= FC_Data_Data_Check_Update(CL_Posted_Hdr, CL_Posted_Data, CC_Posted_Hdr, CC_Posted_Data, _fc_arbiter.PTLP_1, CL_NonPosted_Hdr, CL_NonPosted_Data, CC_NonPosted_Hdr, CC_NonPosted_Data, _fc_arbiter.PTLP_2);
                    end 
                    FC_CPL_H : begin
                        _fc_arbiter.Result <= FC_Data_Hdr_Check_Update(CL_Posted_Hdr, CL_Posted_Data, CC_Posted_Hdr, CC_Posted_Data, _fc_arbiter.PTLP_1, CL_Completion_Hdr, CC_Completion_Hdr);
                    end 
                    FC_CPL_D : begin
                        _fc_arbiter.Result <= FC_Data_Data_Check_Update(CL_Posted_Hdr, CL_Posted_Data, CC_Posted_Hdr, CC_Posted_Data, _fc_arbiter.PTLP_1, CL_Completion_Hdr, CL_Completion_Data, CC_Completion_Hdr, CC_Completion_Data, _fc_arbiter.PTLP_2);
                    end 
                    default: begin
                        _fc_arbiter.Result <= FC_Data_Check_Update(CL_Posted_Hdr, CL_Posted_Data, CC_Posted_Hdr, CC_Posted_Data, _fc_arbiter.PTLP_1);
                    end
                endcase
            end
            FC_NP_H   : begin
                case (_fc_arbiter.Command_2)
                    FC_P_H : begin
                        _fc_arbiter.Result <= FC_Hdr_Hdr_Check_Update(CL_NonPosted_Hdr, CC_NonPosted_Hdr, CL_Posted_Hdr, CC_Posted_Hdr);
                    end 
                    FC_P_D : begin
                        _fc_arbiter.Result <= FC_Hdr_Data_Check_Update(CL_NonPosted_Hdr, CC_NonPosted_Hdr, CL_Posted_Hdr, CL_Posted_Data, CC_Posted_Hdr, CC_Posted_Data, _fc_arbiter.PTLP_2);
                    end 
                    FC_NP_H : begin
                        _fc_arbiter.Result <= FC_Hdr_Check_Update(CL_NonPosted_Hdr, CC_NonPosted_Hdr);
                    end 
                    FC_NP_D : begin
                        _fc_arbiter.Result <= FC_Hdr_Data_Check_Update(CL_NonPosted_Hdr, CC_NonPosted_Hdr, CL_NonPosted_Hdr, CL_NonPosted_Data, CC_NonPosted_Hdr, CC_NonPosted_Data, _fc_arbiter.PTLP_2);
                    end 
                    FC_CPL_H : begin
                        _fc_arbiter.Result <= FC_Hdr_Hdr_Check_Update(CL_NonPosted_Hdr, CC_NonPosted_Hdr, CL_Completion_Hdr, CC_Completion_Hdr);
                    end 
                    FC_CPL_D : begin
                        _fc_arbiter.Result <= FC_Hdr_Data_Check_Update(CL_NonPosted_Hdr, CC_NonPosted_Hdr, CL_Completion_Hdr, CL_Completion_Data, CC_Completion_Hdr, CC_Completion_Data, _fc_arbiter.PTLP_2);
                    end 
                    default: begin
                        _fc_arbiter.Result <= FC_Hdr_Check_Update(CL_NonPosted_Hdr, CC_NonPosted_Hdr);
                    end
                endcase
            end
            FC_NP_D   : begin
                case (_fc_arbiter.Command_2)
                    FC_P_H : begin
                        _fc_arbiter.Result <= FC_Data_Hdr_Check_Update(CL_NonPosted_Hdr, CL_NonPosted_Data, CC_NonPosted_Hdr, CC_NonPosted_Data, _fc_arbiter.PTLP_1, CL_Posted_Hdr, CC_Posted_Hdr);
                    end 
                    FC_P_D : begin
                        _fc_arbiter.Result <= FC_Data_Data_Check_Update(CL_NonPosted_Hdr, CL_NonPosted_Data, CC_NonPosted_Hdr, CC_NonPosted_Data, _fc_arbiter.PTLP_1, CL_Posted_Hdr, CL_Posted_Data, CC_Posted_Hdr, CC_Posted_Data, _fc_arbiter.PTLP_2);
                    end 
                    FC_NP_H : begin
                        _fc_arbiter.Result <= FC_Data_Hdr_Check_Update(CL_NonPosted_Hdr, CL_NonPosted_Data, CC_NonPosted_Hdr, CC_NonPosted_Data, _fc_arbiter.PTLP_1, CL_NonPosted_Hdr, CC_NonPosted_Hdr);
                    end 
                    FC_NP_D : begin
                        _fc_arbiter.Result <= FC_Data_Check_Update(CL_NonPosted_Hdr, CL_NonPosted_Data, CC_NonPosted_Hdr, CC_NonPosted_Data, _fc_arbiter.PTLP_1);
                    end 
                    FC_CPL_H : begin
                        _fc_arbiter.Result <= FC_Data_Hdr_Check_Update(CL_NonPosted_Hdr, CL_NonPosted_Data, CC_NonPosted_Hdr, CC_NonPosted_Data, _fc_arbiter.PTLP_1, CL_Completion_Hdr, CC_Completion_Hdr);
                    end 
                    FC_CPL_D : begin
                        _fc_arbiter.Result <= FC_Data_Data_Check_Update(CL_NonPosted_Hdr, CL_NonPosted_Data, CC_NonPosted_Hdr, CC_NonPosted_Data, _fc_arbiter.PTLP_1, CL_Completion_Hdr, CL_Completion_Data, CC_Completion_Hdr, CC_Completion_Data, _fc_arbiter.PTLP_2);
                    end 
                    default: begin
                        _fc_arbiter.Result <= FC_Data_Check_Update(CL_NonPosted_Hdr, CL_NonPosted_Data, CC_NonPosted_Hdr, CC_NonPosted_Data, _fc_arbiter.PTLP_1);
                    end
                endcase
            end
            FC_CPL_H   : begin
                case (_fc_arbiter.Command_2)
                    FC_P_H : begin
                        _fc_arbiter.Result <= FC_Hdr_Hdr_Check_Update(CL_Completion_Hdr, CC_Completion_Hdr, CL_Posted_Hdr, CC_Posted_Hdr);
                    end 
                    FC_P_D : begin
                        _fc_arbiter.Result <= FC_Hdr_Data_Check_Update(CL_Completion_Hdr, CC_Completion_Hdr, CL_Posted_Hdr, CL_Posted_Data, CC_Posted_Hdr, CC_Posted_Data, _fc_arbiter.PTLP_2);
                    end 
                    FC_NP_H : begin
                        _fc_arbiter.Result <= FC_Hdr_Hdr_Check_Update(CL_Completion_Hdr, CC_Completion_Hdr, CL_NonPosted_Hdr, CC_NonPosted_Hdr);
                    end 
                    FC_NP_D : begin
                        _fc_arbiter.Result <= FC_Hdr_Data_Check_Update(CL_Completion_Hdr, CC_Completion_Hdr, CL_NonPosted_Hdr, CL_NonPosted_Data, CC_NonPosted_Hdr, CC_NonPosted_Data, _fc_arbiter.PTLP_2);
                    end 
                    FC_CPL_H : begin
                        _fc_arbiter.Result <= FC_Hdr_Check_Update(CL_Completion_Hdr, CC_Completion_Hdr);
                    end 
                    FC_CPL_D : begin
                        _fc_arbiter.Result <= FC_Hdr_Data_Check_Update(CL_Completion_Hdr, CC_Completion_Hdr, CL_Completion_Hdr, CL_Completion_Data, CC_Completion_Hdr, CC_Completion_Data, _fc_arbiter.PTLP_2);
                    end 
                    default: begin
                        _fc_arbiter.Result <= FC_Hdr_Check_Update(CL_Completion_Hdr, CC_Completion_Hdr);
                    end
                endcase
            end
            FC_CPL_D   : begin
                case (_fc_arbiter.Command_2)
                    FC_P_H : begin
                        _fc_arbiter.Result <= FC_Data_Hdr_Check_Update(CL_Completion_Hdr, CL_Completion_Data, CC_Completion_Hdr, CC_Completion_Data, _fc_arbiter.PTLP_1, CL_Posted_Hdr, CC_Posted_Hdr);
                    end 
                    FC_P_D : begin
                        _fc_arbiter.Result <= FC_Data_Data_Check_Update(CL_Completion_Hdr, CL_Completion_Data, CC_Completion_Hdr, CC_Completion_Data, _fc_arbiter.PTLP_1, CL_Posted_Hdr, CL_Posted_Data, CC_Posted_Hdr, CC_Posted_Data, _fc_arbiter.PTLP_2);
                    end 
                    FC_NP_H : begin
                        _fc_arbiter.Result <= FC_Data_Hdr_Check_Update(CL_Completion_Hdr, CL_Completion_Data, CC_Completion_Hdr, CC_Completion_Data, _fc_arbiter.PTLP_1, CL_NonPosted_Hdr, CC_NonPosted_Hdr);
                    end 
                    FC_NP_D : begin
                        _fc_arbiter.Result <= FC_Data_Data_Check_Update(CL_Completion_Hdr, CL_Completion_Data, CC_Completion_Hdr, CC_Completion_Data, _fc_arbiter.PTLP_1, CL_NonPosted_Hdr, CL_NonPosted_Data, CC_NonPosted_Hdr, CC_NonPosted_Data, _fc_arbiter.PTLP_2);
                    end 
                    FC_CPL_H : begin
                        _fc_arbiter.Result <= FC_Data_Hdr_Check_Update(CL_Completion_Hdr, CL_Completion_Data, CC_Completion_Hdr, CC_Completion_Data, _fc_arbiter.PTLP_1, CL_Completion_Hdr, CC_Completion_Hdr);
                    end 
                    FC_CPL_D : begin
                        _fc_arbiter.Result <= FC_Data_Check_Update(CL_Completion_Hdr, CL_Completion_Data, CC_Completion_Hdr, CC_Completion_Data, _fc_arbiter.PTLP_1);
                    end 
                    default: begin
                        _fc_arbiter.Result <= FC_Data_Check_Update(CL_Completion_Hdr, CL_Completion_Data, CC_Completion_Hdr, CC_Completion_Data, _fc_arbiter.PTLP_1);
                    end
                endcase
            end
            default: begin
                _fc_arbiter.Result <= FC_INVALID;
            end
        endcase
    end
end

/* Instantiations */

endmodule: Tx_FC
/*********** END_OF_FILE ***********/
