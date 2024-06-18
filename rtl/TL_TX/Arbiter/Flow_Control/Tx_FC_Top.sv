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
// Interface with DLL
logic [FC_HDR_WIDTH  - 1 : 0]   HdrFC;
logic [FC_DATA_WIDTH - 1 : 0]   DataFC;
FC_type_t                       TypeFC;

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
        TypeFC = FC_X; HdrFC = '0; DataFC = '0;
        #(CLK_PERIOD)
        #(CLK_PERIOD/2)
        arst            = 1'b1; 
        TypeFC = FC_P;     HdrFC = 30; DataFC = 1000;
        #(CLK_PERIOD)
        TypeFC = FC_NP;    HdrFC = 15; DataFC = 1000;
        #(CLK_PERIOD)
        TypeFC = FC_CPL;   HdrFC = 30; DataFC = 1000;
        #(CLK_PERIOD)

        // Command_1 = FC_P_D; Command_2 = FC_DEFAULT; PTLP_1 = $urandom() % 265; PTLP_2 = $urandom() % 265; 
        // #(CLK_PERIOD)
        // Command_1 = FC_P_D; Command_2 = FC_P_H; PTLP_1 = $urandom() % 265; PTLP_2 = $urandom() % 265; 
        // #(CLK_PERIOD)
        // Command_1 = FC_P_D; Command_2 = FC_NP_H; PTLP_1 = $urandom() % 265; PTLP_2 = $urandom() % 265; 
        // #(CLK_PERIOD)
        // Command_1 = FC_P_D; Command_2 = FC_CPL_H; PTLP_1 = $urandom() % 265; PTLP_2 = $urandom() % 265; 
        // #(CLK_PERIOD)
        // Command_1 = FC_P_D; Command_2 = FC_NP_D; PTLP_1 = $urandom() % 265; PTLP_2 = $urandom() % 265; 
        // #(CLK_PERIOD)
        // Command_1 = FC_P_D; Command_2 = FC_CPL_D; PTLP_1 = $urandom() % 265; PTLP_2 = $urandom() % 265; 
        // #(CLK_PERIOD)
        // Command_1 = FC_NP_D; Command_2 = FC_CPL_D; PTLP_1 = $urandom() % 265; PTLP_2 = $urandom() % 265; 
        // #(CLK_PERIOD)
        // Command_1 = FC_P_D; Command_2 = FC_NP_D; PTLP_1 = $urandom() % 265; PTLP_2 = $urandom() % 265; 
        // #(CLK_PERIOD)
        // Command_1 = FC_CPL_D; Command_2 = FC_P_D; PTLP_1 = $urandom() % 265; PTLP_2 = $urandom() % 265; 
        // #(CLK_PERIOD)
        // Command_1 = FC_CPL_D; Command_2 = FC_NP_D; PTLP_1 = $urandom() % 265; PTLP_2 = $urandom() % 265; 
        // #(CLK_PERIOD)


        // Command_1 = FC_ERR; Command_2 = FC_NP_H; 
        // #(CLK_PERIOD)
        // Command_1 = FC_ERR; Command_2 = FC_CPL_H; 
        // #(CLK_PERIOD)

        // Command_1 = FC_P_H;    Command_2 = FC_ERR; 
        // #(CLK_PERIOD)
        // Command_1 = FC_NP_H;   Command_2 = FC_ERR; 
        // #(CLK_PERIOD)
        // Command_1 = FC_CPL_H;  Command_2 = FC_ERR; 
        // #(CLK_PERIOD)

        // Command_1 = FC_ERR; Command_2 = FC_P_D;   PTLP_2 = $urandom % 1024;
        // #(CLK_PERIOD)
        // Command_1 = FC_ERR; Command_2 = FC_NP_D;  PTLP_2 = $urandom % 1024;
        // #(CLK_PERIOD)
        // Command_1 = FC_ERR; Command_2 = FC_CPL_D; PTLP_2 = $urandom % 1024;
        // #(CLK_PERIOD)

        // Command_1 = FC_P_D; Command_2 = FC_ERR;   PTLP_1 = $urandom % 1024;
        // #(CLK_PERIOD)
        // Command_1 = FC_NP_D; Command_2 = FC_ERR;  PTLP_1 = $urandom % 1024;
        // #(CLK_PERIOD)
        // Command_1 = FC_CPL_D; Command_2 = FC_ERR; PTLP_1 = $urandom % 1024;
        // #(CLK_PERIOD)

        // Command_1 = FC_ERR; Command_2 = FC_ERR;
        // #(CLK_PERIOD)

        // Command_1 = FC_ERR; Command_2 = FC_DEFAULT;
        // #(CLK_PERIOD)


        // TypeFC = FC_NP; HdrFC = 150; DataFC = 150;
        // #(CLK_PERIOD)
        // TypeFC = FC_CPL; HdrFC = 200; DataFC = 2000;
        // #(CLK_PERIOD)
        // Command_1 = FC_P_D; Command_2 = FC_NP_D; PTLP_1 = 125; PTLP_2 = 200; 
        // #(CLK_PERIOD)
        // Command = FC_P_D; PTLP = 90; 
        // #(CLK_PERIOD)
        // Command = FC_NP_H; PTLP = 0; 
        // #(CLK_PERIOD)
        // Command = FC_NP_D; PTLP = 170;
        // #(CLK_PERIOD)
        // Command = FC_CPL_H; PTLP = 0; 
        // #(CLK_PERIOD)
        // Command = FC_CPL_D; PTLP = 260;
        // #(4*CLK_PERIOD)
        // u_Tx_FC.CL_Posted_Data = 1000;
        // u_Tx_FC.CL_Posted_Hdr  = 1000;
        #(CLK_PERIOD/2)
        repeat(50) begin
            k = $urandom % 8;
            j = $urandom % 8;
            $cast(Tx_FC_if.Command_1, k);
            $cast(Tx_FC_if.Command_2, j);
            Tx_FC_if.PTLP_1     = $urandom() % 1024;
            Tx_FC_if.PTLP_2     = $urandom() % 1024;
            #(CLK_PERIOD);
        end
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
        // Tx FC
        Tx_FC_Interface #(
            .FC_HDR_WIDTH(FC_HDR_WIDTH),
            .FC_DATA_WIDTH(FC_DATA_WIDTH)
        ) Tx_FC_if (
        );
    
    /********* Modules *********/
        // Tx_FC #(
        //     .FC_HDR_WIDTH(FC_HDR_WIDTH),
        //     .FC_DATA_WIDTH(FC_DATA_WIDTH)
        // ) u_Tx_FC (
        //     clk,
        //     arst,
        //     Tx_FC_if,
        //     Tx_FC_if
        // );

    Tx_FC #(
            .FC_HDR_WIDTH(FC_HDR_WIDTH),
            .FC_DATA_WIDTH(FC_DATA_WIDTH)
    ) u_Tx_FC ( 
        .clk(clk),
        .arst(arst),
        ._fc_arbiter(Tx_FC_if),
        .HdrFC (HdrFC),
        .DataFC (DataFC),
        .TypeFC (TypeFC)
    );

    
    endmodule: Tx_FC_Top
    /*********** END_OF_FILE ***********/
    