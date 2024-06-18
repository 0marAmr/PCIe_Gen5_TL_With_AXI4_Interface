/* Module Name	: buffer_frag.sv            */
/* Written By	: Mohamed Aladdin           */
/* Date			: 30-04-2024		        */
/* Version		: V_1			            */
/* Updates		: -			                */
/* Dependencies	: -				            */
/* Used			: 			                */

`timescale 1ns/1ps

/* Parameters */
import Fragmentation_Package::*;
import axi_slave_package::*; 


module buffer_frag ( 
    input bit clk,
    input bit arst,
    buffer_frag_interface.buffer_arbiter            _Src_if, 
    Fragmentation_Interface.TLP_FIFO_FRAGMENTATION    _Dist_if
    // output logic Buffer_Ready,  // it is 1 only before writing anything and after first written in the buffer set it to be always be 0 
    // output logic start_fragment // it is an indicator that the TLP has completed stored, then arbiter can send the following TLP
); 

// Internal memory storage
logic [TLP_FIFO_WIDTH-1:0] MEM [TLP_FIFO_DEPTH-1:0];

logic [TLP_FIFO_ADD_WIDTH - 1 : 0] wr_addr, rd_addr; 


integer i ; 

// to store inside Mem.
always @(posedge clk or negedge arst) begin 
    if (!arst) begin 
        for (i = 0 ; i < TLP_FIFO_DEPTH ; i = i + 1 ) begin 
            MEM[i] <= '0 ; 
        end 
        _Dist_if.rd_data_1 <= '0 ;
        _Dist_if.rd_data_2 <= '0 ;
        _Dist_if.Count <= 1'b0 ; 
        wr_addr <= '0 ; 
        rd_addr <= '0 ; 
    end 
    else begin 
        case ({_Src_if.wr_en, _Dist_if.rd_en}) 
            2'b10 : begin 
                _Dist_if.Count <= (_Dist_if.Count == TLP_FIFO_DEPTH) ? TLP_FIFO_DEPTH : (_Dist_if.Count +  _Src_if.no_loc_wr) ; // store written loc. 
                case (_Src_if.no_loc_wr) 
                    'd1 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ; // last 4 DOUBLE_WORD 
                    end 
                    'd2 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ;
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ;  
                    end 
                    'd3 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ;
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ; 
                        MEM[wr_addr + 2'b10]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 7 - 1 : TLP_FIFO_WIDTH * 6] ; 
                    end 
                    'd4 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ; // last 4 DOUBLE_WORD 
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ; 
                        MEM[wr_addr + 2'b10]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 7 - 1 : TLP_FIFO_WIDTH * 6] ; 
                        MEM[wr_addr + 2'b11]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 6 - 1 : TLP_FIFO_WIDTH * 5] ; 
                    end 
                    'd5 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ; // last 4 DOUBLE_WORD 
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ; 
                        MEM[wr_addr + 2'b10]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 7 - 1 : TLP_FIFO_WIDTH * 6] ; 
                        MEM[wr_addr + 2'b11]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 6 - 1 : TLP_FIFO_WIDTH * 5] ; 
                        MEM[wr_addr + 3'b100]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 5 - 1 : TLP_FIFO_WIDTH * 4] ; 
                    end 
                    'd6 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ; // last 4 DOUBLE_WORD 
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ; 
                        MEM[wr_addr + 2'b10]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 7 - 1 : TLP_FIFO_WIDTH * 6] ; 
                        MEM[wr_addr + 2'b11]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 6 - 1 : TLP_FIFO_WIDTH * 5] ; 
                        MEM[wr_addr + 3'b100]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 5 - 1 : TLP_FIFO_WIDTH * 4] ; 
                        MEM[wr_addr + 3'b101]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 4 - 1 : TLP_FIFO_WIDTH * 3] ; 
                    end 
                    'd7 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ; // last 4 DOUBLE_WORD 
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ; 
                        MEM[wr_addr + 2'b10]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 7 - 1 : TLP_FIFO_WIDTH * 6] ; 
                        MEM[wr_addr + 2'b11]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 6 - 1 : TLP_FIFO_WIDTH * 5] ; 
                        MEM[wr_addr + 3'b100]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 5 - 1 : TLP_FIFO_WIDTH * 4] ; 
                        MEM[wr_addr + 3'b101]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 4 - 1 : TLP_FIFO_WIDTH * 3] ; 
                        MEM[wr_addr + 3'b110]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 3 - 1 : TLP_FIFO_WIDTH * 2] ; 
                    end 
                    'd8 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ; // last 4 DOUBLE_WORD 
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ; 
                        MEM[wr_addr + 2'b10]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 7 - 1 : TLP_FIFO_WIDTH * 6] ; 
                        MEM[wr_addr + 2'b11]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 6 - 1 : TLP_FIFO_WIDTH * 5] ; 
                        MEM[wr_addr + 3'b100]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 5 - 1 : TLP_FIFO_WIDTH * 4] ; 
                        MEM[wr_addr + 3'b101]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 4 - 1 : TLP_FIFO_WIDTH * 3] ; 
                        MEM[wr_addr + 3'b110]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 3 - 1 : TLP_FIFO_WIDTH * 2] ; 
                        MEM[wr_addr + 3'b111]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 2 - 1 : TLP_FIFO_WIDTH * 1] ; 
                    end 
                    'd9 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ; // last 4 DOUBLE_WORD 
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ; 
                        MEM[wr_addr + 2'b10]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 7 - 1 : TLP_FIFO_WIDTH * 6] ; 
                        MEM[wr_addr + 2'b11]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 6 - 1 : TLP_FIFO_WIDTH * 5] ; 
                        MEM[wr_addr + 3'b100]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 5 - 1 : TLP_FIFO_WIDTH * 4] ; 
                        MEM[wr_addr + 3'b101]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 4 - 1 : TLP_FIFO_WIDTH * 3] ; 
                        MEM[wr_addr + 3'b110]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 3 - 1 : TLP_FIFO_WIDTH * 2] ; 
                        MEM[wr_addr + 3'b111]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 2 - 1 : TLP_FIFO_WIDTH * 1] ; 
                        MEM[wr_addr + 4'b1000]  <= _Src_if.data_in[TLP_FIFO_WIDTH * 1 - 1 : 0                 ] ; 
                    end 
                endcase
                wr_addr <= wr_addr + _Src_if.no_loc_wr ; 
            end 
            2'b01 : begin 
                // add feature of address to trigger that rd_Addr --> 
                /* if first write --> wr_addr = rd_addr = 0 ; update 2 pointers for each read and write*/
                _Dist_if.Count <= (_Dist_if.Count == 0) ? 0 : (_Dist_if.Count - (_Dist_if.rd_mode + 1'b1)) ; // decrease read loc. 
                    case (_Dist_if.rd_mode) 
                        'd0 : begin 
                            _Dist_if.rd_data_1       <=  MEM[rd_addr] ; // last 4 DOUBLE_WORD 
                            _Dist_if.rd_data_2[1:0]  <= 2'b00;
                            MEM[rd_addr]             <= '0;   
                        end 
                        'd1 : begin 
                            _Dist_if.rd_data_1       <=  MEM[rd_addr] ; // last 4 DOUBLE_WORD 
                            _Dist_if.rd_data_2       <= MEM[rd_addr + 1'b1] ;  
                            // _Dist_if.rd_data_1[1:0]  <= 2'b00;
                            // _Dist_if.rd_data_2[1:0]  <= 2'b00;
                            MEM[rd_addr]             <= '0;   
                            MEM[rd_addr + 1'b1]      <= '0;   
                        end 
                    endcase
                    rd_addr <= rd_addr + _Dist_if.rd_mode + 1'b1 ; 
            end 
            2'b11 : begin 
                _Dist_if.Count <= _Dist_if.Count - (_Dist_if.rd_mode + 1'b1)  +  _Src_if.no_loc_wr ;  
                case (_Dist_if.rd_mode) 
                    'd0 : begin 
                        _Dist_if.rd_data_1 <=  MEM[rd_addr] ; // last 4 DOUBLE_WORD 
                            _Dist_if.rd_data_2[1:0]  <= 2'b00;
                    end 
                    'd1 : begin 
                        _Dist_if.rd_data_1 <=  MEM[rd_addr] ; // last 4 DOUBLE_WORD 
                        _Dist_if.rd_data_2 <= MEM[rd_addr + 1'b1] ;  
                            // _Dist_if.rd_data_1[1:0]  <= 2'b00;
                            // _Dist_if.rd_data_2[1:0]  <= 2'b00;
                    end 
                endcase
                rd_addr <= rd_addr + _Dist_if.rd_mode + 1'b1 ; 

                case (_Src_if.no_loc_wr) 
                    'd1 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ; // last 4 DOUBLE_WORD 
                    end 
                    'd2 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ;
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ;  
                    end 
                    'd3 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ;
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ; 
                        MEM[wr_addr + 2'b10]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 7 - 1 : TLP_FIFO_WIDTH * 6] ; 
                    end 
                    'd4 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ; // last 4 DOUBLE_WORD 
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ; 
                        MEM[wr_addr + 2'b10]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 7 - 1 : TLP_FIFO_WIDTH * 6] ; 
                        MEM[wr_addr + 2'b11]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 6 - 1 : TLP_FIFO_WIDTH * 5] ; 
                    end 
                    'd5 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ; // last 4 DOUBLE_WORD 
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ; 
                        MEM[wr_addr + 2'b10]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 7 - 1 : TLP_FIFO_WIDTH * 6] ; 
                        MEM[wr_addr + 2'b11]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 6 - 1 : TLP_FIFO_WIDTH * 5] ; 
                        MEM[wr_addr + 3'b100]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 5 - 1 : TLP_FIFO_WIDTH * 4] ; 
                    end 
                    'd6 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ; // last 4 DOUBLE_WORD 
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ; 
                        MEM[wr_addr + 2'b10]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 7 - 1 : TLP_FIFO_WIDTH * 6] ; 
                        MEM[wr_addr + 2'b11]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 6 - 1 : TLP_FIFO_WIDTH * 5] ; 
                        MEM[wr_addr + 3'b100]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 5 - 1 : TLP_FIFO_WIDTH * 4] ; 
                        MEM[wr_addr + 3'b101]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 4 - 1 : TLP_FIFO_WIDTH * 3] ; 
                    end 
                    'd7 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ; // last 4 DOUBLE_WORD 
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ; 
                        MEM[wr_addr + 2'b10]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 7 - 1 : TLP_FIFO_WIDTH * 6] ; 
                        MEM[wr_addr + 2'b11]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 6 - 1 : TLP_FIFO_WIDTH * 5] ; 
                        MEM[wr_addr + 3'b100]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 5 - 1 : TLP_FIFO_WIDTH * 4] ; 
                        MEM[wr_addr + 3'b101]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 4 - 1 : TLP_FIFO_WIDTH * 3] ; 
                        MEM[wr_addr + 3'b110]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 3 - 1 : TLP_FIFO_WIDTH * 2] ; 
                    end 
                    'd8 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ; // last 4 DOUBLE_WORD 
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ; 
                        MEM[wr_addr + 2'b10]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 7 - 1 : TLP_FIFO_WIDTH * 6] ; 
                        MEM[wr_addr + 2'b11]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 6 - 1 : TLP_FIFO_WIDTH * 5] ; 
                        MEM[wr_addr + 3'b100]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 5 - 1 : TLP_FIFO_WIDTH * 4] ; 
                        MEM[wr_addr + 3'b101]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 4 - 1 : TLP_FIFO_WIDTH * 3] ; 
                        MEM[wr_addr + 3'b110]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 3 - 1 : TLP_FIFO_WIDTH * 2] ; 
                        MEM[wr_addr + 3'b111]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 2 - 1 : TLP_FIFO_WIDTH * 1] ; 
                    end 
                    'd9 : begin 
                        MEM[wr_addr]            <= _Src_if.data_in[TLP_FIFO_WIDTH * 9 - 1 : TLP_FIFO_WIDTH * 8] ; // last 4 DOUBLE_WORD 
                        MEM[wr_addr + 1'b1]     <= _Src_if.data_in[TLP_FIFO_WIDTH * 8 - 1 : TLP_FIFO_WIDTH * 7] ; 
                        MEM[wr_addr + 2'b10]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 7 - 1 : TLP_FIFO_WIDTH * 6] ; 
                        MEM[wr_addr + 2'b11]    <= _Src_if.data_in[TLP_FIFO_WIDTH * 6 - 1 : TLP_FIFO_WIDTH * 5] ; 
                        MEM[wr_addr + 3'b100]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 5 - 1 : TLP_FIFO_WIDTH * 4] ; 
                        MEM[wr_addr + 3'b101]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 4 - 1 : TLP_FIFO_WIDTH * 3] ; 
                        MEM[wr_addr + 3'b110]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 3 - 1 : TLP_FIFO_WIDTH * 2] ; 
                        MEM[wr_addr + 3'b111]   <= _Src_if.data_in[TLP_FIFO_WIDTH * 2 - 1 : TLP_FIFO_WIDTH * 1] ; 
                        MEM[wr_addr + 4'b1000]  <= _Src_if.data_in[TLP_FIFO_WIDTH * 1 - 1 : 0                 ] ; 
                    end 
                endcase
                wr_addr <= wr_addr + _Src_if.no_loc_wr ; 
            end 
        endcase 
        // if (start_fragment) begin 
            // start_fragment <= 1'b0 ; 
        // end 
        if ((wr_addr == rd_addr ) && (wr_addr != '0)) begin 
            // start_fragment <= 1'b1 ; 
            // wr_addr <= '0 ; 
            // rd_addr <= '0 ;
            // _Dist_if.rd_data_1 <= '0 ;
            // _Dist_if.rd_data_2 <= '0 ;
        end 

    
    end 
end 

assign _Src_if.empty = (wr_addr == rd_addr);

// always @(*) begin 
//     if ((wr_addr = rd_addr) && (wr_addr != '0)) begin 
//             start_fragment <= 1'b1 ; 
//             wr_addr <= '0 ; 
//     end 
// end 



endmodule : buffer_frag 



