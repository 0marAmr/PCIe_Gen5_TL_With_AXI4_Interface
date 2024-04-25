/*****************************************************************************/
/* Module Name	: axi_slave_fsm_wr.sv                     		             
/* Written By	: Mohamed Aladdin Mohamed                                    
/* Date			: 27-03-2024					                             
/* Version		: V2							                             
/* Updates		: -								                             
/* Dependencies	: -								                             
/* Used			: -							                                 
/* Summary:  This file includes the fsm of push request to handle            
/*           the interface between 2 Request Channels and 2 FIFOs            
/*           for Write Only requests. The FSM is triggered by AWvalid        
/* Feature to be added: 
        1 - add that AW request can go before completing W channel beats     

/*****************************************************************************/


        //`include "FIFOs_interface.sv"
        //`include "axi_interface.sv"
        
        
        module axi_push_fsm_wr (
                                // Global Signals //axi_slave_request_push_fsm
                                input  logic axi_clk, ARESTn,
                                // Interface with 2 Write request channels
                                axi_if.axi_slave_request_push_fsm_wr std_wr_push_fsm_if,
                                // FIFO interface for 2 Write request fifos (AW-W)
                                // FIFOs_if.axi_slave_request_push_fsm_wr  wr_fifos_if
                                Sync_FIFO_Interface.SOURCE_FIFO aw_fifo_if,
                                
                                Request_Recorder_if.request_recorder_rdreqport_wr recorder_if,

                                // Interface with Internal Response
                                Slave_Internal_Response_if.AW_TO_B                resp_wr_mux_if,

                                Sync_FIFO_Interface.SOURCE_FIFO w_fifo_if

        );

        
