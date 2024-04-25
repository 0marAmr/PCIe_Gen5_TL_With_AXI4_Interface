/* Module Name	: Response_Push_FSM         	*/
/* Written By	: Ahmady                     	*/
/* Date			: 27-03-2024					*/
/* Version		: V_2							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: -							    */
/* Future Work  : need to handle glitch         */
/*                happened for FIFO_wr_en and   */
/*                Cpl_Grant signals             */
module Response_Push_FSM # (
    parameter R_FIFO_DEPTH      = 10,
              R_ADDR_WIDTH      = $clog2(R_FIFO_DEPTH) 
)(
    input bit clk,
    input bit arst,
    // Interface with B FIFO
    Sync_FIFO_Interface.SOURCE_FIFO B_FIFO_if,
    // Interface with R FIFO
    Sync_FIFO_Interface.SOURCE_FIFO R_FIFO_if,
    // Interface with P2A
    P2A_Push_FSM_Interface.FSM_P2A  P2A_Cpl_if
);

/* Packages */

/* Parameters */
import axi_slave_package::*;

/* Internal Signals */
state_t state, next; 
Up_Down_Counter_Interface #(
    .MAX_COUNT(R_FIFO_DEPTH)
) Count_if (
);


/* Useful Functions */
// function that perform this equation out = ceil(in % 32) 
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

// function that check if there is available space in fifo enough for push data 
function logic Available_Check(input logic [R_ADDR_WIDTH:0] available, input logic [9:0] length);
    if (available >= Ceil_mod_5(length)) begin
        return 1'b1;
    end
    else begin
        return 1'b0;
    end
endfunction

/* Assign Statements */

/* Always Blocks */
// State Register
always_ff @(posedge clk or negedge arst) begin : State_FF
    if (!arst)
        state <= IDLE_State; 
    else 
        state <= next; 
end

// Next State Decoder
always_comb begin : Next_State_Decoder
    next = XXX;
    case (state) 
    IDLE_State: begin
        // IDLE_State >> B_State
        if ((P2A_Cpl_if.Cpl_Type == CPL) && (!B_FIFO_if.FIFO_full)) begin
            next = B_State;   
        end 
        // IDLE_State >> R_State
        else if ((P2A_Cpl_if.Cpl_Type == CPLD) && (Available_Check(R_FIFO_if.FIFO_available, P2A_Cpl_if.Cpl_Length))) begin
            next = R_State;      
        end
        // IDLE_State >> IDLE_State
        else begin
            next = IDLE_State;
        end
    end
    B_State: begin
        // B_State >> B_State
        if ((P2A_Cpl_if.Cpl_Type == CPL) && (!B_FIFO_if.FIFO_full)) begin
            next = B_State;   
        end 
        // B_State >> R_State
        else if ((P2A_Cpl_if.Cpl_Type == CPLD) && (Available_Check(R_FIFO_if.FIFO_available, P2A_Cpl_if.Cpl_Length))) begin
            next = R_State;           
        end
        // B_State >> IDLE_State
        else begin
            next = IDLE_State;
        end                    
    end
    R_State: begin
        // R_State >> B_State
        // if (Count_if.Done && ((P2A_Cpl_if.Cpl_Type == CPL) && (!B_FIFO_if.FIFO_full))) begin
        //     next = B_State;            
        // end
        // R_State >> R_State
        // else if (Count_if.Done && ((P2A_Cpl_if.Cpl_Type == CPLD) && (Available_Check(R_FIFO_if.FIFO_available, P2A_Cpl_if.Cpl_Length)))) begin
        //     next = R_State;
        // end
        // R_State >> IDLE_State
        if (Count_if.Done) begin
            next = XXX;
        end
        // R_State >> R_State
        else begin
            next = R_State;
        end
    end
    XXX: begin
        // IDLE_State >> B_State
        if ((P2A_Cpl_if.Cpl_Type == CPL) && (!B_FIFO_if.FIFO_full)) begin
            next = B_State;   
        end 
        // IDLE_State >> R_State
        else if ((P2A_Cpl_if.Cpl_Type == CPLD) && (Available_Check(R_FIFO_if.FIFO_available, P2A_Cpl_if.Cpl_Length))) begin
            next = R_State;      
        end
        // IDLE_State >> IDLE_State
        else begin
            next = IDLE_State;
        end
    end
    default: begin
    end
    endcase 
