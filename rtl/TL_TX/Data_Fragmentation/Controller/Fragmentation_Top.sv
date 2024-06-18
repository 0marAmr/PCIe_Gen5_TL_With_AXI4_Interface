/********************************************************************/
/* Module Name	: Fragmentation_Top.sv                              */
/* Written By	: Mohamed Khaled Alahmady                           */
/* Date			: 29-04-2024 					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: -							                        */
/********************************************************************/
module Fragmentation_Top ();

/* Packages */
import axi_slave_package::*;

/* Parameters */
parameter CLK_PERIOD = 10;

/* Internal Signals */
bit clk;
bit arst;
Cpl_TLP_HDR_t Hdr_temp;
/* Useful Functions */

/* Assign Statements */

/* Initial Block */
/********* Stimulus Generation *********/
    int i;
    initial begin
        $monitor("Message: %h", Frag_if.ecrc_Message[127 : 0]);
        arst                = 1'b0; 
        Frag_if.Count       = 0;
        Hdr_temp            = '0;
        Frag_if.rd_data_1   = '0;
        Frag_if.rd_data_2   = '0;
        #(CLK_PERIOD)
        arst                    = 1'b1;
        #(CLK_PERIOD/2)
        Frag_if.Count           = 1;

        Hdr_temp                = '0;
        Hdr_temp.fmt            = TLP_FMT_3DW;
        Hdr_temp.TD             = 1'b1;
        Hdr_temp.Length         = 3;

        Frag_if.rd_data_1       = {Hdr_temp, 32'b0};
        Frag_if.rd_data_2       = 128'habcd_1234_7898_6548_3265_1265_951a_326d;
        #(CLK_PERIOD)
        // repeat(7) begin
        //     Frag_if.rd_data_1       = 128'h1111_2222_3333_4444_5555_6666_7777_8888 + i;
        //     Frag_if.rd_data_1       = 128'h1111_2222_3333_4444_5555_6666_7777_8888 + i + 1;
        //     i++;         
        // end
        Frag_if.Count           = 0;
        #(3*CLK_PERIOD)
        $stop();
    end
    
/* Always Blocks */
/********* Clock Generation *********/
	initial begin
		forever #(CLK_PERIOD/2) clk = ~clk;
	end

/* Instantiations */
/********* Interfaces *********/
    Fragmentation_Interface #(
    ) Frag_if ();

/********* Modules *********/
    Fragmentation #(
    ) u_Fragmentation (
        clk, 
        arst,
        Frag_if,
        Frag_if,
        Frag_if
    );

    ECRC #(
    ) u_ECRC (
        Frag_if
    );

endmodule: Fragmentation_Top
/*********** END_OF_FILE ***********/