// import the defined package for axi
        import axi_slave_package::*;

            
                    request_push_fsm_wr_state                           current_state ,  next_state ;        
                    logic   [$clog2(AWFIFO_DEPTH ) -1          : 0]     ID;


                    /* Temp Register to store the info in AW channel after accepting it, then we can change it 
                        but actually i store it at the final clock cycle to ensure that the data has been completely recieved. 
                        so the POP fsm can work correctly     
                    */
                    
                    logic [AWFIFO_WIDTH - 1                     : 0 ] aw_req; 
                    
                    
                    
                    //logic                                               write_req_flag, valid_beat, last_beat_flag;


        // assign write_req_flag = ((std_wr_push_fsm_if.AWVALID == 1) && (std_wr_push_fsm_if.AWLEN <= w_fifo_if.FIFO_available) && (!aw_fifo_ifFIFO_full))? 1'b1 : 1'b0 ;
        //assign last_beat_flag = (std_wr_push_fsm_if.WVALID == 1'b1  && std_wr_push_fsm_if.WLAST == 1'b1)? 1'b1 : 1'b0 ; 
        //assign valid_beat = ((std_wr_push_fsm_if.WVALID == 1'b1) )? 1'b1 : 1'b0 ;
        // function to map ID to Tag Uniquely 
                    function  [TAG_WIDTH - 2:0] generate_tag;
                        input [$clog2(AWFIFO_DEPTH) - 1 :0] id;
                        begin
        
                            if (TAG_WIDTH - ($clog2(AWFIFO_DEPTH)) > 1 ) begin
                                // Generate a unique 7-bit tag value based on the (4 or 5 or 6) -bit ID input
                                generate_tag[$clog2(AWFIFO_DEPTH) - 1 :0] = id;
                                generate_tag[TAG_WIDTH - 2 :$clog2(AWFIFO_DEPTH)] = {{4'b0, id} ^ 8'b10101010};
                            end
                            else  begin
                             
                             
                                generate_tag[TAG_WIDTH - 2  :0] = id;
                                
                            end
                        end
                    endfunction
            
            always_ff @(posedge axi_clk or negedge ARESTn) begin
            if (!ARESTn ) begin  
                    // Reset Case
                    current_state           <= wr_Idle;
                    aw_req                  <= 'b0;
            end
            else begin
                    current_state           <= next_state ;

                    if (current_state == wr_Idle &&((std_wr_push_fsm_if.AWVALID == 1) && (std_wr_push_fsm_if.AWLEN <= w_fifo_if.FIFO_available) && (!aw_fifo_if.FIFO_full))) begin
                            aw_req          <= {std_wr_push_fsm_if.AWID,std_wr_push_fsm_if.AWADDR,std_wr_push_fsm_if.AWLEN,std_wr_push_fsm_if.AWSIZE,std_wr_push_fsm_if.AWBURST,std_wr_push_fsm_if.AWUSER} ;
                    end 
        
            end
        end
        
        
        always_comb begin
            // // initial values 
            // resp_wr_mux_if.BID = '0  ;
            // resp_wr_mux_if.BVALID = 1'b0 ;
            // resp_wr_mux_if.BRESP =  INVALID;

            case (current_state)
                wr_Idle : begin 
                // Output Transition 
                        ID                             = 'b0     ;
                        std_wr_push_fsm_if.AWREADY     = 'b0     ;
                        std_wr_push_fsm_if.WREADY      = 'b0     ;
                        aw_fifo_if.FIFO_wr_data        = 'b0     ;
                        aw_fifo_if.FIFO_wr_en          = 'b0     ;
                        w_fifo_if.FIFO_wr_data         = 'b0     ;
                        w_fifo_if.FIFO_wr_en           = 'b0     ;
                        // initial values 
                        resp_wr_mux_if.BID = '0  ;
                        resp_wr_mux_if.BVALID = 1'b0 ;
                        resp_wr_mux_if.BRESP =  INVALID;
                        
                        
                        recorder_if.req_rd_addr_wr = {1'b0 , generate_tag(std_wr_push_fsm_if.AWID)}; 

                // State Transition
                            // Write Request with available space in FIFOs (condition on AWVALID - DATA Required related to available space for WFIFO - available space for AWFIFO)
                        // $display ("%d , %d , %d, %d",std_wr_push_fsm_if.AWVALID,std_wr_push_fsm_if.AWLEN, w_fifo_if.FIFO_available,!aw_fifo_if.FIFO_full   );
/*
                        */
                            if (((std_wr_push_fsm_if.AWVALID == 1) && (std_wr_push_fsm_if.AWLEN <= w_fifo_if.FIFO_available) && (!aw_fifo_if.FIFO_full) && (^std_wr_push_fsm_if.AWUSER[1:0]) && (std_wr_push_fsm_if.AWUSER[2:0] != 3'b110 ) && (~recorder_if.req_rd_data_wr[0]))) begin
                                    // $display ("test next_state");
                                    next_state                     = AW_Push ;
                                    ID                             = std_wr_push_fsm_if.AWID   ;
                            end 
                            else if ( ~ ( (^std_wr_push_fsm_if.AWUSER[1:0]) && (std_wr_push_fsm_if.AWUSER[2:0] != 3'b110 )))
                            begin
                                    next_state      = wr_Idle ;
                                    resp_wr_mux_if.BID = std_wr_push_fsm_if.AWID   ;
                                    resp_wr_mux_if.BVALID = 1'b1 ;
                                    resp_wr_mux_if.BRESP =  SLVERR;
                            end
                            else begin 
                                next_state                     = wr_Idle ;

                            end 

                            // if ((resp_wr_mux_if.BDONE && resp_wr_mux_if.BVALID )) begin 
                            // // initial values 
                            //     resp_wr_mux_if.BID = '0   ;
                            //     resp_wr_mux_if.BVALID = 1'b0 ;
                            //     resp_wr_mux_if.BRESP =  '0 ;
                            // end

                end
                AW_Push : begin

                // Output Transition
                        std_wr_push_fsm_if.AWREADY     = 'b1 ;
                        std_wr_push_fsm_if.WREADY      = 'b0 ;
                        //aw_fifo_if.FIFO_wr_data     = {std_wr_push_fsm_if.AWID,std_wr_push_fsm_if.AWADDR,std_wr_push_fsm_if.AWLEN,std_wr_push_fsm_if.AWSIZE,std_wr_push_fsm_if.AWBURST,std_wr_push_fsm_if.AWUSER} ;
                        aw_fifo_if.FIFO_wr_data     = 'b0 ; 
                        aw_fifo_if.FIFO_wr_en       = 'b0 ;
                        w_fifo_if.FIFO_wr_data      = 'b0 ;
                        w_fifo_if.FIFO_wr_en        = 'b0 ;
                        // initial values 
                        resp_wr_mux_if.BID = '0  ;
                        resp_wr_mux_if.BVALID = 1'b0 ;
                        resp_wr_mux_if.BRESP =  INVALID;
        
                // State Transition
                    if (((std_wr_push_fsm_if.WVALID == 1'b1) ) && (std_wr_push_fsm_if.WID == ID))
                        begin 
                            next_state = W_Push ; // Directly to W_Push, especially once AW came so W come
                        end 
                    else begin 
                        next_state = waiting_beat ;  // Wait for the correct beat of W
                        
                    end 
                end 
                W_Push : begin
                    // initial values 
                    resp_wr_mux_if.BID = '0  ;
                    resp_wr_mux_if.BVALID = 1'b0 ;
                    resp_wr_mux_if.BRESP =  INVALID;
                // State Transition
                            if ( ((std_wr_push_fsm_if.WVALID == 1'b1) ) && (std_wr_push_fsm_if.WID == ID) && std_wr_push_fsm_if.WLAST == 1'b0 ) begin
                                next_state                     = W_Push ;
                                // Output Transition
                                std_wr_push_fsm_if.AWREADY     = 'b0 ;
                                std_wr_push_fsm_if.WREADY      = 'b1 ;
                                aw_fifo_if.FIFO_wr_data     = 'b0 ;
                                aw_fifo_if.FIFO_wr_en       = 'b0 ;
                                w_fifo_if.FIFO_wr_data      = {std_wr_push_fsm_if.WDATA } ;
                                w_fifo_if.FIFO_wr_en        = 'b1 ;
                                
                            end 
                            else if ((std_wr_push_fsm_if.WVALID == 1'b1  && std_wr_push_fsm_if.WLAST == 1'b1) && (std_wr_push_fsm_if.WID == ID) ) begin
                                next_state              = W_Push ;
                                        // Output Transition
                                        std_wr_push_fsm_if.AWREADY     = 'b0 ;
                                        std_wr_push_fsm_if.WREADY      = 'b1 ;
                                        aw_fifo_if.FIFO_wr_data     = {aw_req, std_wr_push_fsm_if.WSTRB } ;
                                        aw_fifo_if.FIFO_wr_en       = 'b1 ;
                                        w_fifo_if.FIFO_wr_data      = {std_wr_push_fsm_if.WDATA } ;
                                        w_fifo_if.FIFO_wr_en        = 'b1 ;
                            end
                            else begin 
                                next_state              = wr_Idle ;
                                        // Output Transition
                                        std_wr_push_fsm_if.AWREADY     = 'b0 ;
                                        std_wr_push_fsm_if.WREADY      = 'b0 ;
                                        aw_fifo_if.FIFO_wr_data     = 'b0 ;
                                        aw_fifo_if.FIFO_wr_en       = 'b0 ;
                                        w_fifo_if.FIFO_wr_data      = 'b0 ;
                                        w_fifo_if.FIFO_wr_en        = 'b0 ;
                            end
                        end
                    waiting_beat : begin 
                        std_wr_push_fsm_if.AWREADY     = 'b0 ;
                        std_wr_push_fsm_if.WREADY      = 'b0 ;
                        aw_fifo_if.FIFO_wr_data     = 'b0 ;
                        aw_fifo_if.FIFO_wr_en       = 'b0 ;
                        w_fifo_if.FIFO_wr_data      = 'b0 ;
                        w_fifo_if.FIFO_wr_en        = 'b0 ;
                        // initial values 
                        resp_wr_mux_if.BID = '0  ;
                        resp_wr_mux_if.BVALID = 1'b0 ;
                        resp_wr_mux_if.BRESP =  INVALID;

                        // State Transition
                    if (((std_wr_push_fsm_if.WVALID == 1'b1) ) && (std_wr_push_fsm_if.WID == ID))
                    begin 
                        next_state = W_Push ; // Directly to W_Push, especially once AW came so W come
                        // Output Transition
                        std_wr_push_fsm_if.AWREADY     = 'b0 ;
                        std_wr_push_fsm_if.WREADY      = 'b1 ;
                        w_fifo_if.FIFO_wr_data      = {std_wr_push_fsm_if.WDATA} ;
                        w_fifo_if.FIFO_wr_en        = 'b1 ;
                        if (std_wr_push_fsm_if.WLAST == 1'b1)
                        begin 
                            aw_fifo_if.FIFO_wr_data     = {aw_req, std_wr_push_fsm_if.WSTRB } ;
                            aw_fifo_if.FIFO_wr_en       = 'b1 ;
                        end 
                        else 
                        begin 
                            aw_fifo_if.FIFO_wr_data     = 'b0 ;
                            aw_fifo_if.FIFO_wr_en       = 'b0 ;
                        end 
                    end 
                else begin 
                    next_state = waiting_beat ; // Directly to W_Push, especially once AW came so W come
                    
                end

                    end 
        
                    
            endcase
        end 
        
        
        endmodule