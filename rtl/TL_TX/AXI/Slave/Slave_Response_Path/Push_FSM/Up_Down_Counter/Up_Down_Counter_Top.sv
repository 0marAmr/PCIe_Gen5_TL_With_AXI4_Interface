/* Module Name	: Up_Down_Counter_Top        	*/
/* Written By	: Ahmady                     	*/
/* Date			: 27-03-2024					*/
/* Version		: V_2							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: -							    */
//`timescale 1ns/1ps
module Up_Down_Counter_Top ();
/* Parameters */
localparam CLK_PERIOD = 10;

/* Internal Signals */
bit clk;

/* Assign Statements */

/* Initial Block */
initial begin
    $monitor("At time: %d, Count: %b", $time, _if.Count);
end

/* Always Blocks */
always  begin
    clk = ~clk;
    #(CLK_PERIOD/2);
end

/* Instantiations */
Up_Down_Counter_Interface #(
    .MAX_COUNT(10)
) _if (
    .clk(clk)
);

Up_Down_Counter       dut (_if.DUT);
Up_Down_Counter_tb    tb (_if.TB);

endmodule: Up_Down_Counter_Top
/*********** END_OF_FILE ***********/
