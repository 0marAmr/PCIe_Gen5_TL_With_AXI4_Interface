/* Module Name	: Response_Pop_FSM         	    */
/* Written By	: Ahmady                     	*/
/* Date			: 27-03-2024					*/
/* Version		: V_2							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: -							    */
/* Future Work  :                               */
module Response_Pop_FSM # (
    parameter   B_FIFO_DATA_WIDTH   = 10,
                B_FIFO_DEPTH        = 16,
                R_FIFO_DATA_WIDTH   = 1035,
                R_FIFO_DEPTH        = 16
)(
    input bit clk,
    input bit arst,
    // Interface with B FIFO
    Sync_FIFO_Interface.DIST_FIFO       B_FIFO_if,
    // Interface with R FIFO
    Sync_FIFO_Interface.DIST_FIFO       R_FIFO_if,
    // Interface with master
    Master_Interface.SLAVE 	            Master_if,
    // Interface with Request Path AW
    Slave_Internal_Response_if.B_TO_AW  AW_if,
    // Interface with Request Path AR
    Slave_Internal_Response_if.R_TO_AR  AR_if
);

/* Packages */

/* Parameters */
import axi_slave_package::*;

/* Internal Signals */
B_state_t B_state, B_next; 
R_state_t R_state, R_next; 


// store ID and response status
logic [ID_WIDTH - 1 : 0] BID_reg;
Resp_t                   BRESP_reg;
logic [ID_WIDTH - 1 : 0] RID_reg;
Resp_t                   RRESP_reg;

/* Useful Functions */

/* Assign Statements */

/* Always Blocks */
always_ff @(posedge clk or negedge arst) begin : State_FF
    if (!arst) begin
        B_state     <= B_IDLE; 
        R_state     <= R_IDLE; 
    end
    else begin 
        B_state     <= B_next; 
        R_state     <= R_next; 
    end
end

always_ff @(posedge clk or negedge arst) begin : Store_Resp
    if (!arst) begin
        BID_reg     <= '0;
        BRESP_reg   <= INVALID;
        RID_reg     <= '0;
        RRESP_reg   <= INVALID;
    end
    else begin 
        if (AW_if.BVALID) begin
            BID_reg     <= AW_if.BID;
            BRESP_reg   <= AW_if.BRESP;            
        end
        if (AR_if.RVALID) begin
            RID_reg     <= AR_if.RID;
            RRESP_reg   <= AR_if.RRESP;            
        end
    end
end

