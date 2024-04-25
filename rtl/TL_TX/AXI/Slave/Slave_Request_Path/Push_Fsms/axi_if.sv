/********************************************************************/
/* Module Name	: axi_interface.sv                       		    */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 27-03-2024					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: -							                        */
/* Summary:  This file includes interface of AXI, including all      */
/*     signals of 5 channels with making modports used in design    */
/********************************************************************/



// Define the standard interface of axi (5 channels)

interface axi_if ();


    // import the defined package for axi
    import axi_slave_package::*;

    /*---------------------- AW Channel ---------------------- */ 
    logic [$clog2(AWFIFO_DEPTH ) -1          : 0 ]  AWID        ;
    logic [ADDR_WIDTH - 1                    : 0 ]  AWADDR      ;
    logic [$clog2(AXI_MAX_NUM_TRANSFERS) - 1 : 0 ]  AWLEN       ;
    logic [AxSIZE_WIDTH - 1                  : 0 ]  AWSIZE      ;
    logic                                           AWVALID     ;
    logic [AxBURST_WIDTH - 1                 : 0 ]  AWBURST     ;
    logic [AWUSER_WIDTH - 1                  : 0 ]  AWUSER      ;                                                
    logic                                           AWREADY     ;
    /***********************************************************/
    /*----------------------  W Channel ---------------------- */ 
    logic [$clog2(WFIFO_DEPTH ) -1           : 0 ]  WID         ;
    logic [(AXI_MAX_NUM_BYTES * 8) - 1       : 0 ]  WDATA       ;
    logic [(WSTRB_WIDTH) - 1           : 0 ]        WSTRB       ;
    logic                                           WVALID      ;
    logic                                           WLAST       ;
    logic                                           WREADY      ;
    /***********************************************************/
    /*---------------------- AR Channel ---------------------- */ 
    logic [$clog2(ARFIFO_DEPTH ) -1          : 0 ]  ARID        ;
    logic [ADDR_WIDTH - 1                    : 0 ]  ARADDR      ;
    logic [$clog2(AXI_MAX_NUM_TRANSFERS) - 1 : 0 ]  ARLEN       ;
    logic [AxSIZE_WIDTH - 1                  : 0 ]  ARSIZE      ;
    logic                                           ARVALID     ;
    logic [AxBURST_WIDTH - 1                 : 0 ]  ARBURST     ;
    logic [ARUSER_WIDTH - 1                  : 0 ]  ARUSER      ;                                                
    logic                                           ARREADY     ;
    /***********************************************************/

    // Define modport

    modport axi_slave_request_push_fsm_wr   (
                                input       AWID,
                                            AWADDR,
                                            AWLEN,
                                            AWSIZE,
                                            AWVALID,
                                            AWBURST,
                                            AWUSER,
                                            WID,
                                            WDATA,
                                            WSTRB,
                                            WVALID,
                                            WLAST,
                                        
                                output      AWREADY,
                                            WREADY
    );
    modport axi_slave_request_push_fsm_wr_tb   (
                                output          AWID,
                                                AWADDR,
                                                AWLEN,
                                                AWSIZE,
                                                AWVALID,
                                                AWBURST,
                                                AWUSER,
                                                WID,
                                                WDATA,
                                                WSTRB,
                                                WVALID,
                                                WLAST,
                                        
                                input           AWREADY,
                                                WREADY
    );

    modport axi_slave_request_push_fsm_rd   (
                                input       ARID,
                                            ARADDR,
                                            ARLEN,
                                            ARSIZE,
                                            ARVALID,
                                            ARBURST,
                                            ARUSER,

                                output      ARREADY
);

modport axi_slave_request_push_fsm_rd_tb   (
                                output      ARID,
                                            ARADDR,
                                            ARLEN,
                                            ARSIZE,
                                            ARVALID,
                                            ARBURST,
                                            ARUSER,

                                input      ARREADY
);


modport axi_slave_FIFO_interface   (
                                input       AWREADY,
                                            WREADY,
                                            ARREADY
);

modport axi_slave_top (
                        input       ARID,
                                    ARADDR,
                                    ARLEN,
                                    ARSIZE,
                                    ARVALID,
                                    ARBURST,
                                    ARUSER,

                                    AWID,
                                    AWADDR,
                                    AWLEN,
                                    AWSIZE,
                                    AWVALID,
                                    AWBURST,
                                    AWUSER,
                                    
                                    WID,
                                    WDATA,
                                    WSTRB,
                                    WVALID,
                                    WLAST,

                        output      ARREADY,
                                    AWREADY,
                                    WREADY

);




endinterface  : axi_if