/* Module Name	: Tx_FC_Interface               */
/* Written By	: Ahmady                     	*/
/* Date			: 9-04-2024 					*/
/* Version		: V_1			                */
/* Updates		: -			                    */
/* Dependencies	: -				                */
/* Used			: -			                    */
// `timescale 1ns/1ps
interface Tx_FC_Interface #(
    parameter   FC_HDR_WIDTH    = 12,
                FC_DATA_WIDTH   = 16
);
    import Tx_Arbiter_Package::*;
    logic [9:0]                     PTLP_1;
    logic [9:0]                     PTLP_2;
    FC_command_t                    Command_1;
    FC_command_t                    Command_2;
    FC_result_t                     Result;
    // failed, sucess1, sucess2

    // FC and Arbiter Interface
    modport FC_ARBITER (
        input   PTLP_1,
                PTLP_2,
                Command_1,
                Command_2,

        output  Result
    );

    // Arbiter and FC Interface
    modport ARBITER_FC (
        input   Result,

        output  PTLP_1,
                PTLP_2,
                Command_1,
                Command_2        
    );


endinterface: Tx_FC_Interface
