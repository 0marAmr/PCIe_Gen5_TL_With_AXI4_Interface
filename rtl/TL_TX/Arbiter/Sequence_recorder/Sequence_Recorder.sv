/* Module Name	: Sequence_Recorder         */
/* Written By	: Mohamed Khaled Alahmady                    */
/* Date			: 12-04-2024		        */
/* Version		: V_2			            */
/* Updates		: -			                */
/* Dependencies	: -				            */
/* Used			: -			                */
import axi_slave_package::*; 
import Tx_Arbiter_Package::*;

module Sequence_Recorder(
    input bit clk,
    input bit arst,
    Tx_Arbiter_Sequence_Recorder.SEQUENCE_RECORDER_TX_ARBITER _if_tx_arbiter,
    Arbiter_FSM_Sequence_Recorder.SEQUENCE_RECORDER_ARBITER_FSM _if_arbiter_fsm
);


/* Parameters */
localparam SEQ_ADDR_WIDTH      = $clog2(SEQ_FIFO_DEPTH);

/* Useful Functions */
// Description: Calculate Available Locations in Sequence Recorder based on wr_mode and rd_mode
function void Available_Check(input logic [SEQ_ADDR_WIDTH : 0] available, input logic [1:0] wr_mode, input logic [1:0] rd_mode);
    // 1:18 >> need kam location wr : (Max - need kam location rd)
    if ((_if_arbiter_fsm.available >= wr_mode) && (_if_arbiter_fsm.available <= (SEQ_FIFO_DEPTH - rd_mode))) begin
        if (wr_mode > rd_mode) begin
            // wr_mode = 3
            // rd_mode = 2    
            _if_arbiter_fsm.available  <= _if_arbiter_fsm.available - (wr_mode - rd_mode);        
        end
        else if (wr_mode < rd_mode) begin
            // wr_mode = 2
            // rd_mode = 3    
            _if_arbiter_fsm.available  <= _if_arbiter_fsm.available + (rd_mode - wr_mode);                    
        end
        else begin
            _if_arbiter_fsm.available  <= _if_arbiter_fsm.available;        
        end
    end
    // write only can be done
    // 1:19 >> need kam location wr : MAX
    else if ((_if_arbiter_fsm.available <= SEQ_FIFO_DEPTH)  && (_if_arbiter_fsm.available >= wr_mode)) begin 
        _if_arbiter_fsm.available  <= _if_arbiter_fsm.available - wr_mode;        
    end    
    // read only can be done
    // 0:18 >> 0:(MAX - need kam location rd)
    else if ((_if_arbiter_fsm.available <= (SEQ_FIFO_DEPTH - rd_mode))  && (_if_arbiter_fsm.available >= 0)) begin 
        _if_arbiter_fsm.available  <= _if_arbiter_fsm.available + rd_mode;                                                                        
    end    
endfunction


/* Internal Signals */
Tx_Arbiter_Sources_t MEM [SEQ_FIFO_DEPTH - 1  : 0];
logic [SEQ_ADDR_WIDTH - 1  : 0]    wr_ptr;
logic [SEQ_ADDR_WIDTH - 1 :  0]    rd_ptr;     
logic [SEQ_ADDR_WIDTH - 1 :  0]    wr_ptr_temp; // used to window only 2bits of address to access memory


/* Assign Statements */
assign wr_ptr_temp = wr_ptr + _if_tx_arbiter.wr_mode_tx_arbiter;

// assign _if_arbiter_fsm.full     = ((wr_ptr + 1) == rd_ptr) ? TRUE : FALSE; //({~wr_ptr[SEQ_ADDR_WIDTH], wr_ptr[SEQ_ADDR_WIDTH - 1 : 0]} == rd_ptr) ? TRUE : FALSE;
// assign _if_arbiter_fsm.empty    = (wr_ptr == rd_ptr) ? TRUE : FALSE;

