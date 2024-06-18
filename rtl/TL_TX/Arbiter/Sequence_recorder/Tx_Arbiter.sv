/* Module Name	: Tx_Arbiter         	        */
/* Written By	: Ahmady                     	*/
/* Date			: 27-03-2024					*/
/* Version		: V_2							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: -							    */
/* Future Work  :                               */
module Tx_Arbiter # (
    DATA_WIDTH      = 8,
    FIFO_DEPTH      = 10,
    ADDR_WIDTH      = $clog2(FIFO_DEPTH)
)(
    input bit clk,
    input bit arst,
    // Interface with A2P_1 (Read)
    input logic                a2p1_valid,
    // Interface with A2P_1 (Write)
    input logic                a2p2_valid,
    // Interface with Master (Completion)
    input logic                master_valid,
    // Interface with Rx Router (Completion or Message)    
    input logic [1:0]           rx_router_valid,
    // Interface with Sequence Recorder (Store Sequence of 4 sources)
    Tx_Arbiter_Sequence_Recorder.TX_ARBITER_SEQUENCE_RECORDER    _Sequence_Recorder_if
);

/* Packages */
import Tx_Arbiter_Package::*;

/* Parameters */

/* Internal Signals */
// Delayed Versions of Valid signals for all sources to "Tx Arbiter"
logic A2P_1_delayed_valid;
logic A2P_2_delayed_valid;
logic Master_delayed_valid;
logic Rx_Router_delayed_valid;

// Signals indicate that positive edge occurs for each Valid Signal: pe "Positive Edge"
logic A2P_1_pe_valid;
logic A2P_2_pe_valid;
logic Master_pe_valid;
logic Rx_Router_pe_valid;
 
/* Useful Functions */

/* Assign Statements */

/* Always Blocks */
always_ff @(posedge clk or negedge arst) begin : calc_delayed_valid
    if (!arst) begin
        A2P_1_delayed_valid       <= 1'b0;
        A2P_2_delayed_valid       <= 1'b0;
        Master_delayed_valid      <= 1'b0;
        Rx_Router_delayed_valid   <= 1'b0;
    end
    else begin
        A2P_1_delayed_valid       <= a2p1_valid;
        A2P_2_delayed_valid       <= a2p2_valid;
        Master_delayed_valid      <= master_valid;
        Rx_Router_delayed_valid   <= rx_router_valid[1];
    end
end

always_comb begin : calc_pe_valid
    A2P_1_pe_valid      = a2p1_valid           & (~A2P_1_delayed_valid);
    A2P_2_pe_valid      = a2p2_valid           & (~A2P_2_delayed_valid);
    Master_pe_valid     = master_valid          & (~Master_delayed_valid);
    Rx_Router_pe_valid  = rx_router_valid[1]    & (~Rx_Router_delayed_valid);
end

