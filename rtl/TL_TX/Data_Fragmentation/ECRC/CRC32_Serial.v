/* Module Name	: CRC32_Serial					*/
/* Written By	: Ahmady                     	*/
/* Date			: 26-02-2024					*/
/* Version		: V_1							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: - 							*/
/* Synthesizable: NO                            */
`timescale 1ns/1ps
module CRC32_Serial #(
    parameter   DATA_WIDTH      = 256,
                LENGTH_WIDTH    = 4,
                POLY_WIDTH      = 32
)(
	input 	wire [DATA_WIDTH - 1 : 0]       CRC_i_Message,	
    input   wire [LENGTH_WIDTH - 1 : 0]   	CRC_i_Length,
	input 	wire                            CRC_i_EN,	
    input   wire [POLY_WIDTH - 1 : 0]	    CRC_i_Seed,   
    input   wire 							CRC_i_Seed_Load,                      
	output 	reg  [POLY_WIDTH - 1 : 0]       CRC_o_CRC,			   
	output 	reg                             CRC_o_Done		   
);
// 0 1 2 ..... 31
// 31 30 ....... 0

/* Parameters (must be in upper case) */

/* Internal Signals */
integer i;
reg [POLY_WIDTH : 0] temp;

/* Assign Statements */

/* Always Blocks */
always @(*) begin
    if (CRC_i_EN) begin
        CRC_o_Done  = 1'b1;
		temp = (CRC_i_Seed_Load) ? CRC_i_Seed : CRC_o_CRC;
        // for (i = ((CRC_i_Length << 2) << 3) - 1 ; i >= 0 ; i = i - 1 ) begin
        for (i = 0 ; i < ((CRC_i_Length << 2) << 3) ; i = i + 1 ) begin
            // 7 (0111) (x^2 + x^1 + 1)
            CRC_o_CRC[ 7]    = ~(          temp[31] ^ CRC_i_Message[i]);
            CRC_o_CRC[ 6]    = ~(temp[0] ^ temp[31] ^ CRC_i_Message[i]);
            CRC_o_CRC[ 5]    = ~(temp[1] ^ temp[31] ^ CRC_i_Message[i]);
            CRC_o_CRC[ 4]    = ~(temp[2]);
            // B (1011) (x^7 + x^5 + x^4)
            CRC_o_CRC[ 3]    = ~(temp[3] ^ temp[31] ^ CRC_i_Message[i]);
            CRC_o_CRC[ 2]    = ~(temp[4] ^ temp[31] ^ CRC_i_Message[i]);
            CRC_o_CRC[ 1]    = ~(temp[5]);
            CRC_o_CRC[ 0]    = ~(temp[6] ^ temp[31] ^ CRC_i_Message[i]);
            // D (1101) (x^11 + x^10 + x^8)
            CRC_o_CRC[15]    = ~(temp[7] ^ temp[31] ^ CRC_i_Message[i]);
            CRC_o_CRC[14]    = ~(temp[8]);
            CRC_o_CRC[13]    = ~(temp[9] ^ temp[31] ^ CRC_i_Message[i]);
            CRC_o_CRC[12]    = ~(temp[10] ^ temp[31] ^ CRC_i_Message[i]);
            // 1 (0001) (x^12)
            CRC_o_CRC[11]   = ~(temp[11] ^ temp[31] ^ CRC_i_Message[i]);
            CRC_o_CRC[10]   = ~(temp[12]);
            CRC_o_CRC[9]    = ~(temp[13]);
            CRC_o_CRC[8]    = ~(temp[14]);
            // 1 (0001) (x^16)
            CRC_o_CRC[23]   = ~(temp[15] ^ temp[31] ^ CRC_i_Message[i]);
            CRC_o_CRC[22]   = ~(temp[16]);
            CRC_o_CRC[21]   = ~(temp[17]);
            CRC_o_CRC[20]   = ~(temp[18]);
            // C (1100) (x^23 + x^22)
            CRC_o_CRC[19]   = ~(temp[19]);
            CRC_o_CRC[18]   = ~(temp[20]);
            CRC_o_CRC[17]   = ~(temp[21] ^ temp[31] ^ CRC_i_Message[i]);
            CRC_o_CRC[16]   = ~(temp[22] ^ temp[31] ^ CRC_i_Message[i]);
            // 4 (0100) (x^26)
            CRC_o_CRC[31]   = ~(temp[23]);
            CRC_o_CRC[30]   = ~(temp[24]);
            CRC_o_CRC[29]   = ~(temp[25] ^ temp[31] ^ CRC_i_Message[i]);
            CRC_o_CRC[28]   = ~(temp[26]);
            // 0 (0000) ()
            CRC_o_CRC[27]   = ~(temp[27]);
            CRC_o_CRC[26]   = ~(temp[28]);
            CRC_o_CRC[25]   = ~(temp[29]);
            CRC_o_CRC[24]   = ~(temp[30]);
            // update
            // temp[7:0] = ~CRC_o_CRC[0:7];
            // temp[15:8] = ~CRC_o_CRC[8:15];
            // temp[23:16] = ~CRC_o_CRC[16:23];
            // temp[31:24] = ~CRC_o_CRC[24:31];

            temp[ 0] = ~CRC_o_CRC[ 7];
            temp[ 1] = ~CRC_o_CRC[ 6];
            temp[ 2] = ~CRC_o_CRC[ 5];
            temp[ 3] = ~CRC_o_CRC[ 4];
            temp[ 4] = ~CRC_o_CRC[ 3];
            temp[ 5] = ~CRC_o_CRC[ 2];
            temp[ 6] = ~CRC_o_CRC[ 1];
            temp[ 7] = ~CRC_o_CRC[ 0];

            temp[ 8] = ~CRC_o_CRC[15];
            temp[ 9] = ~CRC_o_CRC[14];
            temp[10] = ~CRC_o_CRC[13];
            temp[11] = ~CRC_o_CRC[12];
            temp[12] = ~CRC_o_CRC[11];
            temp[13] = ~CRC_o_CRC[10];
            temp[14] = ~CRC_o_CRC[ 9];
            temp[15] = ~CRC_o_CRC[ 8];

            temp[16] = ~CRC_o_CRC[23];
            temp[17] = ~CRC_o_CRC[22];
            temp[18] = ~CRC_o_CRC[21];
            temp[19] = ~CRC_o_CRC[20];
            temp[20] = ~CRC_o_CRC[19];
            temp[21] = ~CRC_o_CRC[18];
            temp[22] = ~CRC_o_CRC[17];
            temp[23] = ~CRC_o_CRC[16];

            temp[24] = ~CRC_o_CRC[31];
            temp[25] = ~CRC_o_CRC[30];
            temp[26] = ~CRC_o_CRC[29];
            temp[27] = ~CRC_o_CRC[28];
            temp[28] = ~CRC_o_CRC[27];
            temp[29] = ~CRC_o_CRC[26];
            temp[30] = ~CRC_o_CRC[25];
            temp[31] = ~CRC_o_CRC[24];
        end
    end
    else begin
        CRC_o_CRC   = {POLY_WIDTH{1'b0}};
    end
end
/* Instantiations (connect signals must be by name not by order) */

endmodule
/*********** END_OF_FILE ***********/