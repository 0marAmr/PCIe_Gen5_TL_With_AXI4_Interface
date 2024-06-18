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
import Fragmentation_Package::*;
import axi_slave_package::*; 

module arbiter_Top_tb ();
bit clk;
bit arst;


localparam CLK_PERIOD = 10;

/* Internal Signals */
logic axi_req_wr_grant, axi_wrreq_hdr_valid, axi_req_rd_grant, axi_rdreq_hdr_valid ; 
tlp_header_t     axi_wrreq_hdr, axi_rdreq_hdr;
logic [AXI_MAX_NUM_BYTES * 8 - 1 : 0] axi_req_data ; 

logic                       axi_master_valid;
logic                       axi_master_grant;
// Output of mapper for master
logic [3*DW - 1 : 0]        axi_master_hdr;                          
// Data in case of COMPD
logic [AXI_MAX_NUM_BYTES * 8 - 1 : 0] axi_comp_data; 
// Rx side interface -  Rx Router 
logic [1:0]              rx_router_valid; 
logic                    rx_router_grant;
logic [3*DW - 1 : 0]      rx_router_msg_hdr; // all msgs supported 3Dw
logic [3*DW - 1 : 0]      rx_router_comp_hdr;
// Data in case of COMPD
logic [1*DW  - 1 : 0]     rx_router_data  ;
//  DLL - FC credits interface
logic [FC_HDR_WIDTH  - 1 : 0]   HdrFC;
logic [FC_DATA_WIDTH - 1 : 0]   DataFC;
FC_type_t                       TypeFC;


/* Initial Blocks */
initial begin
    forever #(CLK_PERIOD / 2) clk = ~clk;
end

integer file_handle;
    // Define the file name and mode
    string file_name = "output.txt";
    string file_mode = "w";
    initial begin
        file_handle = $fopen(file_name, file_mode);
        if (file_handle == 0) begin
            $display("Error opening file: %s", file_name);
            $finish;
        end
    end



