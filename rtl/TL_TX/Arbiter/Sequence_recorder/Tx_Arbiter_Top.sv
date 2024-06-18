/* Module Name	: Tx_Arbiter_Top         	    */
/* Written By	: Ahmady                     	*/
/* Date			: 27-03-2024					*/
/* Version		: V_2							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: -							    */
/* Future Work  :                               */
module Tx_Arbiter_Top;
bit clk;
bit arst;

/* Packages */
import Tx_Arbiter_Package::*;

/* Parameters */
localparam CLK_PERIOD = 10;

/* Internal Signals */
 
/* Useful Functions */

/* Assign Statements */

/* Initial Blocks */
initial begin
    forever #(CLK_PERIOD / 2) clk = ~clk;
end

initial begin
    arst = 1'b0; A2P_1_if.Valid = 1'b0; A2P_2_if.Valid = 1'b0; Master_if.Valid = 1'b0; Rx_Router_if.Valid = 1'b0; 
    #CLK_PERIOD
    arst = 1'b1; 
    repeat(5) begin
        A2P_1_if.Valid              = $urandom() % 2;
        A2P_2_if.Valid              = $urandom() % 2;
        Master_if.Valid             = $urandom() % 2;
        Rx_Router_if.Valid          = $urandom() % 4;         
        #(CLK_PERIOD);
    end
    #(2*CLK_PERIOD)
    $stop();
end

/* Always Blocks */

/* Instantiations */

/* Interfaces */
    Tx_Arbiter_A2P_1 #(
    ) A2P_1_if (
    );

    Tx_Arbiter_A2P_2 #(
    ) A2P_2_if (
    );

    Tx_Arbiter_Master #(
    ) Master_if (
    );

    Tx_Arbiter_Rx_Router #(
    ) Rx_Router_if (
    );

    Tx_Arbiter_Sequence_Recorder #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) Sequence_Recorder_if (
    );

/* Modules */
    Tx_Arbiter # (
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_Tx_Arbiter (
        clk,
        arst,
        // Interface with A2P_1 (Read)
        A2P_1_if,
        // Interface with A2P_1 (Write)
        A2P_2_if,
        // Interface with Master (Completion)
        Master_if,
        // Interface with Rx Router (Completion or Message)    
        Rx_Router_if,
        // Interface with Sequence Recorder
        Sequence_Recorder_if
    );

    Sequence_Recorder #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_Sequence_Recorder (
        clk,
        arst,
        Sequence_Recorder_if
    );

endmodule: Tx_Arbiter_Top
/*********** END_OF_FILE ***********/
