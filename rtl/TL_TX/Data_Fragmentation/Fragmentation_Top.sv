/********************************************************************/
/* Module Name	: Fragmentation_Top.sv                              */
/* Written By	: Mohamed Khaled Alahmady                           */
/* Date			: 29-04-2024 					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: -							                        */
/********************************************************************/
module Fragmentation_Top ();

/* Packages */
import axi_slave_package::*;
import Fragmentation_Package::*;

/* Parameters */
parameter CLK_PERIOD = 10;

/* Internal Signals */
bit             clk;
bit             arst;
Cpl_TLP_HDR_t   Hdr_temp;
logic           Buffer_Ready;
logic           start_fragment;
// logic                                       Halt_1;
// logic                                       Halt_2;
// logic                                       Throttle;
// logic                                       sop;
// logic                                       eop;
// logic [DLL_LENGTH_WIDTH - 1 : 0]            Length;
// logic                                       TLP_valid;
// valid_bytes_encoding                        Valid_Bytes;
// logic [DLL_TLP_WIDTH - 1 : 0]               TLP;
/* Useful Functions */

/* Assign Statements */

/* Initial Block */
/********* Stimulus Generation *********/
    int i;
    initial begin
        arst                    = 1'b0; 
        buffer_if.wr_en         = 1'b1;
        buffer_if.no_loc_wr     = 0;
        buffer_if.data_in       = '0;
        Hdr_temp                = buffer_if.data_in[1151:1056];
        Frag_if.Halt_1          = 1'b0;
        Frag_if.Halt_2          = 1'b0;
        Frag_if.Throttle        = 1'b0;
        #(CLK_PERIOD)
        arst                    = 1'b1;
        Frag_if.Halt_1          = 1'b0;
        Frag_if.Halt_2          = 1'b0;
        // #(CLK_PERIOD/2)
        buffer_if.wr_en         = 1'b1;
        buffer_if.no_loc_wr     = 3;
        buffer_if.data_in       = {
            // 1st 4DW
                // 1DW
                    // fmt (3 bits)
                    TLP_FMT_3DW,
                    // type (5 bits)
                    TLP_TYPE_3DW_MWR,
                    // T9
                    1'b0,
                    // TC
                    3'b000,
                    // T8
                    1'b0,
                    // Attr1
                    1'b0,
                    // LN
                    1'b0,
                    // TH
                    1'b0,
                    // TD
                    1'b1,
                    // EP
                    1'b0,
                    // Attr2
                    2'b00,
                    // AT
                    2'b00,
                    // Length
                    10'd7,
                // 2DW
                    // Requester ID
                    16'habcd,
                    // Tag
                    8'd10,
                    // LBE
                    4'b0000,
                    // FBE
                    4'b1111,
                // 3DW
                    // Address [31:2]
                    30'h12,
                    // PH
                    2'b00,
                // 4DW
                    30'b0,
                    2'b11,
            2'b11,
            // 2nd 4DW
                128'h9876_1234_0000_0000_0000_0000_0000_1212,
            2'b11,
            // 3rd 4DW
                128'h0000_0000_0000_0000_0000_0000_6666_5555,
            2'b11,
            // 4th 4DW
                128'h0000_0000_0000_0000_0000_0000_0000_0000,
            2'b00,
            // 5th 4DW
                128'h1111_2222_0000_0000_0000_0000_0000_8888,
            2'b00,
            // 6th 4DW
                128'h0000_0000_0000_0000_0000_0000_0000_7777,
            2'b00,
            // 7th 4DW
                128'h0000_0000_0000_0000_0000_0000_0000_0000,
            2'b00,
            // reset of 36 DW
            260'b0
        };
        Hdr_temp                = buffer_if.data_in[WR_DATA_WIDTH - 1 :WR_DATA_WIDTH - 3 * DOUBLE_WORD];
        #(CLK_PERIOD)
        buffer_if.wr_en         = 1'b0;
        buffer_if.no_loc_wr     = 0;
        // #(CLK_PERIOD/2)
        #(2*CLK_PERIOD)
        buffer_if.wr_en         = 1'b1;
        buffer_if.no_loc_wr     = 3;
        buffer_if.data_in       = {
            // 1st 4DW
                // 1DW
                    // fmt (3 bits)
                    TLP_FMT_3DW,
                    // type (5 bits)
                    TLP_TYPE_3DW_MWR,
                    // T9
                    1'b0,
                    // TC
                    3'b000,
                    // T8
                    1'b0,
                    // Attr1
                    1'b0,
                    // LN
                    1'b0,
                    // TH
                    1'b0,
                    // TD
                    1'b1,
                    // EP
                    1'b0,
                    // Attr2
                    2'b00,
                    // AT
                    2'b00,
                    // Length
                    10'd7,
                // 2DW
                    // Requester ID
                    16'habcd,
                    // Tag
                    8'd10,
                    // LBE
                    4'b0000,
                    // FBE
                    4'b1111,
                // 3DW
                    // Address [31:2]
                    30'h12,
                    // PH
                    2'b00,
                // 4DW
                    30'b0,
                    2'b11,
            2'b11,
            // 2nd 4DW
                128'h9876_1234_0000_0000_0000_0000_0000_1212,
            2'b11,
            // 3rd 4DW
                128'h0000_0000_0000_0000_0000_0000_6666_5555,
            2'b11,
            // 4th 4DW
                128'h0000_0000_0000_0000_0000_0000_0000_0000,
            2'b00,
            // 5th 4DW
                128'h1111_2222_0000_0000_0000_0000_0000_8888,
            2'b00,
            // 6th 4DW
                128'h0000_0000_0000_0000_0000_0000_0000_7777,
            2'b00,
            // 7th 4DW
                128'h0000_0000_0000_0000_0000_0000_0000_0000,
            2'b00,
            // reset of 36 DW
            260'b0
        };
        #(CLK_PERIOD)
        buffer_if.wr_en         = 1'b0;
        buffer_if.no_loc_wr     = 0;
        #(CLK_PERIOD)
        Frag_if.Halt_1          = 1'b0;
        Frag_if.Halt_2          = 1'b0;
        #(3*CLK_PERIOD)
        Frag_if.Halt_1          = 1'b0;
        Frag_if.Halt_2          = 1'b0;
        #(5*CLK_PERIOD)
        $stop();
    end
    
