/********************************************************************/
/* Module Name	: fifo_pop_rd.sv                       		        */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 2/ 4 / 2024					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: -							                        */
/* Summary:  This file includes the fsm responsible for pop from    
             AR FIFO with handling the interface with arbiter       */
/********************************************************************/




// Import package 
import axi_slave_package::*;

module fifo_pop_rd (
    // Global Signal 
    input bit CLK , ARESTn ,

    // Interface with AW FIFO and W FIFO
    // FIFOs_if.pop_rd_atop  rd_fifos_if,
    Sync_FIFO_Interface.DIST_FIFO ar_fifo_if,

    // Interface with mapper
    output bit rd_atop_en, 
    Slave_Internal_Response_if.AR_TO_R                resp_rd_mux_if,

 
    // Interface with arbiter of pcie core
    input  logic  axi_req_rd_grant 

);

request_pop_fsm_rd_state current_state, next_state;

logic [$clog2(ARFIFO_DEPTH) - 1 : 0] ARID ; 
logic [ARUSER_WIDTH - 1 : 0] ARUSER ;


assign ARID    = ar_fifo_if.FIFO_rd_data[AxBURST_WIDTH + ARUSER_WIDTH + AxSIZE_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS) + ADDR_WIDTH + $clog2(ARFIFO_DEPTH) - 1           : AxBURST_WIDTH + ARUSER_WIDTH + AxSIZE_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS) + ADDR_WIDTH  ] ;
assign ARUSER   = ar_fifo_if.FIFO_rd_data[ARUSER_WIDTH - 1                                                                                                             : 0                                                                                                  ] ; // ARUSER from data read from AR FIFO

always_comb begin 
    if ((ARUSER[2:0] == 3'b011) && axi_req_rd_grant) 
       begin 
        resp_rd_mux_if.RID =  ARID ;
        resp_rd_mux_if.RVALID = 1'b1 ;
        resp_rd_mux_if.RRESP =  OKAY;


       end 
     else begin 
       // initial values 
        resp_rd_mux_if.RID = '0  ;
        resp_rd_mux_if.RVALID = 1'b0 ;
        resp_rd_mux_if.RRESP =  INVALID;
     end 

end 






    always_ff @(posedge CLK or negedge ARESTn) begin
            if (!ARESTn) begin 
                current_state <= rd_pop_Idle;
            end 
            else begin 
                current_state <= next_state;
            end 
    end
    /*
        output :    rd_atop_en
                    ARFIFO_rd_en

        Input :     axi_req_rd_grant
                    ARFIFO_rd_data,
                    ARFIFO_empty

*/
    always_comb begin 
        case (current_state)
            rd_pop_Idle : begin 
                        rd_atop_en = 1'b0 ;
                        ar_fifo_if.FIFO_rd_en = 1'b0 ;

                        if (ar_fifo_if.FIFO_empty == 1'b0)
                            begin 
                                    next_state = AR_Pop ;
                                    rd_atop_en = 1'b0 ;
                                    ar_fifo_if.FIFO_rd_en = 1'b1 ;

                            end 
                        else
                        begin 
                                    next_state = rd_pop_Idle ;
                                    rd_atop_en = 1'b0 ;
                                    ar_fifo_if.FIFO_rd_en = 1'b0 ;
                        end
                      end  
            AR_Pop : begin 
                        rd_atop_en = 1'b1 ;
                        ar_fifo_if.FIFO_rd_en = 1'b0 ;

                        if (axi_req_rd_grant )
                            begin 
                                next_state = rd_pop_Idle ;
                                rd_atop_en = 1'b0 ;
                                ar_fifo_if.FIFO_rd_en = 1'b0 ;
                            end 
                        else begin 
                                next_state = AR_Pop ;
                                rd_atop_en = 1'b1 ;
                                ar_fifo_if.FIFO_rd_en = 1'b0 ;
                        end 
                
            end 
        endcase
    end 

endmodule : fifo_pop_rd