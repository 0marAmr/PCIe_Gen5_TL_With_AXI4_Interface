/* Module Name	: P2A         	                */
/* Written By	: Ahmady                     	*/
/* Date			: 4-04-2024 					*/
/* Version		: V_2							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: -							    */
/* Future Work  :                               */
module P2A # (
)(
    input logic clk,
    input logic arst,
    // Interface with Push FSM
    P2A_Push_FSM_Interface.P2A_FSM          		 _push_if,
    // Interface with Rx Router
    P2A_Rx_Router_Interface.P2A_RX_ROUTER       	 _router_if,
    // Interface with Request Recorder
    Request_Recorder_if.P2A_REQUEST_RECORDER        _recorder_if
);

/* Packages */
import axi_slave_package::*;

/* Parameters */

/* Internal Signals */
cpl_t           Cpl_Type;
logic [9:0]     Cpl_Length;
logic [1033:0]  Cpl_Data;
logic [REQUESTER_RECORDER_WIDTH - 2 : 0]        ID_reg;

logic           wr_en;
logic [3:0]     wr_addr;
logic [8:0]     wr_data;

/* Useful Functions */
// Mapping between Axi Response and PCIe Completion Status
function logic [1:0] Response_Mapping (input logic [2:0] PCIe_Cpl_Status);
    case (PCIe_Cpl_Status)
        // need to know the actual mapping :(
        SC :      return OKAY;
        UR :      return EXOKAY;
        CRS:      return SLVERR;
        CA :      return DECERR;
        default:  return INVALID;
    endcase
endfunction

/* Assign Statements */

/* Always Blocks */
always_ff @(posedge clk or negedge arst) begin
    if (!arst) begin
        // Push FSM
        _push_if.Cpl_Type       <= DEFAULT;
        _push_if.Cpl_Length     <= '0;
        _push_if.Cpl_Data       <= '0;
        ID_reg                  <= '0;
        // Request Recorder
        // _recorder_if.resp_wr_en      <= 1'b1;
        // _recorder_if.resp_wr_addr    <= '0;
        // _recorder_if.resp_wr_data    <= '0;

    end
    else begin
        // Push FSM
        _push_if.Cpl_Type   <= Cpl_Type;
        _push_if.Cpl_Length <= Cpl_Length;
        _push_if.Cpl_Data   <= Cpl_Data;  
        // Request Recorder
        if (!_push_if.Cpl_Command) begin
            ID_reg          <= _recorder_if.resp_rd_data[REQUESTER_RECORDER_WIDTH - 1 : 1];
        end
    end
end