initial begin
    arst = 1'b0; 
    axi_wrreq_hdr_valid = 1'b0; 
    axi_rdreq_hdr_valid = 1'b0; 
    axi_master_valid        = 1'b0; 
    rx_router_valid     = 2'b00; 
    TypeFC              = FC_X; 
    HdrFC               = '0; 
    DataFC              = '0;
    axi_wrreq_hdr       = '0;
    axi_rdreq_hdr       = '0;
    axi_req_data        = '0;
    axi_master_hdr      = '0;
    axi_comp_data       = '0;
    rx_router_msg_hdr   = '0;
    rx_router_comp_hdr  = '0;
    rx_router_data      = '0;
    frag_if.rd_en       = 1'b0 ;
    frag_if.rd_mode     = 1'b0 ;

    // frag_if.empty       = 1'b0;
    #CLK_PERIOD
    arst = 1'b1; 
    // frag_if.empty       = 1'b1;
    TypeFC = FC_P;     HdrFC = 30; DataFC = 1000;
    #(CLK_PERIOD)
    TypeFC = FC_NP;    HdrFC = 30; DataFC = 1000;
    #(CLK_PERIOD)
    TypeFC = FC_CPL;   HdrFC = 30; DataFC = 1000;
    #(CLK_PERIOD)
    repeat(1) begin
        axi_wrreq_hdr_valid             = 1'b0; // $urandom() % 2;
        axi_rdreq_hdr_valid             = 1'b0; // $urandom() % 2;
        axi_master_valid                = 1'b1; // $urandom() % 2;
        rx_router_valid                 = 1'b0; // $urandom() % 4;
        axi_rdreq_hdr                   = {
            // 1st DW
                TLP_FMT_3DW_DATA,      /* Format field of TLP header*/
                5'b00000,      /* Type field of TLP Header */
                1'b0  ,
                3'b000  ,      /* Traffic Class Field     */
                1'b0  ,     
                1'b0 ,
                1'b0 ,
                1'b0 ,
                1'b0 ,
                1'b0 ,
                2'b00 ,
                2'b00,          /* Attribute field        */
                10'd4,          /* Length field           */

                // BYTE 4   --  BYTE 5 -- BYTE 6 -- BYTE 7
            // 2nd DW
                16'hABCD, /* Requester ID */
                8'd12,         /* Tag field              */
                4'b000,
                4'b1111,

                // BYTE 8   --  BYTE 9 -- BYTE 10 -- BYTE 11
            // 3rd DW
                32'h1000, /* Higher address bits */ 

                // BYTE 12   --  BYTE 13 -- BYTE 14 -- BYTE 15
            // 4th DW
                30'h500, /* lower address bits  */
                2'b00 /* PH field */
        };
        axi_master_hdr                  = {3'b010 , 
                                           5'b0_1010,
                                           1'b0  ,
                                           3'b000  ,      /* Traffic Class Field     */
                                           1'b0  ,     
                                           1'b0 ,
                                           1'b0 ,
                                           1'b0 ,
                                           1'b0 ,
                                           1'b0 ,
                                           2'b00 ,
                                           2'b00,          /* Attribute field        */
                                           10'd36,          /* Length field           */
                                           // BYTE 4   --  BYTE 5 -- BYTE 6 -- BYTE 7
                                           //2nd DW
                                           16'hABCD, /* Requester ID */
                                           8'd12,         /* Tag field              */
                                           4'b000,
                                           4'b1111,  
                                            // BYTE 8   --  BYTE 9 -- BYTE 10 -- BYTE 11
                                           // 3rd DW
                                           32'h1000 /* Higher address bits */  }; 


                                           axi_comp_data                    = {32'habcd_1234, 992'b0};

        $fdisplay(file_handle, " The Header for TLP ");
        $fdisplay(file_handle, "%h_%h_%h", axi_master_hdr[3*DW - 1 : 2 * DW] , axi_master_hdr[2*DW - 1 : 1 * DW], axi_master_hdr[1*DW - 1 : 0 * DW]);
        // $display ("the value of HDR in hexa : %h" , axi_wrreq_hdr );
        $fdisplay(file_handle, " The Length for TLP Data ");
        $fdisplay(file_handle, "%d", axi_rdreq_hdr.Length);


        // axi_req_data                    = {32'habcd_1234, 992'b0};
        $fdisplay(file_handle, " The Data for TLP ");
        $fdisplay(file_handle, "%h_%h_%h_%h", axi_comp_data[32*DW - 1 : 31 * DW] , axi_comp_data[31*DW - 1 : 30 * DW], axi_comp_data[30*DW - 1 : 29 * DW], axi_comp_data[29*DW - 1 : 28 * DW] );
        $fdisplay(file_handle, "%h_%h_%h_%h", axi_comp_data[28*DW - 1 : 27 * DW] , axi_comp_data[27*DW - 1 : 26 * DW], axi_comp_data[26*DW - 1 : 25 * DW], axi_comp_data[25*DW - 1 : 24 * DW] );
        $fdisplay(file_handle, "%h_%h_%h_%h", axi_comp_data[24*DW - 1 : 23 * DW] , axi_comp_data[23*DW - 1 : 22 * DW], axi_comp_data[22*DW - 1 : 21 * DW], axi_comp_data[21*DW - 1 : 20 * DW] );
        $fdisplay(file_handle, "%h_%h_%h_%h", axi_comp_data[20*DW - 1 : 19 * DW] , axi_comp_data[19*DW - 1 : 18 * DW], axi_comp_data[18*DW - 1 : 17 * DW], axi_comp_data[17*DW - 1 : 16 * DW] );
        $fdisplay(file_handle, "%h_%h_%h_%h", axi_comp_data[16*DW - 1 : 15 * DW] , axi_comp_data[15*DW - 1 : 14 * DW], axi_comp_data[14*DW - 1 : 13 * DW], axi_comp_data[13*DW - 1 : 12 * DW] );
        $fdisplay(file_handle, "%h_%h_%h_%h", axi_comp_data[12*DW - 1 : 11 * DW] , axi_comp_data[11*DW - 1 : 10 * DW], axi_comp_data[10*DW - 1 : 9 * DW], axi_comp_data[9*DW - 1 : 8 * DW] );
        $fdisplay(file_handle, "%h_%h_%h_%h", axi_comp_data[8*DW - 1 : 7 * DW] , axi_comp_data[7*DW - 1 : 6 * DW], axi_comp_data[6*DW - 1 : 5 * DW], axi_comp_data[5*DW - 1 : 4 * DW] );
        $fdisplay(file_handle, "%h_%h_%h_%h", axi_comp_data[4*DW - 1 : 3 * DW] , axi_comp_data[3*DW - 1 : 2 * DW], axi_comp_data[2*DW - 1 : 1 * DW], axi_comp_data[1*DW - 1 : 0 * DW] );


        #(CLK_PERIOD);

        // $fclose(file_handle);


        
    end
    #(2.5*CLK_PERIOD)
        // $display (" axi_grant : %d ", axi_req_wr_grant);
        $fdisplay(file_handle, " The Stored Data in buffer ");
        $fdisplay(file_handle, "%h_%h_%h_%h_%2b", u_arbiter_Top.frag_buffer_if.data_in[FIRST_4TH_DW_WITH_2_BITS - 1   : FIRST_4TH_DW_WITH_2_BITS - DW ] , u_arbiter_Top.frag_buffer_if.data_in[FIRST_4TH_DW_WITH_2_BITS - DW - 1 : FIRST_4TH_DW_WITH_2_BITS - 2 * DW], u_arbiter_Top.frag_buffer_if.data_in[FIRST_4TH_DW_WITH_2_BITS - 2 * DW - 1 : FIRST_4TH_DW_WITH_2_BITS - 3 * DW], u_arbiter_Top.frag_buffer_if.data_in[FIRST_4TH_DW_WITH_2_BITS - 3 * DW - 1 : FIRST_4TH_DW_WITH_2_BITS - 4 * DW], u_arbiter_Top.frag_buffer_if.data_in[ FIRST_4TH_DW_WITH_2_BITS - 4  * DW - 1 : SECOND_4TH_DW_WITH_2_BITS] );
        $fdisplay(file_handle, "%h_%h_%h_%h_%2b", u_arbiter_Top.frag_buffer_if.data_in[SECOND_4TH_DW_WITH_2_BITS - 1   : SECOND_4TH_DW_WITH_2_BITS - DW ] , u_arbiter_Top.frag_buffer_if.data_in[SECOND_4TH_DW_WITH_2_BITS - DW - 1 : SECOND_4TH_DW_WITH_2_BITS - 2 * DW], u_arbiter_Top.frag_buffer_if.data_in[SECOND_4TH_DW_WITH_2_BITS - 2 * DW - 1 : SECOND_4TH_DW_WITH_2_BITS - 3 * DW], u_arbiter_Top.frag_buffer_if.data_in[SECOND_4TH_DW_WITH_2_BITS - 3 * DW - 1 : SECOND_4TH_DW_WITH_2_BITS - 4 * DW], u_arbiter_Top.frag_buffer_if.data_in[ SECOND_4TH_DW_WITH_2_BITS - 4  * DW - 1 : THIRD_4TH_DW_WITH_2_BITS] );
        $fdisplay(file_handle, "%h_%h_%h_%h_%2b", u_arbiter_Top.frag_buffer_if.data_in[THIRD_4TH_DW_WITH_2_BITS - 1   : THIRD_4TH_DW_WITH_2_BITS - DW ] , u_arbiter_Top.frag_buffer_if.data_in[THIRD_4TH_DW_WITH_2_BITS - DW - 1 : THIRD_4TH_DW_WITH_2_BITS - 2 * DW], u_arbiter_Top.frag_buffer_if.data_in[THIRD_4TH_DW_WITH_2_BITS - 2 * DW - 1 : THIRD_4TH_DW_WITH_2_BITS - 3 * DW], u_arbiter_Top.frag_buffer_if.data_in[THIRD_4TH_DW_WITH_2_BITS - 3 * DW - 1 : THIRD_4TH_DW_WITH_2_BITS - 4 * DW], u_arbiter_Top.frag_buffer_if.data_in[ THIRD_4TH_DW_WITH_2_BITS - 4  * DW - 1 : FOURTH_4TH_DW_WITH_2_BITS] );
        $fdisplay(file_handle, "%h_%h_%h_%h_%2b", u_arbiter_Top.frag_buffer_if.data_in[FOURTH_4TH_DW_WITH_2_BITS - 1   : FOURTH_4TH_DW_WITH_2_BITS - DW ] , u_arbiter_Top.frag_buffer_if.data_in[FOURTH_4TH_DW_WITH_2_BITS - DW - 1 : FOURTH_4TH_DW_WITH_2_BITS - 2 * DW], u_arbiter_Top.frag_buffer_if.data_in[FOURTH_4TH_DW_WITH_2_BITS - 2 * DW - 1 : FOURTH_4TH_DW_WITH_2_BITS - 3 * DW], u_arbiter_Top.frag_buffer_if.data_in[FOURTH_4TH_DW_WITH_2_BITS - 3 * DW - 1 : FOURTH_4TH_DW_WITH_2_BITS - 4 * DW], u_arbiter_Top.frag_buffer_if.data_in[ FOURTH_4TH_DW_WITH_2_BITS - 4  * DW - 1 : FIFTH_4TH_DW_WITH_2_BITS] );
        $fdisplay(file_handle, "%h_%h_%h_%h_%2b", u_arbiter_Top.frag_buffer_if.data_in[FIFTH_4TH_DW_WITH_2_BITS - 1   : FIFTH_4TH_DW_WITH_2_BITS - DW ] , u_arbiter_Top.frag_buffer_if.data_in[FIFTH_4TH_DW_WITH_2_BITS - DW - 1 : FIFTH_4TH_DW_WITH_2_BITS - 2 * DW], u_arbiter_Top.frag_buffer_if.data_in[FIFTH_4TH_DW_WITH_2_BITS - 2 * DW - 1 : FIFTH_4TH_DW_WITH_2_BITS - 3 * DW], u_arbiter_Top.frag_buffer_if.data_in[FIFTH_4TH_DW_WITH_2_BITS - 3 * DW - 1 : FIFTH_4TH_DW_WITH_2_BITS - 4 * DW], u_arbiter_Top.frag_buffer_if.data_in[ FIFTH_4TH_DW_WITH_2_BITS - 4  * DW - 1 : SIXTH_4TH_DW_WITH_2_BITS] );
        $fdisplay(file_handle, "%h_%h_%h_%h_%2b", u_arbiter_Top.frag_buffer_if.data_in[SIXTH_4TH_DW_WITH_2_BITS - 1   : SIXTH_4TH_DW_WITH_2_BITS - DW ] , u_arbiter_Top.frag_buffer_if.data_in[SIXTH_4TH_DW_WITH_2_BITS - DW - 1 : SIXTH_4TH_DW_WITH_2_BITS - 2 * DW], u_arbiter_Top.frag_buffer_if.data_in[SIXTH_4TH_DW_WITH_2_BITS - 2 * DW - 1 : SIXTH_4TH_DW_WITH_2_BITS - 3 * DW], u_arbiter_Top.frag_buffer_if.data_in[SIXTH_4TH_DW_WITH_2_BITS - 3 * DW - 1 : SIXTH_4TH_DW_WITH_2_BITS - 4 * DW], u_arbiter_Top.frag_buffer_if.data_in[ SIXTH_4TH_DW_WITH_2_BITS - 4  * DW - 1 : SEVENTH_4TH_DW_WITH_2_BITS] );
        $fdisplay(file_handle, "%h_%h_%h_%h_%2b", u_arbiter_Top.frag_buffer_if.data_in[SEVENTH_4TH_DW_WITH_2_BITS - 1   : SEVENTH_4TH_DW_WITH_2_BITS - DW ] , u_arbiter_Top.frag_buffer_if.data_in[SEVENTH_4TH_DW_WITH_2_BITS - DW - 1 : SEVENTH_4TH_DW_WITH_2_BITS - 2 * DW], u_arbiter_Top.frag_buffer_if.data_in[SEVENTH_4TH_DW_WITH_2_BITS - 2 * DW - 1 : SEVENTH_4TH_DW_WITH_2_BITS - 3 * DW], u_arbiter_Top.frag_buffer_if.data_in[SEVENTH_4TH_DW_WITH_2_BITS - 3 * DW - 1 : SEVENTH_4TH_DW_WITH_2_BITS - 4 * DW], u_arbiter_Top.frag_buffer_if.data_in[ SEVENTH_4TH_DW_WITH_2_BITS - 4  * DW - 1 : EIGHTH_4TH_DW_WITH_2_BITS] );
        $fdisplay(file_handle, "%h_%h_%h_%h_%2b", u_arbiter_Top.frag_buffer_if.data_in[EIGHTH_4TH_DW_WITH_2_BITS - 1   : EIGHTH_4TH_DW_WITH_2_BITS - DW ] , u_arbiter_Top.frag_buffer_if.data_in[EIGHTH_4TH_DW_WITH_2_BITS - DW - 1 : EIGHTH_4TH_DW_WITH_2_BITS - 2 * DW], u_arbiter_Top.frag_buffer_if.data_in[EIGHTH_4TH_DW_WITH_2_BITS - 2 * DW - 1 : EIGHTH_4TH_DW_WITH_2_BITS - 3 * DW], u_arbiter_Top.frag_buffer_if.data_in[EIGHTH_4TH_DW_WITH_2_BITS - 3 * DW - 1 : EIGHTH_4TH_DW_WITH_2_BITS - 4 * DW], u_arbiter_Top.frag_buffer_if.data_in[ EIGHTH_4TH_DW_WITH_2_BITS - 4  * DW - 1 : NINTH_4TH_DW_WITH_2_BITS] );
        $fdisplay(file_handle, "%h_%h_%h_%h_%2b", u_arbiter_Top.frag_buffer_if.data_in[NINTH_4TH_DW_WITH_2_BITS - 1   : NINTH_4TH_DW_WITH_2_BITS - DW ] , u_arbiter_Top.frag_buffer_if.data_in[NINTH_4TH_DW_WITH_2_BITS - DW - 1 : NINTH_4TH_DW_WITH_2_BITS - 2 * DW], u_arbiter_Top.frag_buffer_if.data_in[NINTH_4TH_DW_WITH_2_BITS - 2 * DW - 1 : NINTH_4TH_DW_WITH_2_BITS - 3 * DW], u_arbiter_Top.frag_buffer_if.data_in[NINTH_4TH_DW_WITH_2_BITS - 3 * DW - 1 : NINTH_4TH_DW_WITH_2_BITS - 4 * DW], u_arbiter_Top.frag_buffer_if.data_in[ NINTH_4TH_DW_WITH_2_BITS - 4  * DW - 1 : 0] );


        $fdisplay(file_handle, " registers in TLP Buffer ");
        $fdisplay(file_handle, "%h", u_arbiter_Top.frag_buffer_if.data_in[FIRST_4TH_DW_WITH_2_BITS - 1    : SECOND_4TH_DW_WITH_2_BITS  ]  );
        $fdisplay(file_handle, "%h", u_arbiter_Top.frag_buffer_if.data_in[SECOND_4TH_DW_WITH_2_BITS - 1   : THIRD_4TH_DW_WITH_2_BITS   ]  );
        $fdisplay(file_handle, "%h", u_arbiter_Top.frag_buffer_if.data_in[THIRD_4TH_DW_WITH_2_BITS - 1    : FOURTH_4TH_DW_WITH_2_BITS  ]  );
        $fdisplay(file_handle, "%h", u_arbiter_Top.frag_buffer_if.data_in[FOURTH_4TH_DW_WITH_2_BITS - 1   : FIFTH_4TH_DW_WITH_2_BITS   ]  );
        $fdisplay(file_handle, "%h", u_arbiter_Top.frag_buffer_if.data_in[FIFTH_4TH_DW_WITH_2_BITS - 1    : SIXTH_4TH_DW_WITH_2_BITS   ]  );
        $fdisplay(file_handle, "%h", u_arbiter_Top.frag_buffer_if.data_in[SIXTH_4TH_DW_WITH_2_BITS - 1    : SEVENTH_4TH_DW_WITH_2_BITS ]  );
        $fdisplay(file_handle, "%h", u_arbiter_Top.frag_buffer_if.data_in[SEVENTH_4TH_DW_WITH_2_BITS - 1  : EIGHTH_4TH_DW_WITH_2_BITS  ]  );
        $fdisplay(file_handle, "%h", u_arbiter_Top.frag_buffer_if.data_in[EIGHTH_4TH_DW_WITH_2_BITS - 1   : NINTH_4TH_DW_WITH_2_BITS   ]  );
        $fdisplay(file_handle, "%h", u_arbiter_Top.frag_buffer_if.data_in[NINTH_4TH_DW_WITH_2_BITS - 1    : 0                          ]  );     
 
        $fclose(file_handle);

        #(2.5*CLK_PERIOD)
  

    $stop();
end

Fragmentation_Interface #(
    ) frag_if ();

/********* Modules *********/
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
            .master_valid(axi_master_valid),
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
            .frag_if(frag_if)
    );

endmodule 

