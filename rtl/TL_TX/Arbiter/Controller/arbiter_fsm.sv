/********************************************************************/
/* Module Name	: arbiter_fsm.sv                          		    */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 10-04-2024			                            */
/* Version		: V1					                            */
/* Updates		: -					                                */
/* Dependencies	: -						                            */
/* Used			: in Arbiter Modules                                */
/* Summary:  This file includes controller of arbiter               */
/********************************************************************/

/*
    Acknowledgement :  Make the HDR Coming from Rx Side is a type of struct as slave 
*/

// import package
import Tx_Arbiter_Package::*;
import data_frag_package::*;
import axi_slave_package::*;


module arbiter_fsm (
                   // Global signals 
                   input bit clk,
                   input bit arst,

                   // Interface with sequence recorder
                   Tx_Arbiter_Sequence_Recorder.ARBITER_FSM_SEQUENCE_RECORDER recorder_if,

                   // Interface with Ordering 
                   ordering_if.ARBITER_ORDERING_IF ordering_if,

                   // Interface with Flow Control
                   Tx_FC_Interface.ARBITER_FC fc_if,

                   // Interface with FIFO of Data Fragementation
                   buffer_frag_interface.arbiter_buffer buffer_if,
                   
                
                   // Interface with Slave (Rd Request and Wr Request)
                        output logic             axi_req_wr_grant,
                        output logic             axi_req_rd_grant,
                        // Output of mapper for write
                        input tlp_header_t     axi_wrreq_hdr,
                        // Output of mapper for read
                        input tlp_header_t     axi_rdreq_hdr,
                        // Output of POP FSM : output from slave to Tx Arbiter (Data for write request)
                        input logic [AXI_MAX_NUM_BYTES * 8 - 1 : 0] axi_req_data,
                        
                    // Interface with Master
                        output logic             axi_master_grant,
                        // Output of mapper for master
                        input logic [3*DW - 1 : 0]     axi_master_hdr,                          
                        // Data in case of COMPD
                        input logic [AXI_MAX_NUM_BYTES * 8 - 1 : 0] axi_req_data,  
                        
                        
                    // Interface with Rx Router
                        output logic                    rx_router_grant,
                        
                        input logic [3*DW - 1 : 0]      rx_router_msg_hdr,
                        input logic [3*DW - 1 : 0]      rx_router_comp_hdr,
                        
                        // Data in case of COMPD
                        input logic [1*DW  - 1 : 0]     rx_router_data      
                        
                        
);
    // State Definition 
    arbiter_state current_state,next_state ;
    
    // Internal Signals 
    Tx_Arbiter_Sources_t source_1,source_2 ; 
    bool_t ordering_result ;

    // Function to check on ordering block and get the result of ordering block. 
    function bool_t ordering_function (
                                input Tx_Arbiter_Sources_t source_1 , 
                                input Tx_Arbiter_Sources_t source_2 );
                                
        bool_t result ; 
        // case statement: for all types of sources and passing the proper inputs to ordering block
        case ({source_1,source_2}) 
            {A2P_1,A2P_2}   : begin 
                            // Posted Condition for MemWr either 64-bit address or 32-bit address
                            if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                                ordering_if.first_trans = Posted_Req ; 
                            end 
                            else begin 
                                ordering_if.first_trans = Non_Posted_Req ; 
                            end
                            // Non-Posted Request (Msg)
                            if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                                ordering_if.second_trans = Posted_Req ;
                            end 
                            else begin 
                                ordering_if.second_trans = Non_Posted_Req ;
                            end
                            
                            ordering_if.first_RO = axi_wrreq_hdr.Attr[1];
                            ordering_if.first_IDO = axi_wrreq_hdr.ATTR;
                            ordering_if.first_trans_ID = axi_wrreq_hdr.Requester_ID ;

                            ordering_if.comp_typ = 3'b000;
                            
                            ordering_if.second_RO = axi_rdreq_hdr.Attr[1];
                            ordering_if.second_IDO = axi_rdreq_hdr.ATTR ;
                            ordering_if.second_trans_ID = axi_rdreq_hdr.Requester_ID ;
            end 
            {A2P_1,MASTER}   : begin 
                             // Posted Condition for MemWr either 64-bit address or 32-bit address
                                if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                                    ordering_if.first_trans = Posted_Req ; 
                                end 
                                else begin 
                                    ordering_if.first_trans = Non_Posted_Req ; 
                                end
                                ordering_if.first_RO = axi_wrreq_hdr.Attr[1];
                                ordering_if.first_IDO = axi_wrreq_hdr.ATTR;
                                ordering_if.first_trans_ID = axi_wrreq_hdr.Requester_ID ;
                                
                                ordering_if.second_trans = Comp ;
                                ordering_if.second_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                        
                                ordering_if.second_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                                ordering_if.second_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                ordering_if.comp_typ = 3'b000; // I can't Determine unless Cfg wr due to different paths
                                
                                /*  
                                    95 : 0  -->  95 - 16 - 3 = 76  && 95 - 8 - 6 = 81 && [63:48]
                                    15 : 0 , 31 : 16 , 47 : 32 , 63 : 48 
                                */ 
            end 
            {A2P_1,RX_ROUTER_CFG}   : begin 
                            // Posted Condition for MemWr either 64-bit address or 32-bit address
                            if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                                ordering_if.first_trans = Posted_Req ; 
                            end 
                            else begin 
                                ordering_if.first_trans = Non_Posted_Req ; 
                            end
                            ordering_if.first_RO = axi_wrreq_hdr.Attr[1];
                            ordering_if.first_IDO = axi_wrreq_hdr.ATTR;
                            ordering_if.first_trans_ID = axi_wrreq_hdr.Requester_ID ;
                            
                            
                            ordering_if.second_trans = Comp ;
                            ordering_if.second_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                            ordering_if.second_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                            ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                
                            if ((rx_router_comp_hdr[3*DW - 1: 3*DW - 3] == 3'b000)&&(rx_router_comp_hdr[1*DW + 15 : 1 *DW + 13 ] == 3'b000)) // this means the compeletions are comp, successfull and cfgwr
                                begin 
                                        ordering_if.comp_typ = 3'b010; // CFG Wr
                                end 
                            else begin 
                                        ordering_if.comp_typ = 3'b000; // not CFG Wr
                                end 

                            
                            
            end 
            {A2P_1,RX_ROUTER_ERR}   : begin 
                            // Posted Condition for MemWr either 64-bit address or 32-bit address
                            if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                                ordering_if.first_trans = Posted_Req ; 
                            end 
                            else begin 
                                ordering_if.first_trans = Non_Posted_Req ; 
                            end
                            ordering_if.first_RO = axi_wrreq_hdr.Attr[1];
                            ordering_if.first_IDO = axi_wrreq_hdr.ATTR;
                            ordering_if.first_trans_ID = axi_wrreq_hdr.Requester_ID ;
                            
                            ordering_if.second_trans = Comp ; 
                            ordering_if.second_RO = 1'b1;
                            ordering_if.second_IDO = 1'b1;
                            ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                            ordering_if.comp_typ = 3'b000; 

                            
            end
            {A2P_2,A2P_1}   : begin 
                             // Non-Posted Request (Msg)
                            if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                                ordering_if.first_trans = Posted_Req ;
                            end 
                            else begin 
                                ordering_if.first_trans = Non_Posted_Req ;
                            end
                            ordering_if.first_RO = axi_rdreq_hdr.Attr[1];
                            ordering_if.first_IDO = axi_rdreq_hdr.ATTR ;
                            ordering_if.first_trans_ID = axi_rdreq_hdr.Requester_ID ;
                            ordering_if.comp_typ = 3'b000;
                            
                            // Posted Condition for MemWr either 64-bit address or 32-bit address
                            if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                                ordering_if.second_trans = Posted_Req ; 
                            end 
                            else begin 
                                ordering_if.second_trans = Non_Posted_Req ; 
                            end
                            ordering_if.second_RO = axi_wrreq_hdr.Attr[1];
                            ordering_if.second_IDO = axi_wrreq_hdr.ATTR;
                            ordering_if.second_trans_ID = axi_wrreq_hdr.Requester_ID ;
            end 
            {A2P_2,MASTER}   : begin 
                             // Non-Posted Request (Msg)
                                if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                                    ordering_if.first_trans = Posted_Req ;
                                end 
                                else begin 
                                    ordering_if.first_trans = Non_Posted_Req ;
                                end
                                ordering_if.first_RO = axi_rdreq_hdr.Attr[1];
                                ordering_if.first_IDO = axi_rdreq_hdr.ATTR ;
                                ordering_if.first_trans_ID = axi_rdreq_hdr.Requester_ID ;
                                
                                ordering_if.second_trans = Comp ;
                                ordering_if.second_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                ordering_if.second_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                                ordering_if.second_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                ordering_if.comp_typ = 3'b000; // I can't Determine unless Cfg wr due to different paths
            
            end 
            {A2P_2,RX_ROUTER_CFG}   : begin 
                                // Non-Posted Request (Msg)
                                if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                                    ordering_if.first_trans = Posted_Req ;
                                end 
                                else begin 
                                    ordering_if.first_trans = Non_Posted_Req ;
                                end
                                ordering_if.first_RO = axi_rdreq_hdr.Attr[1];
                                ordering_if.first_IDO = axi_rdreq_hdr.ATTR ;
                                ordering_if.first_trans_ID = axi_rdreq_hdr.Requester_ID ;

                                ordering_if.second_trans = Comp ;
                                ordering_if.second_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                ordering_if.second_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                                ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                if ((rx_router_comp_hdr[3*DW - 1: 3*DW - 3] == 3'b000)&&(rx_router_comp_hdr[1*DW + 15 : 1 *DW + 13 ] == 3'b000)) // this means the compeletions are comp, successfull and cfgwr
                                    begin 
                                        ordering_if.comp_typ = 3'b010; // CFG Wr
                                    end 
                                    else begin 
                                        ordering_if.comp_typ = 3'b000; // not CFG Wr
                                    end 
            end 
            {A2P_2,RX_ROUTER_ERR}   : begin 
                                    // Non-Posted Request (Msg)
                                    if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                                        ordering_if.first_trans = Posted_Req ;
                                    end 
                                    else begin 
                                        ordering_if.first_trans = Non_Posted_Req ;
                                    end
                                    ordering_if.first_RO = axi_rdreq_hdr.Attr[1];
                                    ordering_if.first_IDO = axi_rdreq_hdr.ATTR ;
                                    ordering_if.first_trans_ID = axi_rdreq_hdr.Requester_ID ;
                                    
                                    ordering_if.second_trans = Comp ; 
                                    ordering_if.second_RO = 1'b1;
                                    ordering_if.second_IDO = 1'b1;
                                    ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                    ordering_if.comp_typ = 3'b000; 


            end 
            {MASTER,A2P_2}   : begin 
                                // Non-Posted Request (Msg)
                                if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                                    ordering_if.second_trans = Posted_Req ;
                                end 
                                else begin 
                                    ordering_if.second_trans = Non_Posted_Req ;
                                end
                                ordering_if.second_RO = axi_rdreq_hdr.Attr[1];
                                ordering_if.second_IDO = axi_rdreq_hdr.ATTR ;
                                ordering_if.second_trans_ID = axi_rdreq_hdr.Requester_ID ;

                                
                                ordering_if.first_trans = Comp ;
                                ordering_if.first_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                        
                                ordering_if.first_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                                ordering_if.first_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                ordering_if.comp_typ = 3'b000; // I can't Determine unless Cfg wr due to different paths
            
            end 
            {MASTER,A2P_1}   : begin 
            // Posted Condition for MemWr either 64-bit address or 32-bit address
                if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                    ordering_if.second_trans = Posted_Req ; 
                end 
                else begin 
                    ordering_if.second_trans = Non_Posted_Req ; 
                end
                ordering_if.second_RO = axi_wrreq_hdr.Attr[1];
                ordering_if.second_IDO = axi_wrreq_hdr.ATTR;
                ordering_if.second_trans_ID = axi_wrreq_hdr.Requester_ID ;
                
                ordering_if.first_trans = Comp ;
                ordering_if.first_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                ordering_if.first_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.first_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; // I can't Determine unless Cfg wr due to different paths
            
            end 
            {MASTER,RX_ROUTER_CFG}   : begin 
                ordering_if.first_trans = Comp ;
                ordering_if.first_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                        
                ordering_if.first_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.first_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                // ordering_if.comp_typ = 2'b10; 
                // make it depending on fmt and status 
                /* if fmt = 010 --> cfg rd comp 
                   if fmt = 000 and status 000 --> cfg wr otherwise can't determine whether it is comp for cfg wr or rd */
                   ordering_if.second_trans = Comp ;
                    ordering_if.second_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                    ordering_if.second_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                    ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                    if ((rx_router_comp_hdr[3*DW - 1: 3*DW - 3] == 3'b000)&&(rx_router_comp_hdr[1*DW + 15 : 1 *DW + 13 ] == 3'b000)) // this means the compeletions are comp, successfull and cfgwr
                        begin 
                            ordering_if.comp_typ = 3'b010; // CFG Wr
                        end 
                    else begin 
                            ordering_if.comp_typ = 3'b000; // not CFG Wr
                        end
            end 
            {MASTER,RX_ROUTER_ERR}   : begin 
                ordering_if.first_trans = Comp ;
                ordering_if.first_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                ordering_if.first_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.first_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; // I can't Determine unless Cfg wr due to different paths

                ordering_if.second_trans = Comp ; 
                ordering_if.second_RO = 1'b1;
                ordering_if.second_IDO = 1'b1;
                ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
            end
            {RX_ROUTER_CFG,A2P_2}   : begin 
                                 // Posted Request (Msg)                                    
                                 if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                                        ordering_if.second_trans = Posted_Req ;
                                    end 
                                    else begin 
                                        ordering_if.second_trans = Non_Posted_Req ;
                                    end
                                    ordering_if.second_RO = axi_rdreq_hdr.Attr[1];
                                    ordering_if.second_IDO = axi_rdreq_hdr.ATTR ;
                                    ordering_if.second_trans_ID = axi_rdreq_hdr.Requester_ID ;
                                    
                                    ordering_if.first_trans = Comp ;
                                    ordering_if.first_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                                    ordering_if.first_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                                    ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                                    ordering_if.comp_typ = 3'b000; // it represents the second transaction not first not CFG Wr

            
            end 
            {RX_ROUTER_CFG,A2P_1}   : begin 
            // Posted Condition for MemWr either 64-bit address or 32-bit address
                if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                    ordering_if.second_trans = Posted_Req ; 
                end 
                else begin 
                    ordering_if.second_trans = Non_Posted_Req ; 
                end
                ordering_if.second_RO = axi_wrreq_hdr.Attr[1];
                ordering_if.second_IDO = axi_wrreq_hdr.ATTR;
                ordering_if.second_trans_ID = axi_wrreq_hdr.Requester_ID ;
                
                ordering_if.first_trans = Comp ;
                ordering_if.first_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                ordering_if.first_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; // it represents the second transaction not first not CFG Wr
            
            end 
            {RX_ROUTER_CFG,MASTER}   : begin 
                ordering_if.second_trans = Comp ;
                ordering_if.second_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;
                ordering_if.second_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.second_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                // ordering_if.comp_typ = 3'b000; // I can't Determine unless Cfg wr due to different paths
                ordering_if.first_trans = Comp ;
                ordering_if.first_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                ordering_if.first_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; // not CFG Wr

            end 
            {RX_ROUTER_CFG,RX_ROUTER_ERR}   : begin 
            // ordering_if.comp_typ = 3'b000; // I can't Determine unless Cfg wr due to different paths
                ordering_if.first_trans = Comp ;
                ordering_if.first_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                ordering_if.first_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                
                ordering_if.second_trans = Comp ; 
                ordering_if.second_RO = 1'b1;
                ordering_if.second_IDO = 1'b1;                    
                ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; 

            end
            {RX_ROUTER_ERR,A2P_2}   : begin 
                // Posted Request (Msg)                                    
                if (axi_rdreq_hdr.FMT   = TLP_FMT_4DW && axi_rdreq_hdr.TYP[TYP_WIDTH - 1 : TYP_WIDTH - 2]   = 2'b10 )  begin
                        ordering_if.second_trans = Posted_Req ;
                end 
                else begin 
                        ordering_if.second_trans = Non_Posted_Req ;
                end
                ordering_if.second_RO = axi_rdreq_hdr.Attr[1];
                ordering_if.second_IDO = axi_rdreq_hdr.ATTR ;
                ordering_if.second_trans_ID = axi_rdreq_hdr.Requester_ID ;
                                    
                ordering_if.first_trans = Comp ; 
                ordering_if.first_RO = 1'b1;
                ordering_if.first_IDO = 1'b1;                    
                ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; 
                                    
            
            end 
            {RX_ROUTER_ERR,A2P_1}   : begin
            // Posted Condition for MemWr either 64-bit address or 32-bit address
                if ((axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA || axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA)  && axi_wrreq_hdr.TYP   = 'b0_0000)  begin
                    ordering_if.second_trans = Posted_Req ; 
                end 
                else begin 
                    ordering_if.second_trans = Non_Posted_Req ; 
                end
                ordering_if.second_RO = axi_wrreq_hdr.Attr[1];
                ordering_if.second_IDO = axi_wrreq_hdr.ATTR;
                ordering_if.second_trans_ID = axi_wrreq_hdr.Requester_ID ;
                
                ordering_if.first_trans = Comp ; 
                ordering_if.first_RO = 1'b1;
                ordering_if.first_IDO = 1'b1;                    
                ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; 
            
            end 
            {RX_ROUTER_ERR,MASTER}   : begin 
                ordering_if.first_trans = Comp ; 
                ordering_if.first_RO = 1'b1;
                ordering_if.first_IDO = 1'b1;                    
                ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                ordering_if.comp_typ = 3'b000; 
            
                ordering_if.second_trans = Comp ;
                ordering_if.second_RO = axi_master_hdr[3*DW - 1 - 2 * 8 - 3] ;                     
                ordering_if.second_IDO = axi_master_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.second_trans_ID = axi_master_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
            end 
            {RX_ROUTER_ERR,RX_ROUTER_CFG}   : begin 
                ordering_if.first_trans = Comp ; 
                ordering_if.first_RO = 1'b1;
                ordering_if.first_IDO = 1'b1;                    
                ordering_if.first_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
             
                ordering_if.second_trans = Comp ;
                ordering_if.second_RO = rx_router_comp_hdr[3*DW - 1 - 2 * 8 - 3] ;
                ordering_if.second_IDO = rx_router_comp_hdr[3*DW - 1 - 1 * 8 - 6] ;
                ordering_if.second_trans_ID = rx_router_comp_hdr[3*DW - 1 - 1 * DW : 3*DW  - 1 * DW - 2 * 8] ;
                if ((rx_router_comp_hdr[3*DW - 1: 3*DW - 3] == 3'b000)&&(rx_router_comp_hdr[1*DW + 15 : 1 *DW + 13 ] == 3'b000)) // this means the compeletions are comp, successfull and cfgwr
                    begin 
                        ordering_if.comp_typ = 3'b010; // CFG Wr
                    end 
                    else begin 
                            ordering_if.comp_typ = 3'b000; // not CFG Wr
                        end 
            end 
        endcase

        result = ordering_if.ordering_result ;        
        return result;
    endfunction

    // function to check on ordering block and get the result of flow control block.
    function  
    endfunction 

    always_ff (@posedge clk or negedge arst)
        begin 
            if (!arst)
                begin 
                    current_state <= IDLE;
                end 
            else begin 
                    current_state <= next_state;
            end 
        end 
    


    always_comb begin 
    
    case (next_state)
        IDLE : begin 
        // Output of State    
            /* Sequence Recorder */
                    recorder_if.rd_en = 1'b0 ;
                    recorder_if.wr_en = 1'b0 ;
                    recorder_if.wr_mode = 3'b0 ;
                    recorder_if.rd_mode = 3'b0 ;
                    recorder_if.wr_data_1 = NO_SOURCE ;
                    recorder_if.wr_data_2 = NO_SOURCE ;
                    // recorder_if.available  ;  they are inputs 
                    // recorder_if.rd_data_1  ;
                    // recorder_if.rd_data_2  ;


            
            /* Ordering Block Interface */
                    ordering_if.first_trans = No_Req;
                    ordering_if.second_trans =No_Req ;
                    ordering_if.first_RO = 1'b0;
                    ordering_if.second_RO = 1'b0 ;
                    ordering_if.first_IDO = 1'b0;
                    ordering_if.second_IDO = 1'b0 ;
                    ordering_if.first_trans_ID = 'b0 ;
                    ordering_if.second_trans_ID = 'b0;
                    ordering_if.comp_typ = 2'b00;
                    
                    // ordering_if.ordering_result  ; it is an input to this block

            /* FLOW control Block */
                    fc_if.PTLP_1 = '0;
                    fc_if.PTLP_2 = '0;
                    fc_if.Command_1 = FC_DEFAULT ;
                    fc_if.Command_2 = FC_DEFAULT ; 
                   //  fc_if.Result; it is an input to this block 
                
            /* Buffer Data Fragmentation Block */
                    buffer_if.wr_en = 1'b0;
                    buffer_if.data_in = '0 ;
                    buffer_if.no_loc_wr ='b0 ; 
                    //   buffer_if.empty_loc;  // it is an input to this block 
                
            /* ECRC Block */
                    ecrc_if.CRC_i_Message = '0 ;
                    ecrc_if.CRC_i_Length = 0;
                    ecrc_if.CRC_i_EN = 1'b0 ;
                    ecrc_if.CRC_i_Seed = ;  // Complete
                    ecrc_if.CRC_i_Seed_Load = ; //  Complete

                
                
        // State Transition 
            if (recorder_if.available  != FIFO_DEPTH )  
                begin 
                next_state = selection_state ;
                
                    if (recorder_if.available  == FIFO_DEPTH - 1'b1 )
                        begin 
                            recorder_if.rd_en = 1'b1 ;
                            recorder_if.rd_mode = 3'b1 ;
                        end 
                    else begin 
                            recorder_if.rd_en = 1'b1 ;
                            recorder_if.rd_mode = 3'b10 ;
                    end                
                end 
            else begin
                next_state = IDLE ; 
            end                 
        end 
        selection_state : begin 
                // Output of State
                    source_1 = recorder_if.rd_data_1  ;
                    source_2 = recorder_if.rd_data_2  ;
                    
                    
                    
                        
                    
                // State Transition 
        end 
        start_storing_tlp : begin 
                // Output of State
                
                
                // State Transition 
        end 
        storing_beats : begin 
                // Output of State
                
                
                // State Transition 
        end 
    endcase
end 

endmodule