// Next State Decoder
always_comb begin : Next_B_State_Decoder
    B_next = B_XXX;
    case (B_state) 
    B_IDLE: begin
        // B_IDLE >> B_AW (get BVALID)
        if (AW_if.BVALID) begin
            B_next  = B_AW;            
        end
        // B_IDLE >> B_POP (B FIFO not empty)
        else if (!B_FIFO_if.FIFO_empty) begin
            B_next  = B_POP;
        end
        // B_IDLE >> B_IDLE
        else begin
            B_next  = B_IDLE;            
        end
    end
    B_POP: begin
        // B_POP >> B_POP_WAIT (if Master not READY)
        if (!Master_if.B_Channel_Msr.BREADY) begin
            B_next  = B_POP_WAIT;
        end
        // B_POP >> B_AW (if get Master READY and get BVALID)
        if (Master_if.B_Channel_Msr.BREADY && AW_if.BVALID) begin
            B_next  = B_AW;
        end
        // B_POP >> B_POP (new pop) (if get Master READY and B FIFO not empty)
        else if ((Master_if.B_Channel_Msr.BREADY) && (!B_FIFO_if.FIFO_empty)) begin
            B_next  = B_POP;
        end        
        // B_POP >> IDLE (if get Master READY and B FIFO is empty)
        else if ((Master_if.B_Channel_Msr.BREADY) && (B_FIFO_if.FIFO_empty) && (!AW_if.BVALID)) begin
            B_next  = B_IDLE;
        end      
        // B_POP >> B_POP (same pop) can occur ?!
        else begin
            B_next  = B_POP;
        end  
    end
    B_POP_WAIT: begin
        // B_POP_WAIT >> B_POP_WAIT (if Master not READY)
        if (!Master_if.B_Channel_Msr.BREADY) begin
            B_next  = B_POP_WAIT;
        end
        // B_POP_WAIT >> B_AW (if get Master READY and get BVALID)
        if ((Master_if.B_Channel_Msr.BREADY) && (AW_if.BVALID)) begin
            B_next  = B_AW;
        end
        // B_POP_WAIT >> B_POP (if get Master READY and (B FIFO not empty))
        else if ((Master_if.B_Channel_Msr.BREADY) && (!B_FIFO_if.FIFO_empty)) begin
            B_next  = B_POP;
        end
        // B_POP_WAIT >> IDLE (if get Master READY and B FIFO is empty and no BVALID)
        else if ((Master_if.B_Channel_Msr.BREADY) && (B_FIFO_if.FIFO_empty) && (!AW_if.BVALID)) begin
            B_next  = B_IDLE;
        end      
        // B_POP_WAIT >> B_POP_WAIT
        else begin
            B_next  = B_POP_WAIT;
        end  
    end
    B_AW: begin
        // B_AW >> B_POP_WAIT (if Master not READY)
        if (!Master_if.B_Channel_Msr.BREADY) begin
            B_next  = B_AW_WAIT;
        end
        // B_AW >> B_AW (if get Master READY and get BVALID)
        if (Master_if.B_Channel_Msr.BREADY && AW_if.BVALID) begin
            B_next  = B_AW;
        end
        // B_AW >> B_POP (new pop) (if get Master READY and B FIFO not empty)
        else if ((Master_if.B_Channel_Msr.BREADY) && (!B_FIFO_if.FIFO_empty)) begin
            B_next  = B_POP;
        end        
        // B_AW >> IDLE (if get Master READY and B FIFO is empty)
        else if ((Master_if.B_Channel_Msr.BREADY) && (B_FIFO_if.FIFO_empty) && (!AW_if.BVALID)) begin
            B_next  = B_IDLE;
        end      
        // B_AW >> B_POP (same pop) can occur ?!
        else begin
            B_next  = B_AW;
        end  
    end
    B_AW_WAIT: begin
        // B_AW_WAIT >> B_AW_WAIT (if Master not READY)
        if (!Master_if.B_Channel_Msr.BREADY) begin
            B_next  = B_AW_WAIT;
        end
        // B_AW_WAIT >> B_AW (if get Master READY and get BVALID)
        if ((Master_if.B_Channel_Msr.BREADY) && (AW_if.BVALID)) begin
            B_next  = B_AW;
        end
        // B_AW_WAIT >> B_POP (if get Master READY and (B FIFO not empty))
        else if ((Master_if.B_Channel_Msr.BREADY) && (!B_FIFO_if.FIFO_empty)) begin
            B_next  = B_POP;
        end
        // B_AW_WAIT >> IDLE (if get Master READY and B FIFO is empty and no BVALID)
        else if ((Master_if.B_Channel_Msr.BREADY) && (B_FIFO_if.FIFO_empty) && (!AW_if.BVALID)) begin
            B_next  = B_IDLE;
        end      
        // B_AW_WAIT >> B_AW_WAIT
        else begin
            B_next  = B_AW_WAIT;
        end  
    end
    default: begin
    end
    endcase 
end 