// always_ff @(posedge clk or negedge arst) begin : calc_wr_en
//     if (!arst) begin
//         _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b0;
//         _Sequence_Recorder_if.wr_mode_tx_arbiter       <= '0; 
//         _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= NO_SOURCE;
//         _Sequence_Recorder_if.wr_data_2_tx_arbiter     <= NO_SOURCE;
//         _Sequence_Recorder_if.wr_data_3_tx_arbiter     <= NO_SOURCE;
//         _Sequence_Recorder_if.wr_data_4_tx_arbiter     <= NO_SOURCE;
//     end
//     else begin
//         case ({A2P_1_pe_valid, A2P_2_pe_valid, Master_pe_valid, Rx_Router_pe_valid})
//             // 4 valid
//                 // push 4 positions in "Sequence Recorder", need to prioritize between them which one first and second and so on..
//                 4'b1111 : begin
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= 4;
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b1;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= A2P_1;
//                     _Sequence_Recorder_if.wr_data_2_tx_arbiter     <= A2P_2;
//                     _Sequence_Recorder_if.wr_data_3_tx_arbiter     <= MASTER;
//                     _Sequence_Recorder_if.wr_data_4_tx_arbiter     <= (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;
//                 end
//             // 3 valid
//                 // push 3 positions in "Sequence Recorder", need to prioritize between them which one first and second and so on..                    
//                 4'b0111 : begin
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= 3;
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b1;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= A2P_2;
//                     _Sequence_Recorder_if.wr_data_2_tx_arbiter     <= MASTER;
//                     _Sequence_Recorder_if.wr_data_3_tx_arbiter     <= (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;
//                 end
//                 4'b1011 : begin
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= 3;
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b1;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= A2P_1;
//                     _Sequence_Recorder_if.wr_data_2_tx_arbiter     <= MASTER;
//                     _Sequence_Recorder_if.wr_data_3_tx_arbiter     <= (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;                    
//                 end
//                 4'b1101 : begin
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= 3;
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b1;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= A2P_1;
//                     _Sequence_Recorder_if.wr_data_2_tx_arbiter     <= A2P_2;
//                     _Sequence_Recorder_if.wr_data_3_tx_arbiter     <= (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;
//                 end
//                 4'b1110 : begin
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= 3;
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b1;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= A2P_1;
//                     _Sequence_Recorder_if.wr_data_2_tx_arbiter     <= A2P_2;
//                     _Sequence_Recorder_if.wr_data_3_tx_arbiter     <= MASTER;
//                 end
//             // 2 valid
//                 // push 2 positions in "Sequence Recorder", need to prioritize between them which one first and second and so on..
//                 4'b1100 : begin
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= 2;
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b1;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= A2P_1;
//                     _Sequence_Recorder_if.wr_data_2_tx_arbiter     <= A2P_2;
//                 end
//                 4'b1010 : begin
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= 2;
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b1;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= A2P_1;
//                     _Sequence_Recorder_if.wr_data_2_tx_arbiter     <= MASTER;                    
//                 end
//                 4'b1001 : begin
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= 2;
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b1;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= A2P_1;
//                     _Sequence_Recorder_if.wr_data_2_tx_arbiter     <= (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;
//                 end
//                 4'b0110 : begin
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= 2;
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b1;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= A2P_2;
//                     _Sequence_Recorder_if.wr_data_2_tx_arbiter     <= MASTER;
//                 end
//                 4'b0101 : begin
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= 2;
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b1;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= A2P_2;
//                     _Sequence_Recorder_if.wr_data_2_tx_arbiter     <= (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;
//                 end
//                 4'b0011 : begin
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= 2;
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b1;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= MASTER;
//                     _Sequence_Recorder_if.wr_data_2_tx_arbiter     <= (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;
//                 end
//             // 1 valid
//                 4'b1000 : begin
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= 1;
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b1;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= A2P_1;
//                 end
//                 4'b0100 : begin
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= 1;
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b1;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= A2P_2;                    
//                 end
//                 4'b0010 : begin
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= 1;
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b1;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= MASTER;
//                 end
//                 4'b0001 : begin
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= 1;
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b1;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;
//                 end
//             default: begin
//                     _Sequence_Recorder_if.wr_en_tx_arbiter         <= 1'b0;
//                     _Sequence_Recorder_if.wr_mode_tx_arbiter       <= '0;
//                     _Sequence_Recorder_if.wr_data_1_tx_arbiter     <= NO_SOURCE;
//                     _Sequence_Recorder_if.wr_data_2_tx_arbiter     <= NO_SOURCE;
//                     _Sequence_Recorder_if.wr_data_3_tx_arbiter     <= NO_SOURCE;
//                     _Sequence_Recorder_if.wr_data_4_tx_arbiter     <= NO_SOURCE;
//             end
//         endcase
//     end
// end

