/* Module Name	: Up_Down_Counter_Interface     */
/* Written By	: Ahmady                     	*/
/* Date			: 27-03-2024		*/
/* Version		: V_1                   */
/* Updates		: -			*/
/* Dependencies	: -				*/
/* Used			: -			*/
// `timescale 1ns/1ps
interface Up_Down_Counter_Interface #(
    parameter   MAX_COUNT       = 8,
                COUNT_WIDTH     = $clog2(MAX_COUNT) 
);
    import axi_slave_package::*;
    logic En;                                       // counter enable to count up or down
    logic Load;                                     // enable for load new count
    logic [COUNT_WIDTH - 1 : 0] Load_Count;         // Count Value to start with it
    logic Mode;                                     // ctr signal for operation mode (0 for up and 1 for down)
    logic [COUNT_WIDTH - 1 : 0] Count;              // hold counter value
    logic Done;                                     // done signal raised when count reach max (up mode) or zero (down mode)
    // DUT
    modport DUT (
        input   En,
                Load,
                Load_Count,
                Mode,

        output  Count,
                Done
    );

    // TB
    modport TB (
        output  En,
                Load,
                Load_Count,
                Mode,

        input   Count,
                Done
    );
    
endinterface: Up_Down_Counter_Interface
