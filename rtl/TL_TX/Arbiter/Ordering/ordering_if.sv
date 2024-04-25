/********************************************************************/
/* Module Name	: ordering_if.sv                    		    */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 10-04-2024			            */
/* Version		: V1					    */
/* Updates		: -					    */
/* Dependencies	: -						    */
/* Used			: in Arbiter Modules                        */
/* Summary:  This file includes the rules for ordering model 
inside PCIe with respect the axi ordering rules                      */
/********************************************************************/
// import package
import Tx_Arbiter_Package::*;

interface ordering_if ;

    Req_Type_t                          first_trans, second_trans ;
    // Parameters need in posted requests and Completions 
    logic                               first_RO , first_IDO ; 
    logic                               second_RO, second_IDO ; 
    /* RO --> Attr [1] of Attr [1:0] , IDO --> Attr[2] */
    /* Attr  - Attr [1:0] -- > IDO - RO - No Snoop */
    logic [REQUESTER_ID_WIDTH - 1 : 0]  first_trans_ID, second_trans_ID ;
    // parameter used only for configuration following poster --> need to know IO/CFG wr Completion
    logic   [2:0]                       comp_typ; 
    /* Mapping: 001 --> IO_wr ,  010 --> CFG_wr , 011 --> MEM_wr ,  
                100 --> IO_rd ,  101 --> CFG_rd , 110 --> MEM_rd */

    bool_t                          ordering_result ;


    modport ORDERING_ARBITER_IF (
        input   first_trans,
                second_trans,
                first_RO,
                second_RO,
                first_IDO,
                second_IDO,
                first_trans_ID,
                second_trans_ID,
                comp_typ,
        output  ordering_result
    );

    modport ARBITER_ORDERING_IF (
        output  first_trans,
                second_trans,
                first_RO,
                second_RO,
                first_IDO,
                second_IDO,
                first_trans_ID,
                second_trans_ID,
                comp_typ,
        input  ordering_result
    );

endinterface : ordering_if

