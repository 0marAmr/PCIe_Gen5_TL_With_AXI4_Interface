/********************************************************************/
/* Module Name	: arbiter_Top.sv                                    */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 1-05-2024 					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: this integration between all arbiter block        */
/*(FC -Ordering -Arbiter Fsm -Sequence recorder   )                 */
/********************************************************************/
// import the defined package for arbiter 
import Tx_Arbiter_Package::*;
import Fragmentation_Package::*;
import axi_slave_package::*; 

module arbiter_Top ( 
                   input bit clk,
                   input bit arst, 
            // Interface of Axi Slave 
                // write request 
                    output logic           axi_req_wr_grant,
                    // Output of mapper for write
                    input tlp_header_t     axi_wrreq_hdr,
                    // Output of POP FSM : output from slave to Tx Arbiter (Data for write request)
                    input logic [AXI_MAX_NUM_BYTES * 8 - 1 : 0] axi_req_data,
                    input logic              a2p1_valid,
                // read request 
                    output logic             axi_req_rd_grant,
                    // Output of mapper for read
                    input tlp_header_t     axi_rdreq_hdr,
                    input logic            a2p2_valid, 
            // Interface with Axi Master 
                    output logic             axi_master_grant,
                    // Output of mapper for master
                    input logic [3*DW - 1 : 0]     axi_master_hdr,                          
                    // Data in case of COMPD
                    input logic [AXI_MAX_NUM_BYTES * 8 - 1 : 0] axi_comp_data, 
                    input logic                     master_valid,
            // Interface with Rx Router
                    output logic                    rx_router_grant,
                    input  logic [1:0]              rx_router_valid, 
                        
                    input logic [4*DW - 1 : 0]      rx_router_msg_hdr, 
                    input logic [3*DW - 1 : 0]      rx_router_comp_hdr,
                    
                    // Data in case of COMPD
                    input logic [1*DW  - 1 : 0]     rx_router_data, 
            // Interface with DLL of FC credits 
                    input logic [FC_HDR_WIDTH  - 1 : 0]   HdrFC,
                    input logic [FC_DATA_WIDTH - 1 : 0]   DataFC,
                    input FC_type_t                       TypeFC,

            // Output of buffer fragmentation 
                buffer_frag_interface.arbiter_buffer               buffer_if
);

  Tx_Arbiter_Sequence_Recorder seq_rec_tx_arb_if (); 
  Arbiter_FSM_Sequence_Recorder seq_rec_arbiter_fsm_if ();

  Tx_FC_Interface fc_if (); 
  
  ordering_if ordering_if() ;  



    // Ordering Block
    ordering u_ordering (
        ._if (ordering_if.ORDERING_ARBITER_IF)
    );

    // FC Block 
    Tx_FC u_Tx_FC ( 
        .clk(clk),
        .arst(arst),
        ._fc_arbiter(fc_if.FC_ARBITER),
        .HdrFC (HdrFC),
        .DataFC (DataFC),
        .TypeFC (TypeFC)
    );




    // Sequecne recorder handler
    Tx_Arbiter u_Tx_Arbiter ( 
        .clk(clk),
        .arst(arst),
        .a2p1_valid(a2p1_valid),
        .a2p2_valid(a2p2_valid),
        .master_valid(master_valid),
        .rx_router_valid(rx_router_valid),
        ._Sequence_Recorder_if(seq_rec_tx_arb_if.TX_ARBITER_SEQUENCE_RECORDER)   
    ); 


    
    // Sequence recorder buffer 
    Sequence_Recorder u_Sequence_Recorder ( 
        .clk(clk),
        .arst(arst),
        ._if_arbiter_fsm(seq_rec_arbiter_fsm_if.SEQUENCE_RECORDER_ARBITER_FSM),
        ._if_tx_arbiter(seq_rec_tx_arb_if.SEQUENCE_RECORDER_TX_ARBITER)
    );

    // Arbiter FSM 
    arbiter_fsm u_arbiter_fsm ( 
        .clk(clk),
        .arst(arst),
    // sequence recorder interface
        .recorder_if(seq_rec_arbiter_fsm_if.ARBITER_FSM_SEQUENCE_RECORDER),
    // ordering interface 
        .ordering_if(ordering_if.ARBITER_ORDERING_IF),
    // flow control interface
        .fc_if(fc_if.ARBITER_FC),
    // TLP buffer interface 
        .buffer_if(buffer_if),
    // axi slave interface 
        .axi_req_wr_grant(axi_req_wr_grant),
        .axi_req_rd_grant(axi_req_rd_grant),
        .axi_wrreq_hdr(axi_wrreq_hdr),
        .axi_rdreq_hdr(axi_rdreq_hdr),
        .axi_req_data(axi_req_data),
    // axi master interface 
        .axi_master_grant(axi_master_grant),
        .axi_master_hdr(axi_master_hdr),
        .axi_comp_data(axi_comp_data),
    // rx router interface 
        .rx_router_grant(rx_router_grant),
        .rx_router_msg_hdr(rx_router_msg_hdr),
        .rx_router_comp_hdr(rx_router_comp_hdr),
        .rx_router_data(rx_router_data)
);


endmodule 

