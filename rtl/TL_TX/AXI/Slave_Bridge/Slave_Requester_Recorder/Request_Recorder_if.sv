
/* Module Name	: Request_Recorder_if.sv	    */
/* Written By	: Mohamed Aladdin             	*/
/* Date			: 04-04-2024					*/
/* Version		: V_1							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: - 							*/
/* Synthesizable: YES                           */
/* Summary : it is a dual port ram used for     */
/*           record the request and read        */

// Define the interface of dual port ram 

interface Request_Recorder_if;


    // import the defined package for axi
    import axi_slave_package::*;

    /*  Request Recorder interface signals */
    // First Port for Request path
    logic                                     req_wr_en;
    logic [REQUESTER_RECORDER_ADDR_WIDTH - 1 : 0]  req_wr_addr;
    logic [REQUESTER_RECORDER_WIDTH - 1 : 0]       req_wr_data;
    logic [REQUESTER_RECORDER_ADDR_WIDTH - 1 : 0]  req_rd_addr_wr;
    logic [REQUESTER_RECORDER_ADDR_WIDTH - 1 : 0]  req_rd_addr_rd;

    logic [REQUESTER_RECORDER_WIDTH - 1 : 0]       req_rd_data_wr;
    logic [REQUESTER_RECORDER_WIDTH - 1 : 0]       req_rd_data_rd;

    // Second Port for Respond Paths 
    logic                                     resp_wr_en;
    logic [REQUESTER_RECORDER_ADDR_WIDTH - 1 : 0]  resp_wr_addr;
    logic [REQUESTER_RECORDER_WIDTH - 1 : 0]       resp_wr_data;
    logic [REQUESTER_RECORDER_ADDR_WIDTH - 1 : 0]  resp_rd_addr;
    logic [REQUESTER_RECORDER_WIDTH - 1 : 0]       resp_rd_data;

    // Read Port for request path from push fsm 
    modport rdreqport_wr_request_recorder (
                                     output req_rd_addr_wr ,
                                     input  req_rd_data_wr 
    );
    // Read Port for request path from Request Recorder 
    modport request_recorder_rdreqport_wr (
                                     input  req_rd_addr_wr ,
                                     output req_rd_data_wr 
    );
    
    modport rdreqport_rd_request_recorder (
                                     output req_rd_addr_rd ,
                                     input  req_rd_data_rd 
    );
    
    modport request_recorder_rdreqport_rd (
                                     input  req_rd_addr_rd ,
                                     output req_rd_data_rd 
    );

     // Write Port for request path to memory of request recorder, it is the input of Mux.
    modport wrreqport_request_recorder (
                                     input  req_wr_en ,
                                            req_wr_data, 
                                            req_wr_addr
    );
     // Write Port for request path to memory of request recorder, it is the output of Mux.
    modport request_recorder_wrreqport (
                                     output  req_wr_en ,
                                            req_wr_data, 
                                            req_wr_addr
    );
    
    
    // Interface P2A with Request Recorder
    modport P2A_REQUEST_RECORDER (
        input   resp_rd_data,

        output  resp_wr_en,
                resp_wr_addr,
                resp_wr_data,
                resp_rd_addr
    );

    modport REQUEST_RECORDER_P2A (
        output  resp_rd_data,

        input   resp_wr_en,
                resp_wr_addr,
                resp_wr_data,
                resp_rd_addr
    );   


endinterface:  Request_Recorder_if

