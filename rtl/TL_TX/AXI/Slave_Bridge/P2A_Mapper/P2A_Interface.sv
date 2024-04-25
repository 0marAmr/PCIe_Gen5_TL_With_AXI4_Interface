/* Module Name	: P2A_Interface                 */
/* Written By	: Ahmady                     	*/
/* Date			: 4-04-2024 					*/
/* Version		: V_1							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: -							    */
// `timescale 1ns/1ps
interface P2A_Push_FSM_Interface #(
    parameter DATA_WIDTH = 1024
)(
);
    import axi_slave_package::*;

    /* P2A and Push FSM interface signals */
    cpl_t                       Cpl_Type;
    logic [9:0]                 Cpl_Length;
    logic [DATA_WIDTH - 1 : 0]  Cpl_Data;
    logic                       Cpl_Grant;
    // this signal output from "Push FSM" to P2A for indication that process DATA not HDR
    // when Push FSM in "R Push" state must raise this signal.
    // Cpl_Command = 1 >> handle DATA inly and ignore HDR
    // Cpl_Command = 0 >> handle HDR
    logic                       Cpl_Command;    


    // Interface P2A with Push FSM
    modport P2A_FSM (
        input   Cpl_Grant,
                Cpl_Command,

        output  Cpl_Type,
                Cpl_Length,
                Cpl_Data
    );

    modport FSM_P2A (
        output  Cpl_Grant,
                Cpl_Command,

        input   Cpl_Type,
                Cpl_Length,
                Cpl_Data
    );

endinterface: P2A_Push_FSM_Interface

interface P2A_Rx_Router_Interface #(
    parameter DATA_WIDTH = 1024
)(
);
    // import P2A_Cpl_Package::*;
    import axi_slave_package::*;

    /* P2A and Push FSM interface signals */
    Cpl_TLP_HDR_t               Resp_HDR;
    logic [DATA_WIDTH - 1 : 0]  Resp_Data;
    logic                       Resp_Valid;
    logic                       Resp_Grant;

    // Interface P2A with Rx Router
    modport P2A_RX_ROUTER (
        input   Resp_HDR,
                Resp_Data,
                Resp_Valid,
        
        output  Resp_Grant
    );

    modport RX_ROUTER_P2A (
        output  Resp_HDR,
                Resp_Data,
                Resp_Valid,
        
        input   Resp_Grant
    );
endinterface: P2A_Rx_Router_Interface

// interface P2A_Request_Recorder_Interface #(
//     parameter DATA_WIDTH    = 9,
//               MEM_DEPTH     = 256,
//               ADDR_WIDTH    = $clog2(MEM_DEPTH)  
// )(
// );
//     /* P2A and Request Recorder interface signals */
//     logic                       wr_en;
//     logic [ADDR_WIDTH - 1 : 0]  wr_addr;
//     logic [DATA_WIDTH - 1 : 0]  wr_data;
//     logic [ADDR_WIDTH - 1 : 0]  rd_addr;
//     logic [DATA_WIDTH - 1 : 0]  rd_data;

//     // Interface P2A with Request Recorder
//     modport P2A_REQUEST_RECORDER (
//         input   rd_data,

//         output  wr_en,
//                 wr_addr,
//                 wr_data,
//                 rd_addr
//     );

//     modport REQUEST_RECORDER_P2A (
//         output  rd_data,

//         input   wr_en,
//                 wr_addr,
//                 wr_data,
//                 rd_addr
//     );    
    
// endinterface: P2A_Request_Recorder_Interface

