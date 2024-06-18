/* Module Name	: CRC_TB						*/
/* Written By	: Ahmady                     	*/
/* Date			: 26-02-2024					*/
/* Version		: V_1							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: -							    */
// `include "CRC32_Serial.v"
// `include "CRC32_Parallel.v"
`timescale 1ns/1ps
module CRC_TB ();
parameter   DATA_WIDTH    = 256,
            LENGTH_WIDTH  = 4,
            POLY_WIDTH    = 32;
reg     [DATA_WIDTH - 1: 0]     CRC_i_Message;	
reg     [LENGTH_WIDTH - 1 : 0]  CRC_i_Length;
reg                             CRC_i_EN;		
reg     [POLY_WIDTH - 1: 0]     CRC_i_Seed;         
reg                             CRC_i_Seed_Load;       
wire    [POLY_WIDTH - 1 : 0]    CRC_o_CRC_Serial;			   
wire    [POLY_WIDTH - 1 : 0]    CRC_o_CRC_Parallel;			   

/* Parameters (must be in upper case) */
parameter TEST_CASES = 100;
integer i;
integer PASSED, FAILED;

/* Internal Signals */

/* Assign Statements */

/* Always Blocks */

/* Initial Blocks */
initial begin
    $dumpfile ("CRC32.vcd");
    $dumpvars (1,CRC_TB);
    CRC_i_EN        = 1'b0;
    CRC_i_Seed      = 32'd1;
    CRC_i_Seed_Load = 1'b0;
    CRC_i_Length    = 'd0;
    PASSED          = 0;
    FAILED          = 0;
    #10;
    CRC_i_EN = 1'b1; CRC_i_Seed = {POLY_WIDTH{1'b1}}; CRC_i_Length = 4'd4; CRC_i_Seed_Load = 1'b1; //CRC_i_Message = 256'h1980_1697_320d_698a_abfd_2264_1298_6548_abcd_6987_1245_0000_5678_9876_abcd_1234;
    // CRC_i_Message = 96'h0000_8000_0001_0002_0000_0000;
    CRC_i_Message = 128'h20008001000000000000000000000000;
    #10;
    $display("polynomial:   04C11DB7");
    $display("Seed:         %h", CRC_i_Seed);
    $display("Data:         %h", CRC_i_Message);
    $display("CRC Serial:   %h", CRC_o_CRC_Serial);
    $display("CRC Parallel: %h", CRC_o_CRC_Parallel);
    // CRC_i_EN = 1'b1; CRC_i_Seed = {POLY_WIDTH{1'b1}}; CRC_i_Length = 4'd4; CRC_i_Seed_Load = 1'b0; CRC_i_Message = 256'hadbc_2265_9161_0324_1245_9875_1265_6598;
    // #10;
    // $display("Message: %h", CRC_i_Message);
    // $display("CRC Serial: %h", CRC_o_CRC_Serial);
    // $display("CRC Parallel: %h", CRC_o_CRC_Parallel);
    // CRC_i_EN = 1'b1; CRC_i_Seed = {POLY_WIDTH{1'b1}}; CRC_i_Length = 4'd8; CRC_i_Seed_Load = 1'b1; CRC_i_Message = 256'hadbc_2265_9161_0324_1245_9875_1265_6598_abcd_6987_1245_0000_5678_9876_abcd_1234;
    // #10;
    // $display("Message: %h", CRC_i_Message);
    // $display("CRC Serial: %h", CRC_o_CRC_Serial);
    // $display("CRC Parallel: %h", CRC_o_CRC_Parallel);

    // for (i = 0; i < TEST_CASES ; i = i + 1) begin
    // repeat(TEST_CASES) begin
    //     CRC_i_Message = $random;
    //     #10
    //     if (CRC_o_CRC_Serial == CRC_o_CRC_Parallel) begin
    //         PASSED = PASSED + 1;
    //     end
    //     else begin
    //         FAILED = FAILED + 1;
    //     end
    // end
    // #10
    // $display("PASSED: %d", PASSED);
    // $display("FAILED: %d", FAILED);
    $finish;
end

/* Instantiations (connect signals must be by name not by order) */
CRC32_Serial #(
    .DATA_WIDTH(DATA_WIDTH),
    .LENGTH_WIDTH(LENGTH_WIDTH),
    .POLY_WIDTH(POLY_WIDTH)    
) u_CRC32_Serial_1 (
    .CRC_i_Message(CRC_i_Message),
    .CRC_i_Length(CRC_i_Length),
    .CRC_i_EN(CRC_i_EN),
    .CRC_i_Seed(CRC_i_Seed),
    .CRC_i_Seed_Load(CRC_i_Seed_Load),
    .CRC_o_CRC(CRC_o_CRC_Serial)
);

CRC32_Parallel #(
    .DATA_WIDTH(DATA_WIDTH),
    .LENGTH_WIDTH(LENGTH_WIDTH),
    .POLY_WIDTH(POLY_WIDTH)    
) u_CRC32_Parallel_1 (
    .CRC_i_Message(CRC_i_Message),
    .CRC_i_Length(CRC_i_Length),
    .CRC_i_EN(CRC_i_EN),
    .CRC_i_Seed(CRC_i_Seed),
    .CRC_i_Seed_Load(CRC_i_Seed_Load),
    .CRC_o_CRC(CRC_o_CRC_Parallel)
);

endmodule
/*********** END_OF_FILE ***********/