/* Module Name	: tlp_frag.sv               */
/* Written By	: Mohamed Aladdin           */
/* Date			: 30-04-2024		        */
/* Version		: V_1			            */
/* Updates		: -			                */
/* Dependencies	: -				            */
/* Used			: 			                */
module Sequence_Recorder #(
    parameter   DATA_WIDTH      = 4 * 4 * 8,
                FIFO_DEPTH      = 257,
                ADDR_WIDTH      = $clog2(FIFO_DEPTH)
)(
    input bit clk,
    input bit arst,
    buffer_frag_interface.buffer _if,
    output logic Buffer_Ready , // it is 1 only before writing anything first, Otherwise it is always 0
    output logic start_fragment // it is an indicator that the TLP stored was gone to DLL and Arbiter can store the next one 
);

/* Parameters */
import data_frag_package::*;

/* Useful Functions */
// Description: Calculate Available Locations in Sequence Recorder based on wr_mode and rd_mode
function void Available_Check(input logic [ADDR_WIDTH : 0] available, input logic [2:0] wr_mode, input logic [1:0] rd_mode);
    // 1:18 >> need kam location wr : (Max - need kam location rd)
    if ((_if.available >= wr_mode) && (_if.available <= (FIFO_DEPTH - rd_mode)) && (!_if.full)) begin
        if (wr_mode > rd_mode) begin
            // wr_mode = 3
            // rd_mode = 2    
            _if.available  <= _if.available - (wr_mode - rd_mode);        
        end
        else if (wr_mode < rd_mode) begin
            // wr_mode = 2
            // rd_mode = 3    
            _if.available  <= _if.available + (rd_mode - wr_mode);                    
        end
        else begin
            _if.available  <= _if.available;        
        end
    end
    // write only can be done
    // 1:19 >> need kam location wr : MAX
    else if ((_if.available <= FIFO_DEPTH)  && (_if.available >= wr_mode)) begin 
        _if.available  <= _if.available - wr_mode;        
    end    
    // read only can be done
    // 0:18 >> 0:(MAX - need kam location rd)
    else if ((_if.available <= (FIFO_DEPTH - rd_mode))  && (_if.available >= 0)) begin 
        _if.available  <= _if.available + rd_mode;                                                                        
    end    
endfunction


/* Internal Signals */
Tx_Arbiter_Sources_t MEM [FIFO_DEPTH - 1  : 0];
logic [ADDR_WIDTH   : 0]    wr_ptr;
logic [ADDR_WIDTH  :  0]    rd_ptr;     

/* Assign Statements */
assign _if.full     = ({~wr_ptr[ADDR_WIDTH], wr_ptr[ADDR_WIDTH - 1 : 0]} == rd_ptr) ? TRUE : FALSE;
assign _if.empty    = (wr_ptr == rd_ptr) ? TRUE : FALSE;

