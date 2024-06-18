/********************************************************************/
/* Module Name	: axi_slave_package.sv                    		    */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 27-03-2024					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: AXI and AXI Bridge                                */
/* Summary:  This file includes the parameters used in AXI Channels */
/*           and for FIFOs & Data Type Definition for FSMs          */
/********************************************************************/

package axi_slave_package ;
    /***********************************************************/
    /*------------ PARAMETERS For Channels ------------------ */ 
        localparam      ADDR_WIDTH            = 64   ,
                        AXI_MAX_NUM_BYTES     = 128  ,   // per beat, we can send 128 Byte as max. payload
                        AXI_MAX_NUM_TRANSFERS = 256  ,   // maximum number of beats 
        
                        /* mapping is   AWUSER [1:0] --> Request Type (00 >> Default, 01 >> Memory, 10 >> IO & 11 >> Rsv'd)
                        AWUSER [2]   -->  Address Type (0 >> 32-bit Address, 1 >> 32-bit Address)        */

                        AWUSER_WIDTH          =  3   ,  

        /* mapping is   ARUSER [1:0] -->  Request Type (00 >> Default, 01 >> Memory, 10 >> IO & 11 >> Rsv'd)
                        ARUSER [2]   -->  Address Type (0 >> 32-bit Address, 1 >> 32-bit Address)        
                        AWUSER [9:3] -->  Message Code */
                        ARUSER_WIDTH          =  11  ,

                        AxBURST_WIDTH         =  11  ,
                        xRESP_WIDTH           =  2   ,  
                        AxSIZE_WIDTH          =  3   ,
                        WSTRB_WIDTH           = AXI_MAX_NUM_BYTES ; 

    
    /***********************************************************/
    /*------------ PARAMETERS for FIFOs --------------------- */ 
        
        // Depth of FIFOs
        localparam  AWFIFO_DEPTH =   256  ,  // Usually it will be same for all fifos
                    ARFIFO_DEPTH =   256  ,
                    WFIFO_DEPTH  =   256  ,
                    RFIFO_DEPTH  =   256  ,
                    BFIFO_DEPTH  =   256  ;

        // Width of location in FIFOs
        localparam  AWFIFO_WIDTH = $clog2(AWFIFO_DEPTH) + ADDR_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS) + AxSIZE_WIDTH + AxBURST_WIDTH + AWUSER_WIDTH + WSTRB_WIDTH ,
                    ARFIFO_WIDTH = $clog2(ARFIFO_DEPTH) + ADDR_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS) + AxSIZE_WIDTH + AxBURST_WIDTH + ARUSER_WIDTH ,
                    WFIFO_WIDTH  = AXI_MAX_NUM_BYTES*8; // + $clog2(WFIFO_DEPTH) + $clog2(AXI_MAX_NUM_BYTES) + 1  ,

        localparam  B_FIFO_DATA_WIDTH                   = 10,       // BID: 8bits, BRESP: 2bits
                    B_FIFO_DEPTH                        = 16,
                    R_FIFO_DATA_WIDTH                   = 1034,     // RID: 8bits, RRESP: 2bits, RDATA: 32 DW (1024 bits) 
                    R_FIFO_DEPTH                        = 16;

                        
    /***********************************************************/
    /*------------ PARAMETERS for FIFOs --------------------- */
        localparam CLK_PERIOD = 10; // define clock period of AXI  


    /***********************************************************/
    /*--------------- Data Type Definition ------------------- */ 
                        
    typedef enum logic [1:0] {wr_Idle = 2'b00 , AW_Push = 2'b10  , W_Push = 2'b11 , waiting_beat = 2'b01  }   request_push_fsm_wr_state ;   // state used in fsm of write requests
    typedef enum logic       {rd_Idle = 1'b0 , AR_Push = 1'b1  }           request_push_fsm_rd_state ;   // state used in fsm of read requests




    /**************************************************************/
    //----------------------------- Parameter Definition ------------------------//

    localparam   DW                      = 4  * 8   ,          /* DW ---> Data Width in bits      */
                HDR_WIDTH               = 4  * DW  ,          // HDR width in bits 
                FMT_WIDTH               = 3        ,
                TYP_WIDTH               = 5        , 
                TC_WIDTH                = 3        ,
                ATTR_WIDTH              = 2        ,
                AT_WIDTH                = 2        ,
                LENGTH_WIDTH            = 10       ,
                PH_WIDTH                = 2        ,
                TAG_WIDTH               = 8        ,
                FIRST_BYTE_EN_WIDTH     = 4        ,
                LAST_BYTE_EN_WIDTH      = 4        ,
                REQUESTER_ID_WIDTH      = 16       ,
                FIRST_ADDR_WIDTH        = 30       ,
                SECOND_ADDR_WIDTH       = 32       ;
 

                //------------------------------ definition TLP datatype ---------------------//

                 /******************** TLP FMT Encoding ********************/
    typedef enum logic [2:0] {
        TLP_FMT_3DW,            // 000 
        TLP_FMT_4DW,            // 001
        TLP_FMT_3DW_DATA,       // 010 
        TLP_FMT_4DW_DATA,       // 011
        TLP_PREFIX              // 100
    } fmt_t;

        typedef struct packed {

            // BYTE 0   --  BYTE 1 -- BYTE 2 -- BYTE 3 
        fmt_t                       FMT ;      /* Format field of TLP header*/
        logic  [TYP_WIDTH - 1 : 0]  TYP ;      /* Type field of TLP Header */
        logic                       T9  ;
        logic  [TC_WIDTH - 1 : 0 ]  TC  ;      /* Traffic Class Field     */
        logic                       T8  ;     
        logic                       ATTR ;
        logic                       LN ;
        logic                       TH ;
        logic                       TD ;
        logic                       EP ;
        logic  [ATTR_WIDTH - 1 : 0] Attr ;
        logic  [AT_WIDTH - 1 : 0]   AT;         /* Attribute field        */
        logic  [LENGTH_WIDTH - 1: 0] Length;     /* Length field           */

            // BYTE 4   --  BYTE 5 -- BYTE 6 -- BYTE 7
        logic  [REQUESTER_ID_WIDTH - 1 : 0] Requester_ID ; /* Requester ID */
        logic  [TAG_WIDTH - 1 : 0] Tag;         /* Tag field              */
        logic  [LAST_BYTE_EN_WIDTH - 1 : 0] last_DW_BE;
        logic  [FIRST_BYTE_EN_WIDTH - 1 : 0] first_DW_BE;
                            
            // BYTE 8   --  BYTE 9 -- BYTE 10 -- BYTE 11
        logic  [SECOND_ADDR_WIDTH - 1 : 0] Higher_Address; /* Higher address bits */ 
        
            // BYTE 12   --  BYTE 13 -- BYTE 14 -- BYTE 15
        logic  [FIRST_ADDR_WIDTH - 1 : 0]  Lower_Address; /* lower address bits  */
        logic  [PH_WIDTH - 1 : 0]   PH; /* PH field */

    } tlp_header_t;



    localparam REQUESTER_ID = 16'hffff;

    typedef enum reg[1:0] {wr_pop_Idle = 2'b00 , AW_Pop = 2'b10 , W_Pop = 2'b11 }                  request_pop_fsm_wr_state ;   // state used in fsm of write requests
    typedef enum reg      {rd_pop_Idle = 1'b0 , AR_Pop = 1'b1 }                                    request_pop_fsm_rd_state ;   // state used in fsm of read requests

   
    /******************** Completion Status ********************/
    typedef enum logic [2:0] {
        SC,                     // 000 >> Successful Completion
        UR,                     // 001 >> Unsupported Request
        CRS,                    // 010 >> Configuration Request Retry Status
        CA=4                    // 100 >> Completer Abort
    } Cpl_Status_t;

    /******************** Completion TLP Header ********************/
    typedef struct packed {
        // 1st DW
            fmt_t       fmt;
            logic [4:0] Type;
            logic       T9;
            logic [2:0] TC;
            logic       T8;
            logic       Attr1;
            logic       LN;
            logic       TH;
            logic       TD;
            logic       EP;
            logic [1:0] Attr2;
            logic [1:0] AT;
            logic [9:0] Length;
        // 2nd DW
            logic [15:0] Completer_ID;
            Cpl_Status_t Cpl_Status;
            logic        BCM;
            logic [11:0] Byte_Count;
        // 3rd DW
            logic [15:0] Requester_ID;
            logic [7:0] Tag;
            logic       Rsvd;
            logic [6:0] Lower_Address;
    } Cpl_TLP_HDR_t;
    
    /******************** TLP TYPE Encoding ********************/
    localparam logic [4:0]   TLP_TYPE_3DW_MRD      = 5'b0_0000,  // Memory Read Request (32-bits Address)         
                            TLP_TYPE_4DW_MRD      = 5'b0_0000,  // Memory Read Request (64-bits Address)        
                            TLP_TYPE_3DW_MRDLK    = 5'b0_0001,  // Memory Read Request-Locked (32-bits Address)        
                            TLP_TYPE_4DW_MRDLK    = 5'b0_0001,  // Memory Read Request-Locked (64-bits Address)        
                            TLP_TYPE_3DW_MWR      = 5'b0_0000,  // Memory Write Request (32-bits Address)        
                            TLP_TYPE_4DW_MWR      = 5'b0_0000,  // Memory Write Request (64-bits Address)        
                            TLP_TYPE_IOR          = 5'b0_0010,  // I/O Read Request        
                            TLP_TYPE_IOWR         = 5'b0_0010,  // I/O Write Request        
                            TLP_TYPE_CFGRD0       = 5'b0_0100,  // Configuration Read Type 0        
                            TLP_TYPE_CFGWR0       = 5'b0_0100,  // Configuration Write Type 0        
                            TLP_TYPE_CFGRD1       = 5'b0_0101,  // Configuration Read Type 1        
                            TLP_TYPE_CFGWR1       = 5'b0_0101,  // Configuration Write Type 1        
                            TLP_TYPE_TCFGRD       = 5'b1_1011,  // Deprecated TLP Type 4       
                            TLP_TYPE_TCFGWR       = 5'b1_1011,  // Deprecated TLP Type 5        
                            TLP_TYPE_CPL          = 5'b0_1010,  // Completion Without Data        
                            TLP_TYPE_CPLD         = 5'b0_1010,  // Completion With Data        
                            TLP_TYPE_CPLLK        = 5'b0_1011,  // Completion For Locked Memory Read Without Data        
                            TLP_TYPE_CPLDLK       = 5'b0_1011,  // Completion For Locked Memory Read With Data        
                            TLP_TYPE_FETCHADD     = 5'b0_1100,  // Fetch and Add AtomicOp Request        
                            TLP_TYPE_SWAP         = 5'b0_1101,  // Unconditional Swap AtomicOp Request        
                            TLP_TYPE_CAS          = 5'b0_1110;  // Compare and Swap AtomicOp Request        

    /******************** AXI RESP Encoding ********************/
    typedef enum logic [2:0] {
        OKAY,
        EXOKAY,
        SLVERR,
        DECERR,
        INVALID
    } Resp_t;

    /******************** Pop FSM States for B FIFO ********************/
    typedef enum logic [2:0] {
        B_IDLE, 
        B_POP, 
        B_POP_WAIT,
        B_AW,
        B_AW_WAIT,
        B_XXX 
    } B_state_t; 

    /******************** Pop FSM States for R FIFO ********************/
    typedef enum logic [2:0] {
        R_IDLE, 
        R_POP,
        R_POP_WAIT,
        R_AR,
        R_AR_WAIT,
        R_XXX 
    } R_state_t; 

    /******************** B Channel Signal out from Slave ********************/
    typedef struct {
        logic [$clog2(AWFIFO_DEPTH) - 1:0]                 BID;
        logic                       BVALID;
        Resp_t                      BRESP;
    } B_Channel_Slv_t;

    /******************** B Channel Signal in Slave ********************/
    typedef struct {
        logic                       BREADY;        
    } B_Channel_Msr_t;

    /******************** R Channel Signal out from Slave ********************/
    typedef struct {
        logic [$clog2(AWFIFO_DEPTH) - 1:0]                 RID;
        logic                       RVALID;
        logic [1023 : 0]            RDATA;   
        Resp_t                      RRESP;
        logic                       RLAST;
    } R_Channel_Slv_t;

    /******************** R Channel Signal in Slave ********************/
    typedef struct {
        logic                       RREADY;     
    } R_Channel_Msr_t;

    /******************** Push FSM States for R, B FIFOs ********************/
    typedef enum logic [1:0] {
        IDLE_State, 
        B_State, 
        R_State, 
        XXX 
    } state_t; 

    /******************** Cpl and CplD Encoding ********************/
    typedef enum logic [1:0] {
        DEFAULT,
        CPL, 
        CPLD
    } cpl_t;   

    /******************** Sync FIFO States Encoding ********************/
    typedef enum logic [1:0] {
        IDLE,           // 00
        READ,           // 01
        WRITE,          // 10
        READ_WRITE      // 11
    } Operation;

    /******************** Counter Mode Encoding ********************/
    typedef enum logic {
        UP,
        DOWN
    } mode_t;    

    /******************** Boolean Type ********************/
    typedef enum logic {
        FALSE,
        TRUE
    } bool_t; 

    /******************** Parameters ********************/
    localparam REQUESTER_RECORDER_WIDTH      = $clog2(AWFIFO_DEPTH) + 1 , // AWID Width equals to clog2(AWFIFO_DEPTH)
               REQUESTER_RECORDER_DEPTH       = 2**TAG_WIDTH  ,  // the summation of AWFIFO and ARFIFO DEPTH
               REQUESTER_RECORDER_ADDR_WIDTH  = $clog2(REQUESTER_RECORDER_DEPTH ),  
               ID_WIDTH                       = $clog2(AWFIFO_DEPTH);  


endpackage
