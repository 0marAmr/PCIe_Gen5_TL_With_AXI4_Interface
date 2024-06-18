/********************************************************************************************************************************/
/* Module Name	: arbiter_fsm.sv                          		                                                                */
/* Written By	: Mohamed Aladdin Mohamed                                                                                       */
/* Date			: 10-04-2024			                                                                                        */
/* Version		: V1					                                                                                        */
/* Updates		: 					                                
                 - reduce internal signals ( delete most of comb signals with modifying the conditions inside always_comb)
                 - convert the part of code which is responsible for manipulation for data to a function.
                 - in arbiter_idle, can read from seq. recorder if empty --> modify to reduce 1 cycle in case of concurrent tlps
                                                                                                                                */
/* Dependencies	: -						                                                                                        */
/* Used			: Arbiter Top Module                                                                                            */
/* Summary      : This file includes controller of arbiter, it handles the 
                  operation of arbitration stage with interfacing with the following modules: (FC - Ordering - Sequence Recorder 
                  - Axi slave - Axi master - rx router - tlp buffer)                                                            */
/* Acknowledgement :  
                - Make the HDR Coming from Rx Side is a type of struct as slave                             - Ignore
                - Ensure that the layout of bits is FMT, TYPE from MSB                                      - ?
                - Ensure that Msg 3 DW due to last DW is reserved                                           - ? 
                - Enure that both HDR Coming from Rx-side is 3DW only                                       - ? 
                - Data Coming from srcs (D0,D1,D2,---) : D0 is the most                                     - ?
                - I need 1 cycle to seperate between valid for each source in case of subsequent 2 requests - ?                  
                - the header of master (3DW --> FMT,TYPE,............) Length: 2DW + 9 : 2DW                - ?
                - Grant will be one cycle only                                                              - ? 

/********************************************************************************************************************************/

// import packages
import Tx_Arbiter_Package::*;
import Fragmentation_Package::*;
import axi_slave_package::*;

