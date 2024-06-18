/********************************************************************/
/* Module Name	: Slave_Top.sv                                      */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 1-04-2024 					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: -							                        */
/********************************************************************/
// import the defined package for axi
import axi_slave_package::*;
module Slave_Top (
        // Global Signals 
        input  bit axi_clk, ARESTn,
        // if asynchronous FIFO added, will add another port for system_clk

        /************************** Request Path Ports **************************/
        // Interface with 2 FSMS of Push
        axi_if                                  slave_push_if,
        // input from Configuration space 
        input logic [REQUESTER_ID_WIDTH - 1 : 0] Requester_ID, 
        input logic                                 config_ecrc,    // this bit from configuration indicate ecrc generation is enabled
        // input from Tx Arbiter
        input logic             axi_req_wr_grant,
        input logic             axi_req_rd_grant,
        // Output of mapper for write
        output logic            axi_wrreq_hdr_valid,
        output tlp_header_t     axi_wrreq_hdr,
        // Output of mapper for read
        output logic            axi_rdreq_hdr_valid ,
        output tlp_header_t     axi_rdreq_hdr,
        // Output of POP FSM : output from slave to Tx Arbiter (Data for write request)
        output logic [AXI_MAX_NUM_BYTES * 8 - 1 : 0] axi_req_data,

        /************************** Response Path Ports **************************/
        Master_Interface.SLAVE            Master_if,
        P2A_Rx_Router_Interface.P2A_RX_ROUTER     Rx_Router_if     
);
    /********* Internal Signals *********/
        logic wr_atop_en, rd_atop_en;    

    /********* Parameters *********/

    /********* Interfaces *********/
        // AW FIFO
        Sync_FIFO_Interface #(
            .DATA_WIDTH(AWFIFO_WIDTH),
            .FIFO_DEPTH(AWFIFO_DEPTH)
        ) AWFIFO_if (
        );

        // W FIFO
        Sync_FIFO_Interface #(
            .DATA_WIDTH(WFIFO_WIDTH),
            .FIFO_DEPTH(WFIFO_DEPTH)
        ) WFIFO_if (
        );

        // AR FIFO
        Sync_FIFO_Interface #(
            .DATA_WIDTH(ARFIFO_WIDTH),
            .FIFO_DEPTH(ARFIFO_DEPTH)
        ) ARFIFO_if (
        );

        // B FIFO
        Sync_FIFO_Interface #(
            .DATA_WIDTH(B_FIFO_DATA_WIDTH),
            .FIFO_DEPTH(B_FIFO_DEPTH)
        ) BFIFO_if (
        );

        // R FIFO
        Sync_FIFO_Interface #(
            .DATA_WIDTH(R_FIFO_DATA_WIDTH),
            .FIFO_DEPTH(R_FIFO_DEPTH)
        ) RFIFO_if (
        );

        // P2A interface with Push FSM
        P2A_Push_FSM_Interface #(
            .DATA_WIDTH(R_FIFO_DATA_WIDTH)
        ) P2A_Push_FMS_if (
        );


        // interface with requester recorder 
        Request_Recorder_if recorder_if ();
        Request_Recorder_if wr_recorder_if ();
        Request_Recorder_if rd_recorder_if ();


        // Interface with internal response generator 
        Slave_Internal_Response_if err_wr_if();
        Slave_Internal_Response_if posted_wr_if();

        Slave_Internal_Response_if posted_rd_if();
        Slave_Internal_Response_if err_rd_if();


        Slave_Internal_Response_if RESP_if();


        

    /********* Modules *********/
            Request_Recorder u_Request_Recorder (  
                       // Global Signals
                    axi_clk,
                    ARESTn ,
                    recorder_if.request_recorder_rdreqport_wr, // drive from push wr fsm request side
                    recorder_if.request_recorder_rdreqport_rd, // drive from push rd fsm request side
                    recorder_if.wrreqport_request_recorder, // drive from mux from request side
                    recorder_if.REQUEST_RECORDER_P2A // drive from mapper response side
            );

            Sync_FIFO #(
                .DATA_WIDTH(AWFIFO_WIDTH),
                .FIFO_DEPTH(AWFIFO_DEPTH)
            ) u_AW_FIFO (
                axi_clk, 
                ARESTn,
                AWFIFO_if.FIFO_SOURCE,
                AWFIFO_if.FIFO_DIST
            );

            Sync_FIFO #(
                .DATA_WIDTH(WFIFO_WIDTH),
                .FIFO_DEPTH(WFIFO_DEPTH)
            ) u_W_FIFO (
                axi_clk, 
                ARESTn,
                WFIFO_if.FIFO_SOURCE,
                WFIFO_if.FIFO_DIST
            );

            Sync_FIFO #(
                .DATA_WIDTH(ARFIFO_WIDTH),
                .FIFO_DEPTH(ARFIFO_DEPTH)
            ) u_AR_FIFO (
                axi_clk, 
                ARESTn,
                ARFIFO_if.FIFO_SOURCE,
                ARFIFO_if.FIFO_DIST
            );

            Sync_FIFO #(
                .DATA_WIDTH(B_FIFO_DATA_WIDTH),
                .FIFO_DEPTH(B_FIFO_DEPTH)
            ) u_B_FIFO (
                axi_clk,
                ARESTn,
                BFIFO_if.FIFO_SOURCE,
                BFIFO_if.FIFO_DIST    
            );

            Sync_FIFO #(
                .DATA_WIDTH(R_FIFO_DATA_WIDTH),
                .FIFO_DEPTH(R_FIFO_DEPTH) 
            ) u_R_FIFO (
                axi_clk,
                ARESTn,
                RFIFO_if.FIFO_SOURCE,
                RFIFO_if.FIFO_DIST    
            );

            Response_Push_FSM  #(
                .R_FIFO_DEPTH(R_FIFO_DEPTH) 
            ) u_Rsp_Push_FSM (
                axi_clk,
                ARESTn,
                BFIFO_if.SOURCE_FIFO,
                RFIFO_if.SOURCE_FIFO,
                P2A_Push_FMS_if.FSM_P2A
            );

            P2A #(
            ) u_P2A (
                axi_clk, 
                ARESTn,
                P2A_Push_FMS_if.P2A_FSM,
                Rx_Router_if,
                recorder_if.P2A_REQUEST_RECORDER
            );

            // Request_Recorder #(
            //     .DATA_WIDTH(REQUEST_RECORDER_DATA_WIDTH),
            //     .MEM_DEPTH(REQUEST_RECORDER_DEPTH)
            // ) u_Request_Recorder (
            //     axi_clk,
            //     ARESTn,
            //     P2A_Request_Recorder_if
            // );

            Response_Pop_FSM  #(
                .B_FIFO_DATA_WIDTH(B_FIFO_DATA_WIDTH),
                .B_FIFO_DEPTH(B_FIFO_DEPTH),
                .R_FIFO_DATA_WIDTH(R_FIFO_DATA_WIDTH),
                .R_FIFO_DEPTH(R_FIFO_DEPTH)
            ) u_Rsp_Pop_FSM (
                axi_clk,
                ARESTn,
                BFIFO_if.DIST_FIFO,
                RFIFO_if.DIST_FIFO,
                Master_if,
                RESP_if.B_TO_AW,
                RESP_if.R_TO_AR
            );


        // Instantiate PUSH FSM for Write 
        axi_push_fsm_wr u_axi_push_fsm_wr (
                axi_clk, 
                ARESTn, 
                slave_push_if.axi_slave_request_push_fsm_wr, 
                AWFIFO_if.SOURCE_FIFO,
                recorder_if.rdreqport_wr_request_recorder,
                err_wr_if.AW_TO_B,
                WFIFO_if.SOURCE_FIFO
            );

        // Instantiate PUSH FSM for Read 
        axi_slave_fsm_rd u_axi_slave_fsm_rd (
                axi_clk, 
                ARESTn, 
                slave_push_if.axi_slave_request_push_fsm_rd, 
                recorder_if.rdreqport_rd_request_recorder,
                err_rd_if.AR_TO_R,
                ARFIFO_if.SOURCE_FIFO
            );
        
        // Instantiate mapper and pop fsm for write requests 
            wr_atop u_wr_atop (
                wr_atop_en,
                AWFIFO_if.FIFO_rd_data,
                Requester_ID,
                config_ecrc,
                axi_wrreq_hdr,
                wr_recorder_if.request_recorder_wrreqport,
                axi_wrreq_hdr_valid,
                axi_req_wr_grant
            );

            fifo_pop_wr u_fifo_pop_wr (
                axi_clk,
                ARESTn,
                AWFIFO_if.DIST_FIFO,
                WFIFO_if.DIST_FIFO, 
                wr_atop_en,
                posted_wr_if.AW_TO_B,
                axi_req_wr_grant,
                axi_req_data
            ); 

            fifo_pop_rd u_fifo_pop_rd (
                axi_clk,
                ARESTn,
                ARFIFO_if.DIST_FIFO,
                rd_atop_en,
                posted_rd_if.AR_TO_R,
                axi_req_rd_grant
            );
    
            rd_atop u_rd_atop (
                rd_atop_en,
                ARFIFO_if.FIFO_rd_data,
                Requester_ID,
                config_ecrc,
                axi_rdreq_hdr,
                rd_recorder_if.request_recorder_wrreqport,
                axi_rdreq_hdr_valid,
                axi_req_rd_grant
            );
            
            // Instantiate Mux for write interface for recorder
 
            wr_interface_mux u_wr_interface_mux (
            wr_recorder_if.wrreqport_request_recorder,
            rd_recorder_if.wrreqport_request_recorder,
            axi_req_wr_grant,
            axi_req_rd_grant,
            recorder_if.request_recorder_wrreqport
            );


            slave_internal_response_rd_mux u_slave_internal_response_rd_mux (
                err_rd_if.R_TO_AR, 
                posted_rd_if.R_TO_AR,
                RESP_if.AR_TO_R

            );

            slave_internal_response_wr_mux u_slave_internal_response_wr_mux (
            err_wr_if.B_TO_AW,
            posted_wr_if.B_TO_AW,
            RESP_if.AW_TO_B
            );
  

endmodule
