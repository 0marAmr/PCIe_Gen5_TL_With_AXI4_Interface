/* Module Name	: Up_Down_Counter_tb         	*/
/* Written By	: Ahmady                     	*/
/* Date			: 27-03-2024					*/
/* Version		: V_2							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: -							    */
//`timescale 1ns/1ps
module Up_Down_Counter_tb (Up_Down_Counter_Interface _if);

/* Packages */
import Up_Down_Counter_Package::*;

/* Parameters */
localparam CLK_PERIOD = 10;

/* Internal Signals */

/* Initial Blocks */
initial begin
    _if.arst = FALSE; _if.En = FALSE; _if.Load = FALSE; _if.Load_Count = '0; _if.Mode = UP;
    #CLK_PERIOD
    _if.arst = TRUE; _if.En = TRUE; _if.Load = FALSE; _if.Load_Count = '0; _if.Mode = UP;
    #(_if.MAX_COUNT*CLK_PERIOD)
    _if.arst = TRUE; _if.En = TRUE; _if.Load = FALSE; _if.Load_Count = '0; _if.Mode = DOWN;
    #(_if.MAX_COUNT*CLK_PERIOD)
    _if.arst = TRUE; _if.En = TRUE; _if.Load = TRUE; _if.Load_Count = 3; _if.Mode = DOWN;
    #(CLK_PERIOD)
    _if.arst = TRUE; _if.En = TRUE; _if.Load = FALSE; _if.Load_Count = 6; _if.Mode = DOWN;
    #(_if.MAX_COUNT*CLK_PERIOD)
    $stop();
end
/* Assign Statements */

/* Always Blocks */

/* Instantiations */

endmodule: Up_Down_Counter_tb
/*********** END_OF_FILE ***********/
