/********************************************************************/
/* Module Name	: ecrc_if.sv                                	    */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 27-03-2024					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: -							                        */
/* Summary:  This file includes interface of ecrc block             */
/********************************************************************/

import Fragmentation_Package::*;


// Define the interface of buffer used in ECRC block

interface ecrc_if ();

    logic [DATA_ECRC_IN_WIDTH - 1 : 0]          CRC_i_Message       ; 
    logic [ECRC_LENGTH_WIDTH - 1  : 0]          CRC_i_Length        ;
    logic                                       CRC_i_EN            ;
    logic [POLY_WIDTH - 1 : 0]                  CRC_i_Seed          ;
    logic                                       CRC_i_Seed_Load     ;
    logic [POLY_WIDTH - 1 : 0]                  CRC_o_CRC           ;


    modport ecrc_if (
                input   CRC_i_Message,
                        CRC_i_Length,
                        CRC_i_EN,
                        CRC_i_Seed,
                        CRC_i_Seed_Load,
                output  CRC_o_CRC                      
    );
    
    modport arbiter_ecrc (
        output      CRC_i_Message,
                    CRC_i_Length,
                    CRC_i_EN,
                    CRC_i_Seed,
                    CRC_i_Seed_Load,
        input       CRC_o_CRC                      
);



endinterface : ecrc_if
