/* Module Name	: Slave_Internal_Response_if    */
/* Written By	: Ahmady                     	*/
/* Date			: 27-03-2024			        */
/* Version		: V_1	        		        */
/* Updates		: -				                */
/* Dependencies	: -	        			        */
/* Used			: -	         		            */
//`timescale 1ns/1ps
interface Slave_Internal_Response_if;
    import axi_slave_package::*;

    // Interface Between "B Pop FSM" and "AW Push, Pop FSM"
    logic [ID_WIDTH - 1 : 0] BID;
    Resp_t                   BRESP;
    logic                    BVALID;

    // Interface Between "R Pop FSM" and "AR Push, Pop FSM"
    logic [ID_WIDTH - 1 : 0] RID;
    Resp_t                   RRESP;
    logic                    RVALID;

    modport B_TO_AW (
        input       BID,
                    BRESP,
                    BVALID

    );

    modport AW_TO_B (
        output      BID,
                    BRESP,
                    BVALID

    );

    modport R_TO_AR (
        input       RID,
                    RRESP,
                    RVALID

    );

    modport AR_TO_R (
        output      RID,
                    RRESP,
                    RVALID

    );

endinterface: Slave_Internal_Response_if