/* Always Blocks */
always_ff @(posedge clk or negedge arst) begin : Write_Read_Operation
    if (!arst) begin
        rd_ptr                          <= '0;
        wr_ptr                          <= '0;
        _if_arbiter_fsm.rd_data_1       <= NO_SOURCE;
        _if_arbiter_fsm.rd_data_2       <= NO_SOURCE;
        _if_arbiter_fsm.available       <= SEQ_FIFO_DEPTH;
        for (int i = 0 ; i <= SEQ_FIFO_DEPTH - 1 ; i ++ ) begin 
            MEM[i] <= NO_SOURCE; 
        end 
    end
    else begin
        case ({_if_tx_arbiter.wr_en_tx_arbiter, _if_arbiter_fsm.wr_en, _if_arbiter_fsm.rd_en})
            // done
            3'b000: begin
                // do nothing
            end
            // done
            3'b001: begin
                case (_if_arbiter_fsm.rd_mode)
                2'b01 : begin
                        if ((_if_arbiter_fsm.available < SEQ_FIFO_DEPTH)) begin
                            _if_arbiter_fsm.rd_data_1               <= MEM[rd_ptr];
                            MEM[rd_ptr]                             <= NO_SOURCE;
                            _if_arbiter_fsm.rd_data_2               <= NO_SOURCE;

                        end
                    end
                2'b10 : begin
                    if ((_if_arbiter_fsm.available < (SEQ_FIFO_DEPTH - 1))) begin
                        _if_arbiter_fsm.rd_data_1               <= MEM[rd_ptr];
                        _if_arbiter_fsm.rd_data_2               <= MEM[rd_ptr + 3'b001];  
                        MEM[rd_ptr]                             <= NO_SOURCE; 
                        MEM[rd_ptr + 3'b001]                             <= NO_SOURCE; 
                    end
                    end                
                default: begin
                end
                endcase    
                rd_ptr                                  <=  rd_ptr + _if_arbiter_fsm.rd_mode;
                Available_Check(_if_arbiter_fsm.available, 2'b00, _if_arbiter_fsm.rd_mode);
            end
            // done
            3'b010: begin
                case (_if_arbiter_fsm.wr_mode)
                2'b01 : begin
                        if ((_if_arbiter_fsm.available >= 1)) begin
                            MEM[wr_ptr]             <= _if_arbiter_fsm.wr_data_1;
                        end
                    end
                2'b10 : begin
                        if ((_if_arbiter_fsm.available >= 2)) begin
                            MEM[wr_ptr]         <= _if_arbiter_fsm.wr_data_1;                         
                            MEM[wr_ptr + 3'b001]     <= _if_arbiter_fsm.wr_data_2;  
                        end
                    end                
                default: begin
                end
                endcase
                wr_ptr                  <= wr_ptr + _if_arbiter_fsm.wr_mode;
                Available_Check(_if_arbiter_fsm.available, _if_arbiter_fsm.wr_mode, 2'b00);
            end
            // done
            3'b011: begin
                // write
                case (_if_arbiter_fsm.wr_mode)
                2'b01 : begin
                        if ((_if_arbiter_fsm.available >= 1)) begin
                            MEM[wr_ptr]             <= _if_arbiter_fsm.wr_data_1;
                        end
                    end
                2'b10 : begin
                        if ((_if_arbiter_fsm.available >= 2)) begin
                            MEM[wr_ptr]         <= _if_arbiter_fsm.wr_data_1;                         
                            MEM[wr_ptr + 3'b001]     <= _if_arbiter_fsm.wr_data_2;  
                        end
                    end                
                default: begin
                end
                endcase
                wr_ptr                  <= wr_ptr + _if_arbiter_fsm.wr_mode;
                // read
                case (_if_arbiter_fsm.rd_mode)
                2'b01 : begin
                        if ((_if_arbiter_fsm.available < SEQ_FIFO_DEPTH)) begin
                            _if_arbiter_fsm.rd_data_1               <= MEM[rd_ptr];
                            MEM[rd_ptr]                             <= NO_SOURCE;
                            _if_arbiter_fsm.rd_data_2               <= NO_SOURCE;

                        end
                    end
                2'b10 : begin
                    if ((_if_arbiter_fsm.available < (SEQ_FIFO_DEPTH - 1))) begin
                            _if_arbiter_fsm.rd_data_1               <= MEM[rd_ptr];
                            _if_arbiter_fsm.rd_data_2               <= MEM[rd_ptr + 3'b001];  
                            MEM[rd_ptr]                             <= NO_SOURCE; 
                            MEM[rd_ptr + 3'b001]                             <= NO_SOURCE; 
                    end
                    end                
                default: begin
                end
                endcase    
                rd_ptr                                  <=  rd_ptr + _if_arbiter_fsm.rd_mode;
                // update available
                Available_Check(_if_arbiter_fsm.available, _if_arbiter_fsm.wr_mode, _if_arbiter_fsm.rd_mode);
            end
            // done
            3'b100: begin
                case (_if_tx_arbiter.wr_mode_tx_arbiter)
                3'b001 : begin
                        if ((_if_arbiter_fsm.available >= 1)) begin
                            MEM[wr_ptr]             <= _if_tx_arbiter.wr_data_1_tx_arbiter;
                        end
                    end
                3'b010 : begin
                        if ((_if_arbiter_fsm.available >= 2)) begin
                            MEM[wr_ptr]         <= _if_tx_arbiter.wr_data_1_tx_arbiter;                         
                            MEM[wr_ptr + 3'b001]     <= _if_tx_arbiter.wr_data_2_tx_arbiter;  
                        end
                    end                
                3'b011 : begin
                        if ((_if_arbiter_fsm.available >= 3)) begin
                            MEM[wr_ptr]         <= _if_tx_arbiter.wr_data_1_tx_arbiter;                         
                            MEM[wr_ptr + 3'b001]     <= _if_tx_arbiter.wr_data_2_tx_arbiter;  
                            MEM[wr_ptr + 3'b010]     <= _if_tx_arbiter.wr_data_3_tx_arbiter;  
                        end
                    end
                3'b100 : begin
                        if ((_if_arbiter_fsm.available >= 4)) begin
                                MEM[wr_ptr]         <= _if_tx_arbiter.wr_data_1_tx_arbiter;                         
                                MEM[wr_ptr + 3'b001]     <= _if_tx_arbiter.wr_data_2_tx_arbiter;  
                                MEM[wr_ptr + 3'b010]     <= _if_tx_arbiter.wr_data_3_tx_arbiter;  
                                MEM[wr_ptr + 3'b011]     <= _if_tx_arbiter.wr_data_4_tx_arbiter;  
                        end
                    end
                default: begin
                end
                endcase
                wr_ptr                  <= wr_ptr + _if_tx_arbiter.wr_mode_tx_arbiter;
                Available_Check(_if_arbiter_fsm.available, _if_tx_arbiter.wr_mode_tx_arbiter, 2'b00);
            end
            // done
            3'b101: begin
                // write
                case (_if_tx_arbiter.wr_mode_tx_arbiter)
                3'b001 : begin
                        if ((_if_arbiter_fsm.available >= 1)) begin
                            MEM[wr_ptr]             <= _if_tx_arbiter.wr_data_1_tx_arbiter;
                        end
                    end
                3'b010 : begin
                        if ((_if_arbiter_fsm.available >= 2)) begin
                            MEM[wr_ptr]         <= _if_tx_arbiter.wr_data_1_tx_arbiter;                         
                            MEM[wr_ptr + 3'b001]     <= _if_tx_arbiter.wr_data_2_tx_arbiter;  
                        end
                    end                
                3'b011 : begin
                        if ((_if_arbiter_fsm.available >= 3)) begin
                            MEM[wr_ptr]         <= _if_tx_arbiter.wr_data_1_tx_arbiter;                         
                            MEM[wr_ptr + 3'b001]     <= _if_tx_arbiter.wr_data_2_tx_arbiter;  
                            MEM[wr_ptr + 3'b010]     <= _if_tx_arbiter.wr_data_3_tx_arbiter;  
                        end
                    end
                3'b100 : begin
                        if ((_if_arbiter_fsm.available >= 4)) begin
                                MEM[wr_ptr]         <= _if_tx_arbiter.wr_data_1_tx_arbiter;                         
                                MEM[wr_ptr + 3'b001]     <= _if_tx_arbiter.wr_data_2_tx_arbiter;  
                                MEM[wr_ptr + 3'b010]     <= _if_tx_arbiter.wr_data_3_tx_arbiter;  
                                MEM[wr_ptr + 3'b011]     <= _if_tx_arbiter.wr_data_4_tx_arbiter;  
                        end
                    end
                default: begin
                end
                endcase
                wr_ptr                  <= wr_ptr + _if_tx_arbiter.wr_mode_tx_arbiter;
                // read
                case (_if_arbiter_fsm.rd_mode)
                2'b01 : begin
                        if ((_if_arbiter_fsm.available < SEQ_FIFO_DEPTH)) begin
                            _if_arbiter_fsm.rd_data_1               <= MEM[rd_ptr];
                            MEM[rd_ptr]                             <= NO_SOURCE;
                            _if_arbiter_fsm.rd_data_2               <= NO_SOURCE;

                        end
                    end
                2'b10 : begin
                    if ((_if_arbiter_fsm.available < (SEQ_FIFO_DEPTH - 1))) begin
                            _if_arbiter_fsm.rd_data_1               <= MEM[rd_ptr];
                            _if_arbiter_fsm.rd_data_2               <= MEM[rd_ptr + 3'b001];  
                            MEM[rd_ptr]                             <= NO_SOURCE; 
                            MEM[rd_ptr + 3'b001]                             <= NO_SOURCE; 
                    end
                    end                
                default: begin
                end
                endcase    
                rd_ptr                                  <=  rd_ptr + _if_arbiter_fsm.rd_mode;
                // update available
                Available_Check(_if_arbiter_fsm.available, _if_tx_arbiter.wr_mode_tx_arbiter, _if_arbiter_fsm.rd_mode);
            end
            3'b110: begin
                // tx arbiter (prioty newcoming TLPs)
                case (_if_tx_arbiter.wr_mode_tx_arbiter)
                3'b001 : begin
                        if ((_if_arbiter_fsm.available >= (_if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode))) begin
                            MEM[wr_ptr]             <= _if_tx_arbiter.wr_data_1_tx_arbiter;
                        end
                    end
                3'b010 : begin
                        if ((_if_arbiter_fsm.available >= (_if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode))) begin
                            MEM[wr_ptr]         <= _if_tx_arbiter.wr_data_1_tx_arbiter;                         
                            MEM[wr_ptr + 3'b001]     <= _if_tx_arbiter.wr_data_2_tx_arbiter;  
                        end
                    end                
                3'b011 : begin
                        if ((_if_arbiter_fsm.available >= (_if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode))) begin
                            MEM[wr_ptr]         <= _if_tx_arbiter.wr_data_1_tx_arbiter;                         
                            MEM[wr_ptr + 3'b001]     <= _if_tx_arbiter.wr_data_2_tx_arbiter;  
                            MEM[wr_ptr + 3'b010]     <= _if_tx_arbiter.wr_data_3_tx_arbiter;  
                        end
                    end
                3'b100 : begin
                        if ((_if_arbiter_fsm.available >= (_if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode))) begin
                                MEM[wr_ptr]         <= _if_tx_arbiter.wr_data_1_tx_arbiter;                         
                                MEM[wr_ptr + 3'b001]     <= _if_tx_arbiter.wr_data_2_tx_arbiter;  
                                MEM[wr_ptr + 3'b010]     <= _if_tx_arbiter.wr_data_3_tx_arbiter;  
                                MEM[wr_ptr + 3'b011]     <= _if_tx_arbiter.wr_data_4_tx_arbiter;  
                        end
                    end
                default: begin
                end
                endcase
                // arbiter fsm
                case (_if_arbiter_fsm.wr_mode)
                2'b01 : begin
                        if ((_if_arbiter_fsm.available >= (_if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode))) begin
                            MEM[wr_ptr_temp]             <= _if_arbiter_fsm.wr_data_1;
                        end
                    end
                2'b10 : begin
                        if ((_if_arbiter_fsm.available >= (_if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode))) begin
                            MEM[wr_ptr_temp]            <= _if_arbiter_fsm.wr_data_1;                         
                            MEM[wr_ptr_temp + 3'b001]    <= _if_arbiter_fsm.wr_data_2;  
                        end
                    end                
                default: begin
                end
                endcase

                wr_ptr                  <= wr_ptr + _if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode;
                Available_Check(_if_arbiter_fsm.available, _if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode, 2'b00);
            end
            3'b111: begin
                // tx arbiter (prioty newcoming TLPs)
                case (_if_tx_arbiter.wr_mode_tx_arbiter)
                3'b001 : begin
                        if ((_if_arbiter_fsm.available >= (_if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode))) begin
                            MEM[wr_ptr]             <= _if_tx_arbiter.wr_data_1_tx_arbiter;
                        end
                    end
                3'b010 : begin
                        if ((_if_arbiter_fsm.available >= (_if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode))) begin
                            MEM[wr_ptr]         <= _if_tx_arbiter.wr_data_1_tx_arbiter;                         
                            MEM[wr_ptr + 3'b001]     <= _if_tx_arbiter.wr_data_2_tx_arbiter;  
                        end
                    end                
                3'b011 : begin
                        if ((_if_arbiter_fsm.available >= (_if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode))) begin
                            MEM[wr_ptr]         <= _if_tx_arbiter.wr_data_1_tx_arbiter;                         
                            MEM[wr_ptr + 3'b001]     <= _if_tx_arbiter.wr_data_2_tx_arbiter;  
                            MEM[wr_ptr + 3'b010]     <= _if_tx_arbiter.wr_data_3_tx_arbiter;  
                        end
                    end
                3'b100 : begin
                        if ((_if_arbiter_fsm.available >= (_if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode))) begin
                                MEM[wr_ptr]         <= _if_tx_arbiter.wr_data_1_tx_arbiter;                         
                                MEM[wr_ptr + 3'b001]     <= _if_tx_arbiter.wr_data_2_tx_arbiter;  
                                MEM[wr_ptr + 3'b010]     <= _if_tx_arbiter.wr_data_3_tx_arbiter;  
                                MEM[wr_ptr + 3'b011]     <= _if_tx_arbiter.wr_data_4_tx_arbiter;  
                        end
                    end
                default: begin
                end
                endcase

                // arbiter fsm
                case (_if_arbiter_fsm.wr_mode)
                2'b01 : begin
                        if ((_if_arbiter_fsm.available >= (_if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode))) begin
                            MEM[wr_ptr_temp]             <= _if_arbiter_fsm.wr_data_1;
                        end
                    end
                2'b10 : begin
                        if ((_if_arbiter_fsm.available >= (_if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode))) begin
                            MEM[wr_ptr_temp]            <= _if_arbiter_fsm.wr_data_1;                         
                            MEM[wr_ptr_temp + 3'b001]    <= _if_arbiter_fsm.wr_data_2;  
                        end
                    end                
                default: begin
                end
                endcase

                // arbiter fsm read
                case (_if_arbiter_fsm.rd_mode)
                2'b01 : begin
                        if ((_if_arbiter_fsm.available < SEQ_FIFO_DEPTH)) begin
                            _if_arbiter_fsm.rd_data_1               <= MEM[rd_ptr];
                            MEM[rd_ptr]                             <= NO_SOURCE;
                            _if_arbiter_fsm.rd_data_2               <= NO_SOURCE;

                        end
                    end
                2'b10 : begin
                    if ((_if_arbiter_fsm.available < (SEQ_FIFO_DEPTH - 1'b1))) begin
                        _if_arbiter_fsm.rd_data_1               <= MEM[rd_ptr];
                        _if_arbiter_fsm.rd_data_2               <= MEM[rd_ptr + 3'b001];  
                        MEM[rd_ptr]                             <= NO_SOURCE; 
                        MEM[rd_ptr + 3'b001]                     <= NO_SOURCE; 
                    end
                    end                
                default: begin
                end
                endcase    

                rd_ptr                  <=  rd_ptr + _if_arbiter_fsm.rd_mode;
                wr_ptr                  <= wr_ptr + _if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode;
                Available_Check(_if_arbiter_fsm.available, _if_tx_arbiter.wr_mode_tx_arbiter + _if_arbiter_fsm.wr_mode, _if_arbiter_fsm.rd_mode);
            end
        endcase
    end
end : Write_Read_Operation

// Note: need to handle case when FIFO empty and wr_en, rd_en (write then read)
// Note: need to handle case when FIFO full and wr_en, rd_en (read then write) (Done)

/* Instantiations */

endmodule: Sequence_Recorder
/*********** END_OF_FILE ***********/
