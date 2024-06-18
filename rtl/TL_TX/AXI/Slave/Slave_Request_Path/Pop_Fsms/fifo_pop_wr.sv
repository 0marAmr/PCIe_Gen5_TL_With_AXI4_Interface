/********************************************************************/
/* Module Name	: fifo_pop_wr.sv                       		        */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 2/ 4 / 2024					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: -							                        */
/* Summary:  This file includes the fsm responsible for pop from 
AW and W FIFOs with handling the interface with arbiter              */
/********************************************************************/


// Import package 
import axi_slave_package::*;


module fifo_pop_wr (
    // Global Signal 
    input bit CLK , ARESTn ,

    // Interface with AW FIFO and W FIFO
    //FIFOs_if.pop_wr_atop  wr_fifos_if,
    Sync_FIFO_Interface.DIST_FIFO aw_fifo_if,
    Sync_FIFO_Interface.DIST_FIFO w_fifo_if,

    // Interface with mapper
    output bit wr_atop_en, 
    
    // Interface with Internal Response
    Slave_Internal_Response_if.AW_TO_B                resp_wr_mux_if,

 
    // Interface with arbiter of pcie core
    input  logic  axi_req_wr_grant, 
    output logic [(AXI_MAX_NUM_BYTES * 8) - 1 : 0] axi_req_data 

);

logic    [ AWUSER_WIDTH - 1 : 0 ] AWUser ; 
logic    [ID_WIDTH - 1 : 0 ] AWID ;

// logic                                          err_reporting_flag ;
logic [ $clog2(AXI_MAX_NUM_TRANSFERS) - 1 : 0] AWLEN ; 
assign AWLEN   = aw_fifo_if.FIFO_rd_data[AxBURST_WIDTH + AWUSER_WIDTH + AxSIZE_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS) - 1 + WSTRB_WIDTH                                 : AxBURST_WIDTH + AWUSER_WIDTH + AxSIZE_WIDTH + WSTRB_WIDTH                                    ] ; 

logic [ $clog2(AXI_MAX_NUM_TRANSFERS) - 1 : 0] num_cycles ; 
request_pop_fsm_wr_state   current_state, next_state; 




assign AWUser  = aw_fifo_if.FIFO_rd_data[AWUSER_WIDTH - 1  + WSTRB_WIDTH                                                                                               : WSTRB_WIDTH                                                                                        ] ;         // AWUSER from data read from AW FIFO
assign AWID    = aw_fifo_if.FIFO_rd_data[AxBURST_WIDTH + AWUSER_WIDTH + AxSIZE_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS) + ADDR_WIDTH + $clog2(AWFIFO_DEPTH) - 1 + WSTRB_WIDTH : AxBURST_WIDTH + AWUSER_WIDTH + AxSIZE_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS) + ADDR_WIDTH + WSTRB_WIDTH ] ;

always_comb begin 
               if ((AWUser[1:0] == 2'b01) && axi_req_wr_grant) 
                  begin 
                    resp_wr_mux_if.BID =  AWID ;
                    resp_wr_mux_if.BVALID = 1'b1 ;
                    resp_wr_mux_if.BRESP =  OKAY;


                  end 
                else begin 
                  // initial values 
                    resp_wr_mux_if.BID = '0  ;
                    resp_wr_mux_if.BVALID = 1'b0 ;
                    resp_wr_mux_if.BRESP =  INVALID;
                end 

end 

// typedef enum reg[1:0] {wr_pop_Idle = 2'b00 , AW_Pop = 2'b10 , W_Pop = 2'b11 }                  request_pop_fsm_wr_state ;   // state used in fsm of write requests
// typedef enum reg      {rd_Idle = 1'b0 , AR_Pop = 1'b1 }                                    request_pop_fsm_rd_state ;   // state used in fsm of read requests

 

always_ff @(posedge CLK or negedge ARESTn) begin
    if (!ARESTn ) begin  
            // Reset Case
            current_state           <= wr_pop_Idle;
            num_cycles              <= 'b0    ;
    end
    else begin
            current_state           <= next_state ;
            if (current_state == AW_Pop) begin 
                num_cycles <= (AWLEN + 1);  // Load 
            end
            else if ((current_state == W_Pop) )begin 
                if ((num_cycles != 1'b0) )
                    num_cycles <= num_cycles - 1'b1 ;
            end
            else begin 
                num_cycles <= 1'b0;  
            end
    end
end



always_comb begin
            next_state = wr_pop_Idle;
            wr_atop_en = 1'b0;
            axi_req_data = 'b0 ;
            aw_fifo_if.FIFO_rd_en =  1'b0 ;
            w_fifo_if.FIFO_rd_en =   1'b0 ;
            
                case (current_state)
                        wr_pop_Idle : begin  
                                if (!aw_fifo_if.FIFO_empty) begin 
                                    next_state = AW_Pop;
                                    aw_fifo_if.FIFO_rd_en =  1'b1 ;
                                    w_fifo_if.FIFO_rd_en =   1'b1 ;
                                end 
                                else  begin
                                    next_state = wr_pop_Idle;
                                end
                        end 
                        AW_Pop : begin 
                                    wr_atop_en = 1'b1;
                                    axi_req_data = w_fifo_if.FIFO_rd_data;
                                    aw_fifo_if.FIFO_rd_en =  1'b0 ;
                                    w_fifo_if.FIFO_rd_en =   1'b0 ;

                                    if (axi_req_wr_grant == 1'b1 &&  AWLEN != 1'b0) begin
                                            next_state = W_Pop ;
                                            w_fifo_if.FIFO_rd_en =   1'b1 ;


                                    end 
                                    else if (axi_req_wr_grant == 1'b1 &&  AWLEN == 1'b0) begin
                                            next_state = wr_pop_Idle;
                                    end 
                                    else begin  
                                        next_state = AW_Pop ;
                                    end 
                                    end
                        W_Pop : begin
                                    if ( num_cycles!= 1'b1) begin
                                        next_state = W_Pop ;
                                        wr_atop_en = 1'b1;
                                        axi_req_data = w_fifo_if.FIFO_rd_data;
                                        aw_fifo_if.FIFO_rd_en =  1'b0 ;
                                        w_fifo_if.FIFO_rd_en =   1'b1 ;
                                    end 
                                    else  begin
                                        next_state = wr_pop_Idle; 
                                        wr_atop_en = 1'b1;
                                        axi_req_data = w_fifo_if.FIFO_rd_data;
                                        aw_fifo_if.FIFO_rd_en =  1'b0 ;
                                        w_fifo_if.FIFO_rd_en =   1'b0 ;
                                    end 
                                end
                endcase
            end 
endmodule : fifo_pop_wr