/* Always Blocks */
always_ff @(posedge clk or negedge arst) begin : Write_Read_Operation
    if (!arst) begin
        rd_ptr              <= '0;
        wr_ptr              <= '0;
        _if.rd_data_1       <= NO_SOURCE;
        _if.rd_data_2       <= NO_SOURCE;
    end
    else begin
        // Write Operation
        if (_if.wr_en) begin
            case (_if.wr_mode)
               3'b001 : begin
                    if ((_if.available >= 1) && (!_if.full)) begin
                        MEM[wr_ptr[ADDR_WIDTH - 1 : 0]]         <= _if.wr_data_1;
                        wr_ptr  <= (wr_ptr[ADDR_WIDTH - 1 : 0] == (FIFO_DEPTH - 1)) ?  {~wr_ptr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} : wr_ptr + 1;
                    end
                end
               3'b010 : begin
                    if ((_if.available >= 2) && (!_if.full)) begin
                        case (wr_ptr)
                           FIFO_DEPTH - 1: begin
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0]]         <= _if.wr_data_1;                         
                                MEM[0]                                  <= _if.wr_data_2;  
                                wr_ptr                                  <= {~wr_ptr[ADDR_WIDTH], {(ADDR_WIDTH - 1){1'b0}}, 1'b1};                           
                           end 
                            default: begin
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0]]         <= _if.wr_data_1;                         
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0] + 1]     <= _if.wr_data_2;                         
                                wr_ptr          <= (wr_ptr[ADDR_WIDTH - 1 : 0] == (FIFO_DEPTH - 2)) ?  {~wr_ptr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} : wr_ptr + 2;
                            end
                        endcase
                    end
                end                
               3'b011 : begin
                    if ((_if.available >= 3) && (!_if.full)) begin
                        case (wr_ptr)
                           FIFO_DEPTH - 2: begin
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0]]         <= _if.wr_data_1;                         
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0] + 1]     <= _if.wr_data_2;                         
                                MEM[0]                                  <= _if.wr_data_3;
                                wr_ptr                                  <= {~wr_ptr[ADDR_WIDTH], {(ADDR_WIDTH - 1){1'b0}}, 1'b1};                           
                           end 
                           FIFO_DEPTH - 1: begin
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0]]         <= _if.wr_data_1;                         
                                MEM[0]                                  <= _if.wr_data_2;                         
                                MEM[1]                                  <= _if.wr_data_3;
                                wr_ptr                                  <= {~wr_ptr[ADDR_WIDTH], {(ADDR_WIDTH - 2){1'b0}}, 2'b10};                           
                           end 
                            default: begin
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0]]         <= _if.wr_data_1;                         
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0] + 1]     <= _if.wr_data_2;                         
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0] + 2]     <= _if.wr_data_3;
                                wr_ptr          <= (wr_ptr[ADDR_WIDTH - 1 : 0] == (FIFO_DEPTH - 3)) ?  {~wr_ptr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} : wr_ptr + 3;
                            end
                        endcase
                    end
                end
               3'b100 : begin
                    if ((_if.available >= 4) && (!_if.full)) begin
                        // to handle if FIFO_DEPTH not multiples of 2
                        case (wr_ptr)
                           FIFO_DEPTH - 3: begin
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0]]         <= _if.wr_data_1;                         
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0] + 1]     <= _if.wr_data_2;                         
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0] + 2]     <= _if.wr_data_3;
                                MEM[0]                                  <= _if.wr_data_4;     
                                wr_ptr                                  <= {~wr_ptr[ADDR_WIDTH], {(ADDR_WIDTH - 1){1'b0}}, 1'b1};                           
                           end 
                           FIFO_DEPTH - 2: begin
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0]]         <= _if.wr_data_1;                         
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0] + 1]     <= _if.wr_data_2;                         
                                MEM[0]                                  <= _if.wr_data_3;
                                MEM[1]                                  <= _if.wr_data_4;                                
                                wr_ptr                                  <= {~wr_ptr[ADDR_WIDTH], {(ADDR_WIDTH - 2){1'b0}}, 2'b10};                           
                           end 
                           FIFO_DEPTH - 1: begin
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0]]         <= _if.wr_data_1;                         
                                MEM[0]                                  <= _if.wr_data_2;                         
                                MEM[1]                                  <= _if.wr_data_3;
                                MEM[2]                                  <= _if.wr_data_4;                                                            
                                wr_ptr                                  <= {~wr_ptr[ADDR_WIDTH], {(ADDR_WIDTH - 2){1'b0}}, 2'b11};                           
                           end 
                            default: begin
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0]]         <= _if.wr_data_1;                         
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0] + 1]     <= _if.wr_data_2;                         
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0] + 2]     <= _if.wr_data_3;
                                MEM[wr_ptr[ADDR_WIDTH - 1 : 0] + 3]     <= _if.wr_data_4;  
                                wr_ptr          <= (wr_ptr[ADDR_WIDTH - 1 : 0] == (FIFO_DEPTH - 4)) ?  {~wr_ptr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} : wr_ptr + 4;
                            end
                        endcase
                    end
                end
                default: begin
                    
                end
            endcase
        end

        // Read Operation
        if (_if.rd_en) begin
            case (_if.rd_mode)
               3'b001 : begin
                    if ((_if.available < FIFO_DEPTH) && (!_if.empty)) begin
                        _if.rd_data_1                           <= MEM[rd_ptr[ADDR_WIDTH - 1 : 0]];
                        MEM[rd_ptr[ADDR_WIDTH - 1 : 0]]         <= NO_SOURCE;
                        rd_ptr                                  <= (rd_ptr[ADDR_WIDTH - 1 : 0] == (FIFO_DEPTH - 1)) ?  {~rd_ptr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} : rd_ptr + 1;
                    end
                end
               3'b010 : begin
                    if ((_if.available < (FIFO_DEPTH - 1)) && (!_if.empty)) begin
                        case (rd_ptr)
                           (FIFO_DEPTH - 1) : begin
                                _if.rd_data_1                           <= MEM[rd_ptr[ADDR_WIDTH - 1 : 0]];
                                _if.rd_data_2                           <= MEM[0];
                                MEM[rd_ptr[ADDR_WIDTH - 1 : 0]]         <= NO_SOURCE;
                                MEM[0]                                  <= NO_SOURCE; 
                                rd_ptr                                  <=  {~rd_ptr[ADDR_WIDTH], {(ADDR_WIDTH - 1){1'b0}}, 1'b1};
                           end
                            default: begin
                                 _if.rd_data_1                          <= MEM[rd_ptr[ADDR_WIDTH - 1 : 0]];
                                 _if.rd_data_2                          <= MEM[rd_ptr[ADDR_WIDTH - 1 : 0] + 1];        
                                MEM[rd_ptr[ADDR_WIDTH - 1 : 0]]         <= NO_SOURCE;
                                MEM[rd_ptr[ADDR_WIDTH - 1 : 0] + 1]     <= NO_SOURCE;                         
                                rd_ptr                           <= (rd_ptr[ADDR_WIDTH - 1 : 0] == (FIFO_DEPTH - 2)) ?  {~rd_ptr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} : rd_ptr + 2;
                            end
                        endcase
                    end
                end                
                default: begin

                end
            endcase
        end
    end
end : Write_Read_Operation


/* Always Blocks */
always_ff @(posedge clk or negedge arst) begin : Calc_Available
    if (!arst) begin
        _if.available = FIFO_DEPTH;
    end
    else begin
        case ({_if.wr_en, _if.rd_en})
            // Write Operation
            2'b10: begin
                case (_if.wr_mode)
                    3'b001 : begin
                        if ((_if.available >= 1) && (!_if.full)) begin
                            _if.available  <= _if.available - 1;
                        end
                    end
                    3'b010 : begin
                        if ((_if.available >= 2) && (!_if.full)) begin
                            _if.available   = _if.available - 2;
                        end
                    end                
                    3'b011 : begin
                        if ((_if.available >= 3) && (!_if.full)) begin
                            _if.available   = _if.available - 3;
                        end
                    end
                    3'b100 : begin
                        if ((_if.available >= 4) && (!_if.full)) begin
                            _if.available   = _if.available - 4;
                        end
                    end
                    default: begin
                    end
                endcase
            end
            // Read Operation
            2'b01: begin
                case (_if.rd_mode)
                    3'b001 : begin
                        if ((_if.available < FIFO_DEPTH) && (!_if.empty)) begin
                            _if.available    = _if.available + 1;
                        end
                    end
                    3'b010 : begin
                        if ((_if.available < (FIFO_DEPTH - 1)) && (!_if.empty)) begin
                            _if.available   = _if.available + 2;
                        end
                    end                
                    default: begin

                    end
                endcase
            end
            // Read and Write Operation
            2'b11: begin
                Available_Check(_if.available, _if.wr_mode, _if.rd_mode);
            end
            default: begin 
            end
        endcase
end
end : Calc_Available

// Note: need to handle case when FIFO empty and wr_en, rd_en (write then read)
// Note: need to handle case when FIFO full and wr_en, rd_en (read then write) (Done)

/* Instantiations */

endmodule: Sequence_Recorder
/*********** END_OF_FILE ***********/
