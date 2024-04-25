/* Module Name	: mux.sv	                        */
/* Written By	: Mohamed Aladdin             	*/
/* Date			: 04-04-2024					      */
/* Version		: V_1							         */
/* Updates		: -								      */
/* Dependencies	: -								   */
/* Used			: - 							*/
/* Synthesizable: YES                           */
/* Summary : it is transform to 2 write interfaces
into one interface                              */


module slave_internal_response_wr_mux (
    Slave_Internal_Response_if.AW_TO_B                in_1_resp_wr_mux_if, // error
    Slave_Internal_Response_if.AW_TO_B                in_2_resp_wr_mux_if, // posted

    Slave_Internal_Response_if.AW_TO_B                out_resp_wr_mux_if
); 

import axi_slave_package :: * ;


always_comb begin 

    out_resp_wr_mux_if.BVALID = 1'b0;
    out_resp_wr_mux_if.BRESP = INVALID;
    out_resp_wr_mux_if.BID = '0;


     case ({in_1_resp_wr_mux_if.BVALID,in_2_resp_wr_mux_if.BVALID})
         2'b00 : begin 
            out_resp_wr_mux_if.BVALID = 1'b0;
            out_resp_wr_mux_if.BRESP = INVALID;
            out_resp_wr_mux_if.BID = '0; 
         end 
         2'b10 : begin 
            out_resp_wr_mux_if.BVALID = in_2_resp_wr_mux_if.BVALID;
            out_resp_wr_mux_if.BRESP   = in_2_resp_wr_mux_if.BRESP  ;
            out_resp_wr_mux_if.BID    = in_2_resp_wr_mux_if.BID   ;
         end 
         2'b10: begin
            out_resp_wr_mux_if.BVALID = in_1_resp_wr_mux_if.BVALID;
            out_resp_wr_mux_if.BRESP   = in_1_resp_wr_mux_if.BRESP  ;
            out_resp_wr_mux_if.BID    = in_1_resp_wr_mux_if.BID   ;                  
         end
         2'b11: begin
            out_resp_wr_mux_if.BVALID = in_2_resp_wr_mux_if.BVALID;
            out_resp_wr_mux_if.BRESP   = in_2_resp_wr_mux_if.BRESP  ;
            out_resp_wr_mux_if.BID    = in_2_resp_wr_mux_if.BID   ;                   
        end
       endcase
         
end 

endmodule
