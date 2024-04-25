/* Module Name	: mux.sv	                   */
/* Written By	: Mohamed Aladdin             	*/
/* Date			: 04-04-2024					*/
/* Version		: V_1							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: - 							*/
/* Synthesizable: YES                           */
/* Summary : it is transform to 2 write interfaces
into one interface                              */


module slave_internal_response_rd_mux (
    Slave_Internal_Response_if.AR_TO_R                in_1_resp_rd_mux_if, // error
    Slave_Internal_Response_if.AR_TO_R                in_2_resp_rd_mux_if, // posted

    Slave_Internal_Response_if.AR_TO_R                out_resp_rd_mux_if
); 

import axi_slave_package :: * ;

always_comb begin 

    out_resp_rd_mux_if.RVALID = 1'b0;
    out_resp_rd_mux_if.RRESP = INVALID;
    out_resp_rd_mux_if.RID = '0;


     case ({in_1_resp_rd_mux_if.RVALID,in_2_resp_rd_mux_if.RVALID})
         2'b00 : begin 
            out_resp_rd_mux_if.RVALID = 1'b0;
            out_resp_rd_mux_if.RRESP = INVALID;
            out_resp_rd_mux_if.RID = '0; 
         end 
         2'b10 : begin 
            out_resp_rd_mux_if.RVALID = in_2_resp_rd_mux_if.RVALID;
            out_resp_rd_mux_if.RRESP   = in_2_resp_rd_mux_if.RRESP  ;
            out_resp_rd_mux_if.RID    = in_2_resp_rd_mux_if.RID   ;
         end 
         2'b10: begin
            out_resp_rd_mux_if.RVALID = in_1_resp_rd_mux_if.RVALID;
            out_resp_rd_mux_if.RRESP   = in_1_resp_rd_mux_if.RRESP  ;
            out_resp_rd_mux_if.RID    = in_1_resp_rd_mux_if.RID   ;                  
         end
         2'b11: begin
            out_resp_rd_mux_if.RVALID = in_2_resp_rd_mux_if.RVALID;
            out_resp_rd_mux_if.RRESP   = in_2_resp_rd_mux_if.RRESP  ;
            out_resp_rd_mux_if.RID    = in_2_resp_rd_mux_if.RID   ;                   
        end
       endcase
         
end 

endmodule: slave_internal_response_rd_mux
