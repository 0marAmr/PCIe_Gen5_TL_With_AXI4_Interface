/********************************************************************/
/* Module Name	: Fragmentation_Package.sv                    		*/
/* Written By	: Mohamed Khaled Alahmady                           */
/* Date			: 29-04-2024					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			:                                                   */
/********************************************************************/

package Fragmentation_Package;

    /******************** TLP FIFO ********************/
    localparam  DOUBLE_WORD        = 4 * 8,
                HDR_WIDTH           = 4  * DOUBLE_WORD, 
                DATA_WIDTH          = 32 * DOUBLE_WORD,
                TLP_FIFO_WIDTH      = 4 * DOUBLE_WORD + 2,                       // 4DW each location
                TLP_FIFO_DEPTH      = ((1024 ) / 4 ),            // (4DW x 256 = 1024 DOUBLE_WORD max TLP)
                TLP_FIFO_ADD_WIDTH  = $clog2(TLP_FIFO_DEPTH),      // 8 bits for 256 locations
				NO_LOC_WR_WIDTH     = 4 ,                           // $clog2((32+4)/4) = 4 bits //  1001 = 9 is the Max. No of loc. write
                WR_DATA_WIDTH  		= (36) * DOUBLE_WORD + 18,                    // Size of Data in is HDR + 32 dw Data
                BUFFER_ADDR_WIDTH   = $clog2(TLP_FIFO_DEPTH),
                COUNT_WIDTH         = 9;
    /******************** DLL ********************/
    localparam   DLL_VALID_BYTES_WIDTH       = 5,            // 5 bits for 32 bytes
                DLL_LENGTH_WIDTH            = 11,
                DLL_TLP_WIDTH               = 256;          // 8 DOUBLE_WORD = 32 bytes = 256 bits

    /******************** ECRC ********************/
    localparam   ECRC_MESSAGE_WIDTH       = 256,             // 5 bits for 32 bytes
                ECRC_LENGTH_WIDTH        = 4,
                ECRC_POLY_WIDTH          = 32;              // 8 DOUBLE_WORD = 32 bytes = 256 bits

    /******************** Fragmentation FSM States ********************/
    typedef enum logic [2:0]{
        FRAG_IDLE,
        FRAG_READ_1,
        FRAG_READ_2,
        FRAG_LOOP,
        FRAG_ECRC,
        FRAG_WAIT_1,
        FRAG_DUMMY
    } frag_state_t;
    localparam  FMT_LOC             = 127,
                FMT_START_LOC       = 127,
                FMT_END_LOC         = 129,
                LENGTH_START_LOC    = 98,
                LENGTH_END_LOC      = 107,
                TD_LOC              = 113;

    /******************** Valid_Bytes Encoding ********************/
    typedef enum logic [DLL_VALID_BYTES_WIDTH - 1 :0]{
        DW0 = 0,
        DW1 = 3,
        DW2 = 7,
        DW3 = 11,
        DW4 = 15,
        DW5 = 19,
        DW6 = 23,
        DW7 = 27,
        DW8 = 31
    } valid_bytes_encoding;

    parameter   FIRST_4TH_DW_WITH_2_BITS   = WR_DATA_WIDTH                                           ,   
                SECOND_4TH_DW_WITH_2_BITS  = FIRST_4TH_DW_WITH_2_BITS   - (4 * DOUBLE_WORD + 2'b10 ) ,    
                THIRD_4TH_DW_WITH_2_BITS   = SECOND_4TH_DW_WITH_2_BITS  - (4 * DOUBLE_WORD + 2'b10 ) ,     
                FOURTH_4TH_DW_WITH_2_BITS  = THIRD_4TH_DW_WITH_2_BITS   - (4 * DOUBLE_WORD + 2'b10 ) ,         
                FIFTH_4TH_DW_WITH_2_BITS   = FOURTH_4TH_DW_WITH_2_BITS  - (4 * DOUBLE_WORD + 2'b10 ) ,         
                SIXTH_4TH_DW_WITH_2_BITS   = FIFTH_4TH_DW_WITH_2_BITS   - (4 * DOUBLE_WORD + 2'b10 ) ,          
                SEVENTH_4TH_DW_WITH_2_BITS = SIXTH_4TH_DW_WITH_2_BITS   - (4 * DOUBLE_WORD + 2'b10 ) ,        
                EIGHTH_4TH_DW_WITH_2_BITS  = SEVENTH_4TH_DW_WITH_2_BITS - (4 * DOUBLE_WORD + 2'b10 ) ,      
                NINTH_4TH_DW_WITH_2_BITS   = EIGHTH_4TH_DW_WITH_2_BITS  - (4 * DOUBLE_WORD + 2'b10 ) ; 
                
endpackage: Fragmentation_Package
