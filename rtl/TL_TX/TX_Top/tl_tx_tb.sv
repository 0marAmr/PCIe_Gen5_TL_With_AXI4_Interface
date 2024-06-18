/********************************************************************/
/* Module Name	: tl_tx.sv                                          */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 3-05-2024 					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: this integration between all submodules of tl tx  */
/********************************************************************/
import Tx_Arbiter_Package::*;
import Fragmentation_Package::*;
import axi_slave_package::*; 

module tl_tx_tb ();

/*************************  Signals - Integers - Parameters **********************************/
    /************ Global Signals ************/
        bit clk;     
        bit arst;   

    /************ Internal Signals ************/
        logic [FC_HDR_WIDTH  - 1 : 0]   HdrFC;
        logic [FC_DATA_WIDTH - 1 : 0]   DataFC;
        FC_type_t                       TypeFC;
        logic                           config_ecrc;

        // Master Interface 
        logic                           axi_master_valid;
        logic                           axi_master_grant;
        logic [3*DW - 1 : 0 ]           axi_master_hdr ; 
        logic [32*DW - 1 : 0]           axi_comp_data ; 

        // RX Router Interface 
        logic [1:0]                     rx_router_valid ; 
        logic                           rx_router_grant ; 
        logic [4*DW - 1 : 0 ]           rx_router_msg_hdr ; 
        logic [3*DW - 1 : 0 ]           rx_router_comp_hdr ; 
        logic [1*DW - 1 : 0 ]           rx_router_data ; 


        logic [$clog2(ARFIFO_DEPTH ) -1  : 0] ARID;
        logic [$clog2(AWFIFO_DEPTH ) -1  : 0] AWID;
        logic [$clog2(ARFIFO_DEPTH ) -1  : 0] AR_queue[$];
        logic [$clog2(AWFIFO_DEPTH ) -1  : 0] AW_queue[$];

        logic [LENGTH_WIDTH - 1  :0] rx_router_length; 
        logic [LENGTH_WIDTH - 1 :0] axi_master_length; 


    /****************  Integers ***************/
        int WID ; 
        int i,k,m ;
        integer number_of_tlps ;

    /************ local parameters ************/
        localparam CLK_PERIOD = 10;
        localparam TEST_CASES = 128 ;

