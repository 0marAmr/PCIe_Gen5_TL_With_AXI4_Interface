/* Module Name	: Tx_Arbiter_Interface         	 */
/* Written By	: Ahmady                     	*/
/* Date			: 27-03-2024					*/
/* Version		: V_2							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: -							    */
/* Future Work  :                               */
interface Tx_Arbiter_A2P_1; 
    /* Packages */
    import Tx_Arbiter_Package::*;

    // Interface with A2P_1
    logic Valid;
    logic Grant;

    modport TX_ARBITER_A2P_1 (
        input   Valid,
        output  Grant
    );

    modport A2P_1_TX_ARBITER (
        input   Valid,
        output  Grant
    );
endinterface: Tx_Arbiter_A2P_1

/***************************************************************/
interface Tx_Arbiter_A2P_2; 
    /* Packages */
    import Tx_Arbiter_Package::*;

    // Interface with A2P_1
    logic Valid;
    logic Grant;

    modport TX_ARBITER_A2P_2 (
        input   Valid,
        output  Grant
    );

    modport A2P_2_TX_ARBITER (
        input   Valid,
        output  Grant
    );
endinterface: Tx_Arbiter_A2P_2

/***************************************************************/
interface Tx_Arbiter_Master; 
    /* Packages */
    import Tx_Arbiter_Package::*;

    // Interface with A2P_1
    logic Valid;
    logic Grant;

    modport TX_ARBITER_MASTER (
        input   Valid,
        output  Grant
    );

    modport A2P_1_TX_MASTER (
        input   Valid,
        output  Grant
    );
endinterface: Tx_Arbiter_Master

/***************************************************************/
interface Tx_Arbiter_Rx_Router; 
    /* Packages */
    import Tx_Arbiter_Package::*;

    // Interface with A2P_1
    /* Valid Encoding                               */
    /*  00   >> Nothing                             */
    /*  01   >> Nothing                             */
    /*  10   >> CFG Cpl                             */
    /*  11   >> ERR (Cpl + Msg)                     */
    /* Note:    Check for positive edge on valid[1] */
    /*          if positive edge occurred check     */
    /*          valid[0] to know it a completion    */ 
    /*          for config or error message         */  
    
    logic [1:0] Valid;
    logic       Grant;

    modport TX_ARBITER_MASTER (
        input   Valid,
        output  Grant
    );

    modport A2P_1_TX_MASTER (
        input   Valid,
        output  Grant
    );
endinterface: Tx_Arbiter_Rx_Router

/***************************************************************/
interface Tx_Arbiter_Sequence_Recorder #(
    parameter   DATA_WIDTH      = 8,
                FIFO_DEPTH      = 4,
                ADDR_WIDTH      = $clog2(FIFO_DEPTH) 
); 
    /* Packages */
    import Tx_Arbiter_Package::*;

    // Interface with A2P_1
    logic                   full;
    logic                   empty;
    logic [ADDR_WIDTH  : 0] available;
    logic                   wr_en;
    logic                   rd_en;
    logic [2:0]             wr_mode;
    logic [1:0]             rd_mode;
    Tx_Arbiter_Sources_t    wr_data_1;
    Tx_Arbiter_Sources_t    wr_data_2;
    Tx_Arbiter_Sources_t    wr_data_3;
    Tx_Arbiter_Sources_t    wr_data_4;

    Tx_Arbiter_Sources_t    rd_data_1;
    Tx_Arbiter_Sources_t    rd_data_2;


    modport ARBITER_FSM_SEQUENCE_RECORDER (
        output  rd_en,
                wr_en,
                wr_mode,
                rd_mode,
                wr_data_1,
                wr_data_2,
                
        input   available,
                rd_data_1,
                rd_data_2

    );


    modport SEQUENCE_RECORDER_ARBITER_FSM (
        input   rd_en,
                wr_en,
                wr_mode,
                rd_mode,
                wr_data_1,
                wr_data_2,
                
        output  available,
                rd_data_1,
                rd_data_2

    );




    modport TX_ARBITER_SEQUENCE_RECORDER (
        output  wr_en,
                rd_en,
                wr_mode,
                rd_mode,
                wr_data_1,
                wr_data_2,
                wr_data_3,
                wr_data_4,

        input   empty,
                full,
                available,
                rd_data_1,
                rd_data_2
    );

    modport SEQUENCE_RECORDER_TX_ARBITER (
        input   wr_en,
                rd_en,
                wr_mode,
                rd_mode,
                wr_data_1,
                wr_data_2,
                wr_data_3,
                wr_data_4,

        output  empty,
                full,
                available,
                rd_data_1,
                rd_data_2
    );
endinterface: Tx_Arbiter_Sequence_Recorder
/*********** END_OF_FILE ***********/
