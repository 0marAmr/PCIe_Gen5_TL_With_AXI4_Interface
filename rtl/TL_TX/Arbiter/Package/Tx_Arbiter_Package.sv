/********************************************************************/
/* Module Name	: Tx_Arbiter_Package.sv                    		    */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 27-03-2024					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: AXI and AXI Bridge                                */
/* Summary:  This file includes the parameters used Arbiter         */
/*           submodules                                             */
/********************************************************************/

package Tx_Arbiter_Package ;

    localparam      FC_HDR_WIDTH    = 12,
                    FC_DATA_WIDTH   = 16; 

    /******************** Tx Arbiter Sources Encoding ********************/
    typedef enum logic [2:0] {
        NO_SOURCE,
        A2P_1, // It is used for wirte requests
        A2P_2, // It is used for read requests
        MASTER,
        RX_ROUTER_CFG,
        RX_ROUTER_ERR
    } Tx_Arbiter_Sources_t;
    
    /******************** Boolean Type ********************/
    // typedef enum logic {
    //     FALSE,
    //     TRUE
    // } bool_t; 

    /******************** Request Recorder Parameters ********************/
    localparam      SEQ_DATA_WIDTH      = 3,
                    SEQ_FIFO_DEPTH      = 8; // consider rx router is 2 srcs 


    /******************** Request_type Type ********************/
    typedef enum logic [1:0] {
                    No_Req,
                    Posted_Req,
                    Non_Posted_Req,
                    Comp
    } Req_Type_t;

    /******************** Ordering Parameters ********************/
    // parameter   TRANS_ID_WIDTH          = 24    ,
    //             REQUESTER_ID_WIDTH      = 16    ;
                
    /******************** Ordering Parameters ********************/
  //  parameter   TRANS_ID_WIDTH          = 24    ,
  //              REQUESTER_ID_WIDTH      = 16    ;
                
    
    /******************** FC Type Encoding ********************/
    typedef enum logic [1:0] {
                    FC_P,      // 00
                    FC_NP,     // 01
                    FC_CPL,    // 10
                    FC_X
        } FC_type_t;
            
                /******************** FC Command Encoding ********************/
                /* 000 >> check FC_P_H      for TLP                    */
                /* 001 >> check FC_P_D      for TLP                    */
                /* 010 >> check FC_NP_H     for TLP                    */
                /* 011 >> check FC_NP_D     for TLP                    */
                /* 100 >> check FC_Cpl_H    for TLP                    */
                /* 101 >> check FC_Cpl_D    for TLP                    */
                /* 110 >> check FC_P_H      for TLP                    */
                /* 111 >> check FC_P_H      for TLP                    */
                typedef enum logic [2:0] {
					FC_DEFAULT,
					FC_P_H,
					FC_P_D,
					FC_NP_H,
					FC_NP_D,
					FC_CPL_H,
					FC_CPL_D,
					FC_ERR
				} FC_command_t;
            
                /******************** FC Result Encoding ********************/
                typedef enum logic [2:0] {
                    FC_INVALID,
                    FC_SUCCESS_1,
                    FC_SUCCESS_2,
                    FC_SUCCESS_1_2,
					FC_FAILED
                } FC_result_t;
            
            
                /********************** FSM of Arbiter **********************/
                typedef enum logic [2:0] {
                    ARBITER_IDLE,
                    TLP1_HDR,  // 1-  Check FC + Ordering, 2- Selection Done, 3- First Cycle of storing inside TLP Buffer 
                    TLP1_Data, // 1-  Only storing all Data of TLP1
                    TLP2_HDR,  // 1- First Cycle of storing inside TLP Buffer 
                    TLP2_Data  // 1-  Only storing all Data of TLP2 
                } arbiter_state;

endpackage

