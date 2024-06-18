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
                FIFO_DEPTH      = 8,
                ADDR_WIDTH      = $clog2(FIFO_DEPTH) 
); 
    /* Packages */
    import Tx_Arbiter_Package::*;
    logic                   wr_en_tx_arbiter;
    logic [2:0]             wr_mode_tx_arbiter;
    Tx_Arbiter_Sources_t    wr_data_1_tx_arbiter;
    Tx_Arbiter_Sources_t    wr_data_2_tx_arbiter;
    Tx_Arbiter_Sources_t    wr_data_3_tx_arbiter;
    Tx_Arbiter_Sources_t    wr_data_4_tx_arbiter;

    modport TX_ARBITER_SEQUENCE_RECORDER (
        output  wr_en_tx_arbiter,
                wr_mode_tx_arbiter,
                wr_data_1_tx_arbiter,
                wr_data_2_tx_arbiter,
                wr_data_3_tx_arbiter,
                wr_data_4_tx_arbiter
    );

    modport SEQUENCE_RECORDER_TX_ARBITER (
        input   wr_en_tx_arbiter,
                wr_mode_tx_arbiter,
                wr_data_1_tx_arbiter,
                wr_data_2_tx_arbiter,
                wr_data_3_tx_arbiter,
                wr_data_4_tx_arbiter
    );
    
endinterface: Tx_Arbiter_Sequence_Recorder

interface Arbiter_FSM_Sequence_Recorder #(
    parameter   DATA_WIDTH      = 8,
                FIFO_DEPTH      = 8,
                ADDR_WIDTH      = $clog2(FIFO_DEPTH) 
); 
    /* Packages */
    import Tx_Arbiter_Package::*;
    logic                   wr_en;
    logic                   rd_en;
    logic [1:0]             wr_mode;
    logic [1:0]             rd_mode;
    Tx_Arbiter_Sources_t    wr_data_1;
    Tx_Arbiter_Sources_t    wr_data_2;
    Tx_Arbiter_Sources_t    rd_data_1;
    Tx_Arbiter_Sources_t    rd_data_2;
    logic [ADDR_WIDTH  : 0] available;




    modport ARBITER_FSM_SEQUENCE_RECORDER (
        output  rd_en,
                wr_en,
                wr_mode,
                rd_mode,
                wr_data_1,
                wr_data_2,
                
        input   rd_data_1,
                rd_data_2,
                available
    );
    
    modport SEQUENCE_RECORDER_ARBITER_FSM (
        input   rd_en,
                wr_en,
                wr_mode,
                rd_mode,
                wr_data_1,
                wr_data_2,
                
        output  rd_data_1,
                rd_data_2,
                available
    );

endinterface: Arbiter_FSM_Sequence_Recorder



/*********** END_OF_FILE ***********/