/* Always Blocks */
/********* Clock Generation *********/
	initial begin
		forever #(CLK_PERIOD/2) clk = ~clk;
	end

/* Instantiations */
/********* Interfaces *********/
    Fragmentation_Interface #(
    ) Frag_if ();

    buffer_frag_interface buffer_if ();

/********* Modules *********/
// TLP Buffer Fragmentation 
    buffer_frag u_buffer_frag ( 
        .clk(clk),
        .arst(arst),
        ._Src_if(buffer_if),
        ._Dist_if(Frag_if.TLP_FIFO_FRAGMENTATION)
    ); 
    
    Frag #(
    ) u_Frag (
        .clk(clk), 
        .arst(arst),
        // TLP Buffer Interface
        ._tlp_fifo_if(Frag_if.FRAGMENTATION_TLP_FIFO),    
        // DLL Interface
        ._dll_if(Frag_if.FRAGMENTATION_DLL),
        // .Halt_1(Halt_1),
        // .Halt_2(Halt_2),
        // .Throttle(Throttle),
        // .sop(sop),
        // .eop(eop),
        // .TLP_valid(TLP_valid),
        // .Valid_Bytes(Valid_Bytes),
        // .Length(Length),
        // .TLP(TLP),
        // ECRC Interface
        ._ecrc_if(Frag_if.FRAGMENTATION_ECRC)
    );

    ECRC #(
    ) u_ECRC (
        .clk(clk), 
        .arst(arst),
        ._if(Frag_if.ECRC_FRAGMENTATION) 
    ); 


endmodule: Fragmentation_Top
/*********** END_OF_FILE ***********/
