/************************/
/* Module Name	: Slave_tb.sv                             		    */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 03-04-2024					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: -							                        */
/* Summary:  This file includes the randomized and self checking testbench for  axi slave */
/************************/
`timescale 1ns/1ps
module Slave_tb ();
    import axi_slave_package::*;
    int arr[3] = {1,1,5};
    int k ; 
    // Global Siganl definition (Clock and Rest signals)
    bit axi_clk,ARESTn;//rst;

    // Create interface Objects
    // Interface  signals to AXI SLAVE 
    axi_if u_axi_if ();
    // Master
    Master_Interface Master_if ();
    // P2A interface with Rx Router
    P2A_Rx_Router_Interface #(
        .DATA_WIDTH(1024)
    ) P2A_Rx_Router_if ();


localparam TEST_CASES = 2;
logic selection;

function logic [4:0] Ceil_mod_5(input logic [9:0] in);
    // if length % 32 == 0
    // if (in ==? 10'b??_???0_0000) begin
    if ((in & 10'b00_0001_1111) == 10'b00_0000_0000) begin
        return (in >> 5);
    end
    else begin
        return (in >> 5) + 1;        
    end
endfunction

    // Signals from Arbiter -  Input  
    logic axi_req_wr_grant, axi_req_rd_grant;

    // Signals from AXI Slave - Output
    logic           axi_wrreq_hdr_valid, axi_rdreq_hdr_valid;
    tlp_header_t    axi_wrreq_hdr, axi_rdreq_hdr; 
    logic [AXI_MAX_NUM_BYTES * 8 - 1 : 0] axi_req_data; 

    // DUT instantiation 

    Slave_Top u_Slave_Top (
        axi_clk,
        ARESTn,
        // Request Path 
        u_axi_if,
        REQUESTER_ID, // hard wired requester ID
        axi_req_wr_grant,
        axi_req_rd_grant,
        axi_wrreq_hdr_valid,
        axi_wrreq_hdr,
        axi_rdreq_hdr_valid,
        axi_rdreq_hdr,
        axi_req_data,
        // Response Path
        Master_if,
        P2A_Rx_Router_if
    );


    int AWID ;
    int AWADDR ;
    int AWLEN ;
    int AWSIZE ;
    int AWBURST ;  //Incr  burst is only supported in this test bench
    int AWUSER ;
    int WID ; 
    int i ;
    int w_req ;

    int ARID;
    int ARADDR;
    int ARSIZE;

  

                /*************************/
    task initialization ();
        begin 
            u_axi_if.AWID = 'd0;
            u_axi_if.AWADDR = 'd0;
            u_axi_if.AWLEN = 'd0;
            u_axi_if.AWSIZE = 'd0;
            u_axi_if.AWVALID = 'd0;
            u_axi_if.AWUSER = 'd0;
            u_axi_if.AWBURST = 'd0;
            u_axi_if.WID = 'd0;
            u_axi_if.WDATA = 'd0;
            u_axi_if.WSTRB = 'd0;
            u_axi_if.WVALID = 'd0;
            u_axi_if.WLAST = 'd0;
            u_axi_if.ARID = 'd0;
            u_axi_if.ARADDR = 'd0;
            u_axi_if.ARLEN = 'd0;
            u_axi_if.ARSIZE = 'd0;
            u_axi_if.ARVALID = 'd0;
            u_axi_if.ARBURST = 'd0;
            u_axi_if.ARUSER = 'd0;

        end 
    endtask
    task Write_request_AW ( input int AWID, input int AWADDR, input int AWLEN, input int AWSIZE, 
                            input int AWVALID, input int AWUSER, input int AWBURST,
                            input int AWFIFO_full, input int WFIFO_full, input int WFIFO_empty_loc
                        );
        begin 
                        u_axi_if.AWID = AWID;
                        u_axi_if.AWADDR = AWADDR;
                        u_axi_if.AWLEN = AWLEN;
                        u_axi_if.AWSIZE = AWSIZE;
                        u_axi_if.AWVALID = AWVALID;
                        u_axi_if.AWUSER = AWUSER;
                        u_axi_if.AWBURST = AWBURST;



        end 
        
    endtask

    task Write_request_W (  input int WID, input int WDATA, input int WSTRB, input int WVALID, 
                            input int WLAST
                        );
        begin 
                        u_axi_if.WID = WID;
                        u_axi_if.WDATA = WDATA;
                        u_axi_if.WSTRB = WSTRB;
                        u_axi_if.WVALID = WVALID;
                        u_axi_if.WLAST = WLAST;
        end 
    endtask

// Task to send read request (AR Channel)
    task read_request_AR   (input int ARID, input int ARADDR, input int ARLEN, input int ARSIZE, 
                            input int ARVALID, input int ARUSER, input int ARBURST,
                            input int ARFIFO_full
                            );
        begin 
                        u_axi_if.ARID = ARID;
                        u_axi_if.ARADDR =ARADDR ;
                        u_axi_if.ARLEN = ARLEN;
                        u_axi_if.ARSIZE = ARSIZE;
                        u_axi_if.ARVALID = ARVALID;
                        u_axi_if.ARBURST = ARBURST;
                        u_axi_if.ARUSER = ARUSER;
        end 
endtask

    // Clock Generation Block
    initial begin : clk_gen
                    forever #(CLK_PERIOD/2) axi_clk=~axi_clk;        
            end
    
    initial begin        
        $dumpfile ("Slave_tb.vcd");
        $dumpvars ();
        axi_clk =   1'b0 ;
        ARESTn = 1'b0 ; // assert reset signal 
        @(negedge axi_clk)
        ARESTn = 1'b0; // assert reset signal
        axi_req_wr_grant = 1'b0 ;
        axi_req_rd_grant = 1'b0 ;

        // initialize  the signals
        initialization();
        #(CLK_PERIOD)
        ARESTn = 1'b1; // deassert reset signal
        //rst    = 1'b0 ;
        
        repeat (TEST_CASES) begin 
            // start of test - Read Request            

            ARID = $urandom_range( 7,  1);
            ARADDR = $urandom_range('hffff_ffff,'h0); 
            ARSIZE = $urandom_range(7,0) ;


            // start of test - write request
            AWID = $urandom_range( 7,  1);
            AWADDR = $urandom_range('hffff_ffff,'h0);
            //AWLEN = ;
            
            AWBURST = 1;  //Incr  burst is only supported in this test bench
            k = $urandom_range (2,0);
            AWUSER = arr[k];
                                //110       101
                                //111       001
                                //011       010
                                //100
                                //000
            if (AWUSER == 3'b010) begin 
                AWLEN = 1'b0;  // 256
                AWSIZE =3'd2 ; //$urandom_range(7,0)
            end 
            else begin
                AWLEN = $urandom_range (15,1);  // 256
                AWSIZE =$urandom_range(7,0) ; //$urandom_range(7,0)
            end 

            read_request_AR(ARID,ARADDR,AWLEN,ARSIZE,1'b1,1'b1,1'b1,1'b0); 
            Write_request_AW(AWID,AWADDR,AWLEN,AWSIZE,1,AWUSER,AWBURST,0,0,256);
                // 1 --> AWVALID -- 0 --> AWFIFO FULL -- 0 --> WFIFO FULL -- 16 --> Empty Loc.


        fork
            begin :  wait_for_write_response
                wait ((u_axi_if.AWREADY == 1));
                begin 
                    // de-assert the request 
                    #CLK_PERIOD
                            u_axi_if.AWID      = 'b0;
                            u_axi_if.AWADDR    = 'b0;
                            u_axi_if.AWLEN     = 'b0;
                            u_axi_if.AWSIZE    = 'b0;
                            u_axi_if.AWVALID   = 'b0;
                            u_axi_if.AWUSER    = 'b0;
                            u_axi_if.AWBURST   = 'b0;


                    WID = AWID;
                    i = AWLEN + 1;

                    // #CLK_PERIOD
                    // #CLK_PERIOD
                    while  (i >= 0 )
                        begin 
                            if (i == 1)
                                begin 
                                    Write_request_W (WID,1024, 3 , 1'b1, 1'b1 );
                                    #CLK_PERIOD
                                    i = i - 1 ;
                                end
                            else if (i == 0)
                                begin
                                    u_axi_if.WID =  'b0;
                                    u_axi_if.WDATA =  'b0;
                                    u_axi_if.WSTRB =  'b0;
                                    u_axi_if.WVALID =  'b0;
                                    u_axi_if.WLAST =  'b0;
                                    i = i - 1;
                                end
                            else begin 
                                        Write_request_W (WID,$urandom_range(32'hFFFF_FFFF,32'h1111_1111), 'b1111_1111 , 1'b1, 1'b0 );
                                        #CLK_PERIOD
                                        wait (u_axi_if.WREADY == 1);
                                        begin 
                                                    i = i - 1;
                                        end
                            end
                                    end
                end
            end 


            begin : wait_for_read_response
                wait (u_axi_if.ARREADY == 1);
                begin 
                    // de-assert the request 
                    #CLK_PERIOD
                        u_axi_if.ARID = 'd0;
                        u_axi_if.ARADDR = 'd0;
                        u_axi_if.ARLEN = 'd0;
                        u_axi_if.ARSIZE = 'd0;
                        u_axi_if.ARVALID = 'd0;
                        u_axi_if.ARBURST = 'd0;
                        u_axi_if.ARUSER = 'd0;
            end 
        end  
        join

        @(posedge axi_wrreq_hdr_valid) 
        axi_req_wr_grant = 1'b1 ;

        // @(posedge axi_rdreq_hdr_valid) 
        // axi_req_rd_grant = 1'b1 ;

        #CLK_PERIOD
        axi_req_wr_grant = 1'b0 ;
        #CLK_PERIOD
        axi_req_rd_grant = 1'b0 ;

        end

            
            #(20*CLK_PERIOD)        
            $stop;
    end

/*** Stimulus Generation ***/
    int kk = 0;
    initial begin
        // Normal Test Cases
        ARESTn                                  = 1'b0; 
        // Rx Router Info
        P2A_Rx_Router_if.Resp_HDR               = '0;
        P2A_Rx_Router_if.Resp_Valid             = 1'b0;
        P2A_Rx_Router_if.Resp_Data              = '0;
        // Master Ready
        Master_if.B_Channel_Msr.BREADY          = 1'b0;
        Master_if.R_Channel_Msr.RREADY          = 1'b0;
        #CLK_PERIOD
        #(CLK_PERIOD/2)
        ARESTn                                    = 1'b1; 
        // #CLK_PERIOD
        // Master_if.B_Channel_Msr.BREADY          = 1'b1;
        // Master_if.R_Channel_Msr.RREADY          = 1'b1;
        for (int i = 0;i < REQUESTER_RECORDER_DEPTH; i++) begin
            // $display("Heeeeeeeere");
            // u_Slave_Top.u_Request_Recorder.MEM[i]           = {$urandom() % 256, 1'b1};        
        end

        P2A_Rx_Router_if.Resp_HDR.T9            = '0;
        P2A_Rx_Router_if.Resp_HDR.TC            = '0;
        P2A_Rx_Router_if.Resp_HDR.T8            = '0;
        P2A_Rx_Router_if.Resp_HDR.Attr1         = '0;
        P2A_Rx_Router_if.Resp_HDR.LN            = '0;
        P2A_Rx_Router_if.Resp_HDR.TH            = '0;
        P2A_Rx_Router_if.Resp_HDR.TD            = '0;
        P2A_Rx_Router_if.Resp_HDR.EP            = '0;
        P2A_Rx_Router_if.Resp_HDR.Attr2         = '0;
        P2A_Rx_Router_if.Resp_HDR.AT            = '0;
        P2A_Rx_Router_if.Resp_HDR.Completer_ID  = 16'habcd;
        P2A_Rx_Router_if.Resp_HDR.BCM           = '0;
        P2A_Rx_Router_if.Resp_HDR.Requester_ID  = 16'h1234;
        P2A_Rx_Router_if.Resp_HDR.Byte_Count    = 1;
        P2A_Rx_Router_if.Resp_HDR.Rsvd          = '0;
        P2A_Rx_Router_if.Resp_HDR.Lower_Address = '0;

        repeat(TEST_CASES) begin
            selection = 1; // $urandom() % 2;
            $monitor("selection: %s", P2A_Rx_Router_if.Resp_HDR.fmt);
            // CPL
            if (selection == 0) begin
                Master_if.B_Channel_Msr.BREADY          = 1'b1;
                P2A_Rx_Router_if.Resp_Valid             = 1'b1;
                P2A_Rx_Router_if.Resp_HDR.fmt           = TLP_FMT_3DW;
                P2A_Rx_Router_if.Resp_HDR.Type          = TLP_TYPE_CPL;
                P2A_Rx_Router_if.Resp_HDR.Length        = 1;
                P2A_Rx_Router_if.Resp_HDR.Tag           = '0;
                @(posedge axi_wrreq_hdr_valid);
                P2A_Rx_Router_if.Resp_HDR.Tag           = axi_wrreq_hdr.Tag;
                P2A_Rx_Router_if.Resp_HDR.Cpl_Status    = UR;
                P2A_Rx_Router_if.Resp_Data              = '0;
                // delay for getting grant from P2A
                @(posedge P2A_Rx_Router_if.Resp_Grant)
                #CLK_PERIOD;
                P2A_Rx_Router_if.Resp_HDR               = '0;
                P2A_Rx_Router_if.Resp_Valid             = 1'b0;
                P2A_Rx_Router_if.Resp_Data              = '0;
                #CLK_PERIOD;
            end
            // CPLD
            else if (selection == 1) begin
                Master_if.R_Channel_Msr.RREADY          = 1'b1;
                P2A_Rx_Router_if.Resp_Valid             = 1'b1;
                P2A_Rx_Router_if.Resp_HDR.fmt           = TLP_FMT_3DW_DATA;
                P2A_Rx_Router_if.Resp_HDR.Type          = TLP_TYPE_CPLD;
                P2A_Rx_Router_if.Resp_HDR.Length        = $urandom() % (32*R_FIFO_DEPTH);
                P2A_Rx_Router_if.Resp_HDR.Tag           = '0;
                @(posedge axi_wrreq_hdr_valid);
                P2A_Rx_Router_if.Resp_HDR.Tag           = axi_wrreq_hdr.Tag;
                P2A_Rx_Router_if.Resp_HDR.Cpl_Status    = CRS;
                P2A_Rx_Router_if.Resp_Data              = $urandom() % 255;            
                // delay for getting grant from P2A
                @(posedge P2A_Rx_Router_if.Resp_Grant)
                P2A_Rx_Router_if.Resp_Data              = $urandom() % 255;            
                #CLK_PERIOD
                P2A_Rx_Router_if.Resp_Valid             = 1'b1;
                while (kk < (Ceil_mod_5(P2A_Rx_Router_if.Resp_HDR.Length) - 2)) begin
                    P2A_Rx_Router_if.Resp_Data          = $urandom() % 255;  
                    Master_if.R_Channel_Msr.RREADY      = $urandom() % 2;          
                    #CLK_PERIOD;    
                    kk = (Master_if.R_Channel_Msr.RREADY) ? kk++ : kk;                    
                end
                P2A_Rx_Router_if.Resp_HDR               = '0;
                P2A_Rx_Router_if.Resp_Valid             = 1'b0;
                P2A_Rx_Router_if.Resp_Data              = '0;
                #CLK_PERIOD;
            end
        end
        #(30*CLK_PERIOD);
        // $stop();
    end


endmodule