end 

// Output Decoder
always_comb begin : Output_Decoder
    /* Default Values */
    // Counter
    Count_if.En                     = FALSE;
    Count_if.Load                   = FALSE;
    Count_if.Load_Count             = '0;
    Count_if.Mode                   = UP;
    
    // B FIFO
    B_FIFO_if.FIFO_wr_en            = 1'b0;
    B_FIFO_if.FIFO_wr_data          = '0;

    // R FIFO
    R_FIFO_if.FIFO_wr_en            = 1'b0;
    R_FIFO_if.FIFO_wr_data          = '0;
    
    // P2A
    P2A_Cpl_if.Cpl_Grant            = 1'b0;
    P2A_Cpl_if.Cpl_Command          = 1'b0;

    case (state) 
    IDLE_State: begin
        /* take default values */
        if ((P2A_Cpl_if.Cpl_Type == CPL) && (!B_FIFO_if.FIFO_full)) begin
            B_FIFO_if.FIFO_wr_en         = 1'b1;
            B_FIFO_if.FIFO_wr_data       = P2A_Cpl_if.Cpl_Data;  
            P2A_Cpl_if.Cpl_Grant         = 1'b1;
        end 
        else if ((P2A_Cpl_if.Cpl_Type == CPLD) && (Available_Check(R_FIFO_if.FIFO_available, P2A_Cpl_if.Cpl_Length))) begin
            // R FIFO
            R_FIFO_if.FIFO_wr_en         = 1'b1;
            // R_FIFO_if.FIFO_wr_data       = P2A_Cpl_if.Cpl_Data;
            R_FIFO_if.FIFO_wr_data       = (Ceil_mod_5(P2A_Cpl_if.Cpl_Length) == 1) ? {P2A_Cpl_if.Cpl_Data[1033:1], 1'b1} : P2A_Cpl_if.Cpl_Data;
            // Counter
            Count_if.Load               = TRUE;
            Count_if.Load_Count         = Ceil_mod_5(P2A_Cpl_if.Cpl_Length) - 1;    
            // P2A
            P2A_Cpl_if.Cpl_Grant        = 1'b1;
            P2A_Cpl_if.Cpl_Command      = 1'b1;
        end
    end
    B_State: begin
        if ((P2A_Cpl_if.Cpl_Type == CPL) && (!B_FIFO_if.FIFO_full)) begin
            B_FIFO_if.FIFO_wr_en         = 1'b1;
            B_FIFO_if.FIFO_wr_data       = P2A_Cpl_if.Cpl_Data;  
            P2A_Cpl_if.Cpl_Grant         = 1'b1;
        end
        else if ((P2A_Cpl_if.Cpl_Type == CPLD) && (Available_Check(R_FIFO_if.FIFO_available, P2A_Cpl_if.Cpl_Length))) begin
            // R FIFO
            R_FIFO_if.FIFO_wr_en         = 1'b1;
            R_FIFO_if.FIFO_wr_data       = (Ceil_mod_5(P2A_Cpl_if.Cpl_Length) == 1) ? {P2A_Cpl_if.Cpl_Data[1033:1], 1'b1} : P2A_Cpl_if.Cpl_Data;
            // Counter
            Count_if.Load                = TRUE;
            Count_if.Load_Count          = Ceil_mod_5(P2A_Cpl_if.Cpl_Length) - 1;    
            // P2A
            P2A_Cpl_if.Cpl_Grant         = 1'b1;
            P2A_Cpl_if.Cpl_Command       = 1'b1;
        end
    end
    R_State: begin
        // R_State >> B_State
        // if (Count_if.Done && ((P2A_Cpl_if.Cpl_Type == CPL) && (!B_FIFO_if.FIFO_full))) begin
        //     B_FIFO_if.FIFO_wr_en         = 1'b1;
        //     B_FIFO_if.FIFO_wr_data       = P2A_Cpl_if.Cpl_Data;    
        // end
        // R_State >> R_State (new push)
        // else if (Count_if.Done && ((P2A_Cpl_if.Cpl_Type == CPLD) && (Available_Check(R_FIFO_if.FIFO_available, P2A_Cpl_if.Cpl_Length)))) begin
        //     // R FIFO
        //     R_FIFO_if.FIFO_wr_en         = 1'b1;
        //     R_FIFO_if.FIFO_wr_data       = P2A_Cpl_if.Cpl_Data;
        //     // Counter
        //     Count_if.Load               = TRUE;
        //     Count_if.Load_Count         = Ceil_mod_5(P2A_Cpl_if.Cpl_Length) - 1;    
        //     // P2A
        //     // P2A_Cpl_if.Cpl_Grant        = 1'b1;  
        //     // P2A_Cpl_if.Cpl_Command       = 1'b1;
        // end
        // R_State >> IDLE_State 
        if (Count_if.Done) begin
            R_FIFO_if.FIFO_wr_en         = 1'b0;
            R_FIFO_if.FIFO_wr_data       = '0;    
            P2A_Cpl_if.Cpl_Grant         = 1'b0;
            P2A_Cpl_if.Cpl_Command       = 1'b0;
        end
        // R_State >> R_State (same push)
        else begin
            R_FIFO_if.FIFO_wr_en         = 1'b1;
            // R_FIFO_if.FIFO_wr_data       = P2A_Cpl_if.Cpl_Data;
            // ADD RLAST
            R_FIFO_if.FIFO_wr_data       = (Count_if.Count == 1) ? {P2A_Cpl_if.Cpl_Data[1033:1], 1'b1} : P2A_Cpl_if.Cpl_Data;
            /* As Done = fun(En) in Counter module and here En = fun(En), thus ModelSim give simulation error */ 
            // Count_if.En                  = TRUE;
            Count_if.Load                = FALSE;
            Count_if.Load_Count          = '0;
            // Count_if.Mode                = DOWN;
            // P2A_Cpl_if.Cpl_Grant         = 1'b1;
            P2A_Cpl_if.Cpl_Command       = 1'b1;
        end
        Count_if.En                 = TRUE;
        Count_if.Mode                = DOWN;
        // P2A_Cpl_if.Cpl_Grant        = 1'b1;  
        // P2A_Cpl_if.Cpl_Command      = 1'b1;
    end
    XXX: begin
        /* take default values */
        if ((P2A_Cpl_if.Cpl_Type == CPL) && (!B_FIFO_if.FIFO_full)) begin
            B_FIFO_if.FIFO_wr_en         = 1'b1;
            B_FIFO_if.FIFO_wr_data       = P2A_Cpl_if.Cpl_Data;  
            P2A_Cpl_if.Cpl_Grant         = 1'b1;
        end 
        else if ((P2A_Cpl_if.Cpl_Type == CPLD) && (Available_Check(R_FIFO_if.FIFO_available, P2A_Cpl_if.Cpl_Length))) begin
            // R FIFO
            R_FIFO_if.FIFO_wr_en         = 1'b1;
            R_FIFO_if.FIFO_wr_data       = (Count_if.Count == 1) ? {P2A_Cpl_if.Cpl_Data[1033:1], 1'b1} : P2A_Cpl_if.Cpl_Data;
            // R_FIFO_if.FIFO_wr_data       = P2A_Cpl_if.Cpl_Data;
            // Counter
            Count_if.Load               = TRUE;
            Count_if.Load_Count         = Ceil_mod_5(P2A_Cpl_if.Cpl_Length) - 1;    
            // P2A
            P2A_Cpl_if.Cpl_Grant        = 1'b1;
            P2A_Cpl_if.Cpl_Command      = 1'b1;
        end

        // P2A_Cpl_if.Cpl_Grant            = 1'b0;
        // P2A_Cpl_if.Cpl_Command          = 1'b0;
    end
    default: begin
        /* take default values */
    end
    endcase 
end

/* Instantiations */
Up_Down_Counter u_Up_Down_Counter (clk, arst, Count_if);

endmodule: Response_Push_FSM
/*********** END_OF_FILE ***********/