/********************************  Clock Generation  ****************************************/
    always  begin
        clk = ~ clk;
        #(CLK_PERIOD/2);
    end

    /********************************  Master Initialization  ****************************************/
        // initalize master 
        task initialization_master ();
            axi_master_valid                = 1'b0;
            axi_master_hdr                  = '0;
            axi_comp_data                   = '0;
        endtask
    /********************************  Rx-Router Initialization  ************************************/
        // initalize master 
        task initialization_rx_router ();
            rx_router_valid     = 2'b00    ; 
            rx_router_msg_hdr   = '0       ; 
            rx_router_comp_hdr  = '0       ;
            rx_router_data      = '0       ; 
        endtask


    /********************* Initialization for 5 Channels  *********************/
        task initialization_AW ();
            begin 
                u_axi_if.AWID       = 'd0;
                u_axi_if.AWADDR     = 'd0;
                u_axi_if.AWLEN      = 'd0;
                u_axi_if.AWSIZE     = 'd0;
                u_axi_if.AWVALID    = 'd0;
                u_axi_if.AWUSER     = 'd0;
                u_axi_if.AWBURST    = 'd0;
            end 
        endtask
    
        task initialization_W ();
            begin 
                u_axi_if.WID    = 'd0;
                u_axi_if.WDATA  = 'd0;
                u_axi_if.WSTRB  = 'd0;
                u_axi_if.WVALID = 'd0;
                u_axi_if.WLAST  = 'd0;
            end 
        endtask
    
        task initialization_AR ();
            begin 
                u_axi_if.ARID       = 'd0;
                u_axi_if.ARADDR     = 'd0;
                u_axi_if.ARLEN      = 'd0;
                u_axi_if.ARSIZE     = 'd0;
                u_axi_if.ARVALID    = 'd0;
                u_axi_if.ARBURST    = 'd0;
                u_axi_if.ARUSER     = 'd0;
            end 
        endtask

       // ADD R and B 

    /************ Write Requests and their response ( AW - W - B) ************/

        task Write_request_AW (logic [$clog2(ARFIFO_DEPTH ) -1 : 0 ] AWID);
            begin 
                static int arr[3] = {1,2,5};
                int k ; 
                // start of test - write request
                u_axi_if.AWID        = AWID;
                u_axi_if.WID    = u_axi_if.AWID;
    
                u_axi_if.AWADDR      = $urandom_range('hffff_ffff,'h0);
                u_axi_if.AWBURST     = 1;  //Incr burst is only supported in this test bench
                k                    = $urandom_range (2,0);
                u_axi_if.AWUSER      = arr[k];
                                     //110       101
                                     //111       001
                                     //011       010
                                     //100
                                     //000
                // if need to send more than one beat, AWSIZE must be maximum
                // else be anything
                if (u_axi_if.AWUSER == 3'b010 || u_axi_if.AWUSER == 3'b110 ) begin  // here is IO , must be 1 DW 
                    u_axi_if.AWLEN =  1'b0;  // 256
                    u_axi_if.AWSIZE = $urandom_range(7,0) ; //  3'd2 ;
                end 
                else begin
                    u_axi_if.AWLEN = $urandom_range (31,0);  // 256  // use to 32 to avoid the data length be greater than 1024 DW
                    if (u_axi_if.AWLEN > 1) begin
                        u_axi_if.AWSIZE = 7;
                    end
                    else begin
                        u_axi_if.AWSIZE = $urandom_range(7,0) ;                
                    end
                end 
                // u_axi_if.AWSIZE      = 5   ;
                // u_axi_if.AWLEN       = 0; //$urandom_range (15,0);  
                u_axi_if.AWVALID     = 1'b1;
            end
        endtask

        task Write_request_W (  input int WID, input int WDATA, input int WSTRB, input int WVALID, input int WLAST );
           begin 
           // u_axi_if.WID    = WID;
           u_axi_if.WDATA  = WDATA;
           u_axi_if.WSTRB  = WSTRB;
           u_axi_if.WVALID = WVALID;
           u_axi_if.WLAST  = WLAST;
           end 
           endtask

        task read_request_AR (logic [$clog2(ARFIFO_DEPTH ) -1 : 0 ] ARID);
            begin 
                static int arr[3] = {1,2,5};
                int k ; 
                // start of test - Read Request            
                u_axi_if.ARID   = ARID;
                u_axi_if.ARADDR = $urandom_range('hffff_ffff,'h0); 
                u_axi_if.ARSIZE = $urandom_range(7,0) ;
                k               = $urandom_range (2,0);
                u_axi_if.ARUSER      = arr[2];
                                     //110       101
                                     //111       001
                                     //011       010
                                     //100
                                     //000
                if (u_axi_if.ARUSER == 3'b010) begin 
                    u_axi_if.ARLEN = 1'b0;  // 256
                end 
                else begin
                    u_axi_if.ARLEN = $urandom_range (15,1);  // 256
                end 
    
                u_axi_if.ARVALID    = 1'b1;
                u_axi_if.ARBURST    = 1'b1;
                // u_axi_if.ARUSER     = u_axi_if.AWUSER;
            end 
        endtask
    
    
    /*************** Read Requests and their response ( AR - R) *************/

    /****************************** Special Tasks ****************************/
        // Task to generate cyclic IDs
        task automatic ID_randomize(  ref logic [$clog2(ARFIFO_DEPTH ) -1  : 0] q[$],
            output logic [$clog2(ARFIFO_DEPTH ) -1  : 0] x );
            logic temp = 1'b0;
            while(!temp) begin
                x 		= $urandom_range((ARFIFO_DEPTH/2) - 1, 0);
            foreach (q[i]) begin
                if (x == q[i]) begin
                    break;
                end
                if (i == (q.size() - 1)) begin
                    q.push_front(x);
                    temp = 1'b1;
                    break;
                end
            end
            end
        endtask
    
    

    /************ Stimulus Generations ************/
    // Generate  Write Requests from AXI Master (In APP. Layer)
        initial begin        
        $dumpfile ("tl_tx_tb.vcd");
        $dumpvars ();
        clk         = 1'b0 ;
        arst        = 1'b0 ;
        config_ecrc = 1'b1;
        @(negedge clk)
        arst        = 1'b0; // assert reset signal
        // initialize  the signals
        initialization_AW();
        initialization_W();
        #(CLK_PERIOD)
        arst = 1'b1; // de-assert reset signal
        AW_queue.push_front($urandom_range(AWFIFO_DEPTH - 1, 0));
        repeat (TEST_CASES) begin 
            // channel signals assertions
            ID_randomize(AW_queue, AWID);
            Write_request_AW(AWID);
            WID = u_axi_if.AWID;
            wait ((u_axi_if.AWREADY == 1));
            $display("AWLEN: %d", u_axi_if.AWLEN);
            i   = u_axi_if.AWLEN + 1;
            $display("i: %d", i);
            // de-assert the request 
            #CLK_PERIOD
            initialization_AW();
            while  (i >= 0 ) begin 
                if (i == 1) begin 
                            Write_request_W(WID, 1024, 2 , 1'b1, 1'b1);  // make a function to take a data randomized as input --> return strobe
                            // 1024 : 10'b000400
                            #CLK_PERIOD;
                        end
                else if (i == 0) begin
                            initialization_W();
                            u_axi_if.WID    =  'b0;
                            u_axi_if.WDATA  =  'b0;
                            u_axi_if.WSTRB  =  'b0;
                            u_axi_if.WVALID =  'b0;
                            u_axi_if.WLAST  =  'b0;
                        end
                else begin 
                    Write_request_W (WID,$urandom_range(32'hFFFF_FFFF,32'h1111_1111), 'b1111_1111 , 1'b1, 1'b0 );
                    #CLK_PERIOD
                    wait (u_axi_if.WREADY == 1);
                end
                i = i - 1;
            end
        end
        initialization_AW();
        initialization_W();
        
        #(50 * TEST_CASES *CLK_PERIOD)        
        $fclose(file_handle);
        $display (" Number of Generated TLPs : %d", number_of_tlps ) ; 
        $stop;
    end


      // Generate sequential Read Requests from AXI Master (In APP. Layer)
           initial begin 
           @(negedge clk)
           initialization_AR();
           #(CLK_PERIOD)
           AR_queue.push_front($urandom_range(ARFIFO_DEPTH - 1, 0));
           repeat (TEST_CASES) begin 
               ID_randomize(AR_queue, ARID);
               read_request_AR(ARID); 
               wait (u_axi_if.ARREADY == 1 );
               #CLK_PERIOD;
           end
           initialization_AR();
       end 
    
    //Generate Completions without Data / with Data from Axi MASTER (In TL. Layer)
        initial begin 
            initialization_master(); 
            @(negedge clk)
            @(posedge clk)
            @(posedge clk)
            @(posedge clk)
            initialization_master(); 
            @(posedge clk)
            repeat (TEST_CASES) begin 
                axi_master_length               = $urandom_range(1023, 0);
                $display ("Length: %d", axi_master_length );
                axi_master_valid                = 1'b1; // $urandom() % 2;
                axi_master_hdr                  = {
                            // 1st DW
                                // fmt 
                                1'b0, 
                                1'b1,//$urandom_range(1, 0), 
                                1'b0,
                                5'b0_1010,
                                1'b0  ,
                                3'b000  ,      /* Traffic Class Field     */
                                1'b0  ,     
                                1'b0 ,
                                1'b0 ,
                                1'b0 ,
                                config_ecrc , // TD
                                1'b0 ,
                                2'b00 ,
                                2'b00,          /* Attribute field        */
                                axi_master_length, // 10'd1,          /* Length field           */
                               // BYTE 4   --  BYTE 5 -- BYTE 6 -- BYTE 7
                               //2nd DW
                                16'hABCD, /* Co ID */
                                8'b0000_1111,         /* Tag field              */
                                4'b000,
                                4'b1111,  
                                // BYTE 8   --  BYTE 9 -- BYTE 10 -- BYTE 11
                               // 3rd DW
                                32'h1000 /* Higher address bits */  
        }; 
        
                axi_comp_data                   = $urandom_range(255, 0); // {32'habcd_1234, 992'b0}; // 32 DW
                wait (axi_master_grant);
                if (axi_master_hdr[3*DW - 2] && ( axi_master_length >= 32)) begin 
                    for (int i = 0; i <= (axi_master_length >> 5 ) - 1 ; i++) begin
                        @(posedge clk)
                        axi_comp_data               = $urandom_range(255, 0); // {32'habcd_1234, 992'b0}; // 32 DW
                    end
                end 
                @(posedge clk)
                initialization_master(); 
                @(posedge clk);

            end 
        end


    // Generate MSGs and Completions from Rx Router (In TL. Layer)
    // CompD (cfg) Comp Msg 
    // valid 2bits : 11 error , 10 comp , 00 default , 01 rsv'd
        initial begin 
        @(negedge clk)
        @(posedge clk)
        @(posedge clk)
        @(posedge clk)
        initialization_rx_router(); 
        @(posedge clk)
        repeat (TEST_CASES) begin 
            rx_router_length               = 10'b1;
            rx_router_valid                = $urandom_range (3 , 2)  ;
    
            if (rx_router_valid == 2'b10) begin 
                rx_router_comp_hdr      = {
                            // 1st DW
                                // fmt 
                                1'b0, 
                                $urandom_range(1, 0), 
                                1'b0,
                                5'b0_1010,
                                1'b0  ,
                                3'b000  ,      /* Traffic Class Field     */
                                1'b0  ,     
                                1'b0 ,
                                1'b0 ,
                                1'b0 ,
                                config_ecrc , // TD
                                1'b0 ,
                                2'b00 ,
                                2'b00,          /* Attribute field        */
                                rx_router_length, // 10'd1,          /* Length field           */
                               // BYTE 4   --  BYTE 5 -- BYTE 6 -- BYTE 7
                               //2nd DW
                                16'hABCD, /* Co ID */
                                $urandom_range(255, 0),         /* Tag field              */
                                4'b000,
                                4'b1111,  
                                // BYTE 8   --  BYTE 9 -- BYTE 10 -- BYTE 11
                               // 3rd DW
                                32'h1000 /* Higher address bits */  
                                          }; 
                if (rx_router_comp_hdr [31 * DW - 2]) begin   // here the second bit in fmt if 1 means CompD, O.W --> Comp
                    rx_router_data = $urandom_range(255,0) ; 
                end 
            end 
            else if (rx_router_valid == 2'b11) begin  
                rx_router_comp_hdr      = {
                    // 1st DW
                        // fmt 
                        1'b0, 
                        $urandom_range(1, 0), 
                        1'b0,
                        5'b0_1010,
                        1'b0  ,
                        3'b000  ,      /* Traffic Class Field     */
                        1'b0  ,     
                        1'b0 ,
                        1'b0 ,
                        1'b0 ,
                        config_ecrc , // TD
                        1'b0 ,
                        2'b00 ,
                        2'b00,          /* Attribute field        */
                        rx_router_length, // 10'd1,          /* Length field           */
                       // BYTE 4   --  BYTE 5 -- BYTE 6 -- BYTE 7
                       //2nd DW
                        16'hABCD, /* Co ID */
                        $urandom_range(255, 0),         /* Tag field              */
                        4'b0000,
                        4'b1111,  
                        // BYTE 8   --  BYTE 9 -- BYTE 10 -- BYTE 11
                       // 3rd DW
                        32'h1000 /* Higher address bits */  
                                  };
                rx_router_msg_hdr = {
                        // 1st DW
                            // fmt 
                            3'b001,
                            5'b1_0000,
                            1'b0  ,
                            3'b000  ,      /* Traffic Class Field     */
                            1'b0  ,     
                            1'b0 ,
                            1'b0 ,
                            1'b0 ,
                            config_ecrc , // TD
                            1'b0,
                            2'b00 ,
                            2'b00 ,          /* Attribute field        */
                            10'b00_0000_0000 , // 10'd1,          /* Length field           */
                           // BYTE 4   --  BYTE 5 -- BYTE 6 -- BYTE 7
                           //2nd DW
                            16'hABCD, /* Co ID */
                            8'b0000_0000,         /* Tag field              */
                            4'b0000,
                            4'b1111,  
                            // BYTE 8   --  BYTE 9 -- BYTE 10 -- BYTE 11
                           // 3rd DW
                            32'h1000,   
                            // 4th DW
                            32'h1000 
                        };
        end 
    
            wait (rx_router_grant);
            @(posedge clk)
            initialization_rx_router(); 
            @(posedge clk);

        end 

    end

    // Driving FC credits from DLL 
        initial begin
            Frag_if.Halt_1          = 1'b0;
            Frag_if.Halt_2          = 1'b0;
            Frag_if.Throttle        = 1'b0;
            TypeFC = FC_X;     HdrFC = '0; DataFC = '0;
            #(2*CLK_PERIOD)
            TypeFC = FC_P;     HdrFC = 10 * TEST_CASES ; DataFC = 2**15;
            #(CLK_PERIOD)
            TypeFC = FC_NP;    HdrFC = 10 * TEST_CASES ; DataFC = 1000;
            #(CLK_PERIOD)
            TypeFC = FC_CPL;   HdrFC = 10 * TEST_CASES ; DataFC = 2**15;
            #(CLK_PERIOD);
        end


        initial begin 
            number_of_tlps = '0 ; 
            forever begin 
                @ (posedge Frag_if.sop)
                #(CLK_PERIOD)
                number_of_tlps = number_of_tlps + 1'b1 ;
            end 
        end 

    
    // Writing the Data in files 
        integer file_handle;
        string file_name = "output.txt"; // Define the file name and mode
        string file_mode = "w";
        initial begin
                file_handle = $fopen(file_name, file_mode);
                $fmonitor(file_handle, "Time: %0t, A2P1 HDR: 0x%x , A2P1 DATA:0x%x,  ", $time, u_tl_tx.u_arbiter_Top.axi_wrreq_hdr, u_tl_tx.u_arbiter_Top.axi_req_data);
                $fmonitor(file_handle, "Time: %0t, A2P2 HDR: 0x%x, ", $time, u_tl_tx.u_arbiter_Top.axi_rdreq_hdr);
                $fmonitor(file_handle, "Time: %0t, Master HDR: 0x%x,  Master DATA: 0x%x,  ", $time, axi_master_hdr, axi_comp_data);
                $fmonitor(file_handle, "Time: %0t, Rx Router MSG HDR: 0x%x, Rx Router COMP HDR: 0x%x, Rx Router COMP Data: 0x%x  ", $time, rx_router_msg_hdr, rx_router_comp_hdr , rx_router_data );
                $fmonitor(file_handle, "Time: %0t, TLP: 0x%x,", $time, Frag_if.TLP);
                $fmonitor(file_handle, "Time: %0t, Length: 0x%d,", $time, Frag_if.Length);
                $fmonitor(file_handle, "Time: %0t, VALID Bytes: 0x%s,", $time, Frag_if.Valid_Bytes);

                // $fclose(file_handle);
        end 


    // Calculating the No. Cycles required from SOP to EOP to verify the functionality
        // integer no_cycles ; 
        // initial begin 
        //     no_cycles = 0 ;
        //     repeat (TEST_CASES) begin
        //     @(posedge Frag_if.sop)
        //     while (Frag_if.TLP_valid) begin 
        //         no_cycles = no_cycles + 1 ;
        //         #(CLK_PERIOD);
        //     end 
        //     $display ("No of Cycles : %d" , no_cycles ); 
        // end 
        // end 
    
/********* Instantiations *****/
/********* Interfaces *********/
	// AXI Interface
	axi_if                  u_axi_if ();
	// Master Interface
	Master_Interface        u_Master_if ();
	// P2A & Rx Router Interface
	P2A_Rx_Router_Interface #(
        .DATA_WIDTH(1024)
    ) u_P2A_Rx_Router_if ();
	// Buffer and Arbiter FSM Interface
	buffer_frag_interface   u_buffer_if ();
	// Fragmentation and DLL Interface
	Fragmentation_Interface #(
    ) Frag_if ();
	
/********* Modules *********/
    tl_tx u_tl_tx ( 
        //  Global Signals 
        .clk(clk),
        .arst(arst),
        // Axi Slave Channels 
        .slave_push_if(u_axi_if),
        .Requester_ID('1), 
        .config_ecrc(config_ecrc),
        .Master_if(u_Master_if),
        .Rx_Router_if(u_P2A_Rx_Router_if),
        // Rx side interface - Master
        .axi_master_valid(axi_master_valid),
        .axi_master_grant(axi_master_grant),
        //  of mapper for master
        .axi_master_hdr(axi_master_hdr),                          
        // Data in case of COMPD
        .axi_comp_data(axi_comp_data), 
        // Rx side interface -  Rx Router 
        .rx_router_valid(rx_router_valid), 
        .rx_router_grant(rx_router_grant),
        .rx_router_msg_hdr(rx_router_msg_hdr), // all msgs supported 3Dw
        .rx_router_comp_hdr(rx_router_comp_hdr),
        // Data in case of COMPD
        .rx_router_data  (rx_router_data),
        //  DLL - FC credits interface
        .HdrFC(HdrFC),  // No. Credits for Header buffer
        .DataFC(DataFC), // No. Credits for Data buffer
        .TypeFC(TypeFC),
        // DLL - TLP interface 
		._dll_if(Frag_if.FRAGMENTATION_DLL)
        // .Halt_1(1'b0),
        // .Halt_2(1'b0),
        // .Throttle(1'b0),
        // .sop(),
        // .eop(),
        // .TLP_valid(),
        // .Valid_Bytes(),
        // .Length(),
        // .TLP()
    );

endmodule 

