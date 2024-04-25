
/********************************************************************/
/* Module Name	: axi_slave_fsm_wr_tb.sv                  		    */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 27-03-2024					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: -							                        */
/* Summary:  This file includes the simple testbench for  FSM       */
/********************************************************************/
`timescale 1ns/1ps



module axi_slave_fsm_tb ();


    import axi_slave_package::*;


    // Global Siganl definition (Clock and Rest signals)
    reg axi_clk,ARESTn;

    // Create inteface Objects
    // Interface  signals to AXI SLAVE 
    axi_if u_axi_if ();
    // Interface  signals to FIFOs  
    FIFOs_if u_FIFOs_if();

    // DUT instantiation 

    // FSM for Write Request 
    axi_push_fsm_wr u_axi_push_fsm_wr (
                                                .axi_clk(axi_clk),
                                                .ARESTn(ARESTn),
                                                .std_wr_push_fsm_if(u_axi_if.axi_slave_request_push_fsm_wr),
                                                .wr_fifos_if(u_FIFOs_if.axi_slave_request_push_fsm_wr)
    );
    // FSM for Read Request -- 
    axi_slave_fsm_rd u_axi_slave_fsm_rd (
                                                .axi_clk(axi_clk),
                                                .ARESTn(ARESTn),
                                                .std_rd_push_fsm_if(u_axi_if.axi_slave_request_push_fsm_rd),
                                                .rd_fifos_if(u_FIFOs_if.axi_slave_request_push_fsm_rd)
    );

                /***************************************************************************/
    task initialization ();
        begin 
            u_axi_if.axi_slave_request_push_fsm_wr_tb.AWID = 'd0;
            u_axi_if.axi_slave_request_push_fsm_wr_tb.AWADDR = 'd0;
            u_axi_if.axi_slave_request_push_fsm_wr_tb.AWLEN = 'd0;
            u_axi_if.axi_slave_request_push_fsm_wr_tb.AWSIZE = 'd0;
            u_axi_if.axi_slave_request_push_fsm_wr_tb.AWVALID = 'd0;
            u_axi_if.axi_slave_request_push_fsm_wr_tb.AWUSER = 'd0;
            u_axi_if.axi_slave_request_push_fsm_wr_tb.AWBURST = 'd0;
            u_axi_if.axi_slave_request_push_fsm_wr_tb.WID = 'd0;
            u_axi_if.axi_slave_request_push_fsm_wr_tb.WDATA = 'd0;
            u_axi_if.axi_slave_request_push_fsm_wr_tb.WSTRB = 'd0;
            u_axi_if.axi_slave_request_push_fsm_wr_tb.WVALID = 'd0;
            u_axi_if.axi_slave_request_push_fsm_wr_tb.WLAST = 'd0;
            u_axi_if.axi_slave_request_push_fsm_rd_tb.ARID = 'd0;
            u_axi_if.axi_slave_request_push_fsm_rd_tb.ARADDR = 'd0;
            u_axi_if.axi_slave_request_push_fsm_rd_tb.ARLEN = 'd0;
            u_axi_if.axi_slave_request_push_fsm_rd_tb.ARSIZE = 'd0;
            u_axi_if.axi_slave_request_push_fsm_rd_tb.ARVALID = 'd0;
            u_axi_if.axi_slave_request_push_fsm_rd_tb.ARBURST = 'd0;
            u_axi_if.axi_slave_request_push_fsm_rd_tb.ARUSER = 'd0;
            u_FIFOs_if.axi_slave_request_push_fsm_wr_tb.AWFIFO_full = 1'b0;
            u_FIFOs_if.axi_slave_request_push_fsm_wr_tb.WFIFO_full = 1'b0;
            u_FIFOs_if.axi_slave_request_push_fsm_wr_tb.WFIFO_empty_loc = 'd0;
            u_FIFOs_if.axi_slave_request_push_fsm_rd_tb.ARFIFO_full = 1'b0;
        end 
    endtask


    task Write_request_AW ( input int AWID, input int AWADDR, input int AWLEN, input int AWSIZE, 
                            input int AWVALID, input int AWUSER, input int AWBURST,
                            input int AWFIFO_full, input int WFIFO_full, input int WFIFO_empty_loc
                        );
        begin 
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.AWID = AWID;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.AWADDR = AWADDR;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.AWLEN = AWLEN;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.AWSIZE = AWSIZE;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.AWVALID = AWVALID;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.AWUSER = AWUSER;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.AWBURST = AWBURST;

                        u_FIFOs_if.axi_slave_request_push_fsm_wr_tb.AWFIFO_full = AWFIFO_full;
                        u_FIFOs_if.axi_slave_request_push_fsm_wr_tb.WFIFO_full = WFIFO_full;
                        u_FIFOs_if.axi_slave_request_push_fsm_wr_tb.WFIFO_empty_loc = WFIFO_empty_loc;

        end 
        
    endtask

    task Write_request_W (  input int WID, input int WDATA, input int WSTRB, input int WVALID, 
                            input int WLAST
                        );
        begin 
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.WID = WID;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.WDATA = WDATA;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.WSTRB = WSTRB;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.WVALID = WVALID;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.WLAST = WLAST;
        end 
    endtask

// Task to send read request (AR Channel)
    task read_request_AR   (input int ARID, input int ARADDR, input int ARLEN, input int ARSIZE, 
                            input int ARVALID, input int ARUSER, input int ARBURST,
                            input int ARFIFO_full
                            );
        begin 
                        u_axi_if.axi_slave_request_push_fsm_rd_tb.ARID = ARID;
                        u_axi_if.axi_slave_request_push_fsm_rd_tb.ARADDR =ARADDR ;
                        u_axi_if.axi_slave_request_push_fsm_rd_tb.ARLEN = ARLEN;
                        u_axi_if.axi_slave_request_push_fsm_rd_tb.ARSIZE = ARSIZE;
                        u_axi_if.axi_slave_request_push_fsm_rd_tb.ARVALID = ARVALID;
                        u_axi_if.axi_slave_request_push_fsm_rd_tb.ARBURST = ARBURST;
                        u_axi_if.axi_slave_request_push_fsm_rd_tb.ARUSER = ARUSER;
                        u_FIFOs_if.axi_slave_request_push_fsm_rd_tb.ARFIFO_full = ARFIFO_full;
        end 
endtask



    // Clock Generation Block
    initial begin : clk_gen
                    axi_clk =   1'b0 ; 
                    forever #(CLK_PERIOD/2) axi_clk=~axi_clk;        
            end
    
    initial begin
        
        //$dumpfile("axi_slave.vcd");
        //$dumpvars(1,"+all");
        // start of test - write request
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


        
        ARESTn = 1'b0; // assert reset signal       
        @(negedge axi_clk)
        ARESTn = 1'b0; // assert reset signal
        // initialize  the signals
        initialization();
        #(CLK_PERIOD)
        ARESTn = 1'b1; // deassert reset signal
        



    repeat (5) begin 
        // start of test - Read Request            

            ARID = $urandom_range( 7,  1);
            ARADDR = $urandom_range('hffff_ffff,'h0); 
            ARSIZE = $urandom_range(7,0) ;


        // start of test - write request
        AWID = $urandom_range( 7,  1);
        AWADDR = $urandom_range('hffff_ffff,'h0);
        //AWLEN = 4;
        AWLEN = $urandom_range (256,1);
        AWSIZE = $urandom_range(7,0);
        AWBURST = 1;  //Incr  burst is only supported in this test bench
        AWUSER = $urandom_range(7,0);
        
        
        read_request_AR(ARID,ARADDR,AWLEN,ARSIZE,1'b1,1'b1,1'b1,1'b0); 

        Write_request_AW(AWID,AWADDR,AWLEN,AWSIZE,1,AWUSER,AWBURST,0,0,256);
            // 1 --> AWVALID -- 0 --> AWFIFO FULL -- 0 --> WFIFO FULL -- 16 --> Empty Loc.


    fork
        begin :  wait_for_write_response
            wait ((u_axi_if.axi_slave_request_push_fsm_wr_tb.AWREADY == 1));
            begin 
                // de-assert the request 
                #CLK_PERIOD
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.AWID      = 'b0;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.AWADDR    = 'b0;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.AWLEN     = 'b0;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.AWSIZE    = 'b0;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.AWVALID   = 'b0;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.AWUSER    = 'b0;
                        u_axi_if.axi_slave_request_push_fsm_wr_tb.AWBURST   = 'b0;


                WID = AWID;
                i = AWLEN;

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
                                u_axi_if.axi_slave_request_push_fsm_wr_tb.WID =  'b0;
                                u_axi_if.axi_slave_request_push_fsm_wr_tb.WDATA =  'b0;
                                u_axi_if.axi_slave_request_push_fsm_wr_tb.WSTRB =  'b0;
                                u_axi_if.axi_slave_request_push_fsm_wr_tb.WVALID =  'b0;
                                u_axi_if.axi_slave_request_push_fsm_wr_tb.WLAST =  'b0;
                                i = i - 1;
                            end
                        else begin 
                                    Write_request_W (WID,$urandom_range(32'hFFFF_FFFF,32'h1111_1111), 'b1111_1111 , 1'b1, 1'b0 );
                                    #CLK_PERIOD
                                    wait (u_axi_if.axi_slave_request_push_fsm_wr_tb.WREADY == 1);
                                    begin 
                                                i = i - 1;
                                    end
                        end
                                end
            end
        end 


        begin : wait_for_read_response
            wait (u_axi_if.axi_slave_request_push_fsm_rd_tb.ARREADY == 1);
            begin 
                // de-assert the request 
                #CLK_PERIOD
                    u_axi_if.axi_slave_request_push_fsm_rd_tb.ARID = 'd0;
                    u_axi_if.axi_slave_request_push_fsm_rd_tb.ARADDR = 'd0;
                    u_axi_if.axi_slave_request_push_fsm_rd_tb.ARLEN = 'd0;
                    u_axi_if.axi_slave_request_push_fsm_rd_tb.ARSIZE = 'd0;
                    u_axi_if.axi_slave_request_push_fsm_rd_tb.ARVALID = 'd0;
                    u_axi_if.axi_slave_request_push_fsm_rd_tb.ARBURST = 'd0;
                    u_axi_if.axi_slave_request_push_fsm_rd_tb.ARUSER = 'd0;
        end 
    end  
    join

end 
        

            // if (w_req == 1)
            //     begin 
                        
            //     end 

        //     if (w_req)
        //     begin 
        //     // @(negedge axi_clk)
        //     WID = AWID;
        //    // int WDATA = $urandom_range(32'hFFFF_FFFF,32'h1111_1111);
        //     i = AWLEN;
        //     while  (i > 0 )
        //         begin 
        //             if (i == 1)
        //                 begin 
        //                     int size ;
        //                     byte data[128];
        //                     size = $urandom % 128 + 1 ;
        //                     randomize(data) with {
        //                         size == size;
        //                     };
        //                     Write_request_W (WID,{$shortint( data )}, size , 1'b1, 1'b1 );
        //                 end 
        //             else begin 
        //                         Write_request_W (WID,$urandom_range(32'hFFFF_FFFF,32'h1111_1111), 'b1111_1111 , 1'b1, 1'b0 );
        //                         wait (u_axi_if.axi_slave_request_push_fsm_wr_tb.WREADY == 1);
        //                         begin 
        //                                     i = i - 1;
        //                         end
        //             end
        //                      end 
        //                     end 

        #(2*CLK_PERIOD)
        
        $stop;

    end


// int AWID = $urandom_range(maxval = 7, minval = 1);
// int AWADDR = $urandom_range('hffff_ffff,'h0);
// int AWLEN = $urandom_range (256,1);
// int AWSIZE = $urandom_range(7,0);
// int AWBURST = 1;  //Incr  burst is only supported in this test bench
// int AWUSER = $urandom_range(7,0);


// int ARID = $urandom_range(maxval = 7, minval = 1);
// int ARADDR = $urandom_range('hffff_ffff,'h0);
// int ARLEN = $urandom_range (256,1);
// int ARSIZE = $urandom_range(7,0);
// int ARBURST = 1;  //Incr  burst is only supported in this test bench
// int ARUSER = $urandom_range(7,0);



initial begin 

    $monitor ("AWReady = %d",u_axi_if.axi_slave_request_push_fsm_wr_tb.AWREADY);

end 






endmodule