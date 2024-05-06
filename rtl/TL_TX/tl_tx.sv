/********************************************************************/
/* Module Name	: tl_tx.sv                                          */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 3-05-2024 					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: this integration between all submodules of tl tx  */
/********************************************************************/
// import the defined package for arbiter 
import Tx_Arbiter_Package::*;
import data_frag_package::*;
import axi_slave_package::*; 

module tl_tx ( 
            //  Global Signals 
                    input bit                       clk ,
                    input bit                       arst,
            // Axi Slave Channels 
                    axi_if                         slave_push_if,
                    input logic [REQUESTER_ID_WIDTH - 1 : 0] Requester_ID, 
                    Master_Interface                Master_if,
                    P2A_Rx_Router_Interface         Rx_Router_if,
            // Rx side interface - Master
                    input logic                    master_valid,
                    output logic                   axi_master_grant,
                    // Output of mapper for master
                    input logic [3*DW - 1 : 0]     axi_master_hdr,                          
                    // Data in case of COMPD
                    input logic [AXI_MAX_NUM_BYTES * 8 - 1 : 0] axi_comp_data, 
            // Rx side interface -  Rx Router 
                    input  logic [1:0]              rx_router_valid, 
                    output logic                    rx_router_grant,
                    input logic [3*DW - 1 : 0]      rx_router_msg_hdr, // all msgs supported 3Dw
                    input logic [3*DW - 1 : 0]      rx_router_comp_hdr,
                    // Data in case of COMPD
                    input logic [1*DW  - 1 : 0]     rx_router_data  ,
            //  DLL - FC credits interface
                    input logic [FC_HDR_WIDTH  - 1 : 0]   HdrFC,
                    input logic [FC_DATA_WIDTH - 1 : 0]   DataFC,
                    input FC_type_t                       TypeFC,

            // DLL - TLP interface 
);
// Internal Connections 
    logic axi_req_wr_grant, axi_wrreq_hdr_valid, axi_req_rd_grant, axi_rdreq_hdr_valid ; 
    tlp_header_t     axi_wrreq_hdr, axi_rdreq_hdr;
    logic [AXI_MAX_NUM_BYTES * 8 - 1 : 0] axi_req_data ; 

    logic start_fragment, Buffer_Ready ; 
    buffer_frag_interface        frag_if(); 

// Axi Slave  

    Slave_Top u_Slave_Top ( 
        .axi_clk(clk),
        .ARESTn(arst),
        .slave_push_if(slave_push_if),
        .Requester_ID(Requester_ID),
        .axi_req_wr_grant(axi_req_wr_grant),
        .axi_req_rd_grant(axi_req_rd_grant),
        .axi_wrreq_hdr_valid(axi_wrreq_hdr_valid),
        .axi_wrreq_hdr(axi_wrreq_hdr),
        .axi_rdreq_hdr_valid(axi_rdreq_hdr_valid),
        .axi_rdreq_hdr(axi_rdreq_hdr),
        .axi_req_data(axi_req_data),
        .Master_if(Master_if),
        .Rx_Router_if(Rx_Router_if)
    ); 

// Arbiter 

    arbiter_Top u_arbiter_Top ( 
        // global signals 
            .clk(clk),
            .arst(arst),
        // Axi slave - Write Request
            .axi_req_wr_grant(axi_req_wr_grant),
            .axi_wrreq_hdr(axi_wrreq_hdr),
            .axi_req_data(axi_req_data),
            .a2p1_valid(axi_wrreq_hdr_valid),
        // Axi slave - Read Request
            .axi_req_rd_grant(axi_req_rd_grant),
            .axi_rdreq_hdr(axi_rdreq_hdr),
            .a2p2_valid(axi_rdreq_hdr_valid), 
        // Axi master 
            .axi_master_grant(axi_master_grant),
            .axi_master_hdr(axi_master_hdr),
            .axi_comp_data(axi_comp_data),
            .master_valid(master_valid),
        // Rx Router 
            .rx_router_grant(rx_router_grant),
            .rx_router_valid(rx_router_valid),
            .rx_router_msg_hdr(rx_router_msg_hdr), 
            .rx_router_comp_hdr(rx_router_comp_hdr),
            .rx_router_data(rx_router_data),
        // Interface with DLL of FC credits 
            .HdrFC(HdrFC),
            .DataFC(DataFC),
            .TypeFC(TypeFC),
        // Interface with Data Fragmentation 
            .start_fragment(start_fragment),
            .Buffer_Ready(Buffer_Ready),
            .frag_if(frag_if)
    );

//  Data Fragmentation  
    data_frag_Top u_data_frag_Top ( 
            .clk(clk),
            .arst(arst),
            .start_fragment(start_fragment),
            .Buffer_Ready(Buffer_Ready),
            .frag_if(frag_if)
    ); 

endmodule 