always_comb begin : P2A_Mapping
    // Push FSM
    Cpl_Type    = DEFAULT;
    Cpl_Length  = '0;
    Cpl_Data    = '0;

    // Rx Router
    _router_if.Resp_Grant = _push_if.Cpl_Grant;

    // Request Recorder
    _recorder_if.resp_wr_en      = 1'b0;
    _recorder_if.resp_wr_addr    = '0;
    _recorder_if.resp_wr_data    = '0;
    _recorder_if.resp_rd_addr    = '0;

    // P2A Logic
    if (_push_if.Cpl_Command) begin
        // enable "Push FSM"
        Cpl_Type   = CPLD;
        Cpl_Length = _router_if.Resp_HDR.Length;
        /*
            R_FIFO_if.FIFO_rd_data [R_FIFO_DATA_WIDTH - 1: 0] 
            RID     [R_FIFO_DATA_WIDTH - 1 : 1027]
            RDATA   [1026 : 3]
            RRESP   [2:1]
            RLAST   [0]
        */
        // Cpl_Data   = {_recorder_if.resp_rd_data[8:1], _router_if.Resp_Data, Response_Mapping(_router_if.Resp_HDR.Cpl_Status), 1'b0};
        Cpl_Data   = {ID_reg, _router_if.Resp_Data, Response_Mapping(_router_if.Resp_HDR.Cpl_Status), 1'b0};
        // Cpl_Data   = {'0, _router_if.Resp_Data};
    end
    else if (_router_if.Resp_Valid && !(_push_if.Cpl_Grant)) begin
        // check if there is previous request stored in "Request Recorder"
        _recorder_if.resp_rd_addr    =  _router_if.Resp_HDR.Tag;
        // check this location is valid
        if (_recorder_if.resp_rd_data[0] == 1'b1) begin
            // check that this is completion TLP without data
            if ((_router_if.Resp_HDR.fmt == TLP_FMT_3DW) && (_router_if.Resp_HDR.Type == TLP_TYPE_CPL)) begin
                // enable "Push FSM"
                Cpl_Type   = CPL;
                Cpl_Length = 1;
                // BID [7:0], BRESP [1:0]
                Cpl_Data   = {_recorder_if.resp_rd_data[REQUESTER_RECORDER_WIDTH - 1 : 1], Response_Mapping(_router_if.Resp_HDR.Cpl_Status)};
            end
            // check that this is completion TLP with data
            else if ((_router_if.Resp_HDR.fmt == TLP_FMT_3DW_DATA) && (_router_if.Resp_HDR.Type == TLP_TYPE_CPLD)) begin
                // enable "Push FSM"
                Cpl_Type   = CPLD;
                Cpl_Length = _router_if.Resp_HDR.Length;
                /*
                    R_FIFO_if.FIFO_rd_data [R_FIFO_DATA_WIDTH - 1: 0] 
                    RID     [R_FIFO_DATA_WIDTH - 1 : 1027]
                    RDATA   [1026 : 3]
                    RRESP   [2:1]
                    RLAST   [0]
                */

                Cpl_Data   = {_recorder_if.resp_rd_data[REQUESTER_RECORDER_WIDTH - 1 : 1], _router_if.Resp_Data, Response_Mapping(_router_if.Resp_HDR.Cpl_Status), 1'b0};
                // Cpl_Data   = {'0, _router_if.Resp_Data};
            end
        end
        else begin
        end
    end
    // flush "Request Recorder" only if "Push FSM" grant to take the completion
    if (_push_if.Cpl_Grant) begin
        _recorder_if.resp_wr_en      = 1'b1;
        _recorder_if.resp_wr_addr    =_router_if.Resp_HDR.Tag;
        _recorder_if.resp_wr_data    =  '0; // {'0, 1'b1};
    end
end

// always_comb begin : P2A_Mapping
//     // Push FSM
//     $cast(_push_if.Cpl_Type, '0);
//     _push_if.Cpl_Length = '0;
//     _push_if.Cpl_Data   = '0;

//     // Rx Router
//     _router_if.Resp_Grant = 1'b0;

//     // Request Recorder
//     _recorder_if.resp_wr_en      = 1'b0;
//     _recorder_if.resp_wr_addr    = '0;
//     _recorder_if.resp_wr_data    = '0;
//     _recorder_if.resp_rd_addr    = '0;

//     // P2A Logic
//     if (_push_if.Cpl_Command == 1'b1) begin
//         // enable "Push FSM"
//         _push_if.Cpl_Type   = CPLD;
//         _push_if.Cpl_Length = _router_if.Resp_HDR.Length;
//         // BID [7:0], BRESP [1:0], RDATA
//         /*
//             R_FIFO_if.FIFO_rd_data [R_FIFO_DATA_WIDTH - 1: 0] 
//             RID     [R_FIFO_DATA_WIDTH - 1 : 1026]
//             RDATA   [1025 : 2]
//             RRESP   [1:0]
//         */
//         _push_if.Cpl_Data   = {_recorder_if.resp_rd_data[8:1], _router_if.Resp_Data, Response_Mapping(_router_if.Resp_HDR.Cpl_Status)};
//     end
//     else if (_router_if.Resp_Valid) begin
//         // check if there is previous request stored in "Request Recorder"
//         _recorder_if.resp_rd_addr    =  _router_if.Resp_HDR.Tag;
//         // check this location is valid
//         if (_recorder_if.resp_rd_data[0] == 1'b1) begin
//             // check that this is completion TLP without data
//             if ((_router_if.Resp_HDR.fmt == TLP_FMT_3DW) && (_router_if.Resp_HDR.Type == TLP_TYPE_CPL)) begin
//                 // enable "Push FSM"
//                 _push_if.Cpl_Type   = CPL;
//                 _push_if.Cpl_Length = 1;
//                 // BID [7:0], BRESP [1:0]
//                 _push_if.Cpl_Data   = {_recorder_if.resp_rd_data[8:1], Response_Mapping(_router_if.Resp_HDR.Cpl_Status)};
//             end
//             // check that this is completion TLP with data
//             else if ((_router_if.Resp_HDR.fmt == TLP_FMT_3DW_DATA) && (_router_if.Resp_HDR.Type == TLP_TYPE_CPLD)) begin
//                 $display("Here");
//                 // enable "Push FSM"
//                 _push_if.Cpl_Type   = CPLD;
//                 _push_if.Cpl_Length = _router_if.Resp_HDR.Length;
//                 // BID [7:0], BRESP [1:0], RDATA
//                 /*
//                     R_FIFO_if.FIFO_rd_data [R_FIFO_DATA_WIDTH - 1: 0] 
//                     RID     [R_FIFO_DATA_WIDTH - 1 : 1026]
//                     RDATA   [1025 : 2]
//                     RRESP   [1:0]
//                 */
//                 // _push_if.Cpl_Data   = {_recorder_if.resp_rd_data[8:1], _router_if.Resp_Data, Response_Mapping(_router_if.Resp_HDR.Cpl_Status)};
//                 _push_if.Cpl_Data   = {'0, _router_if.Resp_Data};
//             end
//             // flush "Request Recorder"
//             _recorder_if.resp_wr_en      = 1'b1;
//             _recorder_if.resp_wr_addr    =_router_if.Resp_HDR.Tag;
//             _recorder_if.resp_wr_data    = '0;
//         end
//         else begin
//         end
//     end
// end


/* Instantiations */

endmodule: P2A
/*********** END_OF_FILE ***********/
