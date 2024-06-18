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


module wr_interface_mux (
           Request_Recorder_if.wrreqport_request_recorder  write_if,
           Request_Recorder_if.wrreqport_request_recorder  read_if,
           input  logic                                   axi_req_wr_grant,
           input  logic                                   axi_req_rd_grant,         
           // Output 
           Request_Recorder_if.request_recorder_wrreqport  _if
); 

// input  req_wr_en ,
//                                             req_wr_data, 
//                                             req_wr_addr
 always_comb begin 
            // initial values 
            _if.req_wr_en = 1'b0 ;
            _if.req_wr_data = '0 ;
            _if.req_wr_addr = '0 ;
            
            case ({axi_req_wr_grant,axi_req_rd_grant})
                2'b01 : begin 
                    _if.req_wr_en   = read_if.req_wr_en ;
                    _if.req_wr_data = read_if.req_wr_data ;
                    _if.req_wr_addr = read_if.req_wr_addr ;
                end 
                2'b10 : begin 
                    _if.req_wr_en   = write_if.req_wr_en ;
                    _if.req_wr_data = write_if.req_wr_data ;
                    _if.req_wr_addr = write_if.req_wr_addr ;
                end 
                2'b11: begin
                    _if.req_wr_en   = write_if.req_wr_en ;
                    _if.req_wr_data = write_if.req_wr_data ;
                    _if.req_wr_addr = write_if.req_wr_addr ;                    
                end
              endcase
                
 end 

endmodule: wr_interface_mux
