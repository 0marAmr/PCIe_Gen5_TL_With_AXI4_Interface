/* Module Name	: buffer_frag.sv            */
/* Written By	: Mohamed Aladdin           */
/* Date			: 30-04-2024		        */
/* Version		: V_1			            */
/* Updates		: -			                */
/* Dependencies	: -				            */
/* Used			: 			                */

`timescale 1ns/1ps

/* Parameters */
import data_frag_package::*;

module buffer_frag ( 
    input bit clk,
    input bit arst,
    buffer_frag_interface.buffer _if, 
    output logic Buffer_Ready,  // it is 1 only before writing anything and after first written in the buffer set it to be always be 0 
    output logic start_fragment // it is an indicator that the TLP has completed stored, then arbiter can send the following TLP
); 

// Internal memory storage
logic [Buffer_WIDTH-1:0] MEM [Buffer_DEPTH-1:0];

logic [ADDR_WIDTH - 1 : 0] wr_addr, rd_addr; 


integer i ; 

// to store inside Mem.
always @(posedge clk or negedge arst) begin 
    if (!arst) begin 
        Buffer_Ready <= 1'b1 ; 
        for (i = 0 ; i < Buffer_DEPTH ; i = i + 1 ) begin 
            MEM[i] <= '0 ; 
        end 
        _if.rd_data_1 <= '0 ;
        _if.rd_data_2 <= '0 ;
        _if.Count <= 1'b0 ; 
        start_fragment = 1'b0 ; 
        wr_addr <= '0 ; 
        rd_addr <= '0 ; 
    end 
    else begin 
        case ({_if.wr_en, _if.rd_en}) 
            2'b10 : begin 
                Buffer_Ready <= 1'b0 ; 
                _if.Count <= _if.Count +  _if.no_loc_wr ; // store written loc. 
                case (_if.no_loc_wr) 
                    'd1 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                    end 
                    'd2 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ;  
                    end 
                    'd3 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ; 
                        MEM[wr_addr + 2'b10] <= _if.data_in[(28*DW) - 1 : (24*DW) ] ; 
                    end 
                    'd4 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ; 
                        MEM[wr_addr + 2'b10] <= _if.data_in[(28*DW) - 1 : (24*DW) ] ; 
                        MEM[wr_addr + 2'b11] <= _if.data_in[(24*DW) - 1 : (20*DW) ] ; 
                    end 
                    'd5 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ; 
                        MEM[wr_addr + 2'b10] <= _if.data_in[(28*DW) - 1 : (24*DW) ] ; 
                        MEM[wr_addr + 2'b11] <= _if.data_in[(24*DW) - 1 : (20*DW) ] ; 
                        MEM[wr_addr + 3'b100] <= _if.data_in[(20*DW) - 1 : (16*DW) ] ; 
                    end 
                    'd6 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ; 
                        MEM[wr_addr + 2'b10] <= _if.data_in[(28*DW) - 1 : (24*DW) ] ; 
                        MEM[wr_addr + 2'b11] <= _if.data_in[(24*DW) - 1 : (20*DW) ] ; 
                        MEM[wr_addr + 3'b100] <= _if.data_in[(20*DW) - 1 : (16*DW) ] ; 
                        MEM[wr_addr + 3'b101] <= _if.data_in[(16*DW) - 1 : (12*DW) ] ; 
    
                    end 
                    'd7 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ; 
                        MEM[wr_addr + 2'b10] <= _if.data_in[(28*DW) - 1 : (24*DW) ] ; 
                        MEM[wr_addr + 2'b11] <= _if.data_in[(24*DW) - 1 : (20*DW) ] ; 
                        MEM[wr_addr + 3'b100] <= _if.data_in[(20*DW) - 1 : (16*DW) ] ; 
                        MEM[wr_addr + 3'b101] <= _if.data_in[(16*DW) - 1 : (12*DW) ] ; 
                        MEM[wr_addr + 3'b110] <= _if.data_in[(12*DW) - 1 : (8*DW) ] ; 
    
                    end 
                    'd8 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ; 
                        MEM[wr_addr + 2'b10] <= _if.data_in[(28*DW) - 1 : (24*DW) ] ; 
                        MEM[wr_addr + 2'b11] <= _if.data_in[(24*DW) - 1 : (20*DW) ] ; 
                        MEM[wr_addr + 3'b100] <= _if.data_in[(20*DW) - 1 : (16*DW) ] ; 
                        MEM[wr_addr + 3'b101] <= _if.data_in[(16*DW) - 1 : (12*DW) ] ; 
                        MEM[wr_addr + 3'b110] <= _if.data_in[(12*DW) - 1 : (8*DW) ] ; 
                        MEM[wr_addr + 3'b111] <= _if.data_in[(8*DW) - 1 : (4*DW) ] ; 
                    end 
                    'd9 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ; 
                        MEM[wr_addr + 2'b10] <= _if.data_in[(28*DW) - 1 : (24*DW) ] ; 
                        MEM[wr_addr + 2'b11] <= _if.data_in[(24*DW) - 1 : (20*DW) ] ; 
                        MEM[wr_addr + 3'b100] <= _if.data_in[(20*DW) - 1 : (16*DW) ] ; 
                        MEM[wr_addr + 3'b101] <= _if.data_in[(16*DW) - 1 : (12*DW) ] ; 
                        MEM[wr_addr + 3'b110] <= _if.data_in[(12*DW) - 1 : (8*DW) ] ; 
                        MEM[wr_addr + 3'b111] <= _if.data_in[(8*DW) - 1 : (4*DW) ] ; 
                        MEM[wr_addr + 4'b1000] <= _if.data_in[(4*DW) - 1 : 0 ] ; 
                    end 
                endcase
                wr_addr <= wr_addr + _if.no_loc_wr ; 
            end 
            2'b01 : begin 
                // add feature of address to trigger that rd_Addr --> 
                /* if first write --> wr_addr = rd_addr = 0 ; update 2 pointers for each read and write*/
                _if.Count <= _if.Count - (_if.rd_mode + 1'b1) ; // decrease read loc. 
                    case (_if.rd_mode) 
                        'd0 : begin 
                            _if.rd_data_1 <=  MEM[rd_addr] ; // last 4 DW 
                        end 
                        'd1 : begin 
                            _if.rd_data_1 <=  MEM[rd_addr] ; // last 4 DW 
                            _if.rd_data_2 <= MEM[rd_addr + 1'b1] ;  
                        end 
                    endcase
                    rd_addr <= rd_addr + _if.rd_mode + 1'b1 ; 
            end 
            2'b11 : begin 
                _if.Count <= _if.Count - (_if.rd_mode + 1'b1)  +  _if.no_loc_wr ;  
                case (_if.rd_mode) 
                    'd0 : begin 
                        _if.rd_data_1 <=  MEM[rd_addr] ; // last 4 DW 
                    end 
                    'd1 : begin 
                        _if.rd_data_1 <=  MEM[rd_addr] ; // last 4 DW 
                        _if.rd_data_2 <= MEM[rd_addr + 1'b1] ;  
                    end 
                endcase
                rd_addr <= rd_addr + _if.rd_mode + 1'b1 ; 

                case (_if.no_loc_wr) 
                    'd1 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                    end 
                    'd2 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ;  
                    end 
                    'd3 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ; 
                        MEM[wr_addr + 2'b10] <= _if.data_in[(28*DW) - 1 : (24*DW) ] ; 
                    end 
                    'd4 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ; 
                        MEM[wr_addr + 2'b10] <= _if.data_in[(28*DW) - 1 : (24*DW) ] ; 
                        MEM[wr_addr + 2'b11] <= _if.data_in[(24*DW) - 1 : (20*DW) ] ; 
                    end 
                    'd5 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ; 
                        MEM[wr_addr + 2'b10] <= _if.data_in[(28*DW) - 1 : (24*DW) ] ; 
                        MEM[wr_addr + 2'b11] <= _if.data_in[(24*DW) - 1 : (20*DW) ] ; 
                        MEM[wr_addr + 3'b100] <= _if.data_in[(20*DW) - 1 : (16*DW) ] ; 
                    end 
                    'd6 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ; 
                        MEM[wr_addr + 2'b10] <= _if.data_in[(28*DW) - 1 : (24*DW) ] ; 
                        MEM[wr_addr + 2'b11] <= _if.data_in[(24*DW) - 1 : (20*DW) ] ; 
                        MEM[wr_addr + 3'b100] <= _if.data_in[(20*DW) - 1 : (16*DW) ] ; 
                        MEM[wr_addr + 3'b101] <= _if.data_in[(16*DW) - 1 : (12*DW) ] ; 
    
                    end 
                    'd7 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ; 
                        MEM[wr_addr + 2'b10] <= _if.data_in[(28*DW) - 1 : (24*DW) ] ; 
                        MEM[wr_addr + 2'b11] <= _if.data_in[(24*DW) - 1 : (20*DW) ] ; 
                        MEM[wr_addr + 3'b100] <= _if.data_in[(20*DW) - 1 : (16*DW) ] ; 
                        MEM[wr_addr + 3'b101] <= _if.data_in[(16*DW) - 1 : (12*DW) ] ; 
                        MEM[wr_addr + 3'b110] <= _if.data_in[(12*DW) - 1 : (8*DW) ] ; 
    
                    end 
                    'd8 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ; 
                        MEM[wr_addr + 2'b10] <= _if.data_in[(28*DW) - 1 : (24*DW) ] ; 
                        MEM[wr_addr + 2'b11] <= _if.data_in[(24*DW) - 1 : (20*DW) ] ; 
                        MEM[wr_addr + 3'b100] <= _if.data_in[(20*DW) - 1 : (16*DW) ] ; 
                        MEM[wr_addr + 3'b101] <= _if.data_in[(16*DW) - 1 : (12*DW) ] ; 
                        MEM[wr_addr + 3'b110] <= _if.data_in[(12*DW) - 1 : (8*DW) ] ; 
                        MEM[wr_addr + 3'b111] <= _if.data_in[(8*DW) - 1 : (4*DW) ] ; 
                    end 
                    'd9 : begin 
                        MEM[wr_addr] <= _if.data_in[(36*DW) - 1 : (32*DW) ] ; // last 4 DW 
                        MEM[wr_addr + 1'b1] <= _if.data_in[(32*DW) - 1 : (28*DW) ] ; 
                        MEM[wr_addr + 2'b10] <= _if.data_in[(28*DW) - 1 : (24*DW) ] ; 
                        MEM[wr_addr + 2'b11] <= _if.data_in[(24*DW) - 1 : (20*DW) ] ; 
                        MEM[wr_addr + 3'b100] <= _if.data_in[(20*DW) - 1 : (16*DW) ] ; 
                        MEM[wr_addr + 3'b101] <= _if.data_in[(16*DW) - 1 : (12*DW) ] ; 
                        MEM[wr_addr + 3'b110] <= _if.data_in[(12*DW) - 1 : (8*DW) ] ; 
                        MEM[wr_addr + 3'b111] <= _if.data_in[(8*DW) - 1 : (4*DW) ] ; 
                        MEM[wr_addr + 4'b1000] <= _if.data_in[(4*DW) - 1 : 0 ] ; 
                    end 
                endcase
                wr_addr <= wr_addr + _if.no_loc_wr ; 

            end 
        endcase 
        if (start_fragment) begin 
            start_fragment <= 1'b0 ; 
        end 
        else if ((wr_addr == rd_addr ) && (wr_addr != '0)) begin 
            start_fragment <= 1'b1 ; 
            wr_addr <= '0 ; 
            rd_addr <= '0 ;
            _if.rd_data_1 <= '0 ;
            _if.rd_data_2 <= '0 ;

        end 

    
    end 
end 

// always @(*) begin 
//     if ((wr_addr = rd_addr) && (wr_addr != '0)) begin 
//             start_fragment <= 1'b1 ; 
//             wr_addr <= '0 ; 
//     end 
// end 



endmodule : buffer_frag 



