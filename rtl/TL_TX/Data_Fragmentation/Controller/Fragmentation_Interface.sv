/************************************************/
/* Module Name	: Fragmentation_Interface       */
/* Written By	: Mohamed Khaled Alahmady       */
/* Date		: 29-04-2024 			*/
/* Version	: V1			        */
/* Updates	: -	                        */
/* Dependencies	: -	                        */
/* Used		:       	                */
/************************************************/
interface Fragmentation_Interface;
    import Fragmentation_Package::*;
  
    // TLP FIFO Signals
    logic [TLP_FIFO_ADD_WIDTH : 0]              Count;
    logic                                       rd_en;
    logic                                       rd_mode;
    logic [TLP_FIFO_WIDTH - 1 : 0]              rd_data_1;
    logic [TLP_FIFO_WIDTH - 1 : 0]              rd_data_2;

    // DLL Signals
    logic                                       Halt_1;
    logic                                       Halt_2;
    logic                                       Throttle;
    logic                                       sop;
    logic                                       eop;
    logic                                       TLP_valid;
    valid_bytes_encoding                        Valid_Bytes;
    logic [DLL_LENGTH_WIDTH - 1 : 0]            Length;
    logic [DLL_TLP_WIDTH - 1 : 0]               TLP;

    // ECRC Signals
    logic [ECRC_MESSAGE_WIDTH - 1 : 0]          ecrc_Message;
    logic [ECRC_LENGTH_WIDTH - 1 : 0]           ecrc_Length;
    logic                                       ecrc_EN;
    logic [ECRC_POLY_WIDTH - 1 : 0]             ecrc_Seed;
    logic 				                        ecrc_Seed_Load;
    logic [ECRC_POLY_WIDTH - 1 : 0]             ecrc_Result_comb;
    logic [ECRC_POLY_WIDTH - 1 : 0]             ecrc_Result_reg;

    // Fragmentation and TLP FIFO Interface
    modport FRAGMENTATION_TLP_FIFO (
        input   Count,
                rd_data_1,
                rd_data_2,

        output  rd_en,
                rd_mode
    );

    // TLP FIFO and Fragmentation Interface
    modport TLP_FIFO_FRAGMENTATION (
        output  Count,
                rd_data_1,
                rd_data_2,

        input   rd_en,
                rd_mode       
    );

    // Fragmentation and DLL Interface
    modport FRAGMENTATION_DLL (
        input   Halt_1,
                Halt_2,
                Throttle,

        output  sop,
                eop,
                TLP_valid,
                Valid_Bytes,
                Length,
                TLP
    );

    // DLL and Fragmentation Interface
    modport DLL_FRAGMENTATION (
        output  Halt_1,
                Halt_2,
                Throttle,

        input   sop,
                eop,
                TLP_valid,
                Valid_Bytes,
                Length,
                TLP
    );

    // Fragmentation and ecrc Interface
    modport FRAGMENTATION_ECRC (
        input   ecrc_Result_comb,
                ecrc_Result_reg,

        output  ecrc_Message,
                ecrc_Length,
                ecrc_EN,
                ecrc_Seed,
                ecrc_Seed_Load
    );

    // ecrc and Fragmentation Interface
    modport ECRC_FRAGMENTATION (
        output  ecrc_Result_comb,
                ecrc_Result_reg,

        input   ecrc_Message,
                ecrc_Length,
                ecrc_EN,
                ecrc_Seed,
                ecrc_Seed_Load
    );

endinterface: Fragmentation_Interface