// Output Decoder
always_comb begin : B_Output_Decoder
    /* Default Values */
    // B Channel
    Master_if.B_Channel_Slv.BID         = '0; 
    Master_if.B_Channel_Slv.BVALID      = '0; 
    Master_if.B_Channel_Slv.BRESP       = INVALID;

    // B FIFO
    B_FIFO_if.FIFO_rd_en                = 1'b0;

    case (B_state) 
    B_IDLE: begin
        // B_IDLE >> B_AW (get BVALID)
        if (AW_if.BVALID) begin
            Master_if.B_Channel_Slv.BID         = AW_if.BID; 
            Master_if.B_Channel_Slv.BVALID      = 1'b1; 
            Master_if.B_Channel_Slv.BRESP       = AW_if.BRESP;                        
        end
        // B_IDLE >> B_POP (B FIFO not empty)
        else if (!B_FIFO_if.FIFO_empty) begin
            // B FIFO pop operation
            B_FIFO_if.FIFO_rd_en                = 1'b1; 
        end
    end
    B_POP: begin
        /*
            B_FIFO_if.FIFO_rd_data [B_FIFO_DATA_WIDTH : 0] 
                BID     [B_FIFO_DATA_WIDTH - 1:2]
                BRESP   [1:0]
        */
        Master_if.B_Channel_Slv.BID     = B_FIFO_if.FIFO_rd_data[B_FIFO_DATA_WIDTH - 1 : 2];
        Master_if.B_Channel_Slv.BVALID  = 1'b1;
        Master_if.B_Channel_Slv.BRESP   = Resp_t'(B_FIFO_if.FIFO_rd_data[1 : 0]);                                
        // R_POP >> R_POP (new pop)
        if ((Master_if.B_Channel_Msr.BREADY) && (!B_FIFO_if.FIFO_empty)) begin
            B_FIFO_if.FIFO_rd_en        = 1'b1; 
        end            
    end
    B_POP_WAIT: begin
        // keep same values
        Master_if.B_Channel_Slv.BID     = B_FIFO_if.FIFO_rd_data[B_FIFO_DATA_WIDTH - 1 : 2];
        Master_if.B_Channel_Slv.BVALID  = 1'b1;
        Master_if.B_Channel_Slv.BRESP   = Resp_t'(B_FIFO_if.FIFO_rd_data[1 : 0]);            
        // R_POP_WAIT >> R_POP
        if ((Master_if.B_Channel_Msr.BREADY) && (!B_FIFO_if.FIFO_empty)) begin
            B_FIFO_if.FIFO_rd_en        = 1'b1; 
        end
    end
    B_AW: begin
        if (AW_if.BVALID) begin
            Master_if.B_Channel_Slv.BID         = AW_if.BID; 
            Master_if.B_Channel_Slv.BVALID      = 1'b1; 
            Master_if.B_Channel_Slv.BRESP       = AW_if.BRESP;                        
        end
    end
    B_AW_WAIT: begin
        // keep same values
        Master_if.B_Channel_Slv.BID     = BID_reg;
        Master_if.B_Channel_Slv.BVALID  = 1'b1;
        Master_if.B_Channel_Slv.BRESP   = BRESP_reg;                      

        if ((Master_if.B_Channel_Msr.BREADY) &&  (AW_if.BVALID)) begin
            Master_if.B_Channel_Slv.BID         = AW_if.BID; 
            Master_if.B_Channel_Slv.BVALID      = 1'b1; 
            Master_if.B_Channel_Slv.BRESP       = AW_if.BRESP;                        
        end
    end
    default: begin
    end
    endcase 
end

