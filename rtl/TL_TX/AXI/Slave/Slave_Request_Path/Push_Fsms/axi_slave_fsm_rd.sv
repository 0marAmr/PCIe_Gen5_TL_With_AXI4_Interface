/********************************************************************/
/* Module Name	: axi_slave_fsm_rd.sv                     		    */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 27-03-2024					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: -							                        */
/* Summary:  This file includes the fsm of push request to handle   */
/*           the interface between 1 Request Channel and 1 FIFO     */
/*  for Read requests. The FSM is triggered by ARVlaid              */
/********************************************************************/


    // import the defined package for axi
    import axi_slave_package::*;

module axi_slave_fsm_rd (
                        // Global Signals
                        input  logic axi_clk, ARESTn,
                        // Interface with Read request channel
                        axi_if.axi_slave_request_push_fsm_rd std_rd_push_fsm_if,
                        // Interface With Request Recorder
                        Request_Recorder_if.request_recorder_rdreqport_rd recorder_if,
                        
                        // Interface with Internal Response
                        Slave_Internal_Response_if.AR_TO_R                resp_rd_mux_if,
                        
                        // FIFO interface for Read request fifo (AR)
                        //FIFOs_if.axi_slave_request_push_fsm_rd  rd_fifos_if
                        Sync_FIFO_Interface.SOURCE_FIFO ar_fifo_if
);


    
    request_push_fsm_rd_state current_state ,  next_state ;

    // function to map ID to Tag Uniquely 
    function  [TAG_WIDTH - 2:0] generate_tag;
        input [$clog2(AWFIFO_DEPTH) - 1 :0] id;
        begin

            if (TAG_WIDTH - ($clog2(AWFIFO_DEPTH)) > 1'b1 ) begin
                // Generate a unique 7-bit tag value based on the (4 or 5 or 6) -bit ID input
                generate_tag[$clog2(AWFIFO_DEPTH) - 1 :0] = id;
                generate_tag[TAG_WIDTH - 2 :$clog2(AWFIFO_DEPTH)] = {{4'b0, id} ^ 8'b10101010};
            end
            else  begin
                generate_tag[TAG_WIDTH - 2 :0] = id;
            end
        end
    endfunction

    always_ff @(posedge axi_clk or negedge ARESTn) begin
    if (!ARESTn ) begin  
            // Reset Case
            current_state <= rd_Idle;
    end
    else begin
            current_state <= next_state ;
    end
end

always_comb begin

    case (current_state)
        rd_Idle : begin 
                    // Assigning values to all output signals of FSM in idle state
                    std_rd_push_fsm_if.ARREADY     = 'b0 ;
                    ar_fifo_if.FIFO_wr_data     = 'b0 ;
                    ar_fifo_if.FIFO_wr_en       = 'b0 ;
                    
                    // initial values 
                    resp_rd_mux_if.RID = '0  ;
                    resp_rd_mux_if.RVALID = 1'b0 ;
                    resp_rd_mux_if.RRESP =  INVALID;
                    
                    recorder_if.req_rd_addr_rd = {1'b1 , generate_tag(std_rd_push_fsm_if.ARID)}; 
                    // State Transition
                    // condition for recorder is always is related to address for read not write so rd_add[7]=1 is a must condition 
                    // USER[2:0]
                    // 001  >>  Memrd 32bit address
                    // 101  >>  Memrd 64 bit address
                    // 010  >>  i/o
                    // 011  >> message
                    if ((std_rd_push_fsm_if.ARVALID == 1) && (!ar_fifo_if.FIFO_full) && (~recorder_if.req_rd_data_rd[0] ) && 
                        ((std_rd_push_fsm_if.ARUSER[2:0] == 3'b001) || 
                         (std_rd_push_fsm_if.ARUSER[2:0] == 3'b101) || 
                         (std_rd_push_fsm_if.ARUSER[2:0] == 3'b010) ||
                         (std_rd_push_fsm_if.ARUSER[2:0] == 3'b011))) begin
                        next_state = AR_Push;
                    end 
                    else if (~((std_rd_push_fsm_if.ARUSER[2:0] == 3'b001) || 
                    (std_rd_push_fsm_if.ARUSER[2:0] == 3'b101) || 
                    (std_rd_push_fsm_if.ARUSER[2:0] == 3'b010) ||
                    (std_rd_push_fsm_if.ARUSER[2:0] == 3'b011))) begin 
                        
                        next_state = rd_Idle;
                    resp_rd_mux_if.RID = std_rd_push_fsm_if.ARID  ;
                    resp_rd_mux_if.RVALID = 1'b1 ;
                    resp_rd_mux_if.RRESP =  SLVERR;
                    
                        
                    end
                    else begin 
                        next_state = rd_Idle;
                        // initial values 
                    resp_rd_mux_if.RID = '0  ;
                    resp_rd_mux_if.RVALID = 1'b0 ;
                    resp_rd_mux_if.RRESP =  INVALID;
                    
                    end 
        end
        
        AR_Push : begin
                    // Assigning values to all output signals of FSM in W_Push state
                    std_rd_push_fsm_if.ARREADY     = 'b1 ;
                    ar_fifo_if.FIFO_wr_data     = {std_rd_push_fsm_if.ARID, std_rd_push_fsm_if.ARADDR, std_rd_push_fsm_if.ARLEN, std_rd_push_fsm_if.ARSIZE, std_rd_push_fsm_if.ARBURST, std_rd_push_fsm_if.ARUSER } ;
                    ar_fifo_if.FIFO_wr_en       = 'b1 ;
                    // initial values 
                    resp_rd_mux_if.RID = '0  ;
                    resp_rd_mux_if.RVALID = 1'b0 ;
                    resp_rd_mux_if.RRESP =  INVALID;
                    
                    
                    
                    // State Transition
                    // if ((std_rd_push_fsm_if.ARVALID == 1) && (!ar_fifo_if.FIFO_full)) begin    // Check this on testbench !!!!
                    //     next_state = AR_Push;
                    // end 
                    // else begin 
                    //     next_state = rd_Idle;
                    // end

                    
                        next_state = rd_Idle;
                    
        end 
        default : begin 
                    // Default Values
                    std_rd_push_fsm_if.ARREADY     = 'b0 ;
                    ar_fifo_if.FIFO_wr_data     = 'b0 ;
                    ar_fifo_if.FIFO_wr_en       = 'b0 ;
                    next_state                     = rd_Idle;
                    // initial values 
                    resp_rd_mux_if.RID = '0  ;
                    resp_rd_mux_if.RVALID = 1'b0 ;
                    resp_rd_mux_if.RRESP =  INVALID;
                    
        end 
    endcase
end

endmodule