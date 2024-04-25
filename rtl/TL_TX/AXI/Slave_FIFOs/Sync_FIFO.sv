/* Module Name	: Sync_FIFO         		*/
/* Written By	: Ahmady                    */
/* Date			: 27-03-2024		        */
/* Version		: V_2			            */
/* Updates		: -			                */
/* Dependencies	: -				            */
/* Used			: -			                */
module Sync_FIFO #(
    DATA_WIDTH      = 8,
    FIFO_DEPTH      = 10,
    ADDR_WIDTH      = $clog2(FIFO_DEPTH) 
)(
    input bit clk,
    input bit arst,
    Sync_FIFO_Interface.FIFO_SOURCE Src_if,
    Sync_FIFO_Interface.FIFO_DIST   Dist_if
);

/* Parameters */
import axi_slave_package::*;

/* Internal Signals */
logic [DATA_WIDTH - 1  : 0] FIFO_MEM [FIFO_DEPTH - 1  : 0];
logic [ADDR_WIDTH   : 0]    wr_ptr;
logic [ADDR_WIDTH  :  0]    rd_ptr;     

/* Assign Statements */
assign Src_if.FIFO_full   = ({~wr_ptr[ADDR_WIDTH], wr_ptr[ADDR_WIDTH - 1 : 0]} == rd_ptr) ? TRUE : FALSE;
assign Dist_if.FIFO_empty = (wr_ptr == rd_ptr) ? TRUE : FALSE;


/* Always Blocks */
always_ff @(posedge clk or negedge arst) begin : Write_Read_Operation
    if (!arst) begin
	Dist_if.FIFO_rd_data    <= {DATA_WIDTH{1'b0}};
    end
    else begin
        if ((Src_if.FIFO_wr_en && !Src_if.FIFO_full) || (Src_if.FIFO_wr_en && Dist_if.FIFO_rd_en)) begin
            FIFO_MEM[wr_ptr[ADDR_WIDTH - 1 : 0]]    <= Src_if.FIFO_wr_data; 
        end
        else begin
        end
        if ((Dist_if.FIFO_rd_en && !Dist_if.FIFO_empty) || (Dist_if.FIFO_rd_en && Src_if.FIFO_wr_en)) begin
            Dist_if.FIFO_rd_data    <= FIFO_MEM[rd_ptr[ADDR_WIDTH - 1 : 0]];
            // flush read data
            if (!(Dist_if.FIFO_rd_en && Src_if.FIFO_wr_en && Src_if.FIFO_full)) begin
                FIFO_MEM[rd_ptr[ADDR_WIDTH - 1 : 0]]    <= 'd0;   
            end
        end
        else begin

        end
    end
end : Write_Read_Operation

// Note: need to handle case when FIFO empty and wr_en, rd_en (write then read)
// Note: need to handle case when FIFO full and wr_en, rd_en (read then write) (Done)


// rd_ptr, wr_ptr and FIFO_count calculations
always_ff @(posedge clk or negedge arst) begin : rd_ptr_wr_ptr_count_Calc
    if (!arst) begin
        wr_ptr                  <= '0;
        rd_ptr                  <= '0;
        Src_if.FIFO_available   <= FIFO_DEPTH;
        // Dist_if.FIFO_available  <= FIFO_DEPTH;
    end
    else begin
        case ({Src_if.FIFO_wr_en, Dist_if.FIFO_rd_en})
            // need modify: can use casex instead ?!
            // READ
            // 2'b01, 2'bx1, 2'bz1 : begin
            2'b01 : begin 
                if (~Dist_if.FIFO_empty) begin
                    Src_if.FIFO_available  <= (Src_if.FIFO_available  == FIFO_DEPTH) ? FIFO_DEPTH: Src_if.FIFO_available + 1; 
                    // to handle if fifo depth is not multiple of 2
                    // ex. if Depth = 10 then valid rd_ptr values are {0_0000:0_1001 , 1_0000:1_1001}
                    rd_ptr  <= (rd_ptr[ADDR_WIDTH - 1 : 0] == FIFO_DEPTH - 1) ?  {~rd_ptr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} : rd_ptr + 1;          
                end
            end
            // WRITE
            // 2'b10, 2'b1x, 2'b1z: begin
            2'b10 : begin
                if (~Src_if.FIFO_full) begin
                    Src_if.FIFO_available  <= (Src_if.FIFO_available  == '0) ? '0: Src_if.FIFO_available - 1; 
                    wr_ptr  <= (wr_ptr[ADDR_WIDTH - 1 : 0] == FIFO_DEPTH - 1) ?  {~wr_ptr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} : wr_ptr + 1;          
                end
            end
            // READ_WRITE
            2'b11: begin
                // if empty fifo, there is no need to update pointer 
                if (Dist_if.FIFO_empty) begin
                    
                end
                else begin
                    rd_ptr  <= (rd_ptr[ADDR_WIDTH - 1 : 0] == FIFO_DEPTH - 1) ?  {~rd_ptr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} : rd_ptr + 1;          
                    wr_ptr  <= (wr_ptr[ADDR_WIDTH - 1 : 0] == FIFO_DEPTH - 1) ?  {~wr_ptr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} : wr_ptr + 1;                  
                end
            end
            // default: 
        endcase
    end
end : rd_ptr_wr_ptr_count_Calc

/* Instantiations */

endmodule: Sync_FIFO
/*********** END_OF_FILE ***********/