// Next State Decoder
always_comb begin : Next_R_State_Decoder
    R_next = R_XXX;
    case (R_state) 
    R_IDLE: begin
        // R_IDLE >> R_AR (get BVALID)
        if (AR_if.RVALID) begin
            R_next  = R_AR;            
        end
        // R_IDLE >> R_POP (B FIFO not empty)
        else if (!R_FIFO_if.FIFO_empty) begin
            R_next  = R_POP;
        end
        // R_IDLE >> R_IDLE
        else begin
            R_next  = R_IDLE;            
        end
    end
    R_POP: begin
        // R_POP >> R_POP_WAIT (if Master not READY)
        if (!Master_if.R_Channel_Msr.RREADY) begin
            R_next  = R_POP_WAIT;
        end
        // R_POP >> R_AR (if get Master READY and get BVALID)
        if (Master_if.R_Channel_Msr.RREADY && AR_if.RVALID) begin
            R_next  = R_AR;
        end
        // R_POP >> R_POP (new pop) (if get Master READY and B FIFO not empty)
        else if ((Master_if.R_Channel_Msr.RREADY) && (!R_FIFO_if.FIFO_empty)) begin
            R_next  = R_POP;
        end        
        // R_POP >> IDLE (if get Master READY and B FIFO is empty)
        else if ((Master_if.R_Channel_Msr.RREADY) && (R_FIFO_if.FIFO_empty) && (!AR_if.RVALID)) begin
            R_next  = R_IDLE;
        end      
        // R_POP >> R_POP (same pop) can occur ?!
        else begin
            R_next  = R_POP;
        end  
    end
    R_POP_WAIT: begin
        // R_POP_WAIT >> R_POP_WAIT (if Master not READY)
        if (!Master_if.R_Channel_Msr.RREADY) begin
            R_next  = R_POP_WAIT;
        end
        // R_POP_WAIT >> R_AR (if get Master READY and get BVALID)
        if ((Master_if.R_Channel_Msr.RREADY) && (AR_if.RVALID)) begin
            R_next  = R_AR;
        end
        // R_POP_WAIT >> R_POP (if get Master READY and (B FIFO not empty))
        else if ((Master_if.R_Channel_Msr.RREADY) && (!R_FIFO_if.FIFO_empty)) begin
            R_next  = R_POP;
        end
        // R_POP_WAIT >> IDLE (if get Master READY and B FIFO is empty and no BVALID)
        else if ((Master_if.R_Channel_Msr.RREADY) && (R_FIFO_if.FIFO_empty) && (!AR_if.RVALID)) begin
            R_next  = R_IDLE;
        end      
        // R_POP_WAIT >> R_POP_WAIT
        else begin
            R_next  = R_POP_WAIT;
        end  
    end
    R_AR: begin
        // R_AR >> R_POP_WAIT (if Master not READY)
        if (!Master_if.R_Channel_Msr.RREADY) begin
            R_next  = R_AR_WAIT;
        end
        // R_AR >> R_AR (if get Master READY and get BVALID)
        if (Master_if.R_Channel_Msr.RREADY && AR_if.RVALID) begin
            R_next  = R_AR;
        end
        // R_AR >> R_POP (new pop) (if get Master READY and B FIFO not empty)
        else if ((Master_if.R_Channel_Msr.RREADY) && (!R_FIFO_if.FIFO_empty)) begin
            R_next  = R_POP;
        end        
        // R_AR >> IDLE (if get Master READY and B FIFO is empty)
        else if ((Master_if.R_Channel_Msr.RREADY) && (R_FIFO_if.FIFO_empty) && (!AR_if.RVALID)) begin
            R_next  = R_IDLE;
        end      
        // R_AR >> R_POP (same pop) can occur ?!
        else begin
            R_next  = R_AR;
        end  
    end
    R_AR_WAIT: begin
        // R_AR_WAIT >> R_AR_WAIT (if Master not READY)
        if (!Master_if.R_Channel_Msr.RREADY) begin
            R_next  = R_AR_WAIT;
        end
        // R_AR_WAIT >> R_AR (if get Master READY and get BVALID)
        if ((Master_if.R_Channel_Msr.RREADY) && (AR_if.RVALID)) begin
            R_next  = R_AR;
        end
        // R_AR_WAIT >> R_POP (if get Master READY and (B FIFO not empty))
        else if ((Master_if.R_Channel_Msr.RREADY) && (!R_FIFO_if.FIFO_empty)) begin
            R_next  = R_POP;
        end
        // R_AR_WAIT >> IDLE (if get Master READY and B FIFO is empty and no BVALID)
        else if ((Master_if.R_Channel_Msr.RREADY) && (R_FIFO_if.FIFO_empty) && (!AR_if.RVALID)) begin
            R_next  = R_IDLE;
        end      
        // R_AR_WAIT >> R_AR_WAIT
        else begin
            R_next  = R_AR_WAIT;
        end  
    end
    default: begin
    end
    endcase 
end 