always_comb begin : calc_wr_en
    case ({A2P_1_pe_valid, A2P_2_pe_valid, Master_pe_valid, Rx_Router_pe_valid})
        // 4 valid
            // push 4 positions in "Sequence Recorder", need to prioritize between them which one first and second and so on..
            4'b1111 : begin
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = 4;
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b1;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = A2P_1;
                _Sequence_Recorder_if.wr_data_2_tx_arbiter     = A2P_2;
                _Sequence_Recorder_if.wr_data_3_tx_arbiter     = MASTER;
                _Sequence_Recorder_if.wr_data_4_tx_arbiter     = (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;
            end
        // 3 valid
            // push 3 positions in "Sequence Recorder", need to prioritize between them which one first and second and so on..                    
            4'b0111 : begin
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = 3;
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b1;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = A2P_2;
                _Sequence_Recorder_if.wr_data_2_tx_arbiter     = MASTER;
                _Sequence_Recorder_if.wr_data_3_tx_arbiter     = (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;
            end
            4'b1011 : begin
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = 3;
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b1;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = A2P_1;
                _Sequence_Recorder_if.wr_data_2_tx_arbiter     = MASTER;
                _Sequence_Recorder_if.wr_data_3_tx_arbiter     = (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;                    
            end
            4'b1101 : begin
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = 3;
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b1;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = A2P_1;
                _Sequence_Recorder_if.wr_data_2_tx_arbiter     = A2P_2;
                _Sequence_Recorder_if.wr_data_3_tx_arbiter     = (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;
            end
            4'b1110 : begin
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = 3;
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b1;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = A2P_1;
                _Sequence_Recorder_if.wr_data_2_tx_arbiter     = A2P_2;
                _Sequence_Recorder_if.wr_data_3_tx_arbiter     = MASTER;
            end
        // 2 valid
            // push 2 positions in "Sequence Recorder", need to prioritize between them which one first and second and so on..
            4'b1100 : begin
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = 2;
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b1;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = A2P_1;
                _Sequence_Recorder_if.wr_data_2_tx_arbiter     = A2P_2;
            end
            4'b1010 : begin
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = 2;
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b1;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = A2P_1;
                _Sequence_Recorder_if.wr_data_2_tx_arbiter     = MASTER;                    
            end
            4'b1001 : begin
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = 2;
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b1;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = A2P_1;
                _Sequence_Recorder_if.wr_data_2_tx_arbiter     = (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;
            end
            4'b0110 : begin
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = 2;
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b1;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = A2P_2;
                _Sequence_Recorder_if.wr_data_2_tx_arbiter     = MASTER;
            end
            4'b0101 : begin
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = 2;
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b1;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = A2P_2;
                _Sequence_Recorder_if.wr_data_2_tx_arbiter     = (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;
            end
            4'b0011 : begin
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = 2;
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b1;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = MASTER;
                _Sequence_Recorder_if.wr_data_2_tx_arbiter     = (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;
            end
        // 1 valid
            4'b1000 : begin
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = 1;
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b1;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = A2P_1;
            end
            4'b0100 : begin
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = 1;
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b1;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = A2P_2;                    
            end
            4'b0010 : begin
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = 1;
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b1;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = MASTER;
            end
            4'b0001 : begin
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = 1;
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b1;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = (rx_router_valid[0]) ? RX_ROUTER_ERR : RX_ROUTER_CFG;
            end
        default: begin
                _Sequence_Recorder_if.wr_en_tx_arbiter         = 1'b0;
                _Sequence_Recorder_if.wr_mode_tx_arbiter       = '0;
                _Sequence_Recorder_if.wr_data_1_tx_arbiter     = NO_SOURCE;
                _Sequence_Recorder_if.wr_data_2_tx_arbiter     = NO_SOURCE;
                _Sequence_Recorder_if.wr_data_3_tx_arbiter     = NO_SOURCE;
                _Sequence_Recorder_if.wr_data_4_tx_arbiter     = NO_SOURCE;
        end
    endcase
end

/* Instantiations */

endmodule: Tx_Arbiter
/*********** END_OF_FILE ***********/
