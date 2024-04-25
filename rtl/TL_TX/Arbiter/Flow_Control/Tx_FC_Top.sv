/* Module Name	: Tx_FC_Top         	         */
/* Written By	: Ahmady                     	*/
/* Date			: 9-04-2024 					*/
/* Version		: V_1							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: -							    */
/* Future Work  :                               */
module Tx_FC_Top ();
parameter   FC_HDR_WIDTH    = 12,
            FC_DATA_WIDTH   = 16,   
            CLK_PERIOD      = 10;
            

/* Packages */

/* Parameters */
import Tx_Arbiter_Package::*;

/* Internal Signals */
bit clk;
bit arst;

/* Useful Functions */

/* Assign Statements */

/* Initial Block */
/********* Stimulus Generation *********/
    function logic [9 : 0] FC_PTLP_Conv (input logic [9 : 0] PTLP);
        // if PTLP % 4 == 0 (devisable by 4) then result = (PTLP / 4)
        // else result = (PTLP / 4) + 1
        if ((PTLP & 10'b00_0000_0011) == 10'b00_0000_0000) begin
            // xx_xxxx_xx00
            return PTLP >> 2;
        end
        else begin
            return (PTLP >> 2) + 1;        
        end
    endfunction

    int k, j;
    initial begin
        arst            = 1'b0; 
        Tx_FC_if.TypeFC = FC_X; Tx_FC_if.HdrFC = '0; Tx_FC_if.DataFC = '0;
        #(CLK_PERIOD)
        #(CLK_PERIOD/2)
        arst            = 1'b1; 
        Tx_FC_if.TypeFC = FC_P;     Tx_FC_if.HdrFC = 10; Tx_FC_if.DataFC = 1000;
        #(CLK_PERIOD)
        Tx_FC_if.TypeFC = FC_NP;    Tx_FC_if.HdrFC = 10; Tx_FC_if.DataFC = 1000;
        #(CLK_PERIOD)
        Tx_FC_if.TypeFC = FC_CPL;   Tx_FC_if.HdrFC = 10; Tx_FC_if.DataFC = 1000;
        #(CLK_PERIOD)

        // Tx_FC_if.TypeFC = FC_NP; Tx_FC_if.HdrFC = 150; Tx_FC_if.DataFC = 150;
        // #(CLK_PERIOD)
        // Tx_FC_if.TypeFC = FC_CPL; Tx_FC_if.HdrFC = 200; Tx_FC_if.DataFC = 2000;
        // #(CLK_PERIOD)
        // Tx_FC_if.Command_1 = FC_P_D; Tx_FC_if.Command_2 = FC_NP_D; Tx_FC_if.PTLP_1 = 125; Tx_FC_if.PTLP_2 = 200; 
        // #(CLK_PERIOD)
        // Tx_FC_if.Command = FC_P_D; Tx_FC_if.PTLP = 90; 
        // #(CLK_PERIOD)
        // Tx_FC_if.Command = FC_NP_H; Tx_FC_if.PTLP = 0; 
        // #(CLK_PERIOD)
        // Tx_FC_if.Command = FC_NP_D; Tx_FC_if.PTLP = 170;
        // #(CLK_PERIOD)
        // Tx_FC_if.Command = FC_CPL_H; Tx_FC_if.PTLP = 0; 
        // #(CLK_PERIOD)
        // Tx_FC_if.Command = FC_CPL_D; Tx_FC_if.PTLP = 260;
        // #(4*CLK_PERIOD)
        // u_Tx_FC.CL_Posted_Data = 1000;
        // u_Tx_FC.CL_Posted_Hdr  = 1000;
        repeat(20) begin
            k = $urandom % 7;
            j = $urandom % 7;
            $cast(Tx_FC_if.Command_1, k);
            $cast(Tx_FC_if.Command_2, j);
            Tx_FC_if.PTLP_1     = $urandom() % 1024;
            Tx_FC_if.PTLP_2     = $urandom() % 1024;
            #(CLK_PERIOD);
            // $display("CL_H: %d, CC_H: %d", u_Tx_FC.CL_Posted_Hdr, u_Tx_FC.CC_Posted_Hdr);
            // $display("CL_D: %d, CC_D: %d, PTLP: %d (%d), Result: %s", u_Tx_FC.CL_Posted_Data, u_Tx_FC.CC_Posted_Data, Tx_FC_if.PTLP_1, FC_PTLP_Conv(Tx_FC_if.PTLP_1), Tx_FC_if.Result);
            // $display("-----------------------");
        end
        $stop();
    end
    
/* Always Blocks */
/********* Clock Generation *********/
	initial begin
		forever #(CLK_PERIOD/2) clk = ~clk;
	end

/* Instantiations */
/********* Interfaces *********/
    // Tx FC
    Tx_FC_Interface #(
        .FC_HDR_WIDTH(FC_HDR_WIDTH),
        .FC_DATA_WIDTH(FC_DATA_WIDTH)
    ) Tx_FC_if (
    );

/********* Modules *********/
    Tx_FC #(
        .FC_HDR_WIDTH(FC_HDR_WIDTH),
        .FC_DATA_WIDTH(FC_DATA_WIDTH)
    ) u_Tx_FC (
        clk,
        arst,
        Tx_FC_if,
        Tx_FC_if
    );

endmodule: Tx_FC_Top
/*********** END_OF_FILE ***********/
