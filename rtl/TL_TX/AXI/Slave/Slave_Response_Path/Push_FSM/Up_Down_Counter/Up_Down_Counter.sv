/* Module Name	: Up_Down_Counter         	    */
/* Written By	: Ahmady                     	*/
/* Date			: 27-03-2024					*/
/* Version		: V_2							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: -							    */
module Up_Down_Counter (
    input bit clk,
    input bit arst,
    Up_Down_Counter_Interface.DUT _if
);

/* Packages */
import axi_slave_package::*;

/* Parameters */

/* Internal Signals */

/* Assign Statements */

/* Always Blocks */
always_ff @(posedge clk or negedge arst) begin : Count_Calculation
    if (!arst) begin
        _if.Count   <= '0;
    end
    else begin
        if (_if.Load == TRUE) begin
            _if.Count   <= _if.Load_Count;
        end
        else if (_if.En == TRUE) begin
            case (_if.Mode)
                UP: begin
                    _if.Count   <= (_if.Count == _if.MAX_COUNT - 1) ? (_if.MAX_COUNT - 1) : _if.Count + 1;
                end
                DOWN: begin
                    _if.Count   <= (_if.Count == '0) ? '0 : _if.Count - 1;
                end 
                default: begin
                end 
            endcase
        end
        else begin
            _if.Count   <= '0;
        end
    end
end

always_comb begin : Done_Calculation
    // if need to check for counter reach both max or zero
    // _if.Done = (_if.En && ((_if.Count == _if.MAX_COUNT - 1) || (_if.Count == '0))) ? TRUE : FALSE;
    // if need to check for counter reach zero only
    _if.Done = (_if.En && (_if.Count == '0)) ? TRUE : FALSE;
end

/* Instantiations */

endmodule: Up_Down_Counter
/*********** END_OF_FILE ***********/
