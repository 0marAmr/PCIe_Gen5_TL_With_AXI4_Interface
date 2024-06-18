/* Module Name	: Request_Recoder.sv	        */
/* Written By	: Mohamed Aladdin             	*/
/* Date			: 04-04-2024					*/
/* Version		: V_1							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: - 							*/
/* Synthesizable: YES                           */
/* Summary : it is a dual port ram used for     */
/*           record the request and read        */


// import the defined package for axi
import axi_slave_package::*;

module Request_Recorder (  
                       // Global Signals
                       input bit clk, ARESTn ,

                       // Interface of request recorder for request path push fsm
                       Request_Recorder_if.request_recorder_rdreqport_wr rdreqport_if_wr,
                       Request_Recorder_if.request_recorder_rdreqport_rd rdreqport_if_rd,

                       
                       // Interface of request recorder for request path A2P Mapper
                       Request_Recorder_if.wrreqport_request_recorder wrreqport_if,
                       Request_Recorder_if.REQUEST_RECORDER_P2A       respport_if
);



logic [REQUESTER_RECORDER_WIDTH - 1 : 0] MEM [REQUESTER_RECORDER_DEPTH - 1: 0] ;


// Read Request Port
assign  rdreqport_if_wr.req_rd_data_wr = MEM[(rdreqport_if_wr.req_rd_addr_wr[REQUESTER_RECORDER_ADDR_WIDTH - 1 : 0])];

// Read Request Port
assign  rdreqport_if_rd.req_rd_data_rd = MEM[(rdreqport_if_rd.req_rd_addr_rd[REQUESTER_RECORDER_ADDR_WIDTH - 1 : 0])];

// Read Response Port
assign  respport_if.resp_rd_data = MEM[respport_if.resp_rd_addr];

// for Request Ports 
 always_ff @(posedge clk or negedge ARESTn) begin 
        if (!ARESTn) begin 
            for (int i = 0 ; i < REQUESTER_RECORDER_DEPTH ; i++) begin  
                  MEM[i] <= 'b0;
            end 
        end 
        else 
        begin 
            // Write Port
            case ({wrreqport_if.req_wr_en, respport_if.resp_wr_en }) 
                2'b01 : begin 
                    MEM[respport_if.resp_wr_addr] <= respport_if.resp_wr_data ;

                end 
                2'b10 : begin 
                    MEM[wrreqport_if.req_wr_addr] <= wrreqport_if.req_wr_data ;          
                end     
                2'b11 : begin 
                        if (wrreqport_if.req_wr_addr == respport_if.resp_wr_addr )
                            begin 
                                MEM[wrreqport_if.req_wr_addr] <= wrreqport_if.req_wr_data ;           
                            end
                        else begin 
                            MEM[wrreqport_if.req_wr_addr] <= wrreqport_if.req_wr_data ;          
                            MEM[respport_if.resp_wr_addr] <= respport_if.resp_wr_data ;
                        end
                end 
            endcase 

             
        end 
 end 



endmodule





