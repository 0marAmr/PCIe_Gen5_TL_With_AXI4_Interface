/* Module Name	: buffer_frag_tb.sv         */
/* Written By	: Mohamed Aladdin           */
/* Date			: 30-04-2024		        */
/* Version		: V_1			            */
/* Updates		: -			                */
/* Dependencies	: -				            */
/* Used			: 			                */

import data_frag_package::*;

module buffer_frag_tb (); 


    // signals definition 
    bit clk , arst ; 
    logic Buffer_Ready , start_fragment ;  
    buffer_frag_interface _if (); 

    buffer_frag u_buffer_frag ( 
        .clk(clk),
        .arst(arst),
        ._if(_if),
        .Buffer_Ready(Buffer_Ready),
        .start_fragment(start_fragment)
    ); 

    parameter CLK_PERIOD = 10 ; 
     // Clock Generation Block
    initial begin : clk_gen
        clk =   1'b0 ; 
        forever #(CLK_PERIOD/2) clk=~clk;        
end


initial begin 
    $dumpfile ("Slave_tb.vcd");
    $dumpvars ();
    arst = 1'b0 ;
    #(CLK_PERIOD)
    arst = 1'b1 ;
    _if.buffer_tb.wr_en = 1'b1 ; 
    _if.buffer_tb.data_in = {12{32'haaaa_bbbb, 32'hcccc_dddd, 32'heeee_ffff}} ; 
    _if.buffer_tb.no_loc_wr = 4 ; 
    _if.buffer_tb.rd_en = 1'b0 ;
    _if.buffer_tb.rd_mode = 1'b0 ; 
    #(CLK_PERIOD) 
    _if.buffer_tb.rd_en = 1'b1 ;
    _if.buffer_tb.rd_mode = 1'b0 ; 
    #(CLK_PERIOD) 
    _if.buffer_tb.rd_en = 1'b1 ;
    _if.buffer_tb.rd_mode = 1'b0 ; 
    #(CLK_PERIOD) 
    _if.buffer_tb.rd_en = 1'b1 ;
    _if.buffer_tb.rd_mode = 1'b0 ;
    #(CLK_PERIOD) 
    _if.buffer_tb.rd_en = 1'b1 ;
    _if.buffer_tb.rd_mode = 1'b0 ;
    _if.buffer_tb.wr_en = 1'b0 ; 
    
    _if.buffer_tb.data_in = {12{32'haaaa_bbbb, 32'hcccc_dddd, 32'heeee_ffff}} ; 
    _if.buffer_tb.no_loc_wr = 0 ; 
    #(CLK_PERIOD) 
    _if.buffer_tb.rd_en = 1'b1 ;
    #(CLK_PERIOD*0.5) 
    _if.buffer_tb.rd_mode = 1'b1 ;
    #(CLK_PERIOD*5.5) 
    _if.buffer_tb.rd_en = 1'b0 ;
    #(CLK_PERIOD) 
    _if.buffer_tb.wr_en = 1'b1 ; 
    _if.buffer_tb.data_in = {12{32'haaaa_bbbb, 32'hcccc_dddd, 32'heeee_ffff}} ; 
    _if.buffer_tb.no_loc_wr = 4 ; 
    _if.buffer_tb.rd_en = 1'b0 ;
    _if.buffer_tb.rd_mode = 1'b0 ; 
    #(CLK_PERIOD) 
    _if.buffer_tb.rd_en = 1'b1 ;
    _if.buffer_tb.rd_mode = 1'b0 ;




    $stop;

end 


endmodule 