module arbiter_fsm (
    // -----------------------------------------  Global Signals   -----------------------------------------
				   input bit clk,
				   input bit arst,
    // ---------------------- Submodules of Arbiter ( FC - Ordering - Sequence Rec.)  ---------------------- 
		// Interface with sequence recorder
				   Arbiter_FSM_Sequence_Recorder.ARBITER_FSM_SEQUENCE_RECORDER recorder_if,
		// Interface with Ordering 
				   ordering_if.ARBITER_ORDERING_IF ordering_if,
	    // Interface with Flow Control
				   Tx_FC_Interface.ARBITER_FC fc_if,
    // ---------------------- Sources of Arbiter ( AXI Slave - MASTER - Rx Router )  ----------------------- 
        // Interface with Slave (Rd Request and Wr Request)
                   output logic             axi_req_wr_grant,
                   output logic             axi_req_rd_grant,
            // Output of mapper for write
                   input tlp_header_t     axi_wrreq_hdr,
            // Output of mapper for read
                   input tlp_header_t     axi_rdreq_hdr,
            // Output of POP FSM : output from slave to Tx Arbiter (Data for write request)
                   input logic [AXI_MAX_NUM_BYTES * 8 - 1 : 0] axi_req_data,
        // Interface with Master
                   output logic             axi_master_grant,
                   // Output of mapper for master
                   input logic [3*DW - 1 : 0]     axi_master_hdr,                          
                   // Data in case of COMPD
                   input logic [AXI_MAX_NUM_BYTES * 8 - 1 : 0] axi_comp_data,  
        // Interface with Rx Router
                   output logic                    rx_router_grant,
                   input logic [4*DW - 1 : 0]      rx_router_msg_hdr, 
                   input logic [3*DW - 1 : 0]      rx_router_comp_hdr,
                   // Data in case of COMPD
                   input logic [1*DW  - 1 : 0]     rx_router_data,      
    // --------------------------------- Data Fragementation ( Buffer TLP)  --------------------------------- 
        // Interface with Buffer of Data Fragementation
				   buffer_frag_interface.arbiter_buffer buffer_if
);

    // State Definition 
        arbiter_state current_state, next_state ;
    // Internal Signals 
        Tx_Arbiter_Sources_t source_1,source_2 ; 
        logic [1:0] No_rd_loc_seq ; // No. of read locations from sequence recorder
	    logic [5:0] tlp1_no_cycles, tlp1_no_cycles_comb, count_tlp1 ; // Maximum number of cycle is 32 cycle.
        logic [5:0] tlp2_no_cycles, tlp2_no_cycles_comb, count_tlp2 ;
        logic two_req_on_pipe_comb, two_req_on_pipe ; 
        logic [3 * DW - 1 : 0] registered_data, data_comb; 
        logic [9 : 0 ] data_length_comb , data_length ; 
   

    // Calculating the number of required cycles to recieve the data from requester/completer   
        /*
          Length_field ----> all zeros : Length = 1024 DW , No. data_cycle = 1024/32 = 32
                             O.W       : No. Data_cycle = Length / 32 + ( 1 "if mod != 0" OR 0 "if mod == 0")
        */
    function logic [5:0] no_cycles_calc (
                                        input logic [9:0] length_Data );
                        logic [5:0] no_cycles ;
                        if (length_Data == 10'b0) begin  // 1024 DW
                            no_cycles =  6'b10_0000;   
                        end
                        else if (length_Data > 10'b00_0010_0000) begin  // > 32 
                            no_cycles = length_Data >> 5 ;
                            if (length_Data - (no_cycles << 5) != 'b0) begin 
                                no_cycles = no_cycles + 6'd1 ; 
                            end 
                        end 
                        else begin 
                            no_cycles =  6'd1 ; 
                        end                                    
            return no_cycles ; 
    endfunction 

    // this function is responsible for calculating no. of write loc. in buffer of TLP (HDR + Data)
        // the output depends on which cycle will be calling the function so one of the input is last_cycle mode 
    function logic [NO_LOC_WR_WIDTH - 1 :0] no_wr_loc ( 
                                                      input logic [9:0] length_Data, 
                                                      input logic [1:0] last_cycle, // 00 --> first_last_cycle - 01--> first_cycle - 10 --> intermidate_cycle - 11 --> last_cycle
                                                      input logic [5:0] no_cycles, // Total Number of Cycles needed to send it to TLP Buffer
                                                      input logic HDR_3DW_4DW );
                    logic [NO_LOC_WR_WIDTH - 1 : 0] no_wr_loc_sig ; 
                    logic [9:0]                     length_temp   ;  // it will use to store the actual length of rest data after [total cycles - 1] (last cycle)
                    logic [9:0]                     temp1, temp2  ;  // both signals have different logic depending on the case but overall both signals are temp signals used. 
                    if (HDR_3DW_4DW) begin  // 4 DW HDR
                        if (length_Data == 10'b0000_0000_00) begin  // 1024 DW  [ 1st cycle: 1 'HDR' + 8 'D'] [intermid. cycle: 8'D'] [last cycle: 8'D']
                            if ((last_cycle == 2'b11) ||(last_cycle == 2'b10)) begin  // last cycle && intermidate cycles
                                no_wr_loc_sig =  4'b1000;   // here, we will write 8 locations completely 
                            end 
                            else if (last_cycle == 2'b01) begin 
                                no_wr_loc_sig =  4'b1001;   // 9 locations = 8 data + 1 hdr 
                            end 
                            else begin  // Not valid here 1024 DW can't be first_cycle and last_cycle together 
                                no_wr_loc_sig =  4'b0000; 
                            end 
                            length_temp = '0; 
                          end
                        else begin 
                            case (last_cycle)
                                2'b00 : begin  // first cycle and last cycle, means that the TLP will be sent in one cycle
                                    temp1 = length_Data >> 2 ;  // divide by 4 to know, no. of wr. loc. 
                                    length_temp = '0; 
                                    if (length_Data - (temp1 << 2) != 'b0) begin  // here 65 DW for example, No.cycles = 17
                                        temp2 = temp1 + 1'b1 ; 
                                    end 
                                    else begin  // here 64 DW for example, No.cycles = 64 / 4 =  16
                                        temp2 = temp1 ; 
                                    end 
                                    no_wr_loc_sig = 1'b1 + temp2 ;  // include header with data ( temp2 --> no of cycles for data only )
                                end 
                                2'b01 : begin  // first cycle in multi cycles TLP
                                    no_wr_loc_sig = 4'b1001 ;  // 8 data + 1 hdr
                                    length_temp = '0; 
                                end 
                                2'b10 : begin  // intermidate cycle in multi cycles TLP
                                    no_wr_loc_sig = 4'b1000 ; // 8 locs
                                    length_temp = '0; 
                                end
                                2'b11 : begin  // last cycle in multi cycles TLP
                                    // first calculating the rest of length 
                                   temp1 = (no_cycles - 2'b01) << 5 ; // total number of DW sent before last 
                                   length_temp = length_Data - temp1;
                                   temp2 = length_temp >> 2 ;
                                    if (length_temp - (temp2 << 2) != 'b0) begin 
                                        no_wr_loc_sig = temp2 + 1'b1 ; 
                                    end 
                                    else begin  
                                        no_wr_loc_sig = temp2 ; 
                                    end 
                                end 
                            endcase 
                          end 
                    end 
                    else begin  // 3 DW HDR 
                        // Note here there is a difference between the 3DW HDR and 4DW HDR, in 4: 9 8 8 8 ..... X || in 3: 8 8 8 8 8 8 8 ...... X
                        if (length_Data == 10'b0) begin  // 1024 DW  [ 1st cycle: 1 'HDR + 1dw of data' + 8 'D'] [intermid. cycle: 8'D'] [last cycle: 8'D']
                                if ((last_cycle == 2'b11) ) begin  // last cycle 
                                    no_wr_loc_sig =  4'b1001;    //  32 DW --> 8 loc  + 3 DW --> 1 loc
                                end 
                                else if (last_cycle == 2'b01) begin  // first cycle 
                                    no_wr_loc_sig =  4'b1000;  // 1 loc to store (HDR + first DW of Data) , 7 loc to store 28 DW of Data --> total number of loc. = 1 + 7
                                end 
                                else if (last_cycle == 2'b10) begin //  intermidate cycles
                                    no_wr_loc_sig =  4'b1000;  // 8 Loc. to store 32 DW
                                end 
                                else begin 
                                    no_wr_loc_sig =  4'b0000; 
                                end 
                                length_temp = '0; 
                        end 
                        else begin 
                            case (last_cycle)
                                2'b00 : begin  // first cycle and last cycle, means that the TLP will be sent in one cycle
                                    length_temp = length_Data - 1'b1 ; // because 1 DW will go to with 3 DW of Header
                                    temp1 = length_temp >> 2 ;
                                    if (length_temp - (temp1 << 2) != 'b0) begin 
                                        temp2 = temp1 + 1'b1 ; 
                                    end 
                                    else begin  // here 64 DW for example, No.cycles = 
                                        temp2 = temp1 ; 
                                        length_temp = '0; 
                                    end 
                                    no_wr_loc_sig = 1'b1 + temp2 ; 
                                end 
                                2'b01 : begin  // first cycle in multi cycles TLP
                                    no_wr_loc_sig = 4'b1000 ;  // 1 + 7
                                    length_temp = '0; 
                                end 
                                2'b10 : begin  // intermediate cycle in multi cycles TLP
                                    no_wr_loc_sig = 4'b1000 ; // 0 + 8
                                    length_temp = '0; 
                                end
                                2'b11 : begin  // last cycle in multi cycles TLP
                                        if (((length_Data - 6'd29 - 6'd32 * (no_cycles - 2'b10)) % 4) != 1'b0) begin 
                                            no_wr_loc_sig = (length_Data - 6'd29 - 6'd32 * (no_cycles - 2'b10)) / 4  + 1 ; 
                                        end 
                                        else begin 
                                            no_wr_loc_sig = (length_Data - 6'd29 - 6'd32 * (no_cycles - 2'b10)) / 4  ; 
                                        end 
                                end
                            endcase 
                        end 
                    end
            return no_wr_loc_sig ; 
    endfunction 

    always_ff @(posedge clk or negedge arst) begin: Next_State_FF 
        if (!arst) begin 
			current_state           <= ARBITER_IDLE;
			No_rd_loc_seq           <= 2'b00;
			registered_data         <= '0; 
			source_1                <= NO_SOURCE;
			source_2                <= NO_SOURCE ;
			two_req_on_pipe         <= '0;
			tlp2_no_cycles          <='0 ;
			tlp1_no_cycles          <='0 ;
			count_tlp1              <= '0 ;
			count_tlp2              <= '0 ;
            data_length             <= '0 ; 
        end 
        else begin 
            current_state <= next_state;
            case (current_state)
                ARBITER_IDLE : begin 
                    No_rd_loc_seq           <= 2'b00;
			        registered_data         <= '0; 
			        source_1                <= NO_SOURCE;
			        source_2                <= NO_SOURCE ;
			        two_req_on_pipe         <= '0;
			        tlp2_no_cycles          <='0 ;
			        tlp1_no_cycles          <='0 ;
			        count_tlp1              <= '0 ;
			        count_tlp2              <= '0 ;
                    data_length             <= '0 ;
                    if (recorder_if.rd_en) begin 
                        No_rd_loc_seq       <= recorder_if.rd_mode; 
                    end 
                end 
                TLP1_HDR : begin 
							// Assigning the signals of grant & Pushing to TLP Buffer & Sequence recorder buffer
							case (fc_if.Result) 
								FC_SUCCESS_1 : begin 
                                    two_req_on_pipe <= 1'b0 ;
                                    source_1 <= recorder_if.rd_data_1 ; 
									case(recorder_if.rd_data_1) 
										A2P_1 : begin 
											// source_1 <= A2P_1 ; 
											// Interface with buffer 
											tlp1_no_cycles <=tlp1_no_cycles_comb;
                                            count_tlp1 <= tlp1_no_cycles_comb - 1'b1   ;
                                            data_length <= data_length_comb ; 

											if (!((axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   == 'b0_0000))) begin  // 64-bit address + Mem
                                                registered_data <= data_comb ; 
											end 										
											end
										A2P_2 : begin 
											// source_1 <= A2P_2; 
											tlp1_no_cycles <= 1'b1;
                                            count_tlp1 <= 1'b0 ;

											end
										MASTER : begin 
											// source_1 <= MASTER ; 
                                            tlp1_no_cycles <= tlp1_no_cycles_comb ; 
                                            registered_data <= data_comb ; 
                                            count_tlp1 <= tlp1_no_cycles_comb - 1'b1 ;
                                            data_length <= data_length_comb ; 
										end
										RX_ROUTER_CFG : begin 
											// source_1 <= RX_ROUTER_CFG ; 
											tlp1_no_cycles <= 1'b1 ;
                                            count_tlp1 <= 1'b0 ;
										end
                                        RX_ROUTER_ERR : begin 
                                            source_2 <= recorder_if.rd_data_1 ;
                                        end 
									endcase
								end 
								FC_SUCCESS_2 : begin 
                                    two_req_on_pipe <= 1'b1 ;
                                    source_1 <= recorder_if.rd_data_2 ; 
								   case(recorder_if.rd_data_2) 
										A2P_1 : begin 
											// Interface with buffer 
											tlp1_no_cycles <= no_cycles_calc (axi_wrreq_hdr.Length);
                                            count_tlp1 <= no_cycles_calc (axi_wrreq_hdr.Length)  - 1'b1 ;
                                            data_length <= data_length_comb ; 
											if (!((axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   == 'b0_0000))) begin  // 64-bit address + Mem
												registered_data <= axi_req_data [3 * DW - 1 : 0];
											end 										
											end
										A2P_2 : begin 
											tlp1_no_cycles <= 1'b1;
                                            count_tlp1 <= 1'b0 ;

											end
										MASTER : begin 
											// Interface with buffer 
											if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
												tlp1_no_cycles <= no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] );
                                                count_tlp1 <= no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] ) - 1'b1 ;
												registered_data <= axi_comp_data [3 * DW - 1 : 0] ; 
											end 
											else begin // Comp
											tlp1_no_cycles <= 1'b1 ; 
                                            count_tlp1 <= 1'b0 ;

											end 
										end
										RX_ROUTER_CFG : begin 
											tlp1_no_cycles <= 1'b1 ;
                                            count_tlp1 <= 1'b0 ;
										end
                                        RX_ROUTER_ERR : begin 
                                            source_1 <= recorder_if.rd_data_2 ;
                                        end 
									endcase
								end 
								FC_SUCCESS_1_2 : begin 
									if ((recorder_if.rd_data_1 != RX_ROUTER_ERR) && (recorder_if.rd_data_2 != RX_ROUTER_ERR) ) begin 
										source_1 <= recorder_if.rd_data_1 ; 
										source_2 <= recorder_if.rd_data_2 ;
										two_req_on_pipe <= 1'b1 ;
										case(recorder_if.rd_data_1) 
										    A2P_1 : begin 
											    tlp1_no_cycles <= tlp1_no_cycles_comb ;
                                                count_tlp1 <= tlp1_no_cycles_comb - 1'b1  ;
                                                data_length <= data_length_comb ; 
											    if (!((axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   == 'b0_0000))) begin  // 64-bit address + Mem
											    	registered_data <= axi_req_data [3 * DW - 1 : 0];										
											    end
                                            end 
										    A2P_2 : begin 
											    tlp1_no_cycles <= 1'b1;
                                                count_tlp1 <= 1'b0 ;
											end
										    MASTER : begin 
											    // Interface with buffer 
											    if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
											    	tlp1_no_cycles <= no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] );
											    	registered_data <= axi_comp_data [3 * DW - 1 : 0] ; 
                                                    count_tlp1 <= no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] ) - 1'b1 ;
											    end 
											    else begin // Comp
											        tlp1_no_cycles <= 1'b1 ; 
                                                    count_tlp1 <=1'b0 ;
											    end 
										end
										    RX_ROUTER_CFG : begin 
											    tlp1_no_cycles <= 1'b1 ;
                                                count_tlp1 <= 1'b0;    
										end
                                        endcase
									end 
									else if ((recorder_if.rd_data_1 != RX_ROUTER_ERR) && (recorder_if.rd_data_2 == RX_ROUTER_ERR)) begin  // Push the second request 
                                        source_1 <= recorder_if.rd_data_1 ; 
                                        source_2 <= NO_SOURCE;									
                                        two_req_on_pipe         <= 1'b0 ;
                                        case(recorder_if.rd_data_1) 
											A2P_1 : begin 
												tlp1_no_cycles <= tlp1_no_cycles_comb ;
                                                count_tlp1 <= tlp1_no_cycles_comb - 1'b1  ;
                                                data_length <= data_length_comb ; 
											    if (!((axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   == 'b0_0000))) begin  // 64-bit address + Mem
											    	registered_data <= axi_req_data [3 * DW - 1 : 0];										
											    end 										
												end
											A2P_2 : begin 
                                                tlp1_no_cycles <= 1'b1;
                                                count_tlp1 <= 1'b0 ;												
                                            end 
											MASTER : begin 
												 // Interface with buffer 
											    if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
											    	tlp1_no_cycles <= no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] );
											    	registered_data <= axi_comp_data [3 * DW - 1 : 0] ; 
                                                    count_tlp1 <= no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] ) - 1'b1 ;
											    end 
											    else begin // Comp
											        tlp1_no_cycles <= 1'b1 ; 
                                                    count_tlp1 <=1'b0 ;
											    end 
											end
											RX_ROUTER_CFG : begin 
                                                tlp1_no_cycles <= 1'b1 ;
                                                count_tlp1 <= 1'b0;											
                                            end 
										endcase
									end 
									else if ((recorder_if.rd_data_1 == RX_ROUTER_ERR)) begin 
										two_req_on_pipe         <= 1'b1 ;
										source_1                <= recorder_if.rd_data_1 ; 
										source_2                <= recorder_if.rd_data_1 ; // here source1 = source 2 = rx router err
										tlp1_no_cycles          <= 1'b1; // Start with Msg then COMPD
                                        tlp2_no_cycles          <= 1'b1 ; 
									end 
									end 
							endcase 

							if (recorder_if.rd_en) begin 
                                No_rd_loc_seq       <= recorder_if.rd_mode; 
                            end 

							if ((tlp1_no_cycles_comb == 1'b1) && (buffer_if.empty)) begin 
								source_1 <= NO_SOURCE ; 
							end 
							end							
                TLP1_Data : begin 
					// Output of State
					case(source_1) 
						A2P_1 : begin 
                            registered_data <= data_comb ; 
							if (count_tlp1 != 1'b0) begin 
								count_tlp1 <= count_tlp1 - 1'b1 ;
							end							
							end
						MASTER : begin 
                            registered_data <= data_comb ; 
							if (count_tlp1 != 1'b0) begin 
								count_tlp1 <= count_tlp1 - 1'b1 ;
							end							
						end
					endcase    

					if (recorder_if.rd_en) begin 
                        No_rd_loc_seq       <= recorder_if.rd_mode; 
                    end 
					if (count_tlp1 == 1'b1) begin 
						source_1	<= 	NO_SOURCE ; 			
					end
				end 
				TLP2_HDR : begin 
                    // Output of State
					tlp1_no_cycles <= '0;
					count_tlp1 <= '0 ;
                    source_1 <= NO_SOURCE ; 
					case (source_2)
						A2P_1 : begin 
							// Interface with buffer 
							tlp2_no_cycles <= tlp2_no_cycles_comb;
                            count_tlp2 <= tlp2_no_cycles_comb  - 1'b1;
                            data_length <= data_length_comb ; 
							if (((axi_wrreq_hdr.FMT   == TLP_FMT_3DW_DATA)  && (axi_wrreq_hdr.TYP   == 'b0_0000))) begin  // 32-bit address + Mem
								registered_data <= axi_comp_data [3 * DW - 1 : 0] ;  
							end 
						end 
						MASTER : begin 
                            tlp2_no_cycles <= tlp2_no_cycles_comb ; 
                            registered_data <= data_comb ; 
                            count_tlp2 <= tlp2_no_cycles_comb - 1'b1 ;
                            data_length <= data_length_comb ;
						end 
					endcase 
					// State Transition 
					if (recorder_if.rd_en) begin 
                        No_rd_loc_seq       <= recorder_if.rd_mode; 
                    end 
                    if ((tlp2_no_cycles_comb == 1'b1) && (buffer_if.empty)) begin 
                        source_2 <= NO_SOURCE ; 
                        two_req_on_pipe <= 1'b0 ; 

                    end 
					end 
				TLP2_Data : begin 
                    // Output of State
					case(source_2) 
						A2P_1 : begin 
							registered_data <= data_comb ; 
							if (count_tlp2 != 1'b0) begin 
								count_tlp2 <= count_tlp2 - 1'b1 ;
							end							
							end
						MASTER : begin 
							registered_data <= data_comb ; 
							if (count_tlp2 != 1'b0) begin 
								count_tlp2 <= count_tlp2 - 1'b1 ;
							end						
						    end
					endcase    
					if (recorder_if.rd_en) begin 
                        No_rd_loc_seq       <= recorder_if.rd_mode; 
                    end 
					if (count_tlp2 == 1'b1) begin 
						source_2	<= 	NO_SOURCE ; 			
                        two_req_on_pipe <= 1'b0 ; 
					end
				end
            endcase
            end 
    end: Next_State_FF



    
    always_comb begin : Next_State_and_Output_Encoder
			/* Default Values */
                // state 
				    next_state = ARBITER_IDLE ; 
                // grant for sources ( axi slave - axi master - rx router)
				    axi_req_wr_grant  = 1'b0  ; 
				    axi_req_rd_grant  = 1'b0  ; 
				    axi_master_grant  = 1'b0  ; 
				    rx_router_grant   = 1'b0  ;
                // sequence recorder interface
                    // read port 
				    recorder_if.rd_mode   = 2'b00 ; 
				    recorder_if.rd_en     = 1'b0  ;
                    // write port
                    recorder_if.wr_data_2 = NO_SOURCE ; 
				    recorder_if.wr_data_1 = NO_SOURCE ; 
				    recorder_if.wr_mode   = 2'b00 ; 
				    recorder_if.wr_en     = 'b0 ; 
                // TLP Buffer interface 
				    buffer_if.no_loc_wr =  '0   ; 
				    buffer_if.data_in   =  '0   ;
				    buffer_if.wr_en     =  '0   ; 
                // flow control interface 
				    fc_if.Command_2 = FC_DEFAULT ; 
				    fc_if.Command_1 = FC_DEFAULT ; 
				    fc_if.PTLP_2    = 'b0 ; 
				    fc_if.PTLP_1    = 'b0 ; 
                // ordering interface 
				    ordering_if.comp_typ        = 'b0    ; 
                    ordering_if.first_trans_ID  = 'b0    ;
				    ordering_if.second_trans_ID = 'b0    ;
                    ordering_if.first_IDO       = 1'b0   ; 
				    ordering_if.second_IDO      = 1'b0   ; 
                    ordering_if.first_RO        = 1'b0   ; 
				    ordering_if.second_RO       = 1'b0   ; 
                    ordering_if.first_trans     = No_Req ; 
				    ordering_if.second_trans    = No_Req ;
                // Internal Signals 				
				    tlp1_no_cycles_comb  = 1'b0  ;
                    two_req_on_pipe_comb = 1'b0  ; 
                    tlp2_no_cycles_comb  = 1'b0  ; 
                    data_comb            = '0    ;
                    data_length_comb     = '0    ; 

			/*************************************************/
         	/* State Output and states transition */   
		case (current_state)
					ARBITER_IDLE : begin 
						// State Transition 
						if ((recorder_if.available  != SEQ_FIFO_DEPTH) && buffer_if.empty)   
							begin 
								next_state = TLP1_HDR ;
								if (recorder_if.available  == SEQ_FIFO_DEPTH - 1'b1 )
									begin 
										recorder_if.rd_en   = 1'b1 ;
										recorder_if.rd_mode = 2'b01 ; // read 1 location from sequence recorder
									end 
								else begin 
										recorder_if.rd_en   = 1'b1 ;
										recorder_if.rd_mode = 2'b10 ; // read 2 locations from sequence recorder
								end                
							end 
						else begin
								next_state = ARBITER_IDLE ; 
						end                 
					end 
					TLP1_HDR : begin 
						// check FC and Ordering
                        if (buffer_if.empty) begin 
                            case (recorder_if.rd_data_1)
                                A2P_1: begin 
                                    fc_if.PTLP_1 = axi_wrreq_hdr.Length; 
                                    if (axi_wrreq_hdr.TYP   == 'b0_0000)  begin // MEMwr
                                        fc_if.Command_1 = FC_P_D; 
                                    end 
                                    else if (axi_wrreq_hdr.TYP   == 'b0_0010) begin // IOWr
                                        fc_if.Command_1 = FC_NP_D;
                                    end 
                                    if (No_rd_loc_seq == 2'b10) begin
                                        case (recorder_if.rd_data_2) 
                                            A2P_2: begin 
                                                if (axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   == 2'b10 )  begin // for Msg inside A2P2
                                                    fc_if.Command_2 = FC_P_H ;
                                                    fc_if.PTLP_2 = '0 ;
                                                end 
                                                else if (axi_rdreq_hdr.TYP == '0) begin  // Memrd
                                                    fc_if.Command_2 = FC_NP_H ;
                                                    fc_if.PTLP_2 = '0 ;
                                                end 
                                            end 
                                            MASTER: begin 
                                                if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                    fc_if.Command_2 = FC_CPL_D  ;
                                                    fc_if.PTLP_2 = axi_master_hdr[ 2*DW + 9 : 2*DW] ;
                                                end 
                                                else begin  // COMP
                                                    fc_if.Command_2 = FC_CPL_H  ;
                                                    fc_if.PTLP_2 = '0 ;
                                                end
                                            end 
                                            RX_ROUTER_CFG: begin 
                                                if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                    fc_if.Command_2 = FC_CPL_D  ;
                                                    fc_if.PTLP_2 = rx_router_comp_hdr[ 2*DW + 9 : 2*DW] ;
                                                end 
                                                else begin  // COMP
                                                    fc_if.Command_2 = FC_CPL_H  ;
                                                    fc_if.PTLP_2 = '0 ;
                                                end
                                            end 
                                            RX_ROUTER_ERR: begin  
                                                fc_if.Command_2 = FC_ERR ; 
                                                fc_if.PTLP_2 = '0;
                                            end  
                                        endcase
                                    end 
                                end 
                                A2P_2: begin 
                                    if (axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   == 2'b10 )  begin // for Msg inside A2P2
                                        fc_if.Command_1 = FC_P_H ;
                                        fc_if.PTLP_1 = '0 ;
                                    end 
                                    else if (axi_rdreq_hdr.TYP == '0) begin  // Memrd
                                        fc_if.Command_1 = FC_NP_H ;
                                        fc_if.PTLP_1 = '0 ;
                                    end 
                                    if (No_rd_loc_seq == 2'b10) begin
                                        case (recorder_if.rd_data_2) 
                                            A2P_1: begin 
                                            fc_if.PTLP_2 = axi_wrreq_hdr.Length; 
                                            if (axi_wrreq_hdr.TYP   == 'b0_0000)  begin // MEMwr
                                                fc_if.Command_2 = FC_P_D; 
                                            end 
                                            else if (axi_wrreq_hdr.TYP   == 'b0_0010) begin // IOWr
                                                fc_if.Command_2 = FC_NP_D;
                                    end 
                                        end 
                                            MASTER: begin 
                                            if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                fc_if.Command_2 = FC_CPL_D  ;
                                                fc_if.PTLP_2 = axi_master_hdr[ 2*DW + 9 : 2*DW] ;
                                            end 
                                            else begin  // COMP
                                                fc_if.Command_2 = FC_CPL_H  ;
                                                fc_if.PTLP_2 = '0 ;
                                            end
                                        end 
                                            RX_ROUTER_CFG: begin 
                                                if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                fc_if.Command_2 = FC_CPL_D  ;
                                                fc_if.PTLP_2 = rx_router_comp_hdr[ 2*DW + 9 : 2*DW] ;
                                            end 
                                                else begin  // COMP
                                                fc_if.Command_2 = FC_CPL_H  ;
                                                fc_if.PTLP_2 = '0 ;
                                            end
                                            end 
                                            RX_ROUTER_ERR: begin  
                                                fc_if.Command_2 = FC_ERR ; 
                                                fc_if.PTLP_2 = '0;
                                            end  
                                        endcase
                                    end 
                                end 
                                MASTER: begin 
                                    if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                        fc_if.Command_1 = FC_CPL_D  ;
                                        fc_if.PTLP_1 = axi_master_hdr[ 2*DW + 9 : 2*DW] ;
                                    end 
                                    else begin  // COMP
                                        fc_if.Command_1 = FC_CPL_H  ;
                                        fc_if.PTLP_1 = '0 ;
                                    end
                                    if (No_rd_loc_seq == 2'b10) begin
                                        case (recorder_if.rd_data_2) 
                                            A2P_1: begin 
                                                    fc_if.PTLP_2 = axi_wrreq_hdr.Length; 
                                                    if (axi_wrreq_hdr.TYP   == 'b0_0000)  begin // MEMwr
                                                        fc_if.Command_2 = FC_P_D; 
                                                    end 
                                                    else if (axi_wrreq_hdr.TYP   == 'b0_0010) begin // IOWr
                                                        fc_if.Command_2 = FC_NP_D;
                                                    end 
                                                end 
                                            A2P_2: begin 
                                                if (axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   == 2'b10 )  begin // for Msg inside A2P2
                                                    fc_if.Command_2 = FC_P_H ;
                                                    fc_if.PTLP_2 = '0 ;
                                                end 
                                                else if (axi_rdreq_hdr.TYP == '0) begin  // Memrd
                                                    fc_if.Command_2 = FC_NP_H ;
                                                    fc_if.PTLP_2 = '0 ;
                                                end 
                                            end 
                                            RX_ROUTER_CFG: begin 
                                                if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                    fc_if.Command_2 = FC_CPL_D  ;
                                                    fc_if.PTLP_2 = rx_router_comp_hdr[ 2*DW + 9 : 2*DW] ;
                                                end 
                                                else begin  // COMP
                                                fc_if.Command_2 = FC_CPL_H  ;
                                                fc_if.PTLP_2 = '0 ;
                                            end
                                            end 
                                            RX_ROUTER_ERR: begin  
                                                fc_if.Command_2 = FC_ERR ; 
                                                fc_if.PTLP_2 = '0;
                                            end  
                                        endcase
                                    end 
                                    end 
                                RX_ROUTER_CFG: begin 
                                    if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                        fc_if.Command_1 = FC_CPL_D  ;
                                        fc_if.PTLP_1 = rx_router_comp_hdr[ 2*DW + 9 : 2*DW] ;
                                    end 
                                    else begin  // COMP
                                        fc_if.Command_1 = FC_CPL_H  ;
                                        fc_if.PTLP_1 = '0 ;
                                    end	
                                    if (No_rd_loc_seq == 2'b10) begin
                                        case (recorder_if.rd_data_2) 
                                            A2P_1: begin 
                                                fc_if.PTLP_2 = axi_wrreq_hdr.Length; 
                                                if (axi_wrreq_hdr.TYP   == 'b0_0000)  begin // MEMwr
                                                    fc_if.Command_2 = FC_P_D; 
                                                end 
                                                else if (axi_wrreq_hdr.TYP   == 'b0_0010) begin // IOWr
                                                fc_if.Command_2 = FC_NP_D;
                                                end 
                                            end 
                                            MASTER: begin 
                                                if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                    fc_if.Command_2 = FC_CPL_D  ;
                                                    fc_if.PTLP_2 = axi_master_hdr[ 2*DW + 9 : 2*DW] ;
                                                end 
                                                else begin  // COMP
                                                    fc_if.Command_2 = FC_CPL_H  ;
                                                    fc_if.PTLP_2 = '0 ;
                                                end
                                            end 
                                            A2P_2: begin 
                                                if (axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   == 2'b10 )  begin // for Msg inside A2P2
                                                    fc_if.Command_2 = FC_P_H ;
                                                    fc_if.PTLP_2 = '0 ;
                                                end 
                                                else if (axi_rdreq_hdr.TYP == '0) begin  // Memrd
                                                    fc_if.Command_2 = FC_NP_H ;
                                                    fc_if.PTLP_2 = '0 ;
                                                end 
                                            end
                                            RX_ROUTER_ERR: begin  
                                                fc_if.Command_2 = FC_ERR ; 
                                                fc_if.PTLP_2 = '0;
                                            end  
                                        endcase
                                    end 
                                    end 
                                RX_ROUTER_ERR: begin 
                                    fc_if.Command_1 = FC_ERR ; 
                                    fc_if.PTLP_1 = '0;
                                    if (No_rd_loc_seq == 2'b10) begin
                                        case (source_2) 
                                            A2P_1: begin 
                                                fc_if.PTLP_2 = axi_wrreq_hdr.Length; 
                                                if (axi_wrreq_hdr.TYP   == 'b0_0000)  begin // MEMwr
                                                    fc_if.Command_2 = FC_P_D; 
                                                end 
                                                else if (axi_wrreq_hdr.TYP   == 'b0_0010) begin // IOWr
                                                    fc_if.Command_2 = FC_NP_D;
                                                end 
                                            end 
                                            MASTER: begin 
                                                    if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                        fc_if.Command_2 = FC_CPL_D  ;
                                                        fc_if.PTLP_2 = axi_master_hdr[ 2*DW + 9 : 2*DW] ;
                                                    end 
                                                    else begin  // COMP
                                                        fc_if.Command_2 = FC_CPL_H  ;
                                                        fc_if.PTLP_2 = '0 ;
                                                    end
                                            end 
                                            RX_ROUTER_CFG: begin 
                                                    if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                        fc_if.Command_2 = FC_CPL_D  ;
                                                        fc_if.PTLP_2 = rx_router_comp_hdr[ 2*DW + 9 : 2*DW] ;
                                                    end 
                                                    else begin  // COMP
                                                        fc_if.Command_2 = FC_CPL_H  ;
                                                        fc_if.PTLP_2 = '0 ;
                                                    end
                                            end 
                                            A2P_2: begin  
                                                if (axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   == 2'b10 )  begin // for Msg inside A2P2
                                                    fc_if.Command_2 = FC_P_H ;
                                                    fc_if.PTLP_2 = '0 ;
                                                end 
                                                else if (axi_rdreq_hdr.TYP == '0) begin  // Memrd
                                                    fc_if.Command_2 = FC_NP_H ;
                                                    fc_if.PTLP_2 = '0 ;
                                                end 
                                            end  
                                        endcase
                                    end 
                                end 	
                                default: begin
                                    fc_if.Command_2 = FC_DEFAULT; 
                                    fc_if.Command_1 = FC_DEFAULT ; 
                                    fc_if.PTLP_2    = 'b0 ; 
                                    fc_if.PTLP_1    = 'b0 ; 
                                end		
                            endcase
                        end 
						// Check Ordering
                            case ({recorder_if.rd_data_1,recorder_if.rd_data_2}) 
                                {A2P_1,A2P_2}   : begin 
                                                // Posted Condition for MemWr either 64-bit address or 32-bit address
                                                if ((axi_wrreq_hdr.FMT   == TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   == 'b0_0000)  begin
                                                    ordering_if.first_trans = Posted_Req ; 
                                                end 
                                                else begin 
                                                    ordering_if.first_trans = Non_Posted_Req ; 
                                                end
                                                // Non-Posted Request (Msg)
                                                if (axi_rdreq_hdr.FMT   == TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   == 2'b10 )  begin
                                                    ordering_if.second_trans = Posted_Req ;
                                                end 
                                                else begin 
                                                    ordering_if.second_trans = Non_Posted_Req ;
                                                end
                                                
                                                ordering_if.first_RO = axi_wrreq_hdr.Attr[1];
                                                ordering_if.first_IDO = axi_wrreq_hdr.ATTR;
                                                ordering_if.first_trans_ID = axi_wrreq_hdr.Requester_ID ;
                    
                                                ordering_if.comp_typ = 1'b0;
                                                
                                                ordering_if.second_RO = axi_rdreq_hdr.Attr[1];
                                                ordering_if.second_IDO = axi_rdreq_hdr.ATTR ;
                                                ordering_if.second_trans_ID = axi_rdreq_hdr.Requester_ID ;
                                end 
                                {A2P_1,MASTER}   : begin 
                                                 // Posted Condition for MemWr either 64-bit address or 32-bit address
                                                    if ((axi_wrreq_hdr.FMT   == TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   == 'b0_0000)  begin
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
                                                    ordering_if.comp_typ = 1'b0; // I can't Determine unless Cfg wr due to different paths                                
                                                    /*  
                                                        95 : 0  -->  95 - 16 - 3 = 76  && 95 - 8 - 6 = 81 && [63:48]
                                                        15 : 0 , 31 : 16 , 47 : 32 , 63 : 48 
                                                    */ 
                                end 
                                {A2P_1,RX_ROUTER_CFG}   : begin 
                                                // Posted Condition for MemWr either 64-bit address or 32-bit address
                                                if ((axi_wrreq_hdr.FMT   == TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   == 'b0_0000)  begin
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
                                                            ordering_if.comp_typ = 1'b1; // CFG Wr
                                                    end 
                                                else begin 
                                                            ordering_if.comp_typ = 1'b0; // not CFG Wr
                                                    end                                                     
                                end 
                                {A2P_1,RX_ROUTER_ERR}   : begin 
                                                // Posted Condition for MemWr either 64-bit address or 32-bit address
                                                if ((axi_wrreq_hdr.FMT   == TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   == 'b0_0000)  begin
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
                                                ordering_if.comp_typ = 1'b0; 
                    
                                                
                                end
                                {A2P_2,A2P_1}   : begin 
                                                 // Non-Posted Request (Msg)
                                                if (axi_rdreq_hdr.FMT   == TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   == 2'b10 )  begin
                                                    ordering_if.first_trans = Posted_Req ;
                                                end 
                                                else begin 
                                                    ordering_if.first_trans = Non_Posted_Req ;
                                                end
                                                ordering_if.first_RO = axi_rdreq_hdr.Attr[1];
                                                ordering_if.first_IDO = axi_rdreq_hdr.ATTR ;
                                                ordering_if.first_trans_ID = axi_rdreq_hdr.Requester_ID ;
                                                ordering_if.comp_typ = 1'b0;
                                                
                                                // Posted Condition for MemWr either 64-bit address or 32-bit address
                                                if ((axi_wrreq_hdr.FMT   == TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   == 'b0_0000)  begin
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
                                                    if (axi_rdreq_hdr.FMT   == TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   == 2'b10 )  begin
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
                                                    ordering_if.comp_typ = 1'b0; // I can't Determine unless Cfg wr due to different paths
                                
                                end 
                                {A2P_2,RX_ROUTER_CFG}   : begin 
                                                    // Non-Posted Request (Msg)
                                                    if (axi_rdreq_hdr.FMT   == TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   == 2'b10 )  begin
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
                                                            ordering_if.comp_typ = 1'b1; // CFG Wr
                                                        end 
                                                        else begin 
                                                            ordering_if.comp_typ = 1'b0; // not CFG Wr
                                                        end 
                                end 
                                {A2P_2,RX_ROUTER_ERR}   : begin 
                                                        // Non-Posted Request (Msg)
                                                        if (axi_rdreq_hdr.FMT   == TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   == 2'b10 )  begin
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
                                                        ordering_if.comp_typ = 1'b0; 
                                end 
                                {MASTER,A2P_2}   : begin 
                                                    // Non-Posted Request (Msg)
                                                    if (axi_rdreq_hdr.FMT   == TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   == 2'b10 )  begin
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
                                                    ordering_if.comp_typ = 1'b0; // I can't Determine unless Cfg wr due to different paths
                                
                                end 
                                {MASTER,A2P_1}   : begin 
                                // Posted Condition for MemWr either 64-bit address or 32-bit address
                                    if ((axi_wrreq_hdr.FMT   == TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   == 'b0_0000)  begin
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
                                    ordering_if.comp_typ = 1'b0; // I can't Determine unless Cfg wr due to different paths
                                
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
                                                ordering_if.comp_typ = 1'b1; // CFG Wr
                                            end 
                                        else begin 
                                                ordering_if.comp_typ = 1'b0; // not CFG Wr
                                            end
                                end 
                                {MASTER,RX_ROUTER_ERR}   : begin 
                                    ordering_if.first_trans = Comp ;
                                    ordering_if.first_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                    ordering_if.first_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                                    ordering_if.first_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                    ordering_if.comp_typ = 1'b0; // I can't Determine unless Cfg wr due to different paths
                    
                                    ordering_if.second_trans = Comp ; 
                                    ordering_if.second_RO = 1'b1;
                                    ordering_if.second_IDO = 1'b1;
                                    ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                end
                                {RX_ROUTER_CFG,A2P_2}   : begin 
                                                     // Posted Request (Msg)                                    
                                                     if (axi_rdreq_hdr.FMT   == TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   == 2'b10 )  begin
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
                                                        ordering_if.comp_typ = 1'b0; // it represents the second transaction not first not CFG Wr
                    
                                
                                end 
                                {RX_ROUTER_CFG,A2P_1}   : begin 
                                // Posted Condition for MemWr either 64-bit address or 32-bit address
                                    if ((axi_wrreq_hdr.FMT   == TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   == 'b0_0000)  begin
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
                                    ordering_if.comp_typ = 1'b0; // it represents the second transaction not first not CFG Wr
                                
                                end 
                                {RX_ROUTER_CFG,MASTER}   : begin 
                                    ordering_if.second_trans = Comp ;
                                    ordering_if.second_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                    ordering_if.second_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                                    ordering_if.second_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                    // ordering_if.comp_typ = 1'b0; // I can't Determine unless Cfg wr due to different paths
                                    ordering_if.first_trans = Comp ;
                                    ordering_if.first_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                    ordering_if.first_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                                    ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                    ordering_if.comp_typ = 1'b0; // not CFG Wr
                    
                                end 
                                {RX_ROUTER_CFG,RX_ROUTER_ERR}   : begin 
                                // ordering_if.comp_typ = 1'b0; // I can't Determine unless Cfg wr due to different paths
                                    ordering_if.first_trans = Comp ;
                                    ordering_if.first_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                    ordering_if.first_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                                    ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                    
                                    ordering_if.second_trans = Comp ; 
                                    ordering_if.second_RO = 1'b1;
                                    ordering_if.second_IDO = 1'b1;                    
                                    ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                    ordering_if.comp_typ = 1'b0; 
                    
                                end
                                {RX_ROUTER_ERR,A2P_2}   : begin 
                                    // Posted Request (Msg)                                    
                                    if (axi_rdreq_hdr.FMT   == TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   == 2'b10 )  begin
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
                                    ordering_if.comp_typ = 1'b0; 
                                                        
                                
                                end 
                                {RX_ROUTER_ERR,A2P_1}   : begin
                                                        // Posted Condition for MemWr either 64-bit address or 32-bit address
                                                            if ((axi_wrreq_hdr.FMT   == TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   == 'b0_0000)  begin
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
                                                            ordering_if.comp_typ = 1'b0; 
                                
                                end 
                                {RX_ROUTER_ERR,MASTER}   : begin 
                                    ordering_if.first_trans = Comp ; 
                                    ordering_if.first_RO = 1'b1;
                                    ordering_if.first_IDO = 1'b1;                    
                                    ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                    ordering_if.comp_typ = 1'b0; 
                                
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
                                                                            ordering_if.comp_typ = 1'b1; // CFG Wr
                                                                        end 
                                                                        else begin 
                                                                                ordering_if.comp_typ = 1'b0; // not CFG Wr
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
				        // Assigning the signals of grant & Pushing to TLP Buffer & Sequence recorder buffer
						case (fc_if.Result) 
							FC_SUCCESS_1 : begin 
									buffer_if.wr_en =  buffer_if.empty ? 1'b1 : 1'b0 ;
									case(recorder_if.rd_data_1) 
										A2P_1 : begin 
												// Interface with source itself
												axi_req_wr_grant = buffer_if.empty ? 1'b1 : 1'b0 ;
												// Interface with buffer 
												tlp1_no_cycles_comb =  buffer_if.empty ?  no_cycles_calc (axi_wrreq_hdr.Length) : 'b0 ;
                                                data_comb <= buffer_if.empty ? axi_req_data [3 * DW - 1 : 0] : '0 ; 
                                                data_length_comb = buffer_if.empty ? axi_wrreq_hdr.Length : 'b0 ; 

                                                if (buffer_if.empty) begin 
												    if ((axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   == 'b0_0000) ) begin  // 64-bit address + Mem
												    	if (tlp1_no_cycles_comb == 1) begin 
												    		    buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp1_no_cycles_comb , 1 );
                                                                case (buffer_if.no_loc_wr) 
                                                                    4'd2 : begin 
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 910'b0 } ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0 , 2'b10, 910'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 910'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 910'b0} ;
                                                                                end 
                                                                            endcase
                                                            end 
                                                                    4'd3 : begin 
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 780'b0} ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 780'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 780'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 780'b0} ;
                                                                                end 
                                                                            endcase
                                                            end 
                                                                    4'd4 : begin 
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 650'b0} ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0,  2'b10, 650'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01, 650'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0 ,  2'b00, 650'b0} ;
                                                                                end 
                                                                            endcase
                                                            end 
                                                                    4'd5 : begin 
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 520'b0} ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 520'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW],64'b0, 2'b01,  520'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW],96'b0, 2'b00,  520'b0} ;
                                                                                end 
                                                                            endcase
                                                                           end 
                                                                    4'd6 : begin
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 390'b0} ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 390'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 390'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 390'b0} ;
                                                                                end 
                                                                            endcase
                                                                           end 
                                                                    4'd7 : begin 
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11,260'b0} ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10,260'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01,260'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[21*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0,  2'b00,260'b0} ;
                                                                                end 
                                                                            endcase
                                                            end 
                                                                    4'd8 : begin 
                                                                                case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                    2'b00 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 130'b0} ;
                                                                                    end 
                                                                                    2'b01 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[27*DW -1 :23*DW], 2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 130'b0} ;
                                                                                    end 
                                                                                    2'b10 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[26*DW -1 :22*DW], 2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 130'b0} ;
                                                                                    end 
                                                                                    2'b11 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[25*DW -1 :21*DW], 2'b11, axi_req_data[22*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 130'b0} ;
                                                                                    end 
                                                                                endcase
                                                            end 
                                                                    4'd9 : begin 
                                                                                case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                    2'b00 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[32*DW -1 :28*DW], 2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11} ;
                                                                                    end 
                                                                                    2'b01 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[31*DW -1 :27*DW], 2'b11, axi_req_data[27*DW -1 :23*DW], 2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10} ;
                                                                                    end 
                                                                                    2'b10 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[30*DW -1 :26*DW], 2'b11, axi_req_data[26*DW -1 :22*DW], 2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01} ;
                                                                                    end 
                                                                                    2'b11 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[29*DW -1 :25*DW], 2'b11, axi_req_data[25*DW -1 :21*DW], 2'b11, axi_req_data[21*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0,  2'b00} ;
                                                                                    end 
                                                                                endcase
                                                            end 
                                                                endcase 
												    	end 
												    	else begin 
												    		buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp1_no_cycles_comb , 1 );
                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[32*DW -1 :28*DW], 2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11} ;
												    	end 
												    end 
												    else begin 
													    if (tlp1_no_cycles_comb == 1) begin 
														buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp1_no_cycles_comb , 0 );
                                                        case (buffer_if.no_loc_wr) 
                                                            4'd1 : begin // here is posted request (write with data) and it will store 1 locations 
																buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 1*DW - 1 :  0*DW], 2'b11 , 1040'd0 } ;
                                                            end 
                                                            4'd2 : begin 
                                                                    case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                        2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 5*DW - 1  :  4*DW], 2'b11 , axi_req_data[ 4*DW - 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                        2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 4*DW - 1  :  3*DW], 2'b11 , axi_req_data[ 3*DW - 1 :  0*DW], 32'b0 ,  2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                        2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 3*DW - 1  :  2*DW], 2'b11 , axi_req_data[ 2*DW - 1 :  0*DW], 64'b0 ,  2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                        2'b11 : begin  
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 2*DW - 1  :  1*DW], 2'b11 , axi_req_data[ 1*DW - 1 :  0*DW], 96'b0 ,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    endcase 
                                                                end 
                                                            4'd3 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 9 - 1 :  8*DW], 2'b11 , axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[4*DW - 1 :  0*DW],  2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 8 - 1 :  7*DW], 2'b11 , axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[3*DW - 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 7 - 1 :  6*DW], 2'b11 , axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[2*DW - 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 6 - 1 :  5*DW], 2'b11 , axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[1*DW - 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd4 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 13 - 1 :  12*DW], 2'b11 , axi_req_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW - 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 12 - 1 :  11*DW], 2'b11 , axi_req_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 11 - 1 :  10*DW], 2'b11 , axi_req_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 10 - 1 :  9*DW], 2'b11 , axi_req_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW - 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd5 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 17 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 16 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 15 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 14 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd6 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 21 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 20 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 19 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0, 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 18 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd7 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 25 - 1 :  24*DW], 2'b11, axi_req_data[ DW * 24 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 24 - 1 :  23*DW], 2'b11, axi_req_data[ DW * 23 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 23 - 1 :  22*DW], 2'b11, axi_req_data[ DW * 22 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0,  2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 22 - 1 :  21*DW], 2'b11, axi_req_data[ DW * 21 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end
                                                                endcase 
                                                            end 
                                                            4'd8 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 29 - 1 :  28*DW], 2'b11, axi_req_data[ DW * 28 - 1 :  24*DW], 2'b11, axi_req_data[ DW * 24 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 28 - 1 :  27*DW], 2'b11, axi_req_data[ DW * 27 - 1 :  23*DW], 2'b11, axi_req_data[ DW * 23 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0 , 2'b10 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 27 - 1 :  26*DW], 2'b11, axi_req_data[ DW * 26 - 1 :  22*DW], 2'b11, axi_req_data[ DW * 22 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 26 - 1 :  25*DW], 2'b11, axi_req_data[ DW * 25 - 1 :  21*DW], 2'b11, axi_req_data[ DW * 21 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd9 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[  32 * DW - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_req_data[27*DW - 1 :  23*DW], 2'b11 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW - 1 :  0 *DW] , 32'b0,2'b11} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 31 * DW - 1 :  30*DW], 2'b11 , axi_req_data[ 30*DW - 1 :  26*DW], 2'b11 ,axi_req_data[26*DW - 1 :  22*DW], 2'b11 ,axi_req_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_req_data[ 18*DW- 1 :  14*DW], 2'b11 ,axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW - 1 :  0 *DW] , 64'b0,2'b10} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[  30 * DW - 1 :  29*DW], 2'b11 , axi_req_data[ 29*DW - 1 :  25*DW], 2'b11 ,axi_req_data[25*DW - 1 :  21*DW], 2'b11 ,axi_req_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_req_data[ 17*DW- 1 :  13*DW], 2'b11 ,axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW - 1 :  0 *DW] , 96'b0,2'b01} ;
                                                                    end 
                                                                    2'b11 : begin // Can't happen
                                                                        buffer_if.data_in = '0 ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                        endcase 
													end 
													    else begin 
														buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp1_no_cycles_comb , 0 );
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_req_data[27*DW - 1 :  23*DW], 2'b11 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b00} ;
													    end 
                                                    end 
                                                end 
												else begin 
                                                    buffer_if.no_loc_wr = '0 ; 
                                                    buffer_if.data_in = '0 ;
                                                end 
                                            end 
										A2P_2 : begin 
												// Interface with source itself
												axi_req_rd_grant = buffer_if.empty ? 1'b1 : 1'b0 ;
												// Interface with buffer 
                                                if (buffer_if.empty ) begin 
                                                    buffer_if.data_in = {(axi_rdreq_hdr[4*DW - 3]) ? {axi_rdreq_hdr[4*DW - 1 : 0],  2'b11 }  : {axi_rdreq_hdr[4*DW - 1 : DW], 32'd0 , 2'b10 } , 1040'd0} ;    // repeat 
                                                end 
                                                else begin 
                                                    buffer_if.data_in = '0 ; 
                                                end 
												buffer_if.no_loc_wr = buffer_if.empty ? 1'b1 : 1'b0 ;
												tlp1_no_cycles_comb = buffer_if.empty ? 1'b1 : 1'b0 ; 
											end
										MASTER : begin 
												// Interface with source itself
												axi_master_grant = buffer_if.empty ? 1'b1 : 1'b0 ;
												// Interface with buffer 
                                                data_length_comb = buffer_if.empty ? axi_master_hdr[ 2*DW + 9 : 2*DW] : 'b0 ; 
                                                data_comb <= buffer_if.empty ? axi_comp_data [3 * DW - 1 : 0] : '0 ; 
												// Interface with buffer 
                                                if (buffer_if.empty ) begin 
												    if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                        tlp1_no_cycles_comb = no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] ) ;  
												        if (tlp1_no_cycles_comb == 1) begin 
												        	buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b00, tlp1_no_cycles_comb , 0 );
                                                            case (buffer_if.no_loc_wr) 
                                                                4'd1 : begin // here is posted request (write with data) and it will store 1 locations 
                                                                buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 1 * DW - 1 : 0], 2'b11 , 1040'd0} ;
                                                            end 
                                                                4'd2 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 5 * DW - 1 :  4*DW], 2'b11 , axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 4 * DW - 1 :  3*DW], 2'b11 , axi_comp_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 3 * DW - 1 :  2*DW], 2'b11 , axi_comp_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 2 * DW - 1 :  1*DW], 2'b11 , axi_comp_data[ 1*DW - 1 :  0*DW] , 96'b0, 2'b00 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                                4'd3 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 9 * DW - 1 :  8*DW], 2'b11 , axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 8 * DW - 1 :  7*DW], 2'b11 , axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[3*DW - 1 :  0*DW], 32'b0 , 2'b10 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 7 * DW - 1 :  6*DW], 2'b11 , axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 6 * DW - 1 :  5*DW], 2'b11 , axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[1*DW - 1 :  0*DW], 96'b0 , 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                                4'd4 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 13 * DW - 1 :  12*DW], 2'b11 , axi_comp_data[ 12*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 12 * DW - 1 :  11*DW], 2'b11 , axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 11 * DW - 1 :  10*DW], 2'b11 , axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 10 * DW - 1 :  9*DW], 2'b11 , axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'b0, 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                                4'd5 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 17 * DW - 1 :  16*DW], 2'b11 , axi_comp_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW- 1 :  0*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 16 * DW - 1 :  15*DW], 2'b11 , axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW- 1 :  0*DW], 32'b0,  2'b10 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 15 * DW - 1 :  14*DW], 2'b11 , axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW- 1 :  0*DW], 64'b0,  2'b01 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 14 * DW - 1 :  13*DW], 2'b11 , axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                                4'd6 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 21 * DW - 1 :  20*DW], 2'b11 , axi_comp_data[ 20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW- 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 20 * DW - 1 :  19*DW], 2'b11 , axi_comp_data[ 19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW- 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'B0,  2'b10 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 19 * DW - 1 :  18*DW], 2'b11 , axi_comp_data[ 18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW- 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'B0, 2'b01 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 18 * DW - 1 :  17*DW], 2'b11 , axi_comp_data[ 17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW- 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'B0, 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                                4'd7 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[25* DW - 1 :  24*DW], 2'b11 , axi_comp_data[ 24*DW - 1 :  20*DW], 2'b11 ,axi_comp_data[20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW- 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[24* DW - 1 :  23*DW], 2'b11 , axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW- 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[3*DW - 1 :  0*DW], 32'B0 ,  2'b10 , 128'b0 , 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[23* DW - 1 :  22*DW], 2'b11 , axi_comp_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW- 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[2*DW - 1 :  0*DW], 64'B0 , 2'b01 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[22* DW - 1 :  21*DW], 2'b11 , axi_comp_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW- 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[1*DW - 1 :  0*DW], 96'B0 , 2'b00 , 128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                                4'd8 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[29 * DW - 1 :  28*DW], 2'b11 , axi_comp_data[ 28*DW - 1 :  24*DW], 2'b11 ,axi_comp_data[24*DW - 1 :  20*DW], 2'b11 ,axi_comp_data[ 20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[ 16*DW- 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[28 * DW - 1 :  27*DW], 2'b11 , axi_comp_data[ 27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW- 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'B0, 2'b10 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[27 * DW - 1 :  26*DW], 2'b11 , axi_comp_data[ 26*DW - 1 :  22*DW], 2'b11 ,axi_comp_data[22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[ 18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW- 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'B0, 2'b01 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[26 * DW - 1 :  25*DW], 2'b11 , axi_comp_data[ 25*DW - 1 :  21*DW], 2'b11 ,axi_comp_data[21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[ 17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW- 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'B0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                                4'd9 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin // Can't happen
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b11} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , axi_comp_data[ 3*DW - 1 :  0*DW] ,  32'b0,2'b10} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 31*DW - 1 :  30*DW], 2'b11 , axi_comp_data[ 30*DW - 1 :  26*DW], 2'b11 ,axi_comp_data[26*DW - 1 :  22*DW], 2'b11 ,axi_comp_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[ 18*DW- 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 , axi_comp_data[ 2*DW - 1 :  0*DW] ,  64'b0,2'b01} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 30*DW - 1:  29*DW], 2'b11 , axi_comp_data[ 29*DW - 1 :  25*DW], 2'b11 ,axi_comp_data[25*DW - 1 :  21*DW], 2'b11 ,axi_comp_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[ 17*DW- 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 , axi_comp_data[ 1*DW - 1 :  0*DW] ,  96'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            endcase 
												        end 
												        else begin 
													    buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b01, tlp1_no_cycles_comb , 1'b0 );
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b00} ;
												    end 
												    end 
												    else begin // Comp
                                                        tlp1_no_cycles_comb = 1'b1 ;  
                                                        buffer_if.data_in = {axi_master_hdr, 32'd0 , 2'b10 , 1040'd0} ; 
												        buffer_if.no_loc_wr = 1'b1;
												    end 
                                                end 
                                                else begin 
                                                    tlp1_no_cycles_comb = 1'b0 ;
                                                    buffer_if.data_in = '0 ; 
                                                    buffer_if.no_loc_wr = 1'b0;
                                                end 
												end
										RX_ROUTER_CFG : begin 
												// Interface with source itself
												rx_router_grant = buffer_if.empty ? 1'b1 : 1'b0 ;
												buffer_if.no_loc_wr = buffer_if.empty ? 1'b1 : 1'b0 ;
												tlp1_no_cycles_comb =buffer_if.empty ? 1'b1 : 1'b0 ;
												// Interface with buffer 
                                                if (buffer_if.empty) begin 
												    if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                        buffer_if.data_in = {rx_router_comp_hdr, rx_router_data , 2'b11 , 1040'd0} ;
												    end 
												    else begin 
                                                        buffer_if.data_in = {rx_router_comp_hdr, 32'd0 , 2'b10 , 1040'd0} ;
												    end 
                                                end 
                                                else begin 
                                                    buffer_if.data_in  = '0 ; 
                                                end 
											end												
                                        RX_ROUTER_ERR : begin 
                                            buffer_if.wr_en = buffer_if.empty ? 1'b1  : 1'b0  ;
											// assert signals of case statement 
											// Interface with source itself
											rx_router_grant =  1'b0 ;
											// Interface with buffer 
											buffer_if.data_in = {rx_router_msg_hdr,  2'b11,  {1040{1'b0}}} ;
											buffer_if.no_loc_wr = buffer_if.empty ? 1'b1 : 1'b0 ;
											tlp1_no_cycles_comb = buffer_if.empty ? 1'b1 : 1'b0 ;
                                            two_req_on_pipe_comb = buffer_if.empty ? 1'b1 : 1'b0 ; 
                                        end 
									endcase

									//Interface with Sequence Buffer 															
									if ((recorder_if.rd_data_2 != NO_SOURCE )) begin 
										recorder_if.wr_en = 1'b1 ;
										recorder_if.wr_mode = 2'b01 ;
										recorder_if.wr_data_1 = recorder_if.rd_data_2 ;
									end
									else begin 
										recorder_if.wr_en = 1'b0 ;
										recorder_if.wr_mode = 2'b00 ;
										recorder_if.wr_data_1 = NO_SOURCE ;
									end 
									recorder_if.wr_data_2 = NO_SOURCE ;

								end 
							FC_SUCCESS_2 : begin 
									if (ordering_if.ordering_result == TRUE) begin 
										buffer_if.wr_en =  buffer_if.empty ? 1'b1 : 1'b0 ;
									    case(recorder_if.rd_data_2) 
									    	A2P_1 : begin 
												// Interface with source itself
												axi_req_wr_grant = buffer_if.empty ? 1'b1 : 1'b0 ;
                                                data_comb <= buffer_if.empty ? axi_req_data [3 * DW - 1 : 0] : '0 ; 
                                                data_length_comb = buffer_if.empty ? axi_wrreq_hdr.Length : 'b0 ; 
												// Interface with buffer 
												tlp1_no_cycles_comb =  buffer_if.empty ?  no_cycles_calc (axi_wrreq_hdr.Length) : 'b0 ;
                                                if (buffer_if.empty) begin 
												    if ((axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   == 'b0_0000) ) begin  // 64-bit address + Mem
												    	if (tlp1_no_cycles_comb == 1) begin 
												    		    buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp1_no_cycles_comb , 1 );
                                                                case (buffer_if.no_loc_wr) 
                                                                    4'd2 : begin 
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 910'b0 } ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0 , 2'b10, 910'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 910'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 910'b0} ;
                                                                                end 
                                                                            endcase
                                                            end 
                                                                    4'd3 : begin 
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 780'b0} ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 780'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 780'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 780'b0} ;
                                                                                end 
                                                                            endcase
                                                            end 
                                                                    4'd4 : begin 
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 650'b0} ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0,  2'b10, 650'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01, 650'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0 ,  2'b00, 650'b0} ;
                                                                                end 
                                                                            endcase
                                                            end 
                                                                    4'd5 : begin 
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 520'b0} ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 520'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW],64'b0, 2'b01,  520'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW],96'b0, 2'b00,  520'b0} ;
                                                                                end 
                                                                            endcase
                                                                           end 
                                                                    4'd6 : begin
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 390'b0} ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 390'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 390'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 390'b0} ;
                                                                                end 
                                                                            endcase
                                                                           end 
                                                                    4'd7 : begin 
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11,260'b0} ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10,260'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01,260'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[21*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0,  2'b00,260'b0} ;
                                                                                end 
                                                                            endcase
                                                            end 
                                                                    4'd8 : begin 
                                                                                case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                    2'b00 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 130'b0} ;
                                                                                    end 
                                                                                    2'b01 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[27*DW -1 :23*DW], 2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 130'b0} ;
                                                                                    end 
                                                                                    2'b10 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[26*DW -1 :22*DW], 2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 130'b0} ;
                                                                                    end 
                                                                                    2'b11 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[25*DW -1 :21*DW], 2'b11, axi_req_data[22*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 130'b0} ;
                                                                                    end 
                                                                                endcase
                                                            end 
                                                                    4'd9 : begin 
                                                                                case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                    2'b00 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[32*DW -1 :28*DW], 2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11} ;
                                                                                    end 
                                                                                    2'b01 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[31*DW -1 :27*DW], 2'b11, axi_req_data[27*DW -1 :23*DW], 2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10} ;
                                                                                    end 
                                                                                    2'b10 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[30*DW -1 :26*DW], 2'b11, axi_req_data[26*DW -1 :22*DW], 2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01} ;
                                                                                    end 
                                                                                    2'b11 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[29*DW -1 :25*DW], 2'b11, axi_req_data[25*DW -1 :21*DW], 2'b11, axi_req_data[21*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0,  2'b00} ;
                                                                                    end 
                                                                                endcase
                                                            end 
                                                                endcase 
												    	end 
												    	else begin 
												    		buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp1_no_cycles_comb , 1 );
                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[32*DW -1 :28*DW], 2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11} ;
												    	end 
												    end 
												    else begin 
													    if (tlp1_no_cycles_comb == 1) begin 
														buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp1_no_cycles_comb , 0 );
                                                        case (buffer_if.no_loc_wr) 
                                                            4'd1 : begin // here is posted request (write with data) and it will store 1 locations 
																buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 1*DW - 1 :  0*DW], 2'b11 , 1040'd0 } ;
                                                            end 
                                                            4'd2 : begin 
                                                                    case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                        2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 5*DW - 1  :  4*DW], 2'b11 , axi_req_data[ 4*DW - 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                        2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 4*DW - 1  :  3*DW], 2'b11 , axi_req_data[ 3*DW - 1 :  0*DW], 32'b0 ,  2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                        2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 3*DW - 1  :  2*DW], 2'b11 , axi_req_data[ 2*DW - 1 :  0*DW], 64'b0 ,  2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                        2'b11 : begin  
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 2*DW - 1  :  1*DW], 2'b11 , axi_req_data[ 1*DW - 1 :  0*DW], 96'b0 ,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    endcase 
                                                                end 
                                                            4'd3 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 9 - 1 :  8*DW], 2'b11 , axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[4*DW - 1 :  0*DW],  2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 8 - 1 :  7*DW], 2'b11 , axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[3*DW - 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 7 - 1 :  6*DW], 2'b11 , axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[2*DW - 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 6 - 1 :  5*DW], 2'b11 , axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[1*DW - 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd4 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 13 - 1 :  12*DW], 2'b11 , axi_req_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW - 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 12 - 1 :  11*DW], 2'b11 , axi_req_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 11 - 1 :  10*DW], 2'b11 , axi_req_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 10 - 1 :  9*DW], 2'b11 , axi_req_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW - 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd5 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 17 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 16 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 15 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 14 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd6 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 21 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 20 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 19 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0, 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 18 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd7 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 25 - 1 :  24*DW], 2'b11, axi_req_data[ DW * 24 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 24 - 1 :  23*DW], 2'b11, axi_req_data[ DW * 23 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 23 - 1 :  22*DW], 2'b11, axi_req_data[ DW * 22 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0,  2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 22 - 1 :  21*DW], 2'b11, axi_req_data[ DW * 21 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end
                                                                endcase 
                                                            end 
                                                            4'd8 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 29 - 1 :  28*DW], 2'b11, axi_req_data[ DW * 28 - 1 :  24*DW], 2'b11, axi_req_data[ DW * 24 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 28 - 1 :  27*DW], 2'b11, axi_req_data[ DW * 27 - 1 :  23*DW], 2'b11, axi_req_data[ DW * 23 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0 , 2'b10 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 27 - 1 :  26*DW], 2'b11, axi_req_data[ DW * 26 - 1 :  22*DW], 2'b11, axi_req_data[ DW * 22 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 26 - 1 :  25*DW], 2'b11, axi_req_data[ DW * 25 - 1 :  21*DW], 2'b11, axi_req_data[ DW * 21 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd9 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[  32 * DW - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_req_data[27*DW - 1 :  23*DW], 2'b11 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW - 1 :  0 *DW] , 32'b0,2'b10} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 31 * DW - 1 :  30*DW], 2'b11 , axi_req_data[ 30*DW - 1 :  26*DW], 2'b11 ,axi_req_data[26*DW - 1 :  22*DW], 2'b11 ,axi_req_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_req_data[ 18*DW- 1 :  14*DW], 2'b11 ,axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW - 1 :  0 *DW] , 64'b0,2'b01} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[  30 * DW - 1 :  29*DW], 2'b11 , axi_req_data[ 29*DW - 1 :  25*DW], 2'b11 ,axi_req_data[25*DW - 1 :  21*DW], 2'b11 ,axi_req_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_req_data[ 17*DW- 1 :  13*DW], 2'b11 ,axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW - 1 :  0 *DW] , 96'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin // Can't happen
                                                                        buffer_if.data_in = '0 ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                        endcase 
													end 
													    else begin 
														buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp1_no_cycles_comb , 0 );
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_req_data[27*DW - 1 :  23*DW], 2'b11 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b00} ;
													    end 
                                                    end 
                                                end 
												else begin 
                                                    buffer_if.no_loc_wr = '0 ; 
                                                    buffer_if.data_in = '0 ;
                                                end 
                                            end 
									    	A2P_2 : begin 
												// Interface with source itself
												axi_req_rd_grant = buffer_if.empty ? 1'b1 : 1'b0 ;
												// Interface with buffer 
                                                if (buffer_if.empty ) begin 
                                                    buffer_if.data_in = {(axi_rdreq_hdr[4*DW - 3]) ? {axi_rdreq_hdr[4*DW - 1 : 0],  2'b11 }  : {axi_rdreq_hdr[4*DW - 1 : DW], 32'd0 , 2'b10 } , 1040'd0} ;    // repeat 
                                                end 
                                                else begin 
                                                    buffer_if.data_in = '0 ; 
                                                end 
												buffer_if.no_loc_wr = buffer_if.empty ? 1'b1 : 1'b0 ;
												tlp1_no_cycles_comb = buffer_if.empty ? 1'b1 : 1'b0 ; 
											end
									    	MASTER : begin 
												// Interface with source itself
												axi_master_grant = buffer_if.empty ? 1'b1 : 1'b0 ;
												// Interface with buffer 
                                                data_length_comb = buffer_if.empty ? axi_master_hdr[ 2*DW + 9 : 2*DW] : 'b0 ; 
                                                data_comb <= buffer_if.empty ? axi_comp_data [3 * DW - 1 : 0] :  '0 ; 
												// Interface with buffer 
                                                if (buffer_if.empty ) begin 
												    if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                        tlp1_no_cycles_comb = no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] ) ;  
												        if (tlp1_no_cycles_comb == 1) begin 
												        	buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b00, tlp1_no_cycles_comb , 0 );
                                                            case (buffer_if.no_loc_wr) 
                                                                4'd1 : begin // here is posted request (write with data) and it will store 1 locations 
                                                                buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 1 * DW - 1 : 0], 2'b11 , 1040'd0} ;
                                                            end 
                                                                4'd2 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 5 * DW - 1 :  4*DW], 2'b11 , axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 4 * DW - 1 :  3*DW], 2'b11 , axi_comp_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 3 * DW - 1 :  2*DW], 2'b11 , axi_comp_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 2 * DW - 1 :  1*DW], 2'b11 , axi_comp_data[ 1*DW - 1 :  0*DW] , 96'b0, 2'b00 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                                4'd3 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 9 * DW - 1 :  8*DW], 2'b11 , axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 8 * DW - 1 :  7*DW], 2'b11 , axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[3*DW - 1 :  0*DW], 32'b0 , 2'b10 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 7 * DW - 1 :  6*DW], 2'b11 , axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 6 * DW - 1 :  5*DW], 2'b11 , axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[1*DW - 1 :  0*DW], 96'b0 , 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                                4'd4 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 13 * DW - 1 :  12*DW], 2'b11 , axi_comp_data[ 12*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 12 * DW - 1 :  11*DW], 2'b11 , axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 11 * DW - 1 :  10*DW], 2'b11 , axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 10 * DW - 1 :  9*DW], 2'b11 , axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'b0, 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                                4'd5 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 17 * DW - 1 :  16*DW], 2'b11 , axi_comp_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW- 1 :  0*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 16 * DW - 1 :  15*DW], 2'b11 , axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW- 1 :  0*DW], 32'b0,  2'b10 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 15 * DW - 1 :  14*DW], 2'b11 , axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW- 1 :  0*DW], 64'b0,  2'b01 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 14 * DW - 1 :  13*DW], 2'b11 , axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                                4'd6 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 21 * DW - 1 :  20*DW], 2'b11 , axi_comp_data[ 20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW- 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 20 * DW - 1 :  19*DW], 2'b11 , axi_comp_data[ 19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW- 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'B0,  2'b10 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 19 * DW - 1 :  18*DW], 2'b11 , axi_comp_data[ 18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW- 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'B0, 2'b01 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 18 * DW - 1 :  17*DW], 2'b11 , axi_comp_data[ 17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW- 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'B0, 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                                4'd7 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[25* DW - 1 :  24*DW], 2'b11 , axi_comp_data[ 24*DW - 1 :  20*DW], 2'b11 ,axi_comp_data[20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW- 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[24* DW - 1 :  23*DW], 2'b11 , axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW- 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[3*DW - 1 :  0*DW], 32'B0 ,  2'b10 , 128'b0 , 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[23* DW - 1 :  22*DW], 2'b11 , axi_comp_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW- 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[2*DW - 1 :  0*DW], 64'B0 , 2'b01 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[22* DW - 1 :  21*DW], 2'b11 , axi_comp_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW- 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[1*DW - 1 :  0*DW], 96'B0 , 2'b00 , 128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                                4'd8 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[29 * DW - 1 :  28*DW], 2'b11 , axi_comp_data[ 28*DW - 1 :  24*DW], 2'b11 ,axi_comp_data[24*DW - 1 :  20*DW], 2'b11 ,axi_comp_data[ 20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[ 16*DW- 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[28 * DW - 1 :  27*DW], 2'b11 , axi_comp_data[ 27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW- 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'B0, 2'b10 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[27 * DW - 1 :  26*DW], 2'b11 , axi_comp_data[ 26*DW - 1 :  22*DW], 2'b11 ,axi_comp_data[22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[ 18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW- 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'B0, 2'b01 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[26 * DW - 1 :  25*DW], 2'b11 , axi_comp_data[ 25*DW - 1 :  21*DW], 2'b11 ,axi_comp_data[21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[ 17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW- 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'B0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                                4'd9 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin // Can't happen
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b11} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , axi_comp_data[ 3*DW - 1 :  0*DW] ,  32'b0,2'b10} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 31*DW - 1 :  30*DW], 2'b11 , axi_comp_data[ 30*DW - 1 :  26*DW], 2'b11 ,axi_comp_data[26*DW - 1 :  22*DW], 2'b11 ,axi_comp_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[ 18*DW- 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 , axi_comp_data[ 2*DW - 1 :  0*DW] ,  64'b0,2'b01} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 30*DW - 1:  29*DW], 2'b11 , axi_comp_data[ 29*DW - 1 :  25*DW], 2'b11 ,axi_comp_data[25*DW - 1 :  21*DW], 2'b11 ,axi_comp_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[ 17*DW- 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 , axi_comp_data[ 1*DW - 1 :  0*DW] ,  96'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            endcase 
												        end 
												        else begin 
													        buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b01, tlp1_no_cycles_comb , 1'b0 );
                                                            buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b00} ;
												    end 
												    end 
												    else begin // Comp
                                                        tlp1_no_cycles_comb = 1'b1 ;  
                                                        buffer_if.data_in = {axi_master_hdr, 32'd0 , 2'b10 , 1040'd0} ; 
												        buffer_if.no_loc_wr = 1'b1;
												    end 
                                                end 
                                                else begin 
                                                    tlp1_no_cycles_comb = 1'b0 ;  
                                                    buffer_if.data_in = '0 ; 
                                                    buffer_if.no_loc_wr = 1'b0;
                                                end 
												end
									    	RX_ROUTER_CFG : begin 
												// Interface with source itself
												rx_router_grant = buffer_if.empty ? 1'b1 : 1'b0 ;
												buffer_if.no_loc_wr = buffer_if.empty ? 1'b1 : 1'b0 ;
												tlp1_no_cycles_comb =buffer_if.empty ? 1'b1 : 1'b0 ;
												// Interface with buffer 
                                                if (buffer_if.empty) begin 
												    if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                        buffer_if.data_in = {rx_router_comp_hdr, rx_router_data , 2'b11 , 1040'd0} ;
												    end 
												    else begin 
                                                        buffer_if.data_in = {rx_router_comp_hdr, 32'd0 , 2'b10 , 1040'd0} ;
												    end 
                                                end 
                                                else begin 
                                                    buffer_if.data_in  = '0 ; 
                                                end 
											end												
                                            RX_ROUTER_ERR : begin 
                                                buffer_if.wr_en = buffer_if.empty ? 1'b1  : 1'b0  ;
                                                // assert signals of case statement 
                                                // Interface with source itself
                                                rx_router_grant =  1'b0 ;
                                                // Interface with buffer 
                                                buffer_if.data_in = {rx_router_msg_hdr,  2'b11,  {1040{1'b0}}} ;
                                                buffer_if.no_loc_wr = buffer_if.empty ? 1'b1 : 1'b0 ;
                                                tlp1_no_cycles_comb = buffer_if.empty ? 1'b1 : 1'b0 ;
                                                two_req_on_pipe_comb = buffer_if.empty ? 1'b1 : 1'b0 ; 
                                            end 
									    endcase
									    //Interface with Sequence Buffer 															
									    if ((No_rd_loc_seq == 2'b10)) begin 
										recorder_if.wr_en = 1'b1 ;
										recorder_if.wr_mode = 2'b01 ;
										recorder_if.wr_data_1 = recorder_if.rd_data_1 ;
									end
									    recorder_if.wr_data_2 = NO_SOURCE ;
									    end 
									end 
							FC_SUCCESS_1_2 : begin 
                                /* 1- Not Rx router & Not Rx router*/
                                /* 2- Not Rx router &     Rx router*/
                                /* 3-     Rx router & Not Rx router*/
                                /* 4-     Rx router &     Rx router*/
                                if (buffer_if.empty) begin 
								    if ((recorder_if.rd_data_1 != RX_ROUTER_ERR) && (recorder_if.rd_data_2 != RX_ROUTER_ERR) ) begin 
								    buffer_if.wr_en = 1'b1 ;
                                    two_req_on_pipe_comb = 1'b1 ; 
                                    case(recorder_if.rd_data_1) 
                                        A2P_1 : begin 
                                                // Interface with source itself
                                                axi_req_wr_grant = 1'b1 ;
                                                // Interface with buffer 
                                                tlp1_no_cycles_comb = no_cycles_calc (axi_wrreq_hdr.Length);
                                                data_comb <= buffer_if.empty ? axi_req_data [3 * DW - 1 : 0] : '0 ; 
                                                data_length_comb = buffer_if.empty ? axi_wrreq_hdr.Length : 'b0 ; 
												if ((axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   == 'b0_0000) ) begin  // 64-bit address + Mem
													if (tlp1_no_cycles_comb == 1) begin 
												    		buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp1_no_cycles_comb , 1 );
                                                            case (buffer_if.no_loc_wr) 
                                                                4'd2 : begin 
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 910'b0 } ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0 , 2'b10, 910'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 910'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 910'b0} ;
                                                                                end 
                                                                            endcase
                                                            end 
                                                                4'd3 : begin 
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 780'b0} ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 780'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 780'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 780'b0} ;
                                                                                end 
                                                                            endcase
                                                            end 
                                                                4'd4 : begin 
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 650'b0} ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0,  2'b10, 650'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01, 650'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0 ,  2'b00, 650'b0} ;
                                                                                end 
                                                                            endcase
                                                            end 
                                                                4'd5 : begin 
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 520'b0} ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 520'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW],64'b0, 2'b01,  520'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW],96'b0, 2'b00,  520'b0} ;
                                                                                end 
                                                                            endcase
                                                                           end 
                                                                4'd6 : begin
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 390'b0} ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 390'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 390'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 390'b0} ;
                                                                                end 
                                                                            endcase
                                                                           end 
                                                                4'd7 : begin 
                                                                            case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                2'b00 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11,260'b0} ;
                                                                                end 
                                                                                2'b01 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10,260'b0} ;
                                                                                end 
                                                                                2'b10 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01,260'b0} ;
                                                                                end 
                                                                                2'b11 : begin 
                                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[21*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0,  2'b00,260'b0} ;
                                                                                end 
                                                                            endcase
                                                            end 
                                                                4'd8 : begin 
                                                                                case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                    2'b00 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 130'b0} ;
                                                                                    end 
                                                                                    2'b01 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[27*DW -1 :23*DW], 2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 130'b0} ;
                                                                                    end 
                                                                                    2'b10 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[26*DW -1 :22*DW], 2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 130'b0} ;
                                                                                    end 
                                                                                    2'b11 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[25*DW -1 :21*DW], 2'b11, axi_req_data[22*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 130'b0} ;
                                                                                    end 
                                                                                endcase
                                                            end 
                                                                4'd9 : begin 
                                                                                case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                    2'b00 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[32*DW -1 :28*DW], 2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11} ;
                                                                                    end 
                                                                                    2'b01 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[31*DW -1 :27*DW], 2'b11, axi_req_data[27*DW -1 :23*DW], 2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10} ;
                                                                                    end 
                                                                                    2'b10 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[30*DW -1 :26*DW], 2'b11, axi_req_data[26*DW -1 :22*DW], 2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01} ;
                                                                                    end 
                                                                                    2'b11 : begin 
                                                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[29*DW -1 :25*DW], 2'b11, axi_req_data[25*DW -1 :21*DW], 2'b11, axi_req_data[21*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0,  2'b00} ;
                                                                                    end 
                                                                                endcase
                                                            end 
                                                            endcase 
												    	end 
													else begin 
												    		buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp1_no_cycles_comb , 1 );
                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[32*DW -1 :28*DW], 2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11} ;
												    	end 
												end 
												else begin 
												    if (tlp1_no_cycles_comb == 1) begin 
													buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp1_no_cycles_comb , 0 );
                                                    case (buffer_if.no_loc_wr) 
                                                            4'd1 : begin // here is posted request (write with data) and it will store 1 locations 
																buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 1*DW - 1 :  0*DW], 2'b11 , 1040'd0 } ;
                                                            end 
                                                            4'd2 : begin 
                                                                    case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                        2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 5*DW - 1  :  4*DW], 2'b11 , axi_req_data[ 4*DW - 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                        2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 4*DW - 1  :  3*DW], 2'b11 , axi_req_data[ 3*DW - 1 :  0*DW], 32'b0 ,  2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                        2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 3*DW - 1  :  2*DW], 2'b11 , axi_req_data[ 2*DW - 1 :  0*DW], 64'b0 ,  2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                        2'b11 : begin  
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 2*DW - 1  :  1*DW], 2'b11 , axi_req_data[ 1*DW - 1 :  0*DW], 96'b0 ,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    endcase 
                                                                end 
                                                            4'd3 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 9 - 1 :  8*DW], 2'b11 , axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[4*DW - 1 :  0*DW],  2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 8 - 1 :  7*DW], 2'b11 , axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[3*DW - 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 7 - 1 :  6*DW], 2'b11 , axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[2*DW - 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 6 - 1 :  5*DW], 2'b11 , axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[1*DW - 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd4 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 13 - 1 :  12*DW], 2'b11 , axi_req_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW - 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 12 - 1 :  11*DW], 2'b11 , axi_req_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 11 - 1 :  10*DW], 2'b11 , axi_req_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 10 - 1 :  9*DW], 2'b11 , axi_req_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW - 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd5 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 17 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 16 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 15 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 14 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd6 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 21 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 20 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 19 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0, 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 18 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd7 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 25 - 1 :  24*DW], 2'b11, axi_req_data[ DW * 24 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 24 - 1 :  23*DW], 2'b11, axi_req_data[ DW * 23 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 23 - 1 :  22*DW], 2'b11, axi_req_data[ DW * 22 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0,  2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 22 - 1 :  21*DW], 2'b11, axi_req_data[ DW * 21 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end
                                                                endcase 
                                                            end 
                                                            4'd8 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 29 - 1 :  28*DW], 2'b11, axi_req_data[ DW * 28 - 1 :  24*DW], 2'b11, axi_req_data[ DW * 24 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 28 - 1 :  27*DW], 2'b11, axi_req_data[ DW * 27 - 1 :  23*DW], 2'b11, axi_req_data[ DW * 23 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0 , 2'b10 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 27 - 1 :  26*DW], 2'b11, axi_req_data[ DW * 26 - 1 :  22*DW], 2'b11, axi_req_data[ DW * 22 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 26 - 1 :  25*DW], 2'b11, axi_req_data[ DW * 25 - 1 :  21*DW], 2'b11, axi_req_data[ DW * 21 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd9 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[  32 * DW - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_req_data[27*DW - 1 :  23*DW], 2'b11 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW - 1 :  0 *DW] , 32'b0,2'b11} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 31 * DW - 1 :  30*DW], 2'b11 , axi_req_data[ 30*DW - 1 :  26*DW], 2'b11 ,axi_req_data[26*DW - 1 :  22*DW], 2'b11 ,axi_req_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_req_data[ 18*DW- 1 :  14*DW], 2'b11 ,axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW - 1 :  0 *DW] , 64'b0,2'b10} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[  30 * DW - 1 :  29*DW], 2'b11 , axi_req_data[ 29*DW - 1 :  25*DW], 2'b11 ,axi_req_data[25*DW - 1 :  21*DW], 2'b11 ,axi_req_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_req_data[ 17*DW- 1 :  13*DW], 2'b11 ,axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW - 1 :  0 *DW] , 96'b0,2'b01} ;
                                                                    end 
                                                                    2'b11 : begin // Can't happen
                                                                        buffer_if.data_in = '0 ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                        endcase 
												    end 
												    else begin 
														buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp1_no_cycles_comb , 0 );
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_req_data[27*DW - 1 :  23*DW], 2'b11 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b00} ;
													    end 
                                                end 
                                                end
                                        A2P_2 : begin 
                                                // Interface with source itself
                                                axi_req_rd_grant = 1'b1 ;
                                                // Interface with buffer 
                                                buffer_if.data_in = {(axi_rdreq_hdr[4*DW - 3]) ? {axi_rdreq_hdr[4*DW - 1 : 0],  2'b11 }  : {axi_rdreq_hdr[4*DW - 1 : DW], 32'd0 , 2'b10 } , 1040'd0} ;    // repeat 
                                                buffer_if.no_loc_wr = 1'b1 ;
                                                tlp1_no_cycles_comb = 1'b1 ; 
                                            end
                                        MASTER : begin 
                                                // Interface with source itself
                                                axi_master_grant = 1'b1 ;
                                                // Interface with buffer 
                                                data_length_comb = buffer_if.empty ? axi_master_hdr[ 2*DW + 9 : 2*DW] : 'b0 ; 
                                                data_comb <= buffer_if.empty ? axi_comp_data [3 * DW - 1 : 0] : '0 ; 
                                                // Interface with buffer 
												if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                    tlp1_no_cycles_comb = no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] );
												    if (tlp1_no_cycles_comb == 1) begin 
												    	buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b00, tlp1_no_cycles_comb , 0 );
                                                        case (buffer_if.no_loc_wr) 
                                                            4'd1 : begin // here is posted request (write with data) and it will store 1 locations 
                                                                buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 1 * DW - 1 : 0], 2'b11 , 1040'd0} ;
                                                            end 
                                                            4'd2 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 5 * DW - 1 :  4*DW], 2'b11 , axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 4 * DW - 1 :  3*DW], 2'b11 , axi_comp_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 3 * DW - 1 :  2*DW], 2'b11 , axi_comp_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 2 * DW - 1 :  1*DW], 2'b11 , axi_comp_data[ 1*DW - 1 :  0*DW] , 96'b0, 2'b00 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd3 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 9 * DW - 1 :  8*DW], 2'b11 , axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 8 * DW - 1 :  7*DW], 2'b11 , axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[3*DW - 1 :  0*DW], 32'b0 , 2'b10 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 7 * DW - 1 :  6*DW], 2'b11 , axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 6 * DW - 1 :  5*DW], 2'b11 , axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[1*DW - 1 :  0*DW], 96'b0 , 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd4 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 13 * DW - 1 :  12*DW], 2'b11 , axi_comp_data[ 12*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 12 * DW - 1 :  11*DW], 2'b11 , axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 11 * DW - 1 :  10*DW], 2'b11 , axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 10 * DW - 1 :  9*DW], 2'b11 , axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'b0, 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd5 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 17 * DW - 1 :  16*DW], 2'b11 , axi_comp_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW- 1 :  0*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 16 * DW - 1 :  15*DW], 2'b11 , axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW- 1 :  0*DW], 32'b0,  2'b10 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 15 * DW - 1 :  14*DW], 2'b11 , axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW- 1 :  0*DW], 64'b0,  2'b01 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 14 * DW - 1 :  13*DW], 2'b11 , axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd6 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 21 * DW - 1 :  20*DW], 2'b11 , axi_comp_data[ 20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW- 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 20 * DW - 1 :  19*DW], 2'b11 , axi_comp_data[ 19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW- 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'B0,  2'b10 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 19 * DW - 1 :  18*DW], 2'b11 , axi_comp_data[ 18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW- 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'B0, 2'b01 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 18 * DW - 1 :  17*DW], 2'b11 , axi_comp_data[ 17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW- 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'B0, 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd7 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[25* DW - 1 :  24*DW], 2'b11 , axi_comp_data[ 24*DW - 1 :  20*DW], 2'b11 ,axi_comp_data[20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW- 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[24* DW - 1 :  23*DW], 2'b11 , axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW- 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[3*DW - 1 :  0*DW], 32'B0 ,  2'b10 , 128'b0 , 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[23* DW - 1 :  22*DW], 2'b11 , axi_comp_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW- 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[2*DW - 1 :  0*DW], 64'B0 , 2'b01 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[22* DW - 1 :  21*DW], 2'b11 , axi_comp_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW- 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[1*DW - 1 :  0*DW], 96'B0 , 2'b00 , 128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd8 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[29 * DW - 1 :  28*DW], 2'b11 , axi_comp_data[ 28*DW - 1 :  24*DW], 2'b11 ,axi_comp_data[24*DW - 1 :  20*DW], 2'b11 ,axi_comp_data[ 20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[ 16*DW- 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[28 * DW - 1 :  27*DW], 2'b11 , axi_comp_data[ 27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW- 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'B0, 2'b10 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[27 * DW - 1 :  26*DW], 2'b11 , axi_comp_data[ 26*DW - 1 :  22*DW], 2'b11 ,axi_comp_data[22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[ 18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW- 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'B0, 2'b01 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[26 * DW - 1 :  25*DW], 2'b11 , axi_comp_data[ 25*DW - 1 :  21*DW], 2'b11 ,axi_comp_data[21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[ 17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW- 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'B0, 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd9 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin // Can't happen
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b11} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , axi_comp_data[ 3*DW - 1 :  0*DW] ,  32'b0,2'b10} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 31*DW - 1 :  30*DW], 2'b11 , axi_comp_data[ 30*DW - 1 :  26*DW], 2'b11 ,axi_comp_data[26*DW - 1 :  22*DW], 2'b11 ,axi_comp_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[ 18*DW- 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 , axi_comp_data[ 2*DW - 1 :  0*DW] ,  64'b0,2'b01} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 30*DW - 1:  29*DW], 2'b11 , axi_comp_data[ 29*DW - 1 :  25*DW], 2'b11 ,axi_comp_data[25*DW - 1 :  21*DW], 2'b11 ,axi_comp_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[ 17*DW- 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 , axi_comp_data[ 1*DW - 1 :  0*DW] ,  96'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                        endcase 
												    end 
												    else begin 
													    buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b01, tlp1_no_cycles_comb , 1'b0 );
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b00} ;
												    end 
												end 
												else begin // Comp
                                                    tlp1_no_cycles_comb = '0;
                                                    buffer_if.data_in = {axi_master_hdr, 32'd0 , 2'b10 , 1040'd0} ; 
												    buffer_if.no_loc_wr = 1'b1;
												end 
                                                end
                                        RX_ROUTER_CFG : begin 
                                                // Interface with source itself
                                                rx_router_grant = 1'b1 ;
                                                buffer_if.no_loc_wr = 1'b1 ;
                                                tlp1_no_cycles_comb = 1'b1 ;
                                                // Interface with buffer 
                                                if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                    buffer_if.data_in = {rx_router_comp_hdr, rx_router_data , 2'b11 , 1040'd0} ;
                                                end 
                                                else begin 
                                                    buffer_if.data_in = {rx_router_comp_hdr, 32'd0 , 2'b10 , 1040'd0} ;
                                                end 
                                            end												
                                    endcase
								end 
								    else if ((recorder_if.rd_data_1 != RX_ROUTER_ERR) && (recorder_if.rd_data_2 == RX_ROUTER_ERR) ) begin  // Push the second request - Here both requests are both acceptable but the second is error tlp with comb 
											buffer_if.wr_en = 1'b1 ;
											// assert signals of case statement 
											// Interface with source itself
                                            case(recorder_if.rd_data_1) 
                                                A2P_1 : begin 
                                                        // Interface with source itself
                                                        axi_req_wr_grant = 1'b1 ;
                                                        // Interface with buffer 
                                                        tlp1_no_cycles_comb = no_cycles_calc (axi_wrreq_hdr.Length);
                                                        data_comb <= buffer_if.empty ? axi_req_data [3 * DW - 1 : 0] : '0 ; 
                                                        data_length_comb = buffer_if.empty ? axi_wrreq_hdr.Length : 'b0 ; 
                                                        if ((axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   == 'b0_0000) ) begin  // 64-bit address + Mem
                                                            if (tlp1_no_cycles_comb == 1) begin 
                                                                    buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp1_no_cycles_comb , 1 );
                                                                    case (buffer_if.no_loc_wr) 
                                                                        4'd2 : begin 
                                                                                    case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                        2'b00 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 910'b0 } ;
                                                                                        end 
                                                                                        2'b01 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0 , 2'b10, 910'b0} ;
                                                                                        end 
                                                                                        2'b10 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 910'b0} ;
                                                                                        end 
                                                                                        2'b11 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 910'b0} ;
                                                                                        end 
                                                                                    endcase
                                                                    end 
                                                                        4'd3 : begin 
                                                                                    case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                        2'b00 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 780'b0} ;
                                                                                        end 
                                                                                        2'b01 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 780'b0} ;
                                                                                        end 
                                                                                        2'b10 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 780'b0} ;
                                                                                        end 
                                                                                        2'b11 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 780'b0} ;
                                                                                        end 
                                                                                    endcase
                                                                    end 
                                                                        4'd4 : begin 
                                                                                    case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                        2'b00 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 650'b0} ;
                                                                                        end 
                                                                                        2'b01 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0,  2'b10, 650'b0} ;
                                                                                        end 
                                                                                        2'b10 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01, 650'b0} ;
                                                                                        end 
                                                                                        2'b11 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0 ,  2'b00, 650'b0} ;
                                                                                        end 
                                                                                    endcase
                                                                    end 
                                                                        4'd5 : begin 
                                                                                    case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                        2'b00 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 520'b0} ;
                                                                                        end 
                                                                                        2'b01 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 520'b0} ;
                                                                                        end 
                                                                                        2'b10 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW],64'b0, 2'b01,  520'b0} ;
                                                                                        end 
                                                                                        2'b11 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW],96'b0, 2'b00,  520'b0} ;
                                                                                        end 
                                                                                    endcase
                                                                                   end 
                                                                        4'd6 : begin
                                                                                    case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                        2'b00 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 390'b0} ;
                                                                                        end 
                                                                                        2'b01 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 390'b0} ;
                                                                                        end 
                                                                                        2'b10 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 390'b0} ;
                                                                                        end 
                                                                                        2'b11 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 390'b0} ;
                                                                                        end 
                                                                                    endcase
                                                                                   end 
                                                                        4'd7 : begin 
                                                                                    case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                        2'b00 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11,260'b0} ;
                                                                                        end 
                                                                                        2'b01 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10,260'b0} ;
                                                                                        end 
                                                                                        2'b10 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01,260'b0} ;
                                                                                        end 
                                                                                        2'b11 : begin 
                                                                                            buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[21*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0,  2'b00,260'b0} ;
                                                                                        end 
                                                                                    endcase
                                                                    end 
                                                                        4'd8 : begin 
                                                                                        case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                            2'b00 : begin 
                                                                                                buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 130'b0} ;
                                                                                            end 
                                                                                            2'b01 : begin 
                                                                                                buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[27*DW -1 :23*DW], 2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 130'b0} ;
                                                                                            end 
                                                                                            2'b10 : begin 
                                                                                                buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[26*DW -1 :22*DW], 2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 130'b0} ;
                                                                                            end 
                                                                                            2'b11 : begin 
                                                                                                buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[25*DW -1 :21*DW], 2'b11, axi_req_data[22*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 130'b0} ;
                                                                                            end 
                                                                                        endcase
                                                                    end 
                                                                        4'd9 : begin 
                                                                                        case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                                                            2'b00 : begin 
                                                                                                buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[32*DW -1 :28*DW], 2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11} ;
                                                                                            end 
                                                                                            2'b01 : begin 
                                                                                                buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[31*DW -1 :27*DW], 2'b11, axi_req_data[27*DW -1 :23*DW], 2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10} ;
                                                                                            end 
                                                                                            2'b10 : begin 
                                                                                                buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[30*DW -1 :26*DW], 2'b11, axi_req_data[26*DW -1 :22*DW], 2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01} ;
                                                                                            end 
                                                                                            2'b11 : begin 
                                                                                                buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[29*DW -1 :25*DW], 2'b11, axi_req_data[25*DW -1 :21*DW], 2'b11, axi_req_data[21*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0,  2'b00} ;
                                                                                            end 
                                                                                        endcase
                                                                    end 
                                                                    endcase 
                                                                end 
                                                            else begin 
                                                                    buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp1_no_cycles_comb , 1 );
                                                                    buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[32*DW -1 :28*DW], 2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11} ;
                                                                end 
                                                        end 
                                                        else begin 
                                                            if (tlp1_no_cycles_comb == 1) begin 
                                                            buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp1_no_cycles_comb , 0 );
                                                            case (buffer_if.no_loc_wr) 
                                                                    4'd1 : begin // here is posted request (write with data) and it will store 1 locations 
                                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 1*DW - 1 :  0*DW], 2'b11 , 1040'd0 } ;
                                                                    end 
                                                                    4'd2 : begin 
                                                                            case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                                2'b00 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 5*DW - 1  :  4*DW], 2'b11 , axi_req_data[ 4*DW - 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                                2'b01 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 4*DW - 1  :  3*DW], 2'b11 , axi_req_data[ 3*DW - 1 :  0*DW], 32'b0 ,  2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                                2'b10 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 3*DW - 1  :  2*DW], 2'b11 , axi_req_data[ 2*DW - 1 :  0*DW], 64'b0 ,  2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                                2'b11 : begin  
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 2*DW - 1  :  1*DW], 2'b11 , axi_req_data[ 1*DW - 1 :  0*DW], 96'b0 ,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                            endcase 
                                                                        end 
                                                                    4'd3 : begin 
                                                                        case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                            2'b00 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 9 - 1 :  8*DW], 2'b11 , axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[4*DW - 1 :  0*DW],  2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                            2'b01 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 8 - 1 :  7*DW], 2'b11 , axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[3*DW - 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                            2'b10 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 7 - 1 :  6*DW], 2'b11 , axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[2*DW - 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                            2'b11 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 6 - 1 :  5*DW], 2'b11 , axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[1*DW - 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                        endcase 
                                                                    end 
                                                                    4'd4 : begin 
                                                                        case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                            2'b00 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 13 - 1 :  12*DW], 2'b11 , axi_req_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW - 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                            2'b01 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 12 - 1 :  11*DW], 2'b11 , axi_req_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                            2'b10 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 11 - 1 :  10*DW], 2'b11 , axi_req_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                            2'b11 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 10 - 1 :  9*DW], 2'b11 , axi_req_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW - 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                        endcase 
                                                                    end 
                                                                    4'd5 : begin 
                                                                        case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                            2'b00 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 17 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                            2'b01 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 16 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                            2'b10 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 15 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                            2'b11 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 14 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                                            end 
                                                                        endcase 
                                                                    end 
                                                                    4'd6 : begin 
                                                                        case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                            2'b00 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 21 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                            end 
                                                                            2'b01 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 20 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                            end 
                                                                            2'b10 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 19 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0, 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                            end 
                                                                            2'b11 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 18 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                            end 
                                                                        endcase 
                                                                    end 
                                                                    4'd7 : begin 
                                                                        case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                            2'b00 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 25 - 1 :  24*DW], 2'b11, axi_req_data[ DW * 24 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                            end 
                                                                            2'b01 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 24 - 1 :  23*DW], 2'b11, axi_req_data[ DW * 23 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                            end 
                                                                            2'b10 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 23 - 1 :  22*DW], 2'b11, axi_req_data[ DW * 22 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0,  2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                            end 
                                                                            2'b11 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 22 - 1 :  21*DW], 2'b11, axi_req_data[ DW * 21 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                            end
                                                                        endcase 
                                                                    end 
                                                                    4'd8 : begin 
                                                                        case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                            2'b00 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 29 - 1 :  28*DW], 2'b11, axi_req_data[ DW * 28 - 1 :  24*DW], 2'b11, axi_req_data[ DW * 24 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 } ;
                                                                            end 
                                                                            2'b01 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 28 - 1 :  27*DW], 2'b11, axi_req_data[ DW * 27 - 1 :  23*DW], 2'b11, axi_req_data[ DW * 23 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0 , 2'b10 ,128'b0, 2'b00 } ;
                                                                            end 
                                                                            2'b10 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 27 - 1 :  26*DW], 2'b11, axi_req_data[ DW * 26 - 1 :  22*DW], 2'b11, axi_req_data[ DW * 22 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 } ;
                                                                            end 
                                                                            2'b11 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 26 - 1 :  25*DW], 2'b11, axi_req_data[ DW * 25 - 1 :  21*DW], 2'b11, axi_req_data[ DW * 21 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                                            end 
                                                                        endcase 
                                                                    end 
                                                                    4'd9 : begin 
                                                                        case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                                            2'b00 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[  32 * DW - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_req_data[27*DW - 1 :  23*DW], 2'b11 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW - 1 :  0 *DW] , 32'b0,2'b10} ;
                                                                            end 
                                                                            2'b01 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 31 * DW - 1 :  30*DW], 2'b11 , axi_req_data[ 30*DW - 1 :  26*DW], 2'b11 ,axi_req_data[26*DW - 1 :  22*DW], 2'b11 ,axi_req_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_req_data[ 18*DW- 1 :  14*DW], 2'b11 ,axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW - 1 :  0 *DW] , 64'b0,2'b01} ;
                                                                            end 
                                                                            2'b10 : begin 
                                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[  30 * DW - 1 :  29*DW], 2'b11 , axi_req_data[ 29*DW - 1 :  25*DW], 2'b11 ,axi_req_data[25*DW - 1 :  21*DW], 2'b11 ,axi_req_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_req_data[ 17*DW- 1 :  13*DW], 2'b11 ,axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW - 1 :  0 *DW] , 96'b0,2'b00} ;
                                                                            end 
                                                                            2'b11 : begin // Can't happen
                                                                                buffer_if.data_in = '0 ;
                                                                            end 
                                                                        endcase 
                                                                    end 
                                                                endcase 
                                                            end 
                                                            else begin 
                                                                buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp1_no_cycles_comb , 0 );
                                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_req_data[27*DW - 1 :  23*DW], 2'b11 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b00} ;
                                                                end 
                                                        end 
                                                        end 
                                                A2P_2 : begin 
                                                        // Interface with source itself
                                                        axi_req_rd_grant = 1'b1 ;
                                                        // Interface with buffer 
                                                        buffer_if.data_in = {(axi_rdreq_hdr[4*DW - 3]) ? {axi_rdreq_hdr[4*DW - 1 : 0],  2'b11 }  : {axi_rdreq_hdr[4*DW - 1 : DW], 32'd0 , 2'b10 } , 1040'd0} ;    // repeat 
                                                        buffer_if.no_loc_wr = 1'b1 ;
                                                        tlp1_no_cycles_comb = 1'b1 ; 
                                                    end
                                                MASTER : begin 
                                                        // Interface with source itself
                                                        axi_master_grant = 1'b1 ;
                                                        // Interface with buffer 
                                                        data_length_comb = buffer_if.empty ? axi_master_hdr[ 2*DW + 9 : 2*DW] : 'b0 ; 
                                                        data_comb <= buffer_if.empty ? axi_comp_data [3 * DW - 1 : 0] : '0 ; 
                                                        // Interface with buffer 
												if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                    tlp1_no_cycles_comb = no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] );
												    if (tlp1_no_cycles_comb == 1) begin 
												    	buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b00, tlp1_no_cycles_comb , 0 );
                                                        case (buffer_if.no_loc_wr) 
                                                            4'd1 : begin // here is posted request (write with data) and it will store 1 locations 
                                                                buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , 1040'd0} ;
                                                            end 
                                                            4'd2 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b10 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b01 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b00 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd3 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b10 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b01 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd4 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b10 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b01 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd5 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b10 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b01 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd6 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;

                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b10 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b01 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd7 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;

                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b10 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b01 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd8 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b10 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b01 , 128'b0,2'b00} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                            4'd9 : begin 
                                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                                    2'b00 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b11} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b10} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b01} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b00} ;
                                                                    end 
                                                                endcase 
                                                            end 
                                                        endcase 
												    end 
												    else begin 
													    buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b01, tlp1_no_cycles_comb , 0 );
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b11} ;
												    end 
												end 
												else begin // Comp
                                                    tlp1_no_cycles_comb = '0;
                                                    buffer_if.data_in = {axi_master_hdr, 32'd0 , 2'b10 , 1040'd0} ; 
												    buffer_if.no_loc_wr = 1'b1;
												end
                                                        end
                                                RX_ROUTER_CFG : begin 
                                                        // Interface with source itself
                                                        rx_router_grant = 1'b1 ;
                                                        buffer_if.no_loc_wr = 1'b1 ;
                                                        tlp1_no_cycles_comb = 1'b1 ;
                                                        // Interface with buffer 
                                                        if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                                            buffer_if.data_in = {rx_router_comp_hdr, rx_router_data , 2'b11 , 1040'd0} ;
                                                        end 
                                                        else begin 
                                                            buffer_if.data_in = {rx_router_comp_hdr, 32'd0 , 2'b10 , 1040'd0} ;
                                                        end 
                                                    end												
                                            endcase
											//Interface with Sequence Buffer 															
											recorder_if.wr_en = 1'b1 ;
											recorder_if.wr_mode = 2'b01 ;
											recorder_if.wr_data_1 = recorder_if.rd_data_2 ;
											recorder_if.wr_data_2 = NO_SOURCE ;
										 end 
								    else if ((recorder_if.rd_data_1 == RX_ROUTER_ERR) ) begin 
											buffer_if.wr_en = 1'b1 ;
											// assert signals of case statement 
											// Interface with source itself
											rx_router_grant = 1'b0 ;
											// Interface with buffer 
											buffer_if.data_in = {rx_router_msg_hdr,  2'b11,  {1040{1'b0}}} ;
											buffer_if.no_loc_wr = 1'b1 ;
											tlp1_no_cycles_comb = 1'b1 ;
                                            two_req_on_pipe_comb = 1'b1 ; 
											//Interface with Sequence Buffer 															
											recorder_if.wr_en = 1'b1 ;
											recorder_if.wr_mode = 2'b01 ;
											recorder_if.wr_data_1 = recorder_if.rd_data_2 ;
											recorder_if.wr_data_2 = NO_SOURCE ;
										end 
                                end 
                                else begin 
                                    buffer_if.wr_en = 1'b0 ;
									rx_router_grant = 1'b0 ;
									buffer_if.data_in = '0 ;
									buffer_if.no_loc_wr = 1'b0 ;
									tlp1_no_cycles_comb = 1'b0 ;
									recorder_if.wr_en = 1'b0 ;
									recorder_if.wr_mode = 2'b00 ;
									recorder_if.wr_data_1 = NO_SOURCE ;
									recorder_if.wr_data_2 = NO_SOURCE ;
                                    two_req_on_pipe_comb = 1'b0 ; 
                                end 
                            end 
                            default: begin 
                                if (No_rd_loc_seq != 2'b00 && buffer_if.empty ) begin 
									recorder_if.wr_en = 1'b1 ;
									recorder_if.wr_mode =  No_rd_loc_seq ; // {1'b0, No_rd_loc_seq} ;
									recorder_if.wr_data_1 = recorder_if.rd_data_1 ;
									recorder_if.wr_data_2 = recorder_if.rd_data_2 ;
                                end 
                                end 
						endcase 

				        // State Transition 
						    if (tlp1_no_cycles_comb > 1'b1 ) begin  // Go to Data of TLP1
							next_state = TLP1_Data ;
						end 
						    else if ((tlp1_no_cycles_comb == 1'b1  ) &&  two_req_on_pipe_comb) begin  // Go to TLP2
							next_state = TLP2_HDR ;
						end 
						    // else if ((tlp1_no_cycles_comb == 1'b1) &&  two_req_on_pipe_comb && ! buffer_if.empty) begin // Stay in TLP1_HDR 
						    // 	next_state = TLP1_HDR ; 
						    // end 
						    else if ((tlp1_no_cycles_comb == 1'b1) &&  !two_req_on_pipe_comb && recorder_if.available  != SEQ_FIFO_DEPTH)  begin 
							next_state = TLP1_HDR ;
							if (recorder_if.available  == SEQ_FIFO_DEPTH - 1'b1 ) begin 
							recorder_if.rd_en   = 1'b1 ;
							recorder_if.rd_mode = 2'b01 ; // read 1 location from sequence recorder
							end 
							else begin 
							recorder_if.rd_en   = 1'b1 ;
							recorder_if.rd_mode = 2'b10 ; // read 2 locations from sequence recorder
							end                
						end 
                            else begin 
                                if (!buffer_if.empty) begin 
                                    next_state = TLP1_HDR ;
                                end 
                                else begin 
                                    next_state = ARBITER_IDLE ;
                                end 
                            end 
					end 
					TLP1_Data : begin 
                        buffer_if.wr_en = 1'b1 ;
						case(source_1) 
							A2P_1 : begin 
									//buffer_if.data_in = {axi_req_data} ;
									if ((axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   == 'b0_0000) ) begin  // 64-bit address + Mem
											if (count_tlp1 == 1) begin 
												buffer_if.no_loc_wr = no_wr_loc (data_length , 2'b11, tlp1_no_cycles , 1 );
                                                case (buffer_if.no_loc_wr) 
                                                    4'd1 : begin 
                                                        case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b100 - ((tlp1_no_cycles - 1'b1) * 4'd8)  ))  
                                                            2'b00 : begin 
                                                                buffer_if.data_in = {axi_req_data[4*DW -1 :0*DW], 2'b11, 1040'b0 } ;
                                                            end 
                                                            2'b01 : begin 
                                                                buffer_if.data_in = {axi_req_data[3*DW -1 :0*DW], 32'b0 , 2'b10, 1040'b0} ;
                                                            end 
                                                            2'b10 : begin 
                                                                buffer_if.data_in = {axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 1040'b0} ;
                                                            end 
                                                            2'b11 : begin 
                                                                buffer_if.data_in = {axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 1040'b0} ;
                                                            end 
                                                        endcase
                                                        end 
                                                    4'd2 : begin 
                                                            case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b100 - ((tlp1_no_cycles - 1'b1) * 4'd8)  ))  
                                                                2'b00 : begin 
                                                                    buffer_if.data_in = {axi_req_data[8*DW -1 :4*DW],2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 910'b0 } ;
                                                                end 
                                                                2'b01 : begin 
                                                                    buffer_if.data_in = {axi_req_data[7*DW -1 :3*DW],2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0 , 2'b10, 910'b0} ;
                                                                end 
                                                                2'b10 : begin 
                                                                    buffer_if.data_in = {axi_req_data[6*DW -1 :2*DW],2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 910'b0} ;
                                                                end 
                                                                2'b11 : begin 
                                                                    buffer_if.data_in = {axi_req_data[5*DW -1 :1*DW],2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 910'b0} ;
                                                                end 
                                                            endcase
                                                            end 
                                                    4'd3 : begin 
                                                            case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b100 - ((tlp1_no_cycles - 1'b1) * 4'd8)))  
                                                                2'b00 : begin 
                                                                    buffer_if.data_in = {axi_req_data[12*DW -1 :8*DW],2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 780'b0} ;
                                                                end 
                                                                2'b01 : begin 
                                                                    buffer_if.data_in = {axi_req_data[11*DW -1 :7*DW],2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 780'b0} ;
                                                                end 
                                                                2'b10 : begin 
                                                                    buffer_if.data_in = {axi_req_data[10*DW -1 :6*DW],2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 780'b0} ;
                                                                end 
                                                                2'b11 : begin 
                                                                    buffer_if.data_in = {axi_req_data[9*DW -1 :5*DW],2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 780'b0} ;
                                                                end 
                                                            endcase
                                                            end 
                                                    4'd4 : begin 
                                                        case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b100 - ((tlp1_no_cycles - 1'b1) * 4'd8) ))  
                                                                2'b00 : begin 
                                                                buffer_if.data_in = {axi_req_data[16*DW -1 :12*DW],2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 650'b0} ;
                                                                end 
                                                                2'b01 : begin 
                                                                    buffer_if.data_in = {axi_req_data[15*DW -1 :11*DW],2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0,  2'b10, 650'b0} ;
                                                                end 
                                                                2'b10 : begin 
                                                                    buffer_if.data_in = {axi_req_data[14*DW -1 :10*DW],2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01, 650'b0} ;
                                                                end 
                                                                2'b11 : begin 
                                                                    buffer_if.data_in = {axi_req_data[13*DW -1 :9*DW],2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0 ,  2'b00, 650'b0} ;
                                                                end 
                                                            endcase
                                                            end 
                                                    4'd5 : begin 
                                                            case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b100 - ((tlp1_no_cycles - 1'b1) * 4'd8) ))  
                                                                2'b00 : begin 
                                                                        buffer_if.data_in = {axi_req_data[20*DW -1 :16*DW],2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 520'b0} ;
                                                                        end 
                                                                        2'b01 : begin 
                                                                            buffer_if.data_in = {axi_req_data[19*DW -1 :15*DW],2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 520'b0} ;
                                                                        end 
                                                                        2'b10 : begin 
                                                                            buffer_if.data_in = {axi_req_data[18*DW -1 :14*DW],2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW],64'b0, 2'b01,  520'b0} ;
                                                                        end 
                                                                        2'b11 : begin 
                                                                            buffer_if.data_in = {axi_req_data[17*DW -1 :13*DW],2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW],96'b0, 2'b00,  520'b0} ;
                                                                        end 
                                                            endcase
                                                            end 
                                                    4'd6 : begin
                                                            case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b100 - ((tlp1_no_cycles - 1'b1) * 4'd8) ))  
                                                                2'b00 : begin 
                                                                        buffer_if.data_in = {axi_req_data[24*DW -1 :20*DW],2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 390'b0} ;
                                                                        end 
                                                                        2'b01 : begin 
                                                                            buffer_if.data_in = {axi_req_data[23*DW -1 :19*DW],2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 390'b0} ;
                                                                        end 
                                                                        2'b10 : begin 
                                                                            buffer_if.data_in = {axi_req_data[22*DW -1 :18*DW],2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 390'b0} ;
                                                                        end 
                                                                        2'b11 : begin 
                                                                            buffer_if.data_in = {axi_req_data[21*DW -1 :17*DW],2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 390'b0} ;
                                                                        end 
                                                            endcase
                                                            end 
                                                    4'd7 : begin 
                                                            case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b100 - ((tlp1_no_cycles - 1'b1) * 4'd8) ))  
                                                                2'b00 : begin 
                                                                    buffer_if.data_in = {axi_req_data[28*DW -1 :24*DW],2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11,260'b0} ;
                                                                end 
                                                                2'b01 : begin 
                                                                    buffer_if.data_in = {axi_req_data[27*DW -1 :23*DW],2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10,260'b0} ;
                                                                end 
                                                                2'b10 : begin 
                                                                    buffer_if.data_in = {axi_req_data[26*DW -1 :22*DW],2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01,260'b0} ;
                                                                end 
                                                                2'b11 : begin 
                                                                    buffer_if.data_in = {axi_req_data[25*DW -1 :21*DW],2'b11, axi_req_data[21*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0,  2'b00,260'b0} ;
                                                                end 
                                                            endcase
                                                            end 
                                                    4'd8 : begin 
                                                        case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b100 - ((tlp1_no_cycles - 1'b1) * 4'd8) ))  
                                                            2'b00 : begin 
                                                                    buffer_if.data_in = {axi_req_data[32*DW -1 :28*DW],2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 130'b0} ;
                                                                    end 
                                                            2'b01 : begin 
                                                                        buffer_if.data_in = {axi_req_data[31*DW -1 :27*DW],2'b11, axi_req_data[27*DW -1 :23*DW], 2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 130'b0} ;
                                                                    end 
                                                            2'b10 : begin 
                                                                        buffer_if.data_in = {axi_req_data[30*DW -1 :26*DW],2'b11, axi_req_data[26*DW -1 :22*DW], 2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 130'b0} ;
                                                                    end 
                                                            2'b11 : begin 
                                                                        buffer_if.data_in = {axi_req_data[29*DW -1 :25*DW],2'b11, axi_req_data[25*DW -1 :21*DW], 2'b11, axi_req_data[22*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 130'b0} ;
                                                                    end 
                                                        endcase
                                                            end 
                                                endcase 
											end 
											else begin 
                                                data_comb = axi_req_data [3* DW - 1 : 0] ; 
                                                buffer_if.no_loc_wr = no_wr_loc (data_length , 2'b10, tlp1_no_cycles , 1 );
                                                buffer_if.data_in = {axi_req_data[32*DW -1 :28*DW], 2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11 , 128'b0 , 2'b00 } ;
                                            end
										end 
									else begin 
										// buffer_if.data_in = {registered_data, axi_req_data[AXI_MAX_NUM_BYTES * 8 - 1 :  3*DW]} ; 
										if (count_tlp1 == 1) begin 
											buffer_if.no_loc_wr = no_wr_loc (data_length , 2'b11, tlp1_no_cycles , 0 );
                                            case (buffer_if.no_loc_wr) 
                                                4'd1 : begin // here is posted request (write with data) and it will store 1 locations 
                                                    buffer_if.data_in = {registered_data, axi_req_data[ 1*DW - 1 :  0*DW], 2'b11 , 1040'd0 } ;
                                                end 
                                                4'd2 : begin 
                                                    case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b011 - ((tlp1_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                        2'b00 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ 5*DW - 1  :  4*DW], 2'b11 , axi_req_data[ 4*DW - 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                            2'b01 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ 4*DW - 1  :  3*DW], 2'b11 , axi_req_data[ 3*DW - 1 :  0*DW], 32'b0 ,  2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                            2'b10 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ 3*DW - 1  :  2*DW], 2'b11 , axi_req_data[ 2*DW - 1 :  0*DW], 64'b0 ,  2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                            2'b11 : begin  
                                                            buffer_if.data_in = {registered_data, axi_req_data[ 2*DW - 1  :  1*DW], 2'b11 , axi_req_data[ 1*DW - 1 :  0*DW], 96'b0 ,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                        endcase 
                                                    end 
                                                4'd3 : begin 
                                                    case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b011 - ((tlp1_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                        2'b00 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 9 - 1 :  8*DW], 2'b11 , axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[4*DW - 1 :  0*DW],  2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                        2'b01 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 8 - 1 :  7*DW], 2'b11 , axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[3*DW - 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                        2'b10 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 7 - 1 :  6*DW], 2'b11 , axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[2*DW - 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                        2'b11 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 6 - 1 :  5*DW], 2'b11 , axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[1*DW - 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                    endcase 
                                                end 
                                                4'd4 : begin 
                                                    case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b011 - ((tlp1_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                        2'b00 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 13 - 1 :  12*DW], 2'b11 , axi_req_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW - 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                        2'b01 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 12 - 1 :  11*DW], 2'b11 , axi_req_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                        2'b10 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 11 - 1 :  10*DW], 2'b11 , axi_req_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                        2'b11 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 10 - 1 :  9*DW], 2'b11 , axi_req_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW - 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                    endcase 
                                                end 
                                                4'd5 : begin 
                                                    case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b011 - ((tlp1_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                        2'b00 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 17 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                        2'b01 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 16 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                        2'b10 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 15 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                        2'b11 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 14 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                    endcase 
                                                end 
                                                4'd6 : begin 
                                                    case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b011 - ((tlp1_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                        2'b00 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 21 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                        end 
                                                        2'b01 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 20 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                        end 
                                                        2'b10 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 19 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0, 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                        end 
                                                        2'b11 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 18 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                        end 
                                                    endcase 
                                                end 
                                                4'd7 : begin 
                                                    case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b011 - ((tlp1_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                        2'b00 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 25 - 1 :  24*DW], 2'b11, axi_req_data[ DW * 24 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                        end 
                                                        2'b01 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 24 - 1 :  23*DW], 2'b11, axi_req_data[ DW * 23 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                        end 
                                                        2'b10 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 23 - 1 :  22*DW], 2'b11, axi_req_data[ DW * 22 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0,  2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                        end 
                                                        2'b11 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 22 - 1 :  21*DW], 2'b11, axi_req_data[ DW * 21 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                        end
                                                    endcase 
                                                end 
                                                4'd8 : begin 
                                                    case ((buffer_if.no_loc_wr * 3'd4) - (data_length+ 3'b011 - ((tlp1_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                        2'b00 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 29 - 1 :  28*DW], 2'b11, axi_req_data[ DW * 28 - 1 :  24*DW], 2'b11, axi_req_data[ DW * 24 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 } ;
                                                        end 
                                                        2'b01 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 28 - 1 :  27*DW], 2'b11, axi_req_data[ DW * 27 - 1 :  23*DW], 2'b11, axi_req_data[ DW * 23 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0 , 2'b10 ,128'b0, 2'b00 } ;
                                                        end 
                                                        2'b10 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 27 - 1 :  26*DW], 2'b11, axi_req_data[ DW * 26 - 1 :  22*DW], 2'b11, axi_req_data[ DW * 22 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 } ;
                                                        end 
                                                        2'b11 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ DW * 26 - 1 :  25*DW], 2'b11, axi_req_data[ DW * 25 - 1 :  21*DW], 2'b11, axi_req_data[ DW * 21 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                        end 
                                                    endcase 
                                                end 
                                                4'd9 : begin 
                                                    case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b011 - ((tlp1_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                        2'b00 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[  32 * DW - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_req_data[27*DW - 1 :  23*DW], 2'b11 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW - 1 :  0 *DW] , 32'b0,2'b10} ;
                                                        end 
                                                        2'b01 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[ 31 * DW - 1 :  30*DW], 2'b11 , axi_req_data[ 30*DW - 1 :  26*DW], 2'b11 ,axi_req_data[26*DW - 1 :  22*DW], 2'b11 ,axi_req_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_req_data[ 18*DW- 1 :  14*DW], 2'b11 ,axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW - 1 :  0 *DW] , 64'b0,2'b01} ;
                                                        end 
                                                        2'b10 : begin 
                                                            buffer_if.data_in = {registered_data, axi_req_data[  30 * DW - 1 :  29*DW], 2'b11 , axi_req_data[ 29*DW - 1 :  25*DW], 2'b11 ,axi_req_data[25*DW - 1 :  21*DW], 2'b11 ,axi_req_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_req_data[ 17*DW- 1 :  13*DW], 2'b11 ,axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW - 1 :  0 *DW] , 96'b0,2'b00} ;
                                                        end 
                                                        2'b11 : begin // Can't happen
                                                            buffer_if.data_in = '0 ;
                                                        end 
                                                    endcase 
                                                end 
                                            endcase 
										end 
                                        else begin 
                                            data_comb = axi_req_data [3* DW - 1 : 0] ; 
                                            buffer_if.no_loc_wr = no_wr_loc (data_length, 2'b10, tlp1_no_cycles , 0 );
                                            buffer_if.data_in = {registered_data , axi_req_data[32*DW -1 :31*DW], 2'b11, axi_req_data[31*DW -1 :27*DW], 2'b11, axi_req_data[27*DW -1 :23*DW], 2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11 , 128'b0 , 2'b00 } ;
    
                                        end
									end 
									end
							MASTER : begin 
                                data_comb = axi_comp_data [3* DW - 1 : 0] ; 
                                if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                    if (count_tlp1 == 1) begin 
                                        buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b11, tlp1_no_cycles , 0 );
                                        case (buffer_if.no_loc_wr) 
                                            4'd1 : begin // here is posted request (write with data) and it will store 1 locations 
                                            buffer_if.data_in = {registered_data, axi_comp_data[ 1 * DW - 1 : 0], 2'b11 , 1040'd0} ;
                                        end 
                                            4'd2 : begin 
                                            case ( (buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp1_no_cycles - 1'd1 )) ) ) 
                                                2'b00 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 5 * DW - 1 :  4*DW], 2'b11 , axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b01 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 4 * DW - 1 :  3*DW], 2'b11 , axi_comp_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b10 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 3 * DW - 1 :  2*DW], 2'b11 , axi_comp_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b11 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 2 * DW - 1 :  1*DW], 2'b11 , axi_comp_data[ 1*DW - 1 :  0*DW] , 96'b0, 2'b00 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                            endcase 
                                        end 
                                            4'd3 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp1_no_cycles - 1'd1 )) ) ) 
                                                    2'b00 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 9 * DW - 1 :  8*DW], 2'b11 , axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b01 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 8 * DW - 1 :  7*DW], 2'b11 , axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[3*DW - 1 :  0*DW], 32'b0 , 2'b10 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b10 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 7 * DW - 1 :  6*DW], 2'b11 , axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b11 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 6 * DW - 1 :  5*DW], 2'b11 , axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[1*DW - 1 :  0*DW], 96'b0 , 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                            endcase 
                                        end 
                                            4'd4 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp1_no_cycles - 1'd1 ))))  
                                                    2'b00 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 13 * DW - 1 :  12*DW], 2'b11 , axi_comp_data[ 12*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b01 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 12 * DW - 1 :  11*DW], 2'b11 , axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b10 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 11 * DW - 1 :  10*DW], 2'b11 , axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b11 : begin 
                                                    buffer_if.data_in = {registered_data,axi_comp_data[ 10 * DW - 1 :  9*DW], 2'b11 , axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'b0, 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                            endcase 
                                        end 
                                            4'd5 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp1_no_cycles - 1'd1 ))))  
                                                    2'b00 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 17 * DW - 1 :  16*DW], 2'b11 , axi_comp_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW- 1 :  0*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b01 : begin 
                                                    buffer_if.data_in = {registered_data,axi_comp_data[ 16 * DW - 1 :  15*DW], 2'b11 , axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW- 1 :  0*DW], 32'b0,  2'b10 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b10 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 15 * DW - 1 :  14*DW], 2'b11 , axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW- 1 :  0*DW], 64'b0,  2'b01 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b11 : begin 
                                                    buffer_if.data_in = {registered_data,axi_comp_data[ 14 * DW - 1 :  13*DW], 2'b11 , axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                            endcase 
                                        end 
                                            4'd6 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp1_no_cycles - 1'd1 ))))  
                                                    2'b00 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 21 * DW - 1 :  20*DW], 2'b11 , axi_comp_data[ 20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW- 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b01 : begin 
                                                    buffer_if.data_in = {registered_data,axi_comp_data[ 20 * DW - 1 :  19*DW], 2'b11 , axi_comp_data[ 19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW- 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'B0,  2'b10 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b10 : begin 
                                                    buffer_if.data_in = {registered_data,axi_comp_data[ 19 * DW - 1 :  18*DW], 2'b11 , axi_comp_data[ 18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW- 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'B0, 2'b01 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b11 : begin 
                                                    buffer_if.data_in = {registered_data,axi_comp_data[ 18 * DW - 1 :  17*DW], 2'b11 , axi_comp_data[ 17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW- 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'B0, 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                            endcase 
                                        end 
                                            4'd7 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp1_no_cycles - 1'd1 ))))  
                                                    2'b00 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[25* DW - 1 :  24*DW], 2'b11 , axi_comp_data[ 24*DW - 1 :  20*DW], 2'b11 ,axi_comp_data[20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW- 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b01 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[24* DW - 1 :  23*DW], 2'b11 , axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW- 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[3*DW - 1 :  0*DW], 32'B0 ,  2'b10 , 128'b0 , 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b10 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[23* DW - 1 :  22*DW], 2'b11 , axi_comp_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW- 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[2*DW - 1 :  0*DW], 64'B0 , 2'b01 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                end 
                                                2'b11 : begin 
                                                    buffer_if.data_in = {registered_data,axi_comp_data[22* DW - 1 :  21*DW], 2'b11 , axi_comp_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW- 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[1*DW - 1 :  0*DW], 96'B0 , 2'b00 , 128'b0, 2'b00 , 128'b0,2'b00} ;
                                                end 
                                            endcase 
                                        end 
                                            4'd8 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp1_no_cycles - 1'd1 ))))  
                                                    2'b00 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[29 * DW - 1 :  28*DW], 2'b11 , axi_comp_data[ 28*DW - 1 :  24*DW], 2'b11 ,axi_comp_data[24*DW - 1 :  20*DW], 2'b11 ,axi_comp_data[ 20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[ 16*DW- 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 , 128'b0,2'b00} ;
                                                end 
                                                2'b01 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[28 * DW - 1 :  27*DW], 2'b11 , axi_comp_data[ 27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW- 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'B0, 2'b10 , 128'b0,2'b00} ;
                                                end 
                                                2'b10 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[27 * DW - 1 :  26*DW], 2'b11 , axi_comp_data[ 26*DW - 1 :  22*DW], 2'b11 ,axi_comp_data[22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[ 18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW- 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'B0, 2'b01 , 128'b0,2'b00} ;
                                                end 
                                                2'b11 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[26 * DW - 1 :  25*DW], 2'b11 , axi_comp_data[ 25*DW - 1 :  21*DW], 2'b11 ,axi_comp_data[21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[ 17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW- 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'B0, 2'b00 , 128'b0,2'b00} ;
                                                end 
                                            endcase 
                                        end 
                                            4'd9 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp1_no_cycles - 1'd1 ))))  
                                                2'b00 : begin // Can't happen
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b11} ;
                                                end 
                                                2'b01 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , axi_comp_data[ 3*DW - 1 :  0*DW] ,  32'b0,2'b10} ;
                                                end 
                                                2'b10 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 31*DW - 1 :  30*DW], 2'b11 , axi_comp_data[ 30*DW - 1 :  26*DW], 2'b11 ,axi_comp_data[26*DW - 1 :  22*DW], 2'b11 ,axi_comp_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[ 18*DW- 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 , axi_comp_data[ 2*DW - 1 :  0*DW] ,  64'b0,2'b01} ;
                                                end 
                                                2'b11 : begin 
                                                    buffer_if.data_in = {registered_data, axi_comp_data[ 30*DW - 1:  29*DW], 2'b11 , axi_comp_data[ 29*DW - 1 :  25*DW], 2'b11 ,axi_comp_data[25*DW - 1 :  21*DW], 2'b11 ,axi_comp_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[ 17*DW- 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 , axi_comp_data[ 1*DW - 1 :  0*DW] ,  96'b0,2'b00} ;
                                                end 
                                            endcase 
                                        end 
                                        endcase 
                                    end 
                                    else begin 
                                    buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b10, tlp1_no_cycles , 1'b0 );
                                    buffer_if.data_in = {registered_data, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b00} ;
                                end 
                                end 
                                else begin // Comp
                                    buffer_if.data_in = {axi_master_hdr, 32'd0 , 2'b10 , 1040'd0} ; 
                                    buffer_if.no_loc_wr = 1'b1;
                                end 
							end														
						endcase    
				    // State Transition 
						if ((count_tlp1 != 1'b1) ) begin  // Keep going on Data of TLP1
							next_state = TLP1_Data ;
						end 
						else if ((count_tlp1 == 1'b1) && two_req_on_pipe) begin  // Go to TLP2
							next_state = TLP2_HDR ;
						end 
                        // else if ((count_tlp1 == 1'b1) && two_req_on_pipe && !buffer_if.empty) begin 
						// 	next_state = TLP1_Data ;   // add flag to make it no change in bus if keeping TLP1_Data
                        // end 
						else if (recorder_if.available  != SEQ_FIFO_DEPTH)  begin 
							next_state = TLP1_HDR ;
							if (recorder_if.available  == SEQ_FIFO_DEPTH - 1'b1 ) begin 
								recorder_if.rd_en = 1'b1 ;
								recorder_if.rd_mode = 2'b01 ; // read 1 location from sequence recorder
							end 
							else begin 
								recorder_if.rd_en = 1'b1 ;
								recorder_if.rd_mode = 2'b10 ; // read 2 locations from sequence recorder
							end                
						end 
						else begin
							next_state = ARBITER_IDLE ; 
						end  
					end 
					TLP2_HDR : begin 
						// Output of State
                            buffer_if.wr_en = 1'b0 ;                                     
                            // Interface with source itself
                            axi_req_rd_grant = 1'b0 ;
                            buffer_if.data_in = '0;
                            buffer_if.no_loc_wr =  1'b0 ;
                            tlp2_no_cycles_comb = 1'b0 ;
						    case (source_2)
                                A2P_1 : begin 
                                buffer_if.wr_en = buffer_if.empty ? 1'b1 : 1'b0 ;                                    
                                // Interface with source itself
                                axi_req_wr_grant = buffer_if.empty ? 1'b1 : 1'b0 ;
                                // Interface with buffer 
                                tlp2_no_cycles_comb = buffer_if.empty ? no_cycles_calc (axi_wrreq_hdr.Length) : '0;
                                data_comb <= buffer_if.empty ? axi_req_data [3 * DW - 1 : 0] : '0 ; 
                                data_length_comb = buffer_if.empty ? axi_wrreq_hdr.Length : 'b0 ; 
                                if (buffer_if.empty) begin 
                                    if ((axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   == 'b0_0000) ) begin  // 64-bit address + Mem
                                        if (tlp2_no_cycles_comb == 1) begin 
                                        buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp2_no_cycles_comb , 1 );
                                        case (buffer_if.no_loc_wr) 
                                            4'd2 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 910'b0 } ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0 , 2'b10, 910'b0} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 910'b0} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 910'b0} ;
                                                    end 
                                                endcase
                                            end 
                                            4'd3 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 780'b0} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 780'b0} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 780'b0} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 780'b0} ;
                                                    end 
                                                endcase
                                            end 
                                            4'd4 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 650'b0} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0,  2'b10, 650'b0} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01, 650'b0} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0 ,  2'b00, 650'b0} ;
                                                    end 
                                                endcase
                                            end 
                                            4'd5 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 520'b0} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 520'b0} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW],64'b0, 2'b01,  520'b0} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW],96'b0, 2'b00,  520'b0} ;
                                                    end 
                                                endcase
                                            end 
                                            4'd6 : begin
                                                case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 390'b0} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 390'b0} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 390'b0} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 390'b0} ;
                                                    end 
                                                endcase
                                            end 
                                            4'd7 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11,260'b0} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10,260'b0} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01,260'b0} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[21*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0,  2'b00,260'b0} ;
                                                    end 
                                                endcase
                                            end 
                                            4'd8 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 130'b0} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[27*DW -1 :23*DW], 2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 130'b0} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[26*DW -1 :22*DW], 2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 130'b0} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[25*DW -1 :21*DW], 2'b11, axi_req_data[22*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 130'b0} ;
                                                    end 
                                                endcase
                                            end 
                                            4'd9 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 3'b100))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[32*DW -1 :28*DW], 2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[31*DW -1 :27*DW], 2'b11, axi_req_data[27*DW -1 :23*DW], 2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[30*DW -1 :26*DW], 2'b11, axi_req_data[26*DW -1 :22*DW], 2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[29*DW -1 :25*DW], 2'b11, axi_req_data[25*DW -1 :21*DW], 2'b11, axi_req_data[21*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0,  2'b00} ;
                                                    end 
                                                endcase
                                            end 
                                        endcase 
                                    end 
                                        else begin 
                                        buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp2_no_cycles_comb , 1 );
                                        buffer_if.data_in = {axi_wrreq_hdr,2'b11, axi_req_data[32*DW -1 :28*DW], 2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11} ;
                                    end 
                                    end 
                                    else begin 
                                        if (tlp2_no_cycles_comb == 1) begin 
                                        buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b00, tlp2_no_cycles_comb , 0 );
                                        case (buffer_if.no_loc_wr) 
                                            4'd1 : begin // here is posted request (write with data) and it will store 1 locations 
                                                buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 1*DW - 1 :  0*DW], 2'b11 , 1040'd0 } ;
                                            end 
                                            4'd2 : begin 
                                                if (axi_wrreq_hdr.Length != 10'd0) begin 
                                                    case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                        2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 5*DW - 1  :  4*DW], 2'b11 , axi_req_data[ 4*DW - 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                        2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 4*DW - 1  :  3*DW], 2'b11 , axi_req_data[ 3*DW - 1 :  0*DW], 32'b0 ,  2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                        2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 3*DW - 1  :  2*DW], 2'b11 , axi_req_data[ 2*DW - 1 :  0*DW], 64'b0 ,  2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                        2'b11 : begin  
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 2*DW - 1  :  1*DW], 2'b11 , axi_req_data[ 1*DW - 1 :  0*DW], 96'b0 ,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    endcase 
                                                end 
                                                else begin 
                                                    case ( (buffer_if.no_loc_wr * 3'd4) - (10'd1024 + 2'b11))  
                                                        2'b00 : begin 
                                                            buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_req_data[27*DW - 1 :  23*DW], 2'b00 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_req_data[11*DW - 1 :  7*DW], 2'b00 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                        2'b01 : begin 
                                                            buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b10 ,axi_req_data[27*DW - 1 :  23*DW], 2'b00 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_req_data[11*DW - 1 :  7*DW], 2'b00 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                        2'b10 : begin 
                                                            buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b01 ,axi_req_data[27*DW - 1 :  23*DW], 2'b00 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_req_data[11*DW - 1 :  7*DW], 2'b00 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                        2'b11 : begin 
                                                            buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b00 ,axi_req_data[27*DW - 1 :  23*DW], 2'b00 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_req_data[11*DW - 1 :  7*DW], 2'b00 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                        end 
                                                    endcase
                                                end 
                                            end 
                                            4'd3 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 9 - 1 :  8*DW], 2'b11 , axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[4*DW - 1 :  0*DW],  2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 8 - 1 :  7*DW], 2'b11 , axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[3*DW - 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 7 - 1 :  6*DW], 2'b11 , axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[2*DW - 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 6 - 1 :  5*DW], 2'b11 , axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[1*DW - 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd4 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 13 - 1 :  12*DW], 2'b11 , axi_req_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW - 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 12 - 1 :  11*DW], 2'b11 , axi_req_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 11 - 1 :  10*DW], 2'b11 , axi_req_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 10 - 1 :  9*DW], 2'b11 , axi_req_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW - 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd5 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 17 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 16 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 15 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 14 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd6 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 21 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 20 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 19 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0, 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 18 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd7 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 25 - 1 :  24*DW], 2'b11, axi_req_data[ DW * 24 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 24 - 1 :  23*DW], 2'b11, axi_req_data[ DW * 23 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 23 - 1 :  22*DW], 2'b11, axi_req_data[ DW * 22 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0,  2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 22 - 1 :  21*DW], 2'b11, axi_req_data[ DW * 21 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end
                                                endcase 
                                            end 
                                            4'd8 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 29 - 1 :  28*DW], 2'b11, axi_req_data[ DW * 28 - 1 :  24*DW], 2'b11, axi_req_data[ DW * 24 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 28 - 1 :  27*DW], 2'b11, axi_req_data[ DW * 27 - 1 :  23*DW], 2'b11, axi_req_data[ DW * 23 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0 , 2'b10 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 27 - 1 :  26*DW], 2'b11, axi_req_data[ DW * 26 - 1 :  22*DW], 2'b11, axi_req_data[ DW * 22 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ DW * 26 - 1 :  25*DW], 2'b11, axi_req_data[ DW * 25 - 1 :  21*DW], 2'b11, axi_req_data[ DW * 21 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd9 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_wrreq_hdr.Length + 2'b11))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[  32 * DW - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_req_data[27*DW - 1 :  23*DW], 2'b11 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW - 1 :  0 *DW] , 32'b0,2'b11} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ 31 * DW - 1 :  30*DW], 2'b11 , axi_req_data[ 30*DW - 1 :  26*DW], 2'b11 ,axi_req_data[26*DW - 1 :  22*DW], 2'b11 ,axi_req_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_req_data[ 18*DW- 1 :  14*DW], 2'b11 ,axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW - 1 :  0 *DW] , 64'b0,2'b10} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[  30 * DW - 1 :  29*DW], 2'b11 , axi_req_data[ 29*DW - 1 :  25*DW], 2'b11 ,axi_req_data[25*DW - 1 :  21*DW], 2'b11 ,axi_req_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_req_data[ 17*DW- 1 :  13*DW], 2'b11 ,axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW - 1 :  0 *DW] , 96'b0,2'b01} ;
                                                    end 
                                                    2'b11 : begin // Can't happen
                                                        buffer_if.data_in = '0 ;
                                                    end 
                                                endcase 
                                            end 
                                        endcase 
                                    end 
                                        else begin 
                                        buffer_if.no_loc_wr = no_wr_loc (axi_wrreq_hdr.Length , 2'b01, tlp2_no_cycles_comb , 0 );
                                        buffer_if.data_in = {axi_wrreq_hdr[4*DW - 1 : DW], axi_req_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_req_data[27*DW - 1 :  23*DW], 2'b11 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b11} ;
                                    end 
                                    end
                                end 
                                else begin 
                                    buffer_if.no_loc_wr = '0;
                                    buffer_if.data_in = '0 ;
                                end 
                            end 
                                A2P_2 : begin 
                                buffer_if.wr_en = buffer_if.empty ? 1'b1 : 1'b0 ;                                     
                                // Interface with source itself
                                axi_req_rd_grant = buffer_if.empty ? 1'b1 : 1'b0 ;
                                // Interface with buffer 
                                if (buffer_if.empty ) begin 
                                    buffer_if.data_in = {(axi_rdreq_hdr[4*DW - 3]) ? {axi_rdreq_hdr[4*DW - 1 : 0],  2'b11 }  : {axi_rdreq_hdr[4*DW - 1 : DW], 32'd0 , 2'b10 } , 1040'd0} ;    // repeat 
                                end 
                                else begin 
                                    buffer_if.data_in = '0;
                                end 
                                buffer_if.no_loc_wr = buffer_if.empty ? 1'b1 : 1'b0 ;
                                tlp2_no_cycles_comb = buffer_if.empty ? 1'b1 : 1'b0 ; 
                            end
                                MASTER : begin 
                                buffer_if.wr_en = buffer_if.empty ? 1'b1 : 1'b0 ;                                    
                                // Interface with source itself
                                axi_master_grant = buffer_if.empty ? 1'b1 : 1'b0 ;
                                // Interface with buffer 
                                tlp2_no_cycles_comb = buffer_if.empty ? no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] ) : 1'b0 ;
                                data_length_comb = buffer_if.empty ? axi_master_hdr[ 2*DW + 9 : 2*DW] : 'b0 ; 
                                data_comb <= buffer_if.empty ? axi_comp_data [3 * DW - 1 : 0] : '0 ; 
                                // Interface with buffer 
                                if (buffer_if.empty) begin 
								    if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                        tlp2_no_cycles_comb = no_cycles_calc (axi_master_hdr[ 2*DW + 9 : 2*DW] ) ;
                                    if (tlp2_no_cycles_comb == 1) begin 
                                        buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b00, tlp2_no_cycles_comb , 0 );
                                        case (buffer_if.no_loc_wr) 
                                            4'd1 : begin // here is posted request (write with data) and it will store 1 locations 
                                                buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 1 * DW - 1 : 0], 2'b11 , 1040'd0} ;
                                            end 
                                            4'd2 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 5 * DW - 1 :  4*DW], 2'b11 , axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 4 * DW - 1 :  3*DW], 2'b11 , axi_comp_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 3 * DW - 1 :  2*DW], 2'b11 , axi_comp_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 2 * DW - 1 :  1*DW], 2'b11 , axi_comp_data[ 1*DW - 1 :  0*DW] , 96'b0, 2'b00 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd3 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 9 * DW - 1 :  8*DW], 2'b11 , axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 8 * DW - 1 :  7*DW], 2'b11 , axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[3*DW - 1 :  0*DW], 32'b0 , 2'b10 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 7 * DW - 1 :  6*DW], 2'b11 , axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 6 * DW - 1 :  5*DW], 2'b11 , axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[1*DW - 1 :  0*DW], 96'b0 , 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd4 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 13 * DW - 1 :  12*DW], 2'b11 , axi_comp_data[ 12*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 12 * DW - 1 :  11*DW], 2'b11 , axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 11 * DW - 1 :  10*DW], 2'b11 , axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 10 * DW - 1 :  9*DW], 2'b11 , axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'b0, 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd5 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 17 * DW - 1 :  16*DW], 2'b11 , axi_comp_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW- 1 :  0*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 16 * DW - 1 :  15*DW], 2'b11 , axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW- 1 :  0*DW], 32'b0,  2'b10 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 15 * DW - 1 :  14*DW], 2'b11 , axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW- 1 :  0*DW], 64'b0,  2'b01 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 14 * DW - 1 :  13*DW], 2'b11 , axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd6 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 21 * DW - 1 :  20*DW], 2'b11 , axi_comp_data[ 20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW- 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 20 * DW - 1 :  19*DW], 2'b11 , axi_comp_data[ 19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW- 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'B0,  2'b10 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 19 * DW - 1 :  18*DW], 2'b11 , axi_comp_data[ 18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW- 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'B0, 2'b01 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[ 18 * DW - 1 :  17*DW], 2'b11 , axi_comp_data[ 17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW- 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'B0, 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd7 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[25* DW - 1 :  24*DW], 2'b11 , axi_comp_data[ 24*DW - 1 :  20*DW], 2'b11 ,axi_comp_data[20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW- 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[24* DW - 1 :  23*DW], 2'b11 , axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW- 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[3*DW - 1 :  0*DW], 32'B0 ,  2'b10 , 128'b0 , 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[23* DW - 1 :  22*DW], 2'b11 , axi_comp_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW- 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[2*DW - 1 :  0*DW], 64'B0 , 2'b01 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_master_hdr,axi_comp_data[22* DW - 1 :  21*DW], 2'b11 , axi_comp_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW- 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[1*DW - 1 :  0*DW], 96'B0 , 2'b00 , 128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd8 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[29 * DW - 1 :  28*DW], 2'b11 , axi_comp_data[ 28*DW - 1 :  24*DW], 2'b11 ,axi_comp_data[24*DW - 1 :  20*DW], 2'b11 ,axi_comp_data[ 20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[ 16*DW- 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[28 * DW - 1 :  27*DW], 2'b11 , axi_comp_data[ 27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW- 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'B0, 2'b10 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[27 * DW - 1 :  26*DW], 2'b11 , axi_comp_data[ 26*DW - 1 :  22*DW], 2'b11 ,axi_comp_data[22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[ 18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW- 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'B0, 2'b01 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[26 * DW - 1 :  25*DW], 2'b11 , axi_comp_data[ 25*DW - 1 :  21*DW], 2'b11 ,axi_comp_data[21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[ 17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW- 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'B0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd9 : begin 
                                                case ( (buffer_if.no_loc_wr * 3'd4) - (axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11))  
                                                    2'b00 : begin // Can't happen
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b11} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , axi_comp_data[ 3*DW - 1 :  0*DW] ,  32'b0,2'b10} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 31*DW - 1 :  30*DW], 2'b11 , axi_comp_data[ 30*DW - 1 :  26*DW], 2'b11 ,axi_comp_data[26*DW - 1 :  22*DW], 2'b11 ,axi_comp_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[ 18*DW- 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 , axi_comp_data[ 2*DW - 1 :  0*DW] ,  64'b0,2'b01} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ 30*DW - 1:  29*DW], 2'b11 , axi_comp_data[ 29*DW - 1 :  25*DW], 2'b11 ,axi_comp_data[25*DW - 1 :  21*DW], 2'b11 ,axi_comp_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[ 17*DW- 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 , axi_comp_data[ 1*DW - 1 :  0*DW] ,  96'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                        endcase 
                                    end 
                                    else begin 
                                        buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b01, tlp2_no_cycles_comb , 1'b0 );
                                        buffer_if.data_in = {axi_master_hdr, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b00} ;
                                    end 
                                end 
                                    else begin // Comp
                                        tlp2_no_cycles_comb = 1'b1 ;
                                        buffer_if.data_in = {axi_master_hdr, 32'd0 , 2'b10 , 1040'd0} ; 
                                        buffer_if.no_loc_wr = 1'b1;
                                end 
                                end
                                else begin 
                                    tlp2_no_cycles_comb = '0 ;
                                    buffer_if.data_in = '0; 
                                    buffer_if.no_loc_wr = 1'b0;
                                end 
                            end 
                                RX_ROUTER_CFG : begin 
                                buffer_if.wr_en = buffer_if.empty ? 1'b1 : 1'b0 ;                                    
                                // Interface with source itself
                                rx_router_grant = buffer_if.empty ? 1'b1 : 1'b0 ; 
                                buffer_if.no_loc_wr =buffer_if.empty ? 1'b1 : 1'b0 ; 
                                tlp2_no_cycles_comb = buffer_if.empty ? 1'b1 : 1'b0 ; 
                                // Interface with buffer 
                                if (buffer_if.empty) begin 
                                    if ((rx_router_comp_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (rx_router_comp_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                    buffer_if.data_in = {rx_router_comp_hdr, rx_router_data , 2'b11 , 1040'd0} ;
                                end 
                                    else begin 
                                    buffer_if.data_in = {rx_router_comp_hdr, 32'd0 , 2'b10 , 1040'd0} ;
                                end 
                                end
                                else begin 
                                    buffer_if.data_in = '0; 
                                    buffer_if.no_loc_wr = 1'b0;
                                end 
                            end 
						    	RX_ROUTER_ERR : begin 
                                buffer_if.wr_en = buffer_if.empty ? 1'b1 : 1'b0 ;                                    
								rx_router_grant = buffer_if.empty ? 1'b1 : 1'b0 ;
								// Interface with buffer 
								tlp2_no_cycles_comb = buffer_if.empty ? 1'b1 : 1'b0 ; // Start with Msg then Comp
								buffer_if.data_in = buffer_if.empty ? {rx_router_comp_hdr, 32'b0 , 2'b10,  {1040{1'b0}}} : '0 ;
								buffer_if.no_loc_wr = buffer_if.empty ? 1'b1 : 1'b0 ;
							end 
						    endcase 
				        // State Transition 
                            if (tlp2_no_cycles_comb == 'b0) begin   // AS long as not empty --> still into TLP2HDR
						    	next_state = TLP2_HDR ;  
                            end 
						    else if ((tlp2_no_cycles_comb > 1'b1)) begin  // Go to Data of TLP2
							next_state = TLP2_Data ; 
						    end 
						    else if (tlp2_no_cycles_comb == 1'b1 && (recorder_if.available  != SEQ_FIFO_DEPTH))  begin 
							next_state = TLP1_HDR ;
							if (recorder_if.available  == SEQ_FIFO_DEPTH - 1'b1 ) begin 
								recorder_if.rd_en = 1'b1 ;
								recorder_if.rd_mode = 2'b01 ; // read 1 location from sequence recorder
							end 
							else begin 
								recorder_if.rd_en = 1'b1 ;
								recorder_if.rd_mode = 2'b10 ; // read 2 locations from sequence recorder
							end                
						end 
						    else begin // in this case is the sequence buffer is empty.
                                next_state = ARBITER_IDLE ;  

						    end  
					end 
					TLP2_Data : begin 
                        buffer_if.wr_en = 1'b1 ;
						case(source_2) 
                            A2P_1 : begin 
                                //buffer_if.data_in = {axi_req_data} ;
									if ((axi_wrreq_hdr.FMT   == TLP_FMT_4DW_DATA)  && (axi_wrreq_hdr.TYP   == 'b0_0000) ) begin  // 64-bit address + Mem
                                        if (count_tlp2 == 1) begin 
                                            buffer_if.no_loc_wr = no_wr_loc (data_length , 2'b11, tlp2_no_cycles , 1 );
                                            case (buffer_if.no_loc_wr) 
                                                4'd1 : begin 
                                                    case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b100 - ((tlp2_no_cycles - 1'b1) * 4'd8)  ))  
                                                        2'b00 : begin 
                                                            buffer_if.data_in = {axi_req_data[4*DW -1 :0*DW], 2'b11, 1040'b0 } ;
                                                        end 
                                                        2'b01 : begin 
                                                            buffer_if.data_in = {axi_req_data[3*DW -1 :0*DW], 32'b0 , 2'b10, 1040'b0} ;
                                                        end 
                                                        2'b10 : begin 
                                                            buffer_if.data_in = {axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 1040'b0} ;
                                                        end 
                                                        2'b11 : begin 
                                                            buffer_if.data_in = {axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 1040'b0} ;
                                                        end 
                                                    endcase
                                                    end 
                                                4'd2 : begin 
                                                        case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b100 - ((tlp2_no_cycles - 1'b1) * 4'd8)  ))  
                                                            2'b00 : begin 
                                                                buffer_if.data_in = {axi_req_data[8*DW -1 :4*DW],2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 910'b0 } ;
                                                            end 
                                                            2'b01 : begin 
                                                                buffer_if.data_in = {axi_req_data[7*DW -1 :3*DW],2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0 , 2'b10, 910'b0} ;
                                                            end 
                                                            2'b10 : begin 
                                                                buffer_if.data_in = {axi_req_data[6*DW -1 :2*DW],2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 910'b0} ;
                                                            end 
                                                            2'b11 : begin 
                                                                buffer_if.data_in = {axi_req_data[5*DW -1 :1*DW],2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 910'b0} ;
                                                            end 
                                                        endcase
                                                        end 
                                                4'd3 : begin 
                                                        case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b100 - ((tlp2_no_cycles - 1'b1) * 4'd8)))  
                                                            2'b00 : begin 
                                                                buffer_if.data_in = {axi_req_data[12*DW -1 :8*DW],2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 780'b0} ;
                                                            end 
                                                            2'b01 : begin 
                                                                buffer_if.data_in = {axi_req_data[11*DW -1 :7*DW],2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 780'b0} ;
                                                            end 
                                                            2'b10 : begin 
                                                                buffer_if.data_in = {axi_req_data[10*DW -1 :6*DW],2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 780'b0} ;
                                                            end 
                                                            2'b11 : begin 
                                                                buffer_if.data_in = {axi_req_data[9*DW -1 :5*DW],2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 780'b0} ;
                                                            end 
                                                        endcase
                                                        end 
                                                4'd4 : begin 
                                                    case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b100 - ((tlp2_no_cycles - 1'b1) * 4'd8) ))  
                                                            2'b00 : begin 
                                                            buffer_if.data_in = {axi_req_data[16*DW -1 :12*DW],2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 650'b0} ;
                                                            end 
                                                            2'b01 : begin 
                                                                buffer_if.data_in = {axi_req_data[15*DW -1 :11*DW],2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0,  2'b10, 650'b0} ;
                                                            end 
                                                            2'b10 : begin 
                                                                buffer_if.data_in = {axi_req_data[14*DW -1 :10*DW],2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01, 650'b0} ;
                                                            end 
                                                            2'b11 : begin 
                                                                buffer_if.data_in = {axi_req_data[13*DW -1 :9*DW],2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0 ,  2'b00, 650'b0} ;
                                                            end 
                                                        endcase
                                                        end 
                                                4'd5 : begin 
                                                        case ((buffer_if.no_loc_wr * 3'd4) - (data_length+ 3'b100 - ((tlp2_no_cycles - 1'b1) * 4'd8) ))  
                                                            2'b00 : begin 
                                                                    buffer_if.data_in = {axi_req_data[20*DW -1 :16*DW],2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 520'b0} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_req_data[19*DW -1 :15*DW],2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 520'b0} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_req_data[18*DW -1 :14*DW],2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW],64'b0, 2'b01,  520'b0} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_req_data[17*DW -1 :13*DW],2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW],96'b0, 2'b00,  520'b0} ;
                                                                    end 
                                                        endcase
                                                        end 
                                                4'd6 : begin
                                                        case ((buffer_if.no_loc_wr * 3'd4) - (data_length+ 3'b100 - ((tlp2_no_cycles - 1'b1) * 4'd8) ))  
                                                            2'b00 : begin 
                                                                    buffer_if.data_in = {axi_req_data[24*DW -1 :20*DW],2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 390'b0} ;
                                                                    end 
                                                                    2'b01 : begin 
                                                                        buffer_if.data_in = {axi_req_data[23*DW -1 :19*DW],2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 390'b0} ;
                                                                    end 
                                                                    2'b10 : begin 
                                                                        buffer_if.data_in = {axi_req_data[22*DW -1 :18*DW],2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 390'b0} ;
                                                                    end 
                                                                    2'b11 : begin 
                                                                        buffer_if.data_in = {axi_req_data[21*DW -1 :17*DW],2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 390'b0} ;
                                                                    end 
                                                        endcase
                                                        end 
                                                4'd7 : begin 
                                                        case ((buffer_if.no_loc_wr * 3'd4) - (data_length+ 3'b100 - ((tlp2_no_cycles - 1'b1) * 4'd8) ))  
                                                            2'b00 : begin 
                                                                buffer_if.data_in = {axi_req_data[28*DW -1 :24*DW],2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11,260'b0} ;
                                                            end 
                                                            2'b01 : begin 
                                                                buffer_if.data_in = {axi_req_data[27*DW -1 :23*DW],2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10,260'b0} ;
                                                            end 
                                                            2'b10 : begin 
                                                                buffer_if.data_in = {axi_req_data[26*DW -1 :22*DW],2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0 , 2'b01,260'b0} ;
                                                            end 
                                                            2'b11 : begin 
                                                                buffer_if.data_in = {axi_req_data[25*DW -1 :21*DW],2'b11, axi_req_data[21*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0,  2'b00,260'b0} ;
                                                            end 
                                                        endcase
                                                        end 
                                                4'd8 : begin 
                                                    case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b100 - ((tlp2_no_cycles - 1'b1) * 4'd8) ))  
                                                        2'b00 : begin 
                                                                buffer_if.data_in = {axi_req_data[32*DW -1 :28*DW],2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11, 130'b0} ;
                                                                end 
                                                        2'b01 : begin 
                                                                    buffer_if.data_in = {axi_req_data[31*DW -1 :27*DW],2'b11, axi_req_data[27*DW -1 :23*DW], 2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11, axi_req_data[3*DW -1 :0*DW], 32'b0, 2'b10, 130'b0} ;
                                                                end 
                                                        2'b10 : begin 
                                                                    buffer_if.data_in = {axi_req_data[30*DW -1 :26*DW],2'b11, axi_req_data[26*DW -1 :22*DW], 2'b11, axi_req_data[22*DW -1 :18*DW], 2'b11, axi_req_data[18*DW -1 :14*DW], 2'b11, axi_req_data[14*DW -1 :10*DW], 2'b11, axi_req_data[10*DW -1 :6*DW], 2'b11, axi_req_data[6*DW -1 :2*DW], 2'b11, axi_req_data[2*DW -1 :0*DW], 64'b0, 2'b01, 130'b0} ;
                                                                end 
                                                        2'b11 : begin 
                                                                    buffer_if.data_in = {axi_req_data[29*DW -1 :25*DW],2'b11, axi_req_data[25*DW -1 :21*DW], 2'b11, axi_req_data[22*DW -1 :17*DW], 2'b11, axi_req_data[17*DW -1 :13*DW], 2'b11, axi_req_data[13*DW -1 :9*DW], 2'b11, axi_req_data[9*DW -1 :5*DW], 2'b11, axi_req_data[5*DW -1 :1*DW], 2'b11, axi_req_data[1*DW -1 :0*DW], 96'b0, 2'b00, 130'b0} ;
                                                                end 
                                                    endcase
                                                        end 
                                            endcase 
                                        end 
                                        else begin 
                                            buffer_if.no_loc_wr = no_wr_loc (data_length , 2'b10, tlp2_no_cycles , 1 );
                                            buffer_if.data_in = {axi_req_data[32*DW -1 :28*DW], 2'b11, axi_req_data[28*DW -1 :24*DW], 2'b11, axi_req_data[24*DW -1 :20*DW], 2'b11, axi_req_data[20*DW -1 :16*DW], 2'b11, axi_req_data[16*DW -1 :12*DW], 2'b11, axi_req_data[12*DW -1 :8*DW], 2'b11, axi_req_data[8*DW -1 :4*DW], 2'b11, axi_req_data[4*DW -1 :0*DW], 2'b11 , 128'b0 , 2'b00 } ;
                                        end
                                    end 
                                    else begin 
                                    // buffer_if.data_in = {registered_data, axi_req_data[AXI_MAX_NUM_BYTES * 8 - 1 :  3*DW]} ; 
                                    if (count_tlp2 == 1) begin 
                                        buffer_if.no_loc_wr = no_wr_loc (data_length , 2'b11, tlp2_no_cycles , 0 );
                                        case (buffer_if.no_loc_wr) 
                                            4'd1 : begin // here is posted request (write with data) and it will store 1 locations 
                                                buffer_if.data_in = {registered_data, axi_req_data[ 1*DW - 1 :  0*DW], 2'b11 , 1040'd0 } ;
                                            end 
                                            4'd2 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b011 - ((tlp2_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ 5*DW - 1  :  4*DW], 2'b11 , axi_req_data[ 4*DW - 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                        2'b01 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ 4*DW - 1  :  3*DW], 2'b11 , axi_req_data[ 3*DW - 1 :  0*DW], 32'b0 ,  2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                        2'b10 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ 3*DW - 1  :  2*DW], 2'b11 , axi_req_data[ 2*DW - 1 :  0*DW], 64'b0 ,  2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                        2'b11 : begin  
                                                        buffer_if.data_in = {registered_data, axi_req_data[ 2*DW - 1  :  1*DW], 2'b11 , axi_req_data[ 1*DW - 1 :  0*DW], 96'b0 ,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    endcase 
                                                end 
                                            4'd3 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b011 - ((tlp2_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 9 - 1 :  8*DW], 2'b11 , axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[4*DW - 1 :  0*DW],  2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 8 - 1 :  7*DW], 2'b11 , axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[3*DW - 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 7 - 1 :  6*DW], 2'b11 , axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[2*DW - 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 6 - 1 :  5*DW], 2'b11 , axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[1*DW - 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd4 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b011 - ((tlp2_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 13 - 1 :  12*DW], 2'b11 , axi_req_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW - 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 12 - 1 :  11*DW], 2'b11 , axi_req_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 11 - 1 :  10*DW], 2'b11 , axi_req_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 10 - 1 :  9*DW], 2'b11 , axi_req_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW - 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd5 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b011 - ((tlp2_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 17 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 16 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 15 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 14 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd6 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - (data_length+ 3'b011 - ((tlp2_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 21 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 20 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 19 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0, 2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 18 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd7 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b011 - ((tlp2_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 25 - 1 :  24*DW], 2'b11, axi_req_data[ DW * 24 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 24 - 1 :  23*DW], 2'b11, axi_req_data[ DW * 23 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0, 2'b10 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 23 - 1 :  22*DW], 2'b11, axi_req_data[ DW * 22 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0,  2'b01 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 22 - 1 :  21*DW], 2'b11, axi_req_data[ DW * 21 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0,  2'b00 ,128'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end
                                                endcase 
                                            end 
                                            4'd8 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b011 - ((tlp2_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 29 - 1 :  28*DW], 2'b11, axi_req_data[ DW * 28 - 1 :  24*DW], 2'b11, axi_req_data[ DW * 24 - 1 :  20*DW], 2'b11, axi_req_data[ DW * 20 - 1 :  16*DW], 2'b11 , axi_req_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_req_data[12*DW - 1 :  8*DW], 2'b11 ,axi_req_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_req_data[ 4*DW- 1 :  0*DW], 2'b11 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 28 - 1 :  27*DW], 2'b11, axi_req_data[ DW * 27 - 1 :  23*DW], 2'b11, axi_req_data[ DW * 23 - 1 :  19*DW], 2'b11, axi_req_data[ DW * 19 - 1 :  15*DW], 2'b11 , axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW- 1 :  0*DW], 32'b0 , 2'b10 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 27 - 1 :  26*DW], 2'b11, axi_req_data[ DW * 26 - 1 :  22*DW], 2'b11, axi_req_data[ DW * 22 - 1 :  18*DW], 2'b11, axi_req_data[ DW * 18 - 1 :  14*DW], 2'b11 , axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW- 1 :  0*DW], 64'b0 , 2'b01 ,128'b0, 2'b00 } ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ DW * 26 - 1 :  25*DW], 2'b11, axi_req_data[ DW * 25 - 1 :  21*DW], 2'b11, axi_req_data[ DW * 21 - 1 :  17*DW], 2'b11, axi_req_data[ DW * 17 - 1 :  13*DW], 2'b11 , axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,128'b0, 2'b00 } ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd9 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - (data_length + 3'b011 - ((tlp2_no_cycles - 2'd2) * 4'd8 + 2'd3 + 1'b1)  ))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[  32 * DW - 1 :  31*DW], 2'b11 , axi_req_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_req_data[27*DW - 1 :  23*DW], 2'b11 ,axi_req_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_req_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_req_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_req_data[11*DW - 1 :  7*DW], 2'b11 ,axi_req_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_req_data[ 3*DW - 1 :  0 *DW] , 32'b0,2'b10} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[ 31 * DW - 1 :  30*DW], 2'b11 , axi_req_data[ 30*DW - 1 :  26*DW], 2'b11 ,axi_req_data[26*DW - 1 :  22*DW], 2'b11 ,axi_req_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_req_data[ 18*DW- 1 :  14*DW], 2'b11 ,axi_req_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_req_data[10*DW - 1 :  6*DW], 2'b11 ,axi_req_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_req_data[ 2*DW - 1 :  0 *DW] , 64'b0,2'b01} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {registered_data, axi_req_data[  30 * DW - 1 :  29*DW], 2'b11 , axi_req_data[ 29*DW - 1 :  25*DW], 2'b11 ,axi_req_data[25*DW - 1 :  21*DW], 2'b11 ,axi_req_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_req_data[ 17*DW- 1 :  13*DW], 2'b11 ,axi_req_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_req_data[9*DW - 1 :  5*DW], 2'b11 ,axi_req_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_req_data[ 1*DW - 1 :  0 *DW] , 96'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin // Can't happen
                                                        buffer_if.data_in = '0 ;
                                                    end 
                                                endcase 
                                            end 
                                        endcase 
                                    end 
                                    else begin 
                                        data_comb = axi_req_data [3* DW - 1 : 0] ; 
                                        buffer_if.no_loc_wr = no_wr_loc (data_length, 2'b10, tlp2_no_cycles , 0 );
                                        buffer_if.data_in = {registered_data , axi_req_data[32*DW -1 :31*DW], 2'b11, axi_req_data[31*DW -1 :27*DW], 2'b11, axi_req_data[27*DW -1 :23*DW], 2'b11, axi_req_data[23*DW -1 :19*DW], 2'b11, axi_req_data[19*DW -1 :15*DW], 2'b11, axi_req_data[15*DW -1 :11*DW], 2'b11, axi_req_data[11*DW -1 :7*DW], 2'b11, axi_req_data[7*DW -1 :3*DW], 2'b11 , 128'b0 , 2'b00 } ;
                                    end
                                end  
                                end
                            MASTER : begin 
                                if ((axi_master_hdr[3*DW - 1 : 3*DW - 3] == 3'b010) && (axi_master_hdr[3*DW - 4 : 3*DW - 8] == 5'b0_1010) ) begin  // COMPD
                                    if (count_tlp2 == 1) begin 
                                        buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b11, tlp2_no_cycles , 0 );
                                        case (buffer_if.no_loc_wr) 
                                            4'd1 : begin // here is posted request (write with data) and it will store 1 locations 
                                                buffer_if.data_in = {registered_data, axi_comp_data[ 1 * DW - 1 : 0], 2'b11 , 1040'd0} ;
                                            end 
                                            4'd2 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp2_no_cycles - 1'd1 ))))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 5 * DW - 1 :  4*DW], 2'b11 , axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 4 * DW - 1 :  3*DW], 2'b11 , axi_comp_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 3 * DW - 1 :  2*DW], 2'b11 , axi_comp_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 2 * DW - 1 :  1*DW], 2'b11 , axi_comp_data[ 1*DW - 1 :  0*DW] , 96'b0, 2'b00 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd3 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp2_no_cycles - 1'd1 ))))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 9 * DW - 1 :  8*DW], 2'b11 , axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 8 * DW - 1 :  7*DW], 2'b11 , axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[3*DW - 1 :  0*DW], 32'b0 , 2'b10 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 7 * DW - 1 :  6*DW], 2'b11 , axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 6 * DW - 1 :  5*DW], 2'b11 , axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[1*DW - 1 :  0*DW], 96'b0 , 2'b00 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd4 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp2_no_cycles - 1'd1 ))))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 13 * DW - 1 :  12*DW], 2'b11 , axi_comp_data[ 12*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 12 * DW - 1 :  11*DW], 2'b11 , axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'b0, 2'b10 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 11 * DW - 1 :  10*DW], 2'b11 , axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'b0, 2'b01 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {registered_data,axi_comp_data[ 10 * DW - 1 :  9*DW], 2'b11 , axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'b0, 2'b00 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd5 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp2_no_cycles - 1'd1 ))))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 17 * DW - 1 :  16*DW], 2'b11 , axi_comp_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW- 1 :  0*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {registered_data,axi_comp_data[ 16 * DW - 1 :  15*DW], 2'b11 , axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW- 1 :  0*DW], 32'b0,  2'b10 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 15 * DW - 1 :  14*DW], 2'b11 , axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW- 1 :  0*DW], 64'b0,  2'b01 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {registered_data,axi_comp_data[ 14 * DW - 1 :  13*DW], 2'b11 , axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW- 1 :  0*DW], 96'b0, 2'b00 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd6 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp2_no_cycles - 1'd1 ))))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 21 * DW - 1 :  20*DW], 2'b11 , axi_comp_data[ 20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW- 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {registered_data,axi_comp_data[ 20 * DW - 1 :  19*DW], 2'b11 , axi_comp_data[ 19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW- 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'B0,  2'b10 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {registered_data,axi_comp_data[ 19 * DW - 1 :  18*DW], 2'b11 , axi_comp_data[ 18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW- 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'B0, 2'b01 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {registered_data,axi_comp_data[ 18 * DW - 1 :  17*DW], 2'b11 , axi_comp_data[ 17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW- 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'B0, 2'b00 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b00 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd7 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp2_no_cycles - 1'd1 ))))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[25* DW - 1 :  24*DW], 2'b11 , axi_comp_data[ 24*DW - 1 :  20*DW], 2'b11 ,axi_comp_data[20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[ 16*DW - 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW- 1 :  8*DW], 2'b11 ,axi_comp_data[ 8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[4*DW - 1 :  0*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[24* DW - 1 :  23*DW], 2'b11 , axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW- 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[3*DW - 1 :  0*DW], 32'B0 ,  2'b10 , 128'b0 , 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[23* DW - 1 :  22*DW], 2'b11 , axi_comp_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW- 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[2*DW - 1 :  0*DW], 64'B0 , 2'b01 ,128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {registered_data,axi_comp_data[22* DW - 1 :  21*DW], 2'b11 , axi_comp_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW- 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[1*DW - 1 :  0*DW], 96'B0 , 2'b00 , 128'b0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd8 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp2_no_cycles - 1'd1 ))))  
                                                    2'b00 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[29 * DW - 1 :  28*DW], 2'b11 , axi_comp_data[ 28*DW - 1 :  24*DW], 2'b11 ,axi_comp_data[24*DW - 1 :  20*DW], 2'b11 ,axi_comp_data[ 20*DW - 1 :  16*DW], 2'b11 ,axi_comp_data[ 16*DW- 1 :  12*DW], 2'b11 ,axi_comp_data[ 12*DW - 1 :  8*DW], 2'b11 ,axi_comp_data[8*DW - 1 :  4*DW], 2'b11 ,axi_comp_data[ 4*DW - 1 :  0*DW], 2'b11 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[28 * DW - 1 :  27*DW], 2'b11 , axi_comp_data[ 27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW - 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW- 1 :  11*DW], 2'b11 ,axi_comp_data[ 11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[7*DW - 1 :  3*DW], 2'b11 ,axi_comp_data[ 3*DW - 1 :  0*DW], 32'B0, 2'b10 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[27 * DW - 1 :  26*DW], 2'b11 , axi_comp_data[ 26*DW - 1 :  22*DW], 2'b11 ,axi_comp_data[22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[ 18*DW - 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW- 1 :  10*DW], 2'b11 ,axi_comp_data[ 10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[6*DW - 1 :  2*DW], 2'b11 ,axi_comp_data[ 2*DW - 1 :  0*DW], 64'B0, 2'b01 , 128'b0,2'b00} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[26 * DW - 1 :  25*DW], 2'b11 , axi_comp_data[ 25*DW - 1 :  21*DW], 2'b11 ,axi_comp_data[21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[ 17*DW - 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW- 1 :  9*DW], 2'b11 ,axi_comp_data[ 9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[5*DW - 1 :  1*DW], 2'b11 ,axi_comp_data[ 1*DW - 1 :  0*DW], 96'B0, 2'b00 , 128'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                            4'd9 : begin 
                                                case ((buffer_if.no_loc_wr * 3'd4) - ((axi_master_hdr[ 2*DW + 9 : 2*DW] + 2'b11) - (4'd8 * 3'd4 * (tlp2_no_cycles - 1'd1 ))))  
                                                    2'b00 : begin // Can't happen
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b11} ;
                                                    end 
                                                    2'b01 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , axi_comp_data[ 3*DW - 1 :  0*DW] ,  32'b0,2'b10} ;
                                                    end 
                                                    2'b10 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 31*DW - 1 :  30*DW], 2'b11 , axi_comp_data[ 30*DW - 1 :  26*DW], 2'b11 ,axi_comp_data[26*DW - 1 :  22*DW], 2'b11 ,axi_comp_data[ 22*DW - 1 :  18*DW], 2'b11 ,axi_comp_data[ 18*DW- 1 :  14*DW], 2'b11 ,axi_comp_data[ 14*DW - 1 :  10*DW], 2'b11 ,axi_comp_data[10*DW - 1 :  6*DW], 2'b11 ,axi_comp_data[ 6*DW - 1 :  2*DW], 2'b11 , axi_comp_data[ 2*DW - 1 :  0*DW] ,  64'b0,2'b01} ;
                                                    end 
                                                    2'b11 : begin 
                                                        buffer_if.data_in = {registered_data, axi_comp_data[ 30*DW - 1:  29*DW], 2'b11 , axi_comp_data[ 29*DW - 1 :  25*DW], 2'b11 ,axi_comp_data[25*DW - 1 :  21*DW], 2'b11 ,axi_comp_data[ 21*DW - 1 :  17*DW], 2'b11 ,axi_comp_data[ 17*DW- 1 :  13*DW], 2'b11 ,axi_comp_data[ 13*DW - 1 :  9*DW], 2'b11 ,axi_comp_data[9*DW - 1 :  5*DW], 2'b11 ,axi_comp_data[ 5*DW - 1 :  1*DW], 2'b11 , axi_comp_data[ 1*DW - 1 :  0*DW] ,  96'b0,2'b00} ;
                                                    end 
                                                endcase 
                                            end 
                                        endcase 
                                    end 
                                    else begin 
                                        buffer_if.no_loc_wr = no_wr_loc (axi_master_hdr[ 2*DW + 9 : 2*DW] , 2'b10, tlp2_no_cycles , 1'b0 );
                                        buffer_if.data_in = {registered_data, axi_comp_data[ AXI_MAX_NUM_BYTES * 8 - 1 :  31*DW], 2'b11 , axi_comp_data[ 31*DW - 1 :  27*DW], 2'b11 ,axi_comp_data[27*DW - 1 :  23*DW], 2'b11 ,axi_comp_data[ 23*DW - 1 :  19*DW], 2'b11 ,axi_comp_data[ 19*DW- 1 :  15*DW], 2'b11 ,axi_comp_data[ 15*DW - 1 :  11*DW], 2'b11 ,axi_comp_data[11*DW - 1 :  7*DW], 2'b11 ,axi_comp_data[ 7*DW - 1 :  3*DW], 2'b11 , 128'b0,2'b00} ;
                                    end 
                                end 
                                    else begin // Comp
                                    buffer_if.data_in = {axi_master_hdr, 32'd0 , 2'b10 , 1040'd0} ; 
                                    buffer_if.no_loc_wr = 1'b1;
                                end 
                                end	
						endcase 
						// State Transition 
						    if ((count_tlp2 > 1'b1) ) begin  // Keep going on Data of TLP2
							next_state = TLP2_Data ;
						end 
						    else if ((count_tlp2 == 1'b1) &&(recorder_if.available  != SEQ_FIFO_DEPTH)) begin  
							next_state = TLP1_HDR ;
                            if (recorder_if.available  == SEQ_FIFO_DEPTH - 1'b1 ) begin 
								recorder_if.rd_en = 1'b1 ;
								recorder_if.rd_mode = 2'b01 ; // read 1 location from sequence recorder
							end 
							else begin 
								recorder_if.rd_en = 1'b1 ;
								recorder_if.rd_mode = 2'b10 ; // read 2 locations from sequence recorder
							end
						end 
						    else begin
							next_state = ARBITER_IDLE ; 
						end  
					end		
				endcase
    end : Next_State_and_Output_Encoder
endmodule

