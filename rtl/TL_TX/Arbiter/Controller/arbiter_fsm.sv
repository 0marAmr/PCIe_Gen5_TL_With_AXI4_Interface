/********************************************************************/
/* Module Name	: arbiter_fsm.sv                          		    */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 10-04-2024			                            */
/* Version		: V1					                            */
/* Updates		: -					                                */
/* Dependencies	: -						                            */
/* Used			: in Arbiter Modules                                */
/* Summary:  This file includes controller of arbiter               */
/********************************************************************/

/*
    Acknowledgement :  Make the HDR Coming from Rx Side is a type of struct as slave
                       Ensure that the layout of bits is FMT, TYPE from MSB
                       Ensure that Msg 3 DW !!!!!!
*/

// import package
import Tx_Arbiter_Package::*;
import data_frag_package::*;
import axi_slave_package::*;


module arbiter_fsm (
					// Global signals 
					   input bit clk,
					   input bit arst,

					   // Interface with sequence recorder
					   Tx_Arbiter_Sequence_Recorder.ARBITER_FSM_SEQUENCE_RECORDER recorder_if,

					   // Interface with Ordering 
					   ordering_if.ARBITER_ORDERING_IF ordering_if,

					   // Interface with Flow Control
					   Tx_FC_Interface.ARBITER_FC fc_if,

					   // Interface with FIFO of Data Fragementation
					   buffer_frag_interface.arbiter_buffer buffer_if,
				    // Interface with Data Fragmentation Block 
						input logic 			Buffer_Ready, // this signal means that we can send the following TLP in next cycle
                        input logic             start_fragment,
                        output logic            TLP_stored,
                    // Interface with Slave (Rd Request and Wr Request)
                        output logic             axi_req_wr_grant,
                        output logic             axi_req_rd_grant,
                        // Output of mapper for write
                        input tlp_header_t     axi_wrreq_hdr,
                        // Output of mapper for read
                        input tlp_header_t     axi_rdreq_hdr,
                        // Output of POP FSM : output from slave to Tx Arbiter (Data for write request)
                        input logic [AXI_MAX_NUM_BYTES * 8 - 1 : 0] axi_req_data,
    // -------------------------------------------------------------------- 
                    // Interface with Master
                        output logic             axi_master_grant,
                        // Output of mapper for master
                        input logic [3*DW - 1 : 0]     axi_master_hdr,                          
                        // Data in case of COMPD
                        input logic [AXI_MAX_NUM_BYTES * 8 - 1 : 0] axi_comp_data,  
    // ---------------------------------------------------------------------                          
                    // Interface with Rx Router
                        output logic                    rx_router_grant,
                        
                        input logic [3*DW - 1 : 0]      rx_router_msg_hdr, // all msgs supported 3Dw
                        input logic [3*DW - 1 : 0]      rx_router_comp_hdr,
                        
                        // Data in case of COMPD
                        input logic [1*DW  - 1 : 0]     rx_router_data      
    // -------------------------------------------------------------------------
                    );
    // State Definition 
    arbiter_state current_state,next_state ;
    
    // Internal Signals 
    Tx_Arbiter_Sources_t source_1,source_2 ; 
    bool_t ordering_result ;
    FC_result_t FC_result ; 

    logic [1:0] No_rd_loc_seq ; // No. of read locations from sequence recorder
	logic [5:0] tlp1_no_cycles, count_tlp1 ; // Maximum number of cycle is 32 cycle.
    logic [5:0] tlp2_no_cycles, count_tlp2 ;
	logic one_req_on_pipe, two_req_on_pipe, TLP1_stroing_completed, TLP2_stroing_completed ; 
    logic [3 * DW - 1 : 0] registered_data; 
    // this function is reponsible for asserting the signals for flow control block
    function FC_result_t FC_function ( 
                        input Tx_Arbiter_Sources_t source_1 , 
                        input Tx_Arbiter_Sources_t source_2,
                        input logic rd_1_or_2); // 0 --> rd mode = 1 but 1 --> rd mode = 2
            FC_result_t FC_result ; 
        case (source_1)
            A2P_1: begin 
                fc_if.Command_1 = axi_wrreq_hdr.Length; 
                if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                    fc_if.PTLP_1 = FC_P_D; 
                end 
                else begin 
                    fc_if.PTLP_1 = FC_NP_D;
                end 
                if (rd_1_or_2) begin  // in this case there is another request.
                    case (source_2) 
                        A2P_2: begin 
								if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
									fc_if.PTLP_2 = FC_P_H ;
									fc_if.Command_2 = '0 ;
								else begin 
									fc_if.PTLP_2 = FC_NP_H ;
									fc_if.Command_2 = '0 ;
								end 
							end 
                        MASTER: begin 
                            if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                fc_if.Command_2 = FC_CPL_D  ;
                                fc_if.PTLP_2 = axi_master_hdr[ 2*DW + 9 : 2*DW] ;

                            end 
                            else begin  // COMP
                                fc_if.Command_2 = FC_CPL_H  ;
                                fc_if.PTLP_2 = '0 ;
                            end
                        end 
                        RX_ROUTER_CFG: begin 
                            if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                fc_if.Command_2 = FC_CPL_D  ;
                                fc_if.PTLP_2 = rx_router_comp_hdr[ 2*DW + 9 : 2*DW] ;

                            end 
                            else begin  // COMP
                                fc_if.Command_2 = FC_CPL_H  ;
                                fc_if.PTLP_2 = '0 ;
                            end
                        end 
                        RX_ROUTER_ERR: begin  // Check the harmonization for all ERRs in FC, must check MSG + COMP
                            fc_if.PTLP_2 = FC_ERR ; // I want to Modify it to include P and Comp
                            fc_if.Command_2 = '0;
                        end  
                    endcase
                end 
                else begin    
                    fc_if.PTLP_2 = '0;
                    fc_if.Command_2 = FC_DEFAULT; 
                end
            end 
            end 
            A2P_2: begin 
				if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
							fc_if.PTLP_1 = FC_P_H ;
							fc_if.Command_1 = '0 ;
				else begin 
							fc_if.PTLP_1 = FC_NP_H ;
							fc_if.Command_1 = '0 ;
						end
				if (rd_1_or_2) begin  // in this case there is another request.
                    case (source_2) 
                        A2P_1: begin 
								fc_if.Command_2 = axi_wrreq_hdr.Length; 
								if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
									fc_if.PTLP_2 = FC_P_D; 
								end 
								else begin 
									fc_if.PTLP_2 = FC_NP_D;
								end 
							end 
                        MASTER: begin 
                            if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                fc_if.Command_2 = FC_CPL_D  ;
                                fc_if.PTLP_2 = axi_master_hdr[ 2*DW + 9 : 2*DW] ;

                            end 
                            else begin  // COMP
                                fc_if.Command_2 = FC_CPL_H  ;
                                fc_if.PTLP_2 = '0 ;
                            end
                        end 
                        RX_ROUTER_CFG: begin 
                            if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                fc_if.Command_2 = FC_CPL_D  ;
                                fc_if.PTLP_2 = rx_router_comp_hdr[ 2*DW + 9 : 2*DW] ;

                            end 
                            else begin  // COMP
                                fc_if.Command_2 = FC_CPL_H  ;
                                fc_if.PTLP_2 = '0 ;
                            end
                        end 
                        RX_ROUTER_ERR: begin  // Check the harmonization for all ERRs in FC, must check MSG + COMP
                            fc_if.PTLP_2 = FC_ERR ; // I want to Modify it to include P and Comp
                            fc_if.Command_2 = '0;
                        end  
                    endcase
                end 
                else begin    
                    fc_if.PTLP_2 = '0;
                    fc_if.Command_2 = FC_DEFAULT; 
                end 
            end 
            end 
            MASTER: begin 
				if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                fc_if.Command_1 = FC_CPL_D  ;
                                fc_if.PTLP_1 = axi_master_hdr[ 2*DW + 9 : 2*DW] ;

                            end 
				else begin  // COMP
                                fc_if.Command_1 = FC_CPL_H  ;
                                fc_if.PTLP_1 = '0 ;
                            end
				if (rd_1_or_2) begin  // in this case there is another request.
                    case (source_2) 
                        A2P_1: begin 
								fc_if.Command_2 = axi_wrreq_hdr.Length; 
								if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
									fc_if.PTLP_2 = FC_P_D; 
								end 
								else begin 
									fc_if.PTLP_2 = FC_NP_D;
								end 
							end 
                        A2P_2: begin 
                            if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
							fc_if.PTLP_1 = FC_P_H ;
							fc_if.Command_2 = '0 ;
                            end 
							else begin 
							fc_if.PTLP_1 = FC_NP_H ;
							fc_if.Command_2 = '0 ;
							end
                        end 
                        RX_ROUTER_CFG: begin 
                            if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                fc_if.Command_2 = FC_CPL_D  ;
                                fc_if.PTLP_2 = rx_router_comp_hdr[ 2*DW + 9 : 2*DW] ;
                            end 
                            else begin  // COMP
                                fc_if.Command_2 = FC_CPL_H  ;
                                fc_if.PTLP_2 = '0 ;
                            end
                        end 
                        RX_ROUTER_ERR: begin  // Check the harmonization for all ERRs in FC, must check MSG + COMP
                            fc_if.PTLP_2 = FC_ERR ; // I want to Modify it to include P and Comp
                            fc_if.Command_2 = '0;
                        end  
                    endcase
                end 
                else begin    
                    fc_if.PTLP_2 = '0;
                    fc_if.Command_2 = FC_DEFAULT; 
                end 			
			end 
            RX_ROUTER_CFG: begin 
							if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                fc_if.Command_1 = FC_CPL_D  ;
                                fc_if.PTLP_1 = rx_router_comp_hdr[ 2*DW + 9 : 2*DW] ;
                            end 
                            else begin  // COMP
                                fc_if.Command_1 = FC_CPL_H  ;
                                fc_if.PTLP_1 = '0 ;
                            end	
				            if (rd_1_or_2) begin  // in this case there is another request.
                                case (source_2) 
                                A2P_1: begin 
								fc_if.Command_2 = axi_wrreq_hdr.Length; 
								if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
									fc_if.PTLP_2 = FC_P_D; 
								end 
								else begin 
									fc_if.PTLP_2 = FC_NP_D;
								end 
							    end 
                                MASTER: begin 
                            if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                fc_if.Command_2 = FC_CPL_D  ;
                                fc_if.PTLP_2 = axi_master_hdr[ 2*DW + 9 : 2*DW] ;

                            end 
                            else begin  // COMP
                                fc_if.Command_2 = FC_CPL_H  ;
                                fc_if.PTLP_2 = '0 ;
                            end
                        end 
                        A2P_2: begin 
                            if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
							fc_if.PTLP_2 = FC_P_H ;
							fc_if.Command_2 = '0 ;
                            end 
							else begin 
							fc_if.PTLP_2 = FC_NP_H ;
							fc_if.Command_2 = '0 ;
						end
                        end 
                        RX_ROUTER_ERR: begin  // Check the harmonization for all ERRs in FC, must check MSG + COMP
                            fc_if.PTLP_2 = FC_ERR ; // I want to Modify it to include P and Comp
                            fc_if.Command_2 = '0;
                        end  
                    endcase
                end 
                else begin    
                    fc_if.PTLP_2 = '0;
                    fc_if.Command_2 = FC_DEFAULT; 
                end 
            end 
            RX_ROUTER_ERR: begin 
							fc_if.PTLP_1 = FC_ERR ; 
                            fc_if.Command_1 = '0;
							if (rd_1_or_2) begin  // in this case there is another request.
                    case (source_2) 
                        A2P_1: begin 
								fc_if.Command_2 = axi_wrreq_hdr.Length; 
								if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
									fc_if.PTLP_2 = FC_P_D; 
								end 
								else begin 
									fc_if.PTLP_2 = FC_NP_D;
								end 
							end 
                        MASTER: begin 
                            if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                fc_if.Command_2 = FC_CPL_D  ;
                                fc_if.PTLP_2 = axi_master_hdr[ 2*DW + 9 : 2*DW] ;

                            end 
                            else begin  // COMP
                                fc_if.Command_2 = FC_CPL_H  ;
                                fc_if.PTLP_2 = '0 ;
                            end
                        end 
                        RX_ROUTER_CFG: begin 
                            if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                fc_if.Command_2 = FC_CPL_D  ;
                                fc_if.PTLP_2 = rx_router_comp_hdr[ 2*DW + 9 : 2*DW] ;

                            end 
                            else begin  // COMP
                                fc_if.Command_2 = FC_CPL_H  ;
                                fc_if.PTLP_2 = '0 ;
                            end
                        end 
                        A2P_2: begin  // Check the harmonization for all ERRs in FC, must check MSG + COMP
                            if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
							fc_if.PTLP_2 = FC_P_H ;
							fc_if.Command_2 = '0 ;
                            end 
							else begin 
							fc_if.PTLP_2 = FC_NP_H ;
							fc_if.Command_2 = '0 ;
						end
                        end  
                    endcase
                end 
                else begin    
                    fc_if.PTLP_2 = '0;
                    fc_if.Command_2 = FC_DEFAULT; 
                end 
            end 			
        endcase
		FC_result = fc_if.Result ;        
        return FC_result; 
 endfunction 

    // Function to check on ordering block and get the result of ordering block. 
    function bool_t ordering_function (
                                input Tx_Arbiter_Sources_t source_1 , 
                                input Tx_Arbiter_Sources_t source_2 );
                                
        bool_t result ; 
        // case statement: for all types of sources and passing the proper inputs to ordering block
        case ({source_1,source_2}) 
            {A2P_1,A2P_2}   : begin 
                            // Posted Condition for MemWr either 64-bit address or 32-bit address
                            if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                                ordering_if.first_trans = Posted_Req ; 
                            end 
                            else begin 
                                ordering_if.first_trans = Non_Posted_Req ; 
                            end
                            // Non-Posted Request (Msg)
                            if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                                ordering_if.second_trans = Posted_Req ;
                            end 
                            else begin 
                                ordering_if.second_trans = Non_Posted_Req ;
                            end
                            
                            ordering_if.first_RO = axi_wrreq_hdr.Attr[1];
                            ordering_if.first_IDO = axi_wrreq_hdr.ATTR;
                            ordering_if.first_trans_ID = axi_wrreq_hdr.Requester_ID ;

                            ordering_if.comp_typ = 3'b000;
                            
                            ordering_if.second_RO = axi_rdreq_hdr.Attr[1];
                            ordering_if.second_IDO = axi_rdreq_hdr.ATTR ;
                            ordering_if.second_trans_ID = axi_rdreq_hdr.Requester_ID ;
            end 
            {A2P_1,MASTER}   : begin 
                             // Posted Condition for MemWr either 64-bit address or 32-bit address
                                if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                                    ordering_if.first_trans = Posted_Req ; 
                                end 
                                else begin 
                                    ordering_if.first_trans = Non_Posted_Req ; 
                                end
                                ordering_if.first_RO = axi_wrreq_hdr.Attr[1];
                                ordering_if.first_IDO = axi_wrreq_hdr.ATTR;
                                ordering_if.first_trans_ID = axi_wrreq_hdr.Requester_ID ;
                                
                                ordering_if.second_trans = Comp ;
                                ordering_if.second_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                        
                                ordering_if.second_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                                ordering_if.second_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                ordering_if.comp_typ = 3'b000; // I can't Determine unless Cfg wr due to different paths                                
                                /*  
                                    95 : 0  -->  95 - 16 - 3 = 76  && 95 - 8 - 6 = 81 && [63:48]
                                    15 : 0 , 31 : 16 , 47 : 32 , 63 : 48 
                                */ 
            end 
            {A2P_1,RX_ROUTER_CFG}   : begin 
                            // Posted Condition for MemWr either 64-bit address or 32-bit address
                            if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                                ordering_if.first_trans = Posted_Req ; 
                            end 
                            else begin 
                                ordering_if.first_trans = Non_Posted_Req ; 
                            end
                            ordering_if.first_RO = axi_wrreq_hdr.Attr[1];
                            ordering_if.first_IDO = axi_wrreq_hdr.ATTR;
                            ordering_if.first_trans_ID = axi_wrreq_hdr.Requester_ID ;
                            
                            
                            ordering_if.second_trans = Comp ;
                            ordering_if.second_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                            ordering_if.second_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                            ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                
                            if ((rx_router_comp_hdr[3*DW - 1: 3*DW - 3] == 3'b000)&&(rx_router_comp_hdr[1*DW + 15 : 1 *DW + 13 ] == 3'b000)) // this means the compeletions are comp, successfull and cfgwr
                                begin 
                                        ordering_if.comp_typ = 3'b010; // CFG Wr
                                end 
                            else begin 
                                        ordering_if.comp_typ = 3'b000; // not CFG Wr
                                end                                                     
            end 
            {A2P_1,RX_ROUTER_ERR}   : begin 
                            // Posted Condition for MemWr either 64-bit address or 32-bit address
                            if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                                ordering_if.first_trans = Posted_Req ; 
                            end 
                            else begin 
                                ordering_if.first_trans = Non_Posted_Req ; 
                            end
                            ordering_if.first_RO = axi_wrreq_hdr.Attr[1];
                            ordering_if.first_IDO = axi_wrreq_hdr.ATTR;
                            ordering_if.first_trans_ID = axi_wrreq_hdr.Requester_ID ;
                            
                            ordering_if.second_trans = Comp ;     
                            ordering_if.second_RO = 1'b1;
                            ordering_if.second_IDO = 1'b1;
                            ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                            ordering_if.comp_typ = 3'b000; 

                            
            end
            {A2P_2,A2P_1}   : begin 
                             // Non-Posted Request (Msg)
                            if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                                ordering_if.first_trans = Posted_Req ;
                            end 
                            else begin 
                                ordering_if.first_trans = Non_Posted_Req ;
                            end
                            ordering_if.first_RO = axi_rdreq_hdr.Attr[1];
                            ordering_if.first_IDO = axi_rdreq_hdr.ATTR ;
                            ordering_if.first_trans_ID = axi_rdreq_hdr.Requester_ID ;
                            ordering_if.comp_typ = 3'b000;
                            
                            // Posted Condition for MemWr either 64-bit address or 32-bit address
                            if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                                ordering_if.second_trans = Posted_Req ; 
                            end 
                            else begin 
                                ordering_if.second_trans = Non_Posted_Req ; 
                            end
                            ordering_if.second_RO = axi_wrreq_hdr.Attr[1];
                            ordering_if.second_IDO = axi_wrreq_hdr.ATTR;
                            ordering_if.second_trans_ID = axi_wrreq_hdr.Requester_ID ;
            end 
            {A2P_2,MASTER}   : begin 
                             // Non-Posted Request (Msg)
                                if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                                    ordering_if.first_trans = Posted_Req ;
                                end 
                                else begin 
                                    ordering_if.first_trans = Non_Posted_Req ;
                                end
                                ordering_if.first_RO = axi_rdreq_hdr.Attr[1];
                                ordering_if.first_IDO = axi_rdreq_hdr.ATTR ;
                                ordering_if.first_trans_ID = axi_rdreq_hdr.Requester_ID ;
                                
                                ordering_if.second_trans = Comp ;
                                ordering_if.second_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                ordering_if.second_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                                ordering_if.second_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                ordering_if.comp_typ = 3'b000; // I can't Determine unless Cfg wr due to different paths
            
            end 
            {A2P_2,RX_ROUTER_CFG}   : begin 
                                // Non-Posted Request (Msg)
                                if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                                    ordering_if.first_trans = Posted_Req ;
                                end 
                                else begin 
                                    ordering_if.first_trans = Non_Posted_Req ;
                                end
                                ordering_if.first_RO = axi_rdreq_hdr.Attr[1];
                                ordering_if.first_IDO = axi_rdreq_hdr.ATTR ;
                                ordering_if.first_trans_ID = axi_rdreq_hdr.Requester_ID ;

                                ordering_if.second_trans = Comp ;
                                ordering_if.second_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                ordering_if.second_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                                ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                if ((rx_router_comp_hdr[3*DW - 1: 3*DW - 3] == 3'b000)&&(rx_router_comp_hdr[1*DW + 15 : 1 *DW + 13 ] == 3'b000)) // this means the compeletions are comp, successfull and cfgwr
                                    begin 
                                        ordering_if.comp_typ = 3'b010; // CFG Wr
                                    end 
                                    else begin 
                                        ordering_if.comp_typ = 3'b000; // not CFG Wr
                                    end 
            end 
            {A2P_2,RX_ROUTER_ERR}   : begin 
                                    // Non-Posted Request (Msg)
                                    if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                                        ordering_if.first_trans = Posted_Req ;
                                    end 
                                    else begin 
                                        ordering_if.first_trans = Non_Posted_Req ;
                                    end
                                    ordering_if.first_RO = axi_rdreq_hdr.Attr[1];
                                    ordering_if.first_IDO = axi_rdreq_hdr.ATTR ;
                                    ordering_if.first_trans_ID = axi_rdreq_hdr.Requester_ID ;                                   

                                    ordering_if.second_trans = Comp ; 
                                    ordering_if.second_RO = 1'b1;
                                    ordering_if.second_IDO = 1'b1;
                                    ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                    ordering_if.comp_typ = 3'b000; 


            end 
            {MASTER,A2P_2}   : begin 
                                // Non-Posted Request (Msg)
                                if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                                    ordering_if.second_trans = Posted_Req ;
                                end 
                                else begin 
                                    ordering_if.second_trans = Non_Posted_Req ;
                                end
                                ordering_if.second_RO = axi_rdreq_hdr.Attr[1];
                                ordering_if.second_IDO = axi_rdreq_hdr.ATTR ;
                                ordering_if.second_trans_ID = axi_rdreq_hdr.Requester_ID ;

                                
                                ordering_if.first_trans = Comp ;
                                ordering_if.first_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                        
                                ordering_if.first_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                                ordering_if.first_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                ordering_if.comp_typ = 3'b000; // I can't Determine unless Cfg wr due to different paths
            
            end 
            {MASTER,A2P_1}   : begin 
            // Posted Condition for MemWr either 64-bit address or 32-bit address
                if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                    ordering_if.second_trans = Posted_Req ; 
                end 
                else begin 
                    ordering_if.second_trans = Non_Posted_Req ; 
                end
                ordering_if.second_RO = axi_wrreq_hdr.Attr[1];
                ordering_if.second_IDO = axi_wrreq_hdr.ATTR;
                ordering_if.second_trans_ID = axi_wrreq_hdr.Requester_ID ;
                
                ordering_if.first_trans = Comp ;
                ordering_if.first_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                ordering_if.first_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.first_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; // I can't Determine unless Cfg wr due to different paths
            
            end 
            {MASTER,RX_ROUTER_CFG}   : begin 
                ordering_if.first_trans = Comp ;
                ordering_if.first_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                        
                ordering_if.first_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.first_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                // ordering_if.comp_typ = 2'b10; 
                // make it depending on fmt and status 
                /* if fmt = 010 --> cfg rd comp 
                   if fmt = 000 and status 000 --> cfg wr otherwise can't determine whether it is comp for cfg wr or rd */
                   ordering_if.second_trans = Comp ;
                    ordering_if.second_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                    ordering_if.second_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                    ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                    if ((rx_router_comp_hdr[3*DW - 1: 3*DW - 3] == 3'b000)&&(rx_router_comp_hdr[1*DW + 15 : 1 *DW + 13 ] == 3'b000)) // this means the compeletions are comp, successfull and cfgwr
                        begin 
                            ordering_if.comp_typ = 3'b010; // CFG Wr
                        end 
                    else begin 
                            ordering_if.comp_typ = 3'b000; // not CFG Wr
                        end
            end 
            {MASTER,RX_ROUTER_ERR}   : begin 
                ordering_if.first_trans = Comp ;
                ordering_if.first_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                ordering_if.first_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.first_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; // I can't Determine unless Cfg wr due to different paths

                ordering_if.second_trans = Comp ; 
                ordering_if.second_RO = 1'b1;
                ordering_if.second_IDO = 1'b1;
                ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
            end
            {RX_ROUTER_CFG,A2P_2}   : begin 
                                 // Posted Request (Msg)                                    
                                 if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                                        ordering_if.second_trans = Posted_Req ;
                                    end 
                                    else begin 
                                        ordering_if.second_trans = Non_Posted_Req ;
                                    end
                                    ordering_if.second_RO = axi_rdreq_hdr.Attr[1];
                                    ordering_if.second_IDO = axi_rdreq_hdr.ATTR ;
                                    ordering_if.second_trans_ID = axi_rdreq_hdr.Requester_ID ;
                                    
                                    ordering_if.first_trans = Comp ;
                                    ordering_if.first_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                    ordering_if.first_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                                    ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                    ordering_if.comp_typ = 3'b000; // it represents the second transaction not first not CFG Wr

            
            end 
            {RX_ROUTER_CFG,A2P_1}   : begin 
            // Posted Condition for MemWr either 64-bit address or 32-bit address
                if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                    ordering_if.second_trans = Posted_Req ; 
                end 
                else begin 
                    ordering_if.second_trans = Non_Posted_Req ; 
                end
                ordering_if.second_RO = axi_wrreq_hdr.Attr[1];
                ordering_if.second_IDO = axi_wrreq_hdr.ATTR;
                ordering_if.second_trans_ID = axi_wrreq_hdr.Requester_ID ;
                
                ordering_if.first_trans = Comp ;
                ordering_if.first_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                ordering_if.first_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; // it represents the second transaction not first not CFG Wr
            
            end 
            {RX_ROUTER_CFG,MASTER}   : begin 
                ordering_if.second_trans = Comp ;
                ordering_if.second_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                ordering_if.second_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.second_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                // ordering_if.comp_typ = 3'b000; // I can't Determine unless Cfg wr due to different paths
                ordering_if.first_trans = Comp ;
                ordering_if.first_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                ordering_if.first_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; // not CFG Wr

            end 
            {RX_ROUTER_CFG,RX_ROUTER_ERR}   : begin 
            // ordering_if.comp_typ = 3'b000; // I can't Determine unless Cfg wr due to different paths
                ordering_if.first_trans = Comp ;
                ordering_if.first_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                ordering_if.first_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                
                ordering_if.second_trans = Comp ; 
                ordering_if.second_RO = 1'b1;
                ordering_if.second_IDO = 1'b1;                    
                ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; 

            end
            {RX_ROUTER_ERR,A2P_2}   : begin 
                // Posted Request (Msg)                                    
                if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                        ordering_if.second_trans = Posted_Req ;
                end 
                else begin 
                        ordering_if.second_trans = Non_Posted_Req ;
                end
                ordering_if.second_RO = axi_rdreq_hdr.Attr[1];
                ordering_if.second_IDO = axi_rdreq_hdr.ATTR ;
                ordering_if.second_trans_ID = axi_rdreq_hdr.Requester_ID ;
                                    
                ordering_if.first_trans = Comp ; 
                ordering_if.first_RO = 1'b1;
                ordering_if.first_IDO = 1'b1;                    
                ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; 
                                    
            
            end 
            {RX_ROUTER_ERR,A2P_1}   : begin
            // Posted Condition for MemWr either 64-bit address or 32-bit address
                if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                    ordering_if.second_trans = Posted_Req ; 
                end 
                else begin 
                    ordering_if.second_trans = Non_Posted_Req ; 
                end
                ordering_if.second_RO = axi_wrreq_hdr.Attr[1];
                ordering_if.second_IDO = axi_wrreq_hdr.ATTR;
                ordering_if.second_trans_ID = axi_wrreq_hdr.Requester_ID ;
                
                ordering_if.first_trans = Comp ; 
                ordering_if.first_RO = 1'b1;
                ordering_if.first_IDO = 1'b1;                    
                ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; 
            
            end 
            {RX_ROUTER_ERR,MASTER}   : begin 
                ordering_if.first_trans = Comp ; 
                ordering_if.first_RO = 1'b1;
                ordering_if.first_IDO = 1'b1;                    
                ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; 
            
                ordering_if.second_trans = Comp ;
                ordering_if.second_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;                     
                ordering_if.second_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.second_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
            end 
            {RX_ROUTER_ERR,RX_ROUTER_CFG}   : begin 
                ordering_if.first_trans = Comp ; 
                ordering_if.first_RO = 1'b1;
                ordering_if.first_IDO = 1'b1;                    
                ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
             
                ordering_if.second_trans = Comp ;
                ordering_if.second_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                ordering_if.second_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                if ((rx_router_comp_hdr[3*DW - 1: 3*DW - 3] == 3'b000)&&(rx_router_comp_hdr[1*DW + 15 : 1 *DW + 13 ] == 3'b000)) // this means the compeletions are comp, successfull and cfgwr
                    begin 
                        ordering_if.comp_typ = 3'b010; // CFG Wr
                    end 
                    else begin 
                            ordering_if.comp_typ = 3'b000; // not CFG Wr
                        end 
            end 
            default : begin 
                ordering_if.first_trans = No_Req ; 
                ordering_if.first_RO = 1'b0;
                ordering_if.first_IDO = 1'b0;                    
                ordering_if.first_trans_ID = 'b0;
             
                ordering_if.second_trans = No_Req ;
                ordering_if.second_RO = 1'b0 ;
                ordering_if.second_IDO = 1'b0;
                ordering_if.second_trans_ID = 'b0 ;
            end 
        endcase

        result = ordering_if.ordering_result ;        
        return result;
    endfunction 

    /* Note. This function is reponsible for calculating no. cycles needed to recieve data from sources */
    function logic [5:0] no_cycles_calc (
                                    input logic [9:0] length_Data );
                    logic [5:0] no_cycles ;
                        if (length_Data == 10'b0) begin  // 1024 DW
                          no_cycles =  6'b10_0000; 
                        end
                        else if (length_Data > 10'b00_0010_0000) begin  // 32 
                          no_cycles = length_Data >> 5 ;
                          if (length_Data - (no_cycles << 5) != 'b0) begin 
                          no_cycles = no_cycles + 6'b1 ; 
                        end 
                        end 
                        else begin 
                            no_cycles =  6'b1 ; 
                        end                                    
            return no_cycles ; 
    endfunction 

    // this function is responsible for calculating no. of write loc. in buffer of TLP
    function logic [NO_LOC_WR_WIDTH - 1 :0] no_wr_loc ( 
                                                      input logic [9:0] length_Data, 
                                                      input logic [1:0] last_cycle, // 00 --> first_last_cycle - 01--> first_cycle - 10 --> intermidate_cycle - 11 --> last_cycle
                                                      input logic [5:0] no_cycles, // Total Number of Cycles needed to send it to TLP Buffer
                                                      input logic HDR_3DW_4DW );
            logic [NO_LOC_WR_WIDTH - 1 : 0] no_wr_loc ; 
            logic [3:0] temp1, temp2 ; // to store length / 4 
                    if (HDR_3DW_4DW) begin  // 4 DW HDR
                        if (length_Data == 10'b0) begin  // 1024 DW  [ 1st cycle: 1 'HDR' + 8 'D'] [intermid. cycle: 8'D'] [last cycle: 8'D']
                            if ((last_cycle == 2'b11) ||(last_cycle == 2'b10)) begin  // last cycle && intermidate cycles
                            no_wr_loc =  4'b1000; 
                            end 
                            else if (last_cycle == 2'b10) begin 
                            no_wr_loc =  4'b1001; 
                            end 
                            else begin  // Not valid here 1024 DW can't be first_cycle and last_cycle together 
                                no_wr_loc =  4'b0; 
                            end 
                          end
                        else begin 
                            case (last_cycle)
                                2'b00 : begin // first cycle and last cycle, means that the TLP will be sent in one cycle
                                    temp1 = length_Data >> 2 ;
                                    if (length_Data - (temp1 << 2) != 'b0) begin 
                                        temp2 = temp1 + 1'b1 ; 
                                    end 
                                    else begin  // here 64 DW for example, No.cycles = 
                                        temp2 = temp1 ; 
                                    end 
                                    no_wr_loc = 1'b1 + temp2 ; 
                                end 
                                2'b01 : begin  // first cycle in multi cycles TLP
                                    no_wr_loc = 4'b1001 ;
                                end 
                                2'b10 : begin  // intermidate cycle in multi cycles TLP
                                    no_wr_loc = 4'b1000 ; 
                                end
                                2'b11 : begin // last cycle in multi cycles TLP
                                   temp1 = (no_cycles - 2'b01) << 5 ; // total number of DW sent before last 
                                   length_Data = length_Data - temp1;
                                   temp2 = length_Data >> 2 ;
                                    if (length_Data - (temp2 << 2) != 'b0) begin 
                                        no_wr_loc = temp2 + 1'b1 ; 
                                    end 
                                    else begin  
                                        no_wr_loc = temp2 ; 
                                    end 
                                end 
                            endcase 
                          end 
                          end 
                    else begin  // 3 DW HDR
                        if (length_Data == 10'b0) begin  // 1024 DW  [ 1st cycle: 1 'HDR + 1dw of data' + 8 'D'] [intermid. cycle: 8'D'] [last cycle: 8'D']
                                if ((last_cycle == 2'b11) ) begin  // last cycle 
                                no_wr_loc =  4'b1001;    //  32 DW --> 8 loc  + 3 DW --> 1 loc
                                end 
                                else if (last_cycle == 2'b10) begin  // first cycle 
                                no_wr_loc =  4'b1000;  // 1 loc to store (HDR + first DW of Data) , 7 loc to store 28 DW of Data --> total number of loc. = 1 + 7
                                end 
                                else if (last_cycle == 2'b10) begin //  intermidate cycles
                                no_wr_loc =  4'b1000;  // 8 Loc. to store 32 DW
                                end 
                                else begin 
                                    no_wr_loc =  4'b0; 
                                end 
                        end 
                        else begin 
                            case (last_cycle)
                                2'b00 : begin // first cycle and last cycle, means that the TLP will be sent in one cycle
                                    length_Data = length_Data - 1'b1 ; // because 1 DW will go to with 3 DW of Header
                                    temp1 = length_Data >> 2 ;
                                    if (length_Data - (temp1 << 2) != 'b0) begin 
                                        temp2 = temp1 + 1'b1 ; 
                                    end 
                                    else begin  // here 64 DW for example, No.cycles = 
                                        temp2 = temp1 ; 
                                    end 
                                    no_wr_loc = 1'b1 + temp2 ; 
                                end 
                                2'b01 : begin  // first cycle in multi cycles TLP
                                    no_wr_loc = 4'b1000 ;  // 1 + 7
                                end 
                                2'b10 : begin  // intermidate cycle in multi cycles TLP
                                    no_wr_loc = 4'b1000 ; // 0 + 8
                                end
                                2'b11 : begin // last cycle in multi cycles TLP
                                    temp1 = (no_cycles - 2'b10) << 5 ; // total number of DW sent before last 
                                    length_Data = length_Data - temp1 - (1'b1 + 5'b1_1100 );
                                    temp2 = length_Data >> 2 ;
                                     if (length_Data - (temp2 << 2) != 'b0) begin 
                                         no_wr_loc = temp2 + 1'b1 ; 
                                     end 
                                     else begin  
                                         no_wr_loc = temp2 ; 
                                     end 
                                end
                            endcase 
                        end 
                    end
            return no_wr_loc ; 
    endfunction 

    always_ff (@posedge clk or negedge arst)
    begin 
            if (!arst)
                begin 
                    current_state <= IDLE;
                end 
            else begin 
                    current_state <= next_state;
            end 
    end 
    
    always_comb begin
            case (current_state)
                IDLE : begin 
                // Output of State   --> the output is  initial                 
				// Initial Values 
				// Interface with sequence recorder buffer 
					/* Sequence Recorder */
					recorder_if.rd_en = 1'b0 ;
					recorder_if.wr_en = 1'b0 ;
					recorder_if.wr_mode = 3'b0 ;
					recorder_if.rd_mode = 3'b0 ;
					recorder_if.wr_data_1 = NO_SOURCE ;
					recorder_if.wr_data_2 = NO_SOURCE ;
					// recorder_if.available  ;  they are inputs 
					// recorder_if.rd_data_1  ;
					// recorder_if.rd_data_2  ; 
				// Interface with Ordering Block 
					/* Ordering Block Interface */
					ordering_if.first_trans = No_Req;
					ordering_if.second_trans =No_Req ;
					ordering_if.first_RO = 1'b0;
					ordering_if.second_RO = 1'b0 ;
					ordering_if.first_IDO = 1'b0;
					ordering_if.second_IDO = 1'b0 ;
					ordering_if.first_trans_ID = 'b0 ;
					ordering_if.second_trans_ID = 'b0;
					ordering_if.comp_typ = 2'b00;     
					// ordering_if.ordering_result  ; it is an input to this block
				// Interfaces with Flow Control 
					/* FLOW control Block */
					fc_if.PTLP_1 = '0;
					fc_if.PTLP_2 = '0;
					fc_if.Command_1 = FC_DEFAULT ;
					fc_if.Command_2 = FC_DEFAULT ; 
					//  fc_if.Result; it is an input to this block 
				// Interfaces with FIFO of Data Fragmentation  
                    TLP_stored = 1'b0 ; 
					/* Buffer Data Fragmentation Block */
					buffer_if.wr_en = 1'b0;
					buffer_if.data_in = '0 ;
					buffer_if.no_loc_wr ='b0 ; 
					//   buffer_if.empty_loc;  // it is an input to this block         
				// Interfaces with 3 Sources ( AXI Slave - AXI Master - Rx Router )
					axi_req_wr_grant  = 1'b0
					axi_req_rd_grant  = 1'b0
					axi_master_grant = 1'b0
					rx_router_grant = 1'b0
				// Internal signals initialization
					No_rd_loc_seq = 2'b0;
                    tlp1_no_cycles = 6'b0;  
                    tlp2_no_cycles = 6'b0;
                    one_req_on_pipe = 1'b0 ;
                    two_req_on_pipe = 1'b0 ;
                    TLP1_stroing_completed = 1'b0 ;
                    source_2 = NO_SOURCE ;
                    source_1 = NO_SOURCE ;
                    count_tlp1 = 6'b0 ;
                    count_tlp2 = 6'b0 ;
                    registered_data = '0 ;
                    TLP2_stroing_completed = 1'b0 ; 

                // State Transition 
                    if ((recorder_if.available  != FIFO_DEPTH) && (start_fragment || Buffer_Ready) )  
                        begin 
                        next_state = TLP1_HDR ;
                            if (recorder_if.available  == FIFO_DEPTH - 1'b1 )
                                begin 
                                    recorder_if.rd_en = 1'b1 ;
                                    recorder_if.rd_mode = 3'b1 ; // read 1 location from sequence recorder
                                    No_rd_loc_seq = 2'b1 ;
                                end 
                            else begin 
                                    recorder_if.rd_en = 1'b1 ;
                                    recorder_if.rd_mode = 3'b10 ; // read 2 locations from sequence recorder
                                    No_rd_loc_seq = 2'b10 ;
                            end                
                        end 
                    else begin
                        next_state = IDLE ; 
                    end                 
                end 
                TLP1_HDR : begin 
                        // Output of State
                    TLP2_stroing_completed = 1'b0 ; 
                                // check FC and Ordering
								if (No_rd_loc_seq == 2'b10) begin 
									FC_result  = FC_function (recorder_if.rd_data_1,recorder_if.rd_data_2, 1)  ; 
								// Check Ordering
									ordering_result = ordering_function(recorder_if.rd_data_1,recorder_if.rd_data_2);
								end 
								else if(No_rd_loc_seq == 2'b01) begin 
								FC_result  = FC_function (recorder_if.rd_data_1, No_Req , 0 )  ; 
								ordering_result = FALSE;
                                end 
                                else begin 
                                    // this case can't happen, always if i go inside this state so i actually read one loc. or 2 locations								
                                    FC_result  = FC_INVALID ;   
                                    ordering_result = FALSE;
                                end 
                                axi_req_wr_grant  = 1'b0 ; 
                                axi_req_rd_grant  = 1'b0 ; 
                                axi_master_grant = 1'b0 ; 
                                rx_router_grant = 1'b0  ;
						// Assigning the signals of grant & Pushing to TLP Buffer & Sequence recorder buffer
                                case (FC_result) 
                                    FC_SUCCESS_1 : begin 
                                                    source_2 = NO_SOURCE ; 
                                                    two_req_on_pipe = 1'b0 ;
                                                    one_req_on_pipe = 1'b1 ; // only one request will be serviced and pushed from Buffer sequence
                                                    buffer_if.wr_en = 1'b1 ;
                                                    registered_data = '0 ;
                                                    case(recorder_if.rd_data_1) 
                                                        A2P_1 : begin 
                                                                        source_1 = A2P_1 ; 
                                                                        // Interface with source itself
                                                                        axi_req_wr_grant = 1'b1 ;
                                                                        // Interface with buffer 
                                                                        tlp1_no_cycles = no_cycles_calc (axi_wrreq_hdr.Length);
                                                                        if ((axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   = 'b0_0000) ) begin  // 64-bit address + Mem
                                                                            buffer_if.data_in = {axi_wrreq_hdr, axi_req_data} ;
                                                                                if (tlp1_no_cycles == 1) begin 
                                                                                    buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp1_no_cycles , 1 );
                                                                                    TLP1_stroing_completed = 1'b1 ;
                                                                                end 
                                                                                else begin 
                                                                                    buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp1_no_cycles , 1 );
                                                                                    TLP1_stroing_completed = 1'b0 ;
                                                                                end 
                                                                            end 
                                                                        else begin 
                                                                            buffer_if.data_in = {axi_wrreq_hdr, axi_req_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  3*DW]} ;
                                                                            registered_data = axi_req_data [3 * DW - 1 : 0]; 
                                                                            if (tlp1_no_cycles == 1) begin 
                                                                                buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp1_no_cycles , 0 );
                                                                                TLP1_stroing_completed = 1'b1 ;
                                                                            end 
                                                                            else begin 
                                                                                buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp1_no_cycles , 0 );
                                                                                TLP1_stroing_completed = 1'b0 ;
                                                                            end 
                                                                        end 
                                                                        end
                                                        A2P_2 : begin 
                                                            source_1 = A2P_2; 
                                                            // Interface with source itself
                                                            axi_req_rd_grant = 1'b1 ;
                                                            // Interface with buffer 
                                                            tlp1_no_cycles = 1'b1;
                                                            buffer_if.data_in = axi_rdreq_hdr ;
                                                            TLP1_stroing_completed = 1'b1 ;
                                                            buffer_if.no_loc_wr = 1'b1 ;
                                                            end
                                                        MASTER : begin 
                                                            source_1 = MASTER ; 
                                                            // Interface with source itself
                                                            axi_master_grant = 1'b1 ;
                                                            // Interface with buffer 
                                                            if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                            tlp1_no_cycles = no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] );
                                                            buffer_if.data_in = {axi_master_hdr, axi_comp_data[AXI_MAX_NUM_BYTES * 8 - 1 : 3 * DW]} ;
                                                            registered_data = axi_comp_data [3 * DW - 1 : 0] ; 
                                                            if (tlp1_no_cycles == 1) begin 
                                                                buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b00, tlp1_no_cycles , 0 );
                                                                TLP1_stroing_completed = 1'b1 ;
                                                            end 
                                                            else begin 
                                                                buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b01, tlp1_no_cycles , 0 );
                                                                TLP1_stroing_completed = 1'b0 ;
                                                            end 
                                                            end 
                                                            else begin // Comp
                                                            tlp1_no_cycles = 1'b1 ; 
                                                            buffer_if.data_in = {axi_master_hdr, 32{1'b0}} ;
                                                            buffer_if.no_loc_wr = 1'b1;
                                                            TLP1_stroing_completed = 1'b1 ;
                                                            end 
                                                        end
                                                        RX_ROUTER_CFG : begin 
                                                            source_1 = RX_ROUTER_CFG ; 
                                                                    // Interface with source itself
                                                            rx_router_grant = 1'b1 ;
                                                            tlp1_no_cycles = 1'b1 ;
                                                            TLP1_stroing_completed = 1'b1 ;
                                                            buffer_if.no_loc_wr = 1'b1 ;

                                                            // Interface with buffer 
                                                            if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                            buffer_if.data_in = {rx_router_comp_hdr, rx_router_data} ;
                                                            end 
                                                            else begin 
                                                            buffer_if.data_in = {rx_router_comp_hdr, 32{1'b0}} ;
                                                            end 
                                                        end
                                                        default : begin 
                                                            source_1 = NO_SOURCE ; 
                                                            // Interface with source itself
                                                            rx_router_grant = 1'b0 ;
                                                            tlp1_no_cycles = 1'b0 ;
                                                            TLP1_stroing_completed = 1'b0 ;
                                                            one_req_on_pipe = 1'b0 ; // only one request will be serviced and pushed from Buffer sequence

                                                            buffer_if.no_loc_wr = 1'b0 ;

                                                            // Interface with buffer 
                                                            buffer_if.data_in = 0 ;
                                                          
                                                            recorder_if.wr_en = 1'b0 ;
                                                            recorder_if.wr_mode = 3'b0 ;
                                                            recorder_if.wr_data_1 = NO_SOURCE ;
                                                        end														
                                                    endcase
                                                    //Interface with Sequence Buffer 															
                                                    if ((No_rd_loc_seq == 2'b10) && ((recorder_if.rd_data_1 == A2P_1 ) || (recorder_if.rd_data_1 == A2P_2) || (recorder_if.rd_data_1 == MASTER) || (recorder_if.rd_data_1 == RX_ROUTER_CFG))) begin 
                                                        recorder_if.wr_en = 1'b1 ;
                                                        recorder_if.wr_mode = 3'b1 ;
                                                        recorder_if.wr_data_1 = recorder_if.rd_data_2 ;
                                                    end
                                                    else begin 
                                                        recorder_if.wr_en = 1'b0 ;
                                                        recorder_if.wr_mode = 3'b0 ;
                                                        recorder_if.wr_data_1 = NO_SOURCE ;
                                                    end 
                                                    recorder_if.wr_data_2 = NO_SOURCE ;

                                    end 
                                    FC_SUCCESS_2 : begin 
                                        source_2 = NO_SOURCE ; 
                                            if (ordering_result == TRUE) begin 
                                                    two_req_on_pipe = 1'b0 ;
                                                    one_req_on_pipe = 1'b1 ; // only one request will be serviced and pushed from Buffer sequence
                                                    buffer_if.wr_en = 1'b1 ;
                                                    registered_data = '0 ;

                                                    case(recorder_if.rd_data_2) 
                                                        A2P_1 : begin 
                                                                        source_1 = A2P_1 ; 
                                                                        // Interface with source itself
                                                                        axi_req_wr_grant = 1'b1 ;
                                                                        // Interface with buffer 
                                                                        tlp1_no_cycles = no_cycles_calc (axi_wrreq_hdr.Length);
                                                                        if ((axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   = 'b0_0000) ) begin  // 64-bit address + Mem
                                                                            buffer_if.data_in = {axi_wrreq_hdr, axi_req_data} ;
                                                                                if (tlp1_no_cycles == 1) begin 
                                                                                    buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp1_no_cycles , 1 );
                                                                                    TLP1_stroing_completed = 1'b1 ;
                                                                                end 
                                                                                else begin 
                                                                                    buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp1_no_cycles , 1 );
                                                                                    TLP1_stroing_completed = 1'b0 ;
                                                                                end 
                                                                            end 
                                                                        else begin 
                                                                            buffer_if.data_in = {axi_wrreq_hdr, axi_req_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  3*DW]} ;
                                                                            registered_data = axi_req_data [3 * DW - 1 : 0]; 
                                                                            if (tlp1_no_cycles == 1) begin 
                                                                                buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp1_no_cycles , 0 );
                                                                                TLP1_stroing_completed = 1'b1 ;
                                                                            end 
                                                                            else begin 
                                                                                buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp1_no_cycles , 0 );
                                                                                TLP1_stroing_completed = 1'b0 ;
                                                                            end 
                                                                        end 
                                                                        end
                                                        A2P_2 : begin 
                                                            source_1 = A2P_2 ; 
                                                            // Interface with source itself
                                                            axi_req_rd_grant = 1'b1 ;
                                                            // Interface with buffer 
                                                            tlp1_no_cycles = 1'b1;
                                                            buffer_if.data_in = axi_rdreq_hdr ;
                                                            TLP1_stroing_completed = 1'b1 ;
                                                            buffer_if.no_loc_wr = 1'b1 ;
                                                            end
                                                        MASTER : begin 
                                                            source_1 = MASTER ; 
                                                            // Interface with source itself
                                                            axi_master_grant = 1'b1 ;
                                                            // Interface with buffer 
                                                            if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                            tlp1_no_cycles = no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] );
                                                            buffer_if.data_in = {axi_master_hdr, axi_comp_data[AXI_MAX_NUM_BYTES * 8 - 1 : 3 * DW]} ;
                                                            registered_data = axi_comp_data [3 * DW - 1 : 0] ; 
                                                            if (tlp1_no_cycles == 1) begin 
                                                                buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b00, tlp1_no_cycles , 0 );
                                                                TLP1_stroing_completed = 1'b1 ;
                                                            end 
                                                            else begin 
                                                                buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b01, tlp1_no_cycles , 0 );
                                                                TLP1_stroing_completed = 1'b0 ;
                                                            end 
                                                            end 
                                                            else begin // Comp
                                                            tlp1_no_cycles = 1'b1 ; 
                                                            buffer_if.data_in = {axi_master_hdr, 32{1'b0}} ;
                                                            buffer_if.no_loc_wr = 1'b1;
                                                            TLP1_stroing_completed = 1'b1 ;
                                                            end 
                                                        end
                                                        RX_ROUTER_CFG : begin 
                                                            source_1 = RX_ROUTER_CFG ; 
                                                            // Interface with source itself
                                                            rx_router_grant = 1'b1 ;
                                                            tlp1_no_cycles = 1'b1 ;
                                                            TLP1_stroing_completed = 1'b1 ;
                                                            buffer_if.no_loc_wr = 1'b1 ;

                                                            // Interface with buffer 
                                                            if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                            buffer_if.data_in = {rx_router_comp_hdr, rx_router_data} ;
                                                            end 
                                                            else begin 
                                                            buffer_if.data_in = {rx_router_comp_hdr, 32{1'b0}} ;
                                                            end 
                                                        end
                                                        default : begin 
                                                            source_1 = NO_SOURCE ; 
                                                            // Interface with source itself
                                                            rx_router_grant = 1'b0 ;
                                                            tlp1_no_cycles = 1'b0 ;
                                                            TLP1_stroing_completed = 1'b0 ;
                                                            one_req_on_pipe = 1'b0 ; // only one request will be serviced and pushed from Buffer sequence

                                                            buffer_if.no_loc_wr = 1'b0 ;

                                                            // Interface with buffer 
                                                            buffer_if.data_in = 0 ;
                                                          
                                                            recorder_if.wr_en = 1'b0 ;
                                                            recorder_if.wr_mode = 3'b0 ;
                                                            recorder_if.wr_data_1 = NO_SOURCE ;
                                                        end														
                                                    endcase
                                                    //Interface with Sequence Buffer 															
                                                    if ((No_rd_loc_seq == 2'b10) && ((recorder_if.rd_data_2 == A2P_1 ) || (recorder_if.rd_data_2 == A2P_2) || (recorder_if.rd_data_2 == MASTER) || (recorder_if.rd_data_2 == RX_ROUTER_CFG))) begin 
                                                        recorder_if.wr_en = 1'b1 ;
                                                        recorder_if.wr_mode = 3'b1 ;
                                                        recorder_if.wr_data_1 = recorder_if.rd_data_1 ;
                                                    end
                                                    else begin 
                                                        recorder_if.wr_en = 1'b0 ;
                                                        recorder_if.wr_mode = 3'b0 ;
                                                        recorder_if.wr_data_1 = NO_SOURCE ;
                                                    end 
                                                    recorder_if.wr_data_2 = NO_SOURCE ;
                                            end 
                                            else begin 
                                        source_1 = NO_SOURCE ; 
                                        recorder_if.wr_en = 1'b1 ;
                                        recorder_if.wr_mode = 3'b10 ;
                                        recorder_if.wr_data_1 = recorder_if.rd_data_1 ;
                                        recorder_if.wr_data_2 = recorder_if.rd_data_2 ;
                                        two_req_on_pipe = 1'b0 ;
                                        one_req_on_pipe = 1'b0 ; // only one request will be serviced and pushed from Buffer sequence
                                        buffer_if.wr_en = 1'b0 ;
                                        axi_req_wr_grant  = 1'b0
					                    axi_req_rd_grant  = 1'b0
					                    axi_master_grant = 1'b0
					                    rx_router_grant = 1'b0
                                        buffer_if.data_in = 'b0 ;
                                        buffer_if.no_loc_wr = 'b0;
                                        TLP1_stroing_completed = 1'b0 ;

                                    end 
                                end 
                                    FC_SUCCESS_1_2 : begin 
                                                    axi_req_wr_grant  = 1'b0 ;
					                                axi_req_rd_grant  = 1'b0 ; 
					                                axi_master_grant = 1'b0 ; 
					                                rx_router_grant = 1'b0 ; 
                                                    registered_data = '0 ; 
                                                 if ((recorder_if.rd_data_1 != RX_ROUTER_ERR) && (recorder_if.rd_data_2 != RX_ROUTER_ERR) ) begin 
                                                    source_1 = recorder_if.rd_data_1 ; 
                                                    source_2 = recorder_if.rd_data_2 ;
                                                    two_req_on_pipe = 1'b1 ;
                                                    one_req_on_pipe = 1'b1 ; // only one request will be serviced and pushed from Buffer sequence
                                                    buffer_if.wr_en = 1'b1 ;
                                                    case(recorder_if.rd_data_1) 
                                                        A2P_1 : begin 
                                                                        // Interface with source itself
                                                                        axi_req_wr_grant = 1'b1 ;
                                                                        // Interface with buffer 
                                                                        tlp1_no_cycles = no_cycles_calc (axi_wrreq_hdr.Length);
                                                                        if ((axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   = 'b0_0000) ) begin  // 64-bit address + Mem
                                                                            buffer_if.data_in = {axi_wrreq_hdr, axi_req_data} ;
                                                                                if (tlp1_no_cycles == 1) begin 
                                                                                    buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp1_no_cycles , 1 );
                                                                                    TLP1_stroing_completed = 1'b1 ;
                                                                                end 
                                                                                else begin 
                                                                                    buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp1_no_cycles , 1 );
                                                                                    TLP1_stroing_completed = 1'b0 ;
                                                                                end 
                                                                            end 
                                                                        else begin 
                                                                            buffer_if.data_in = {axi_wrreq_hdr, axi_req_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  3*DW]} ;
                                                                            registered_data = axi_req_data [3 * DW - 1 : 0] ; 
                                                                            if (tlp1_no_cycles == 1) begin 
                                                                                buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp1_no_cycles , 0 );
                                                                                TLP1_stroing_completed = 1'b1 ;
                                                                            end 
                                                                            else begin 
                                                                                buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp1_no_cycles , 0 );
                                                                                TLP1_stroing_completed = 1'b0 ;
                                                                            end 
                                                                        end 
                                                                        end
                                                        A2P_2 : begin 
                                                            // Interface with source itself
                                                            axi_req_rd_grant = 1'b1 ;
                                                            // Interface with buffer 
                                                            tlp1_no_cycles = 1'b1;
                                                            buffer_if.data_in = axi_rdreq_hdr ;
                                                            TLP1_stroing_completed = 1'b1 ;
                                                            buffer_if.no_loc_wr = 1'b1 ;
                                                            end
                                                        MASTER : begin 
                                                            // Interface with source itself
                                                            axi_master_grant = 1'b1 ;
                                                            // Interface with buffer 
                                                            if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                            tlp1_no_cycles = no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] );
                                                            buffer_if.data_in = {axi_master_hdr, axi_comp_data[AXI_MAX_NUM_BYTES * 8 - 1 : 3 * DW]} ;
                                                            registered_data = axi_comp_data [3 * DW - 1 : 0] ; 

                                                            if (tlp1_no_cycles == 1) begin 
                                                                buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b00, tlp1_no_cycles , 0 );
                                                                TLP1_stroing_completed = 1'b1 ;
                                                            end 
                                                            else begin 
                                                                buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b01, tlp1_no_cycles , 0 );
                                                                TLP1_stroing_completed = 1'b0 ;
                                                            end 
                                                            end 
                                                            else begin // Comp
                                                            tlp1_no_cycles = 1'b1 ; 
                                                            buffer_if.data_in = {axi_master_hdr, 32{1'b0}} ;
                                                            buffer_if.no_loc_wr = 1'b1;
                                                            TLP1_stroing_completed = 1'b1 ;
                                                            end 
                                                        end
                                                        RX_ROUTER_CFG : begin 
                                                                    // Interface with source itself
                                                            rx_router_grant = 1'b1 ;
                                                            tlp1_no_cycles = 1'b1 ;
                                                            TLP1_stroing_completed = 1'b1 ;
                                                            buffer_if.no_loc_wr = 1'b1 ;

                                                            // Interface with buffer 
                                                            if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                            buffer_if.data_in = {rx_router_comp_hdr, rx_router_data} ;
                                                            end 
                                                            else begin 
                                                            buffer_if.data_in = {rx_router_comp_hdr, 32{1'b0}} ;
                                                            end 
                                                        end
                                                        default : begin 
                                                            // Interface with source itself
                                                            rx_router_grant = 1'b0 ;
                                                            tlp1_no_cycles = 1'b0 ;
                                                            TLP1_stroing_completed = 1'b0 ;
                                                            one_req_on_pipe = 1'b0 ; // only one request will be serviced and pushed from Buffer sequence

                                                            buffer_if.no_loc_wr = 1'b0 ;

                                                            // Interface with buffer 
                                                            buffer_if.data_in = 0 ;
                                                          
                                                            recorder_if.wr_en = 1'b0 ;
                                                            recorder_if.wr_mode = 3'b0 ;
                                                            recorder_if.wr_data_1 = NO_SOURCE ;
                                                        end														
                                                    endcase
                                                    //Interface with Sequence Buffer 															
                                                        recorder_if.wr_en = 1'b0 ;
                                                        recorder_if.wr_mode = 3'b0 ;
                                                        recorder_if.wr_data_1 = NO_SOURCE ;
                                                        recorder_if.wr_data_2 = NO_SOURCE ;
                                                 end 
                                                 else if ((recorder_if.rd_data_1 != RX_ROUTER_ERR) ) begin  // Push the second request 
                                                    source_1 = recorder_if.rd_data_1 ; 
                                                    source_2 = recorder_if.rd_data_1 ;
                                                    two_req_on_pipe = 1'b1 ;
                                                    one_req_on_pipe = 1'b1 ; // only one request will be serviced and pushed from Buffer sequence
                                                    buffer_if.wr_en = 1'b1 ;
                                                    // assert signals of case statement 
                                                    // Interface with source itself
                                                    rx_router_grant = 1'b1 ;
                                                    // Interface with buffer 
                                                    tlp1_no_cycles = 1'b1; // Start with Msg then Comp
                                                    buffer_if.data_in = {rx_router_msg_hdr,32{1'b0}} ;
                                                    buffer_if.no_loc_wr = 1'b1 ;
                                                    TLP1_stroing_completed = 1'b1 ;
                                                    //Interface with Sequence Buffer 															
                                                        recorder_if.wr_en = 1'b1 ;
                                                        recorder_if.wr_mode = 3'b1 ;
                                                        recorder_if.wr_data_1 = recorder_if.rd_data_2 ;
                                                        recorder_if.wr_data_2 = NO_SOURCE ;
                                                 end 
                                                 else if ((recorder_if.rd_data_2 != RX_ROUTER_ERR) && (ordering_result == TRUE ) ) begin 
                                                    two_req_on_pipe = 1'b1 ;
                                                    one_req_on_pipe = 1'b1 ; // only one request will be serviced and pushed from Buffer sequence
                                                    buffer_if.wr_en = 1'b1 ;
                                                    source_1 = recorder_if.rd_data_1 ; 
                                                    source_2 = recorder_if.rd_data_1 ;
                                                    
                                                    // assert signals of case statement 
                                                    // Interface with source itself
                                                    rx_router_grant = 1'b1 ;
                                                    // Interface with buffer 
                                                    tlp1_no_cycles = 1'b1; // Start with Msg then Comp
                                                    buffer_if.data_in = {rx_router_msg_hdr,32{1'b0}} ;
                                                    buffer_if.no_loc_wr = 1'b1 ;
                                                    TLP1_stroing_completed = 1'b1 ;

                                                    //Interface with Sequence Buffer 															
                                                        recorder_if.wr_en = 1'b1 ;
                                                        recorder_if.wr_mode = 3'b1 ;
                                                        recorder_if.wr_data_1 = recorder_if.rd_data_1 ;
                                                        recorder_if.wr_data_2 = NO_SOURCE ;
                                                 end 
                                                 else begin 
                                                    source_1 = NO_SOURCE ; 
                                                    source_2 = NO_SOURCE ; 
                                                    two_req_on_pipe = 1'b0 ;
                                                    one_req_on_pipe = 1'b0 ; // only one request will be serviced and pushed from Buffer sequence
                                                    buffer_if.wr_en = 1'b0 ;
                                                    recorder_if.wr_en = 1'b0 ;
                                                    recorder_if.wr_mode = 3'b0 ;
                                                    recorder_if.wr_data_1 = NO_SOURCE ;
                                                    recorder_if.wr_data_2 = NO_SOURCE ;
                                                    axi_req_wr_grant  = 1'b0
					                                axi_req_rd_grant  = 1'b0
					                                axi_master_grant = 1'b0
					                                rx_router_grant = 1'b0
                                                    tlp1_no_cycles = 1'b0 ;
                                                    TLP1_stroing_completed = 1'b0 ;
                                                    buffer_if.no_loc_wr = 1'b0 ;
                                                    buffer_if.data_in = '0 ;
                                                 end 
                                    end 
                                    default : begin 
                                                    two_req_on_pipe = 1'b0 ;
                                                    one_req_on_pipe = 1'b0 ; // only one request will be serviced and pushed from Buffer sequence
                                                    buffer_if.wr_en = 1'b0 ;
                                                    recorder_if.wr_en = 1'b0 ;
                                                    recorder_if.wr_mode = 3'b0 ;
                                                    recorder_if.wr_data_1 = NO_SOURCE ;
                                                    recorder_if.wr_data_2 = NO_SOURCE ;
                                                    axi_req_wr_grant  = 1'b0
					                                axi_req_rd_grant  = 1'b0
					                                axi_master_grant = 1'b0
					                                rx_router_grant = 1'b0
                                                    tlp1_no_cycles = 1'b0 ;
                                                    TLP1_stroing_completed = 1'b0 ;
                                                    buffer_if.no_loc_wr = 1'b0 ;
                                                    buffer_if.data_in = '0 ;
                                                    source_1 = NO_SOURCE ; 
                                                    source_2 = NO_SOURCE ;

                                    end 
                                endcase 
                        // State Transition 
                                if ((TLP1_stroing_completed == 1'b0) &&  one_req_on_pipe  ) begin  // Go to Data of TLP1
                                    next_state = TLP1_Data ;
                                    recorder_if.rd_mode = 3'b0 ; // read 1 location from sequence recorder
                                    recorder_if.rd_en = 1'b0 ;
                                    No_rd_loc_seq = 2'b0 ;
                                end 
                                else if ((TLP1_stroing_completed == 1'b1) &&  one_req_on_pipe && two_req_on_pipe && Buffer_Ready ) begin  // Go to TLP2
                                    next_state = TLP2_HDR ;
                                    recorder_if.rd_mode = 3'b0 ; // read 1 location from sequence recorder
                                    recorder_if.rd_en = 1'b0 ;
                                    No_rd_loc_seq = 2'b0 ;
                                end 
                                else if (recorder_if.available  != FIFO_DEPTH && Buffer_Ready )  begin 
                                     next_state = TLP1_HDR ;
                                    if (recorder_if.available  == FIFO_DEPTH - 1'b1 ) begin 
                                    recorder_if.rd_en = 1'b1 ;
                                    recorder_if.rd_mode = 3'b1 ; // read 1 location from sequence recorder
                                    No_rd_loc_seq = 2'b1 ;
                                    end 
                                    else begin 
                                    recorder_if.rd_en = 1'b1 ;
                                    recorder_if.rd_mode = 3'b10 ; // read 2 locations from sequence recorder
                                    No_rd_loc_seq = 2'b10 ;
                                    end                
                                end 
                                else begin
                                    next_state = IDLE ; 
                                    recorder_if.rd_mode = 3'b0 ; // read 1 location from sequence recorder
                                    recorder_if.rd_en = 1'b0 ;
                                    No_rd_loc_seq = 2'b0 ;
                                end  
                                count_tlp1 = tlp1_no_cycles ;
                                count_tlp2 = tlp2_no_cycles ;
                                TLP_stored = TLP1_stroing_completed ; 

                            end 
                TLP1_Data : begin 
                        // Output of State
                                axi_req_wr_grant  = 1'b0 ; 
                                axi_req_rd_grant  = 1'b0 ; 
                                axi_master_grant = 1'b0 ; 
                                rx_router_grant = 1'b0 ;
                                case(source_1) 
                                    A2P_1 : begin 
                                                    registered_data = axi_req_data [3 * DW - 1 : 0] ; 
                                                    // Interface with buffer 
                                                    // tlp1_no_cycles = no_cycles_calc (axi_wrreq_hdr.Length);
                                                    count_tlp1 = count_tlp1 - 1'b1 ; 
                                                    //buffer_if.data_in = {axi_req_data} ;
                                                    if ((axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   = 'b0_0000) ) begin  // 64-bit address + Mem
                                                        buffer_if.data_in = axi_req_data ;
                                                            if (count_tlp1 == 1) begin 
                                                                buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b11, tlp1_no_cycles , 1 );
                                                                TLP1_stroing_completed = 1'b1 ;
                                                            end 
                                                            else begin 
                                                                buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b10, tlp1_no_cycles , 1 );
                                                                TLP1_stroing_completed = 1'b0 ;
                                                            end 
                                                        end 
                                                    else begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[AXI_MAX_NUM_BYTES * 8 - 1 :  3*DW]} ; 
                                                        if (count_tlp1 == 1) begin 
                                                            buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b11, tlp1_no_cycles , 0 );
                                                            TLP1_stroing_completed = 1'b1 ;
                                                        end 
                                                        else begin 
                                                            buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b10, tlp1_no_cycles , 0 );
                                                            TLP1_stroing_completed = 1'b0 ;
                                                        end 
                                                    end 
                                                    end
                                    MASTER : begin 
                                                            registered_data = axi_comp_data [3 * DW - 1 : 0] ; 
                                                            count_tlp1 = count_tlp1 - 1'b1 ; 
                                                            // Interface with buffer 
                                                            if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                            buffer_if.data_in = {registered_data , axi_comp_data [AXI_MAX_NUM_BYTES * 8 - 1 :  3*DW] }  ;
                                                            if (count_tlp1 == 1) begin 
                                                                buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b10, tlp1_no_cycles , 0 );
                                                                TLP1_stroing_completed = 1'b1 ;
                                                            end 
                                                            else begin 
                                                                buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b11, tlp1_no_cycles , 0 );
                                                                TLP1_stroing_completed = 1'b0 ;
                                                            end 
                                                            end 
                                                            else begin // Comp
                                                            tlp1_no_cycles = 1'b1 ; 
                                                            buffer_if.data_in = {axi_master_hdr, 32{1'b0}} ;
                                                            buffer_if.no_loc_wr = 1'b1;
                                                            TLP1_stroing_completed = 1'b1 ;
                                                            end 
                                    end
                                    default : begin 
                                        registered_data = '0 ; 
                                        source_1 = NO_SOURCE ; 
                                        count_tlp1 = 'b0; 
                                        // Interface with source itself
                                        TLP1_stroing_completed = 1'b0 ;
                                        buffer_if.no_loc_wr = 1'b0 ;
                                        // Interface with buffer 
                                        buffer_if.data_in = '0 ;
                                    end														
                                endcase    
                        // State Transition 
                                if ((TLP1_stroing_completed == 1'b0) &&  one_req_on_pipe ) begin  // Keep going on Data of TLP1
                                    next_state = TLP1_Data ;
                                    recorder_if.rd_mode = 3'b0 ; // read 1 location from sequence recorder
                                    recorder_if.rd_en = 1'b0 ;
                                    No_rd_loc_seq = 2'b0 ;
                                end 
                                else if ((TLP1_stroing_completed == 1'b1) &&  one_req_on_pipe && two_req_on_pipe && Buffer_Ready) begin  // Go to TLP2
                                    next_state = TLP2_HDR ;
                                    recorder_if.rd_mode = 3'b0 ; // read 1 location from sequence recorder
                                    recorder_if.rd_en = 1'b0 ;
                                    No_rd_loc_seq = 2'b0 ;
                                end 
                                else if (recorder_if.available  != FIFO_DEPTH && Buffer_Ready)  begin 
                                     next_state = TLP1_HDR ;
                                    if (recorder_if.available  == FIFO_DEPTH - 1'b1 ) begin 
                                    recorder_if.rd_en = 1'b1 ;
                                    recorder_if.rd_mode = 3'b1 ; // read 1 location from sequence recorder
                                    No_rd_loc_seq = 2'b1 ;
                                    end 
                                    else begin 
                                    recorder_if.rd_en = 1'b1 ;
                                    recorder_if.rd_mode = 3'b10 ; // read 2 locations from sequence recorder
                                    No_rd_loc_seq = 2'b10 ;
                                    end                
                                end 
                                else begin
                                    next_state = IDLE ; 
                                    recorder_if.rd_mode = 3'b0 ; // read 1 location from sequence recorder
                                    recorder_if.rd_en = 1'b0 ;
                                    No_rd_loc_seq = 2'b0 ;
                                end  
                                count_tlp1 = '0 ;
                                count_tlp2 = tlp2_no_cycles ;
                                TLP_stored = TLP1_stroing_completed ; 

                            end 
				TLP2_HDR : begin 
                    // Output of State
                            one_req_on_pipe = 1'b0 ; 
                            TLP1_stroing_completed = 1'b0 ;
                            tlp1_no_cycles = '0;
                            count_tlp1 = '0 ;
                            axi_req_wr_grant  = 1'b0 ; 
                            axi_req_rd_grant  = 1'b0 ; 
                            axi_master_grant = 1'b0 ; 
                            rx_router_grant = 1'b0  ;
                            case (source_2)
                                A2P_1 : begin 
                                                                    // Interface with source itself
                                                                    axi_req_wr_grant = 1'b1 ;
                                                                    // Interface with buffer 
                                                                    tlp2_no_cycles = no_cycles_calc (axi_wrreq_hdr.Length);
                                                                    if ((axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   = 'b0_0000) ) begin  // 64-bit address + Mem
                                                                        buffer_if.data_in = {axi_wrreq_hdr, axi_req_data} ;
                                                                            if (tlp2_no_cycles == 1) begin 
                                                                                buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp2_no_cycles , 1 );
                                                                                TLP2_stroing_completed = 1'b1 ;
                                                                            end 
                                                                            else begin 
                                                                                buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp2_no_cycles , 1 );
                                                                                TLP2_stroing_completed = 1'b0 ;
                                                                            end 
                                                                        end 
                                                                    else begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr, axi_req_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  3*DW]} ;
                                                                        registered_data = axi_req_data [3 * DW - 1 : 0]; 
                                                                        if (tlp2_no_cycles == 1) begin 
                                                                            buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp2_no_cycles , 0 );
                                                                            TLP2_stroing_completed = 1'b1 ;
                                                                        end 
                                                                        else begin 
                                                                            buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp2_no_cycles , 0 );
                                                                            TLP2_stroing_completed = 1'b0 ;
                                                                        end 
                                                                    end
                                end 
                                A2P_2 : begin 
                                    // Interface with source itself
                                    axi_req_rd_grant = 1'b1 ;
                                    // Interface with buffer 
                                    tlp2_no_cycles = 1'b1;
                                    buffer_if.data_in = axi_rdreq_hdr ;
                                    TLP2_stroing_completed = 1'b1 ;
                                    buffer_if.no_loc_wr = 1'b1 ;
                                    end
                                MASTER : begin 
                                    // Interface with source itself
                                    axi_master_grant = 1'b1 ;
                                    // Interface with buffer 
                                    if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                    tlp2_no_cycles = no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] );
                                    buffer_if.data_in = {axi_master_hdr, axi_comp_data[AXI_MAX_NUM_BYTES * 8 - 1 : 3 * DW]} ;
                                    registered_data = axi_comp_data [3 * DW - 1 : 0] ; 
                                    if (tlp2_no_cycles == 1) begin 
                                        buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b00, tlp2_no_cycles , 0 );
                                        TLP2_stroing_completed = 1'b1 ;
                                    end 
                                    else begin 
                                        buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b01, tlp2_no_cycles , 0 );
                                        TLP2_stroing_completed = 1'b0 ;
                                    end 
                                    end 
                                    else begin // Comp
                                    tlp2_no_cycles = 1'b1 ; 
                                    buffer_if.data_in = {axi_master_hdr, 32{1'b0}} ;
                                    buffer_if.no_loc_wr = 1'b1;
                                    TLP2_stroing_completed = 1'b1 ;
                                    end 

                                end 
                                RX_ROUTER_CFG : begin 
                                    rx_router_grant = 1'b1 ;
                                                        tlp2_no_cycles = 1'b1 ;
                                                        TLP2_stroing_completed = 1'b1 ;
                                                        buffer_if.no_loc_wr = 1'b1 ;

                                                        // Interface with buffer 
                                                        if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                        buffer_if.data_in = {rx_router_comp_hdr, rx_router_data} ;
                                                        end 
                                                        else begin 
                                                        buffer_if.data_in = {rx_router_comp_hdr, 32{1'b0}} ;
                                                        end 

                                end 
                                RX_ROUTER_ERR : begin 
                                    buffer_if.wr_en = 1'b1 ;                                    
                                    rx_router_grant = 1'b1 ;
                                    // Interface with buffer 
                                    tlp2_no_cycles = 1'b1; // Start with Msg then Comp
                                    buffer_if.data_in = {rx_router_comp_hdr, 32{1'b0}} ;
                                    buffer_if.no_loc_wr = 1'b1 ;
                                    TLP2_stroing_completed = 1'b1 ;
                                end 
                            endcase 
                                                           
                    // State Transition 
                            if ((TLP2_stroing_completed == 1'b0) &&  two_req_on_pipe && !one_req_on_pipe ) begin  // Go to Data of TLP2
                                next_state = TLP2_Data ; 
                                recorder_if.rd_mode = 3'b0 ; // read 1 location from sequence recorder
                                    recorder_if.rd_en = 1'b0 ;
                                    No_rd_loc_seq = 2'b0 ;
                            end 
                            else if (recorder_if.available  != FIFO_DEPTH  && Buffer_Ready)  begin 
                                 next_state = TLP1_HDR ;
                                if (recorder_if.available  == FIFO_DEPTH - 1'b1 ) begin 
                                recorder_if.rd_en = 1'b1 ;
                                recorder_if.rd_mode = 3'b1 ; // read 1 location from sequence recorder
                                No_rd_loc_seq = 2'b1 ;
                                end 
                                else begin 
                                recorder_if.rd_en = 1'b1 ;
                                recorder_if.rd_mode = 3'b10 ; // read 2 locations from sequence recorder
                                No_rd_loc_seq = 2'b10 ;
                                end                
                            end 
                            else begin
                                next_state = IDLE ; 
                                recorder_if.rd_mode = 3'b0 ; // read 1 location from sequence recorder
                                    recorder_if.rd_en = 1'b0 ;
                                    No_rd_loc_seq = 2'b0 ;
                            end  
                            count_tlp1 = '0 ;
                            count_tlp2 = tlp2_no_cycles ;
                            TLP_stored = TLP2_stroing_completed ; 

                        end 
				TLP2_Data : begin 
                    axi_req_wr_grant  = 1'b0 ; 
                    axi_req_rd_grant  = 1'b0 ; 
                    axi_master_grant = 1'b0 ; 
                    rx_router_grant = 1'b0 ;
                    case(source_2) 
                        A2P_1 : begin 
                                        registered_data = axi_req_data [3 * DW - 1 : 0] ; 
                                        // Interface with buffer 
                                        // tlp1_no_cycles = no_cycles_calc (axi_wrreq_hdr.Length);
                                        count_tlp2 = count_tlp2 - 1'b1 ; 
                                        //buffer_if.data_in = {axi_req_data} ;
                                        if ((axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   = 'b0_0000) ) begin  // 64-bit address + Mem
                                            buffer_if.data_in = axi_req_data ;
                                                if (count_tlp2 == 1) begin 
                                                    buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b11, tlp2_no_cycles , 1 );
                                                    TLP2_stroing_completed = 1'b1 ;
                                                end 
                                                else begin 
                                                    buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b10, tlp2_no_cycles , 1 );
                                                    TLP2_stroing_completed = 1'b0 ;
                                                end 
                                            end 
                                        else begin 
                                            buffer_if.data_in = {registered_data, axi_req_data[AXI_MAX_NUM_BYTES * 8 - 1 :  3*DW]} ; 
                                            if (count_tlp2 == 1) begin 
                                                buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b11, tlp2_no_cycles , 0 );
                                                TLP2_stroing_completed = 1'b1 ;
                                            end 
                                            else begin 
                                                buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b10, tlp2_no_cycles , 0 );
                                                TLP2_stroing_completed = 1'b0 ;
                                            end 
                                        end 
                                        end
                        MASTER : begin 
                                                registered_data = axi_comp_data [3 * DW - 1 : 0] ; 
                                                count_tlp2 = count_tlp2 - 1'b1 ; 
                                                // Interface with buffer 
                                                if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) || (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                buffer_if.data_in = {registered_data , axi_comp_data [AXI_MAX_NUM_BYTES * 8 - 1 :  3*DW] }  ;
                                                if (count_tlp2 == 1) begin 
                                                    buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b10, tlp2_no_cycles , 0 );
                                                    TLP2_stroing_completed = 1'b1 ;
                                                end 
                                                else begin 
                                                    buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b11, tlp2_no_cycles , 0 );
                                                    TLP2_stroing_completed = 1'b0 ;
                                                end 
                                                end 
                                                else begin // Comp
                                                tlp2_no_cycles = 1'b1 ; 
                                                buffer_if.data_in = {axi_master_hdr, 32{1'b0}} ;
                                                buffer_if.no_loc_wr = 1'b1;
                                                TLP2_stroing_completed = 1'b1 ;
                                                end 
                        end
                        default : begin 
                            registered_data = '0 ; 
                            source_2 = NO_SOURCE ; 
                            count_tlp2 = 'b0; 
                            // Interface with source itself
                            TLP2_stroing_completed = 1'b0 ;
                            buffer_if.no_loc_wr = 1'b0 ;
                            // Interface with buffer 
                            buffer_if.data_in = '0 ;
                        end														
                    endcase 
                    two_req_on_pipe = 1'b0 ; 
                    // State Transition 
                    if ((TLP2_stroing_completed == 1'b0) &&  two_req_on_pipe && !one_req_on_pipe ) begin  // Keep going on Data of TLP1
                        next_state = TLP2_Data ;
                        recorder_if.rd_mode = 3'b0 ; // read 1 location from sequence recorder
                                    recorder_if.rd_en = 1'b0 ;
                                    No_rd_loc_seq = 2'b0 ;
                    end 
                    else if (recorder_if.available  != FIFO_DEPTH && Buffer_Ready )  begin 
                         next_state = TLP1_HDR ;
                        if (recorder_if.available  == FIFO_DEPTH - 1'b1 ) begin 
                        recorder_if.rd_en = 1'b1 ;
                        recorder_if.rd_mode = 3'b1 ; // read 1 location from sequence recorder
                        No_rd_loc_seq = 2'b1 ;
                        end 
                        else begin 
                        recorder_if.rd_en = 1'b1 ;
                        recorder_if.rd_mode = 3'b10 ; // read 2 locations from sequence recorder
                        No_rd_loc_seq = 2'b10 ;
                        end                
                    end 
                    else begin
                        next_state = IDLE ; 
                        recorder_if.rd_mode = 3'b0 ; // read 1 location from sequence recorder
                        recorder_if.rd_en = 1'b0 ;
                        No_rd_loc_seq = 2'b0 ;
                    end  
                    count_tlp1 = '0 ;
                    count_tlp2 = '0 ;
                    TLP_stored = TLP2_stroing_completed ; 
				end		
            endcase
        end 
endmodule