// Output Decoder
always_comb begin : R_Output_Decoder
    /* Default Values */
        // R Channel
    Master_if.R_Channel_Slv.RID     = '0; 
    Master_if.R_Channel_Slv.RVALID  = '0;
    Master_if.R_Channel_Slv.RDATA   = '0;
    Master_if.R_Channel_Slv.RRESP   = INVALID;
    Master_if.R_Channel_Slv.RLAST   = '0; 

        // R FIFO
    R_FIFO_if.FIFO_rd_en    = 1'b0;

    case (R_state) 
    R_IDLE: begin
        // R_IDLE >> R_AR (get RVALID)
        if (AR_if.RVALID) begin
            Master_if.R_Channel_Slv.RID         = AR_if.RID; 
            Master_if.R_Channel_Slv.RVALID      = 1'b1; 
            Master_if.R_Channel_Slv.RDATA       = '0;
            Master_if.R_Channel_Slv.RRESP       = AR_if.RRESP;  
            Master_if.R_Channel_Slv.RLAST       = '1;   // be 0 1 ? 
        end
        // R_IDLE >> R_POP (B FIFO not empty)
        else if (!R_FIFO_if.FIFO_empty) begin
            // B FIFO pop operation
            R_FIFO_if.FIFO_rd_en                = 1'b1; 
        end
    end
    R_POP: begin
        /*
            R_FIFO_if.FIFO_rd_data [R_FIFO_DATA_WIDTH - 1: 0] 
                RID     [R_FIFO_DATA_WIDTH - 1 : 1027]
                RDATA   [1026 : 3]
                RRESP   [2:1]
                RLAST   [0]
        */
        Master_if.R_Channel_Slv.RVALID  = 1'b1;
        Master_if.R_Channel_Slv.RID     = R_FIFO_if.FIFO_rd_data[R_FIFO_DATA_WIDTH - 1 : 1027];
        Master_if.R_Channel_Slv.RDATA   = R_FIFO_if.FIFO_rd_data[1026 : 3];
	    Master_if.R_Channel_Slv.RRESP   = Resp_t'(R_FIFO_if.FIFO_rd_data[2 : 1]);
        Master_if.R_Channel_Slv.RLAST   = R_FIFO_if.FIFO_rd_data[0];

        // R_POP >> R_POP (new pop)
        if ((Master_if.R_Channel_Msr.RREADY) && (!R_FIFO_if.FIFO_empty)) begin
            R_FIFO_if.FIFO_rd_en        = 1'b1; 
        end            
    end
    R_POP_WAIT: begin
        // keep same values
        Master_if.R_Channel_Slv.RID     = R_FIFO_if.FIFO_rd_data[R_FIFO_DATA_WIDTH - 1 : 1027];
        Master_if.R_Channel_Slv.RVALID  = 1'b1;
        Master_if.R_Channel_Slv.RDATA   = R_FIFO_if.FIFO_rd_data[1026 : 3];
    	Master_if.R_Channel_Slv.RRESP   = Resp_t'(R_FIFO_if.FIFO_rd_data[2 : 1]); 
        Master_if.R_Channel_Slv.RLAST   = R_FIFO_if.FIFO_rd_data[0];

        // R_POP_WAIT >> R_POP
        if ((Master_if.R_Channel_Msr.RREADY) && (!R_FIFO_if.FIFO_empty)) begin
            R_FIFO_if.FIFO_rd_en        = 1'b1; 
        end        
    end
    R_AR: begin
        if (AR_if.RVALID) begin
            Master_if.R_Channel_Slv.RID         = AR_if.RID; 
            Master_if.R_Channel_Slv.RVALID      = 1'b1; 
            Master_if.R_Channel_Slv.RDATA       = '0;
            Master_if.R_Channel_Slv.RRESP       = AR_if.RRESP;  
            Master_if.R_Channel_Slv.RLAST       = '1;   // be 0 1 ? 
        end
    end
    R_AR_WAIT: begin
        // keep same values
        Master_if.R_Channel_Slv.RID     = RID_reg;
        Master_if.R_Channel_Slv.RVALID  = 1'b1;
        Master_if.R_Channel_Slv.RDATA   = '0;
        Master_if.R_Channel_Slv.RRESP   = RRESP_reg;                      
        Master_if.R_Channel_Slv.RLAST       = '1;   // be 0 1 ? 

        if ((Master_if.R_Channel_Msr.RREADY) &&  (AR_if.RVALID)) begin
            Master_if.R_Channel_Slv.RID         = AR_if.RID; 
            Master_if.R_Channel_Slv.RVALID      = 1'b1; 
            Master_if.R_Channel_Slv.RDATA       = '0;
            Master_if.R_Channel_Slv.RRESP       = AR_if.RRESP;  
            Master_if.R_Channel_Slv.RLAST       = '1;   // be 0 1 ? 
        end
    end
    default: begin
    end
    endcase 
end

/* Instantiations */

endmodule: Response_Pop_FSM
/**** END_OF_FILE ****/