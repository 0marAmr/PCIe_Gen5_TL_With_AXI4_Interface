/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_fc_hdr
   DEPARTMENT :     tl_rx_fc
   AUTHOR :         Reem Mohamed - Omar Amr
   AUTHOR’S EMAIL : reemmuhamed118@gmail.com
   -----------------------------------------------------------------------------
   RELEASE HISTORY
   VERSION  DATE        AUTHOR      DESCRIPTION
   1.0      2024-04-15              initial version
   -----------------------------------------------------------------------------
   PURPOSE :
   -----------------------------------------------------------------------------
   REUSE ISSUES
   Reset Strategy   : n/a
   Clock Domains    : n/a
   Critical Timing  : n/a
   Test Features    :
   Asynchronous I/F : n/a
   Scan Methodology : n/a
   Instantiations   :
   Synthesizable    : Y
   Other            :
   -FHDR------------------------------------------------------------------------*/
module tl_rx_fc_hdr #(
    parameter   HDR_FIELD_SIZE=8,
                HDR_FIFO_DEPTH = 2**7
) (
    input wire clk,
    input wire rst,
    input wire dll_init,
    input wire cr_hdr_inc,
    input wire ca_hdr_inc,
    output reg [HDR_FIELD_SIZE-1:0] creds_alloc_hdr,
    output reg [HDR_FIELD_SIZE-1:0] creds_rcv_hdr,
    output wire [1:0] dll_hdr_scale,
    output reg hdr_update
);
                

reg [4:0]ca_hdr_inc_reg;
reg [4:0]cr_hdr_inc_reg;
reg ca_hdr_inc_en;
reg cr_hdr_inc_en;
reg update_sig;

generate
    case (HDR_FIELD_SIZE)
        8:begin
            assign dll_hdr_scale=2'b00;
        end
        10:begin
            assign dll_hdr_scale=2'b10;
        end
        12:begin
            assign dll_hdr_scale=2'b11;
        end
    endcase
endgenerate

reg [2:0] next_state;
reg [2:0] present_state;

localparam [2:0] IDLE = 3'b000,
            INIT = 3'b001,
            INCR = 3'b010,
            UPDATE_COND=3'b011,
            UPDATE = 3'b100;

reg creds_alloc_hdr_init_en=0;
reg creds_rcv_hdr_init_en=0;
reg creds_alloc_hdr_inc_en=0;
reg creds_rcv_hdr_inc_en=0;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        present_state<=IDLE;
    end
    else
    present_state<=next_state;
end
always @(*) begin
creds_alloc_hdr_init_en=0;
creds_rcv_hdr_init_en=0;
hdr_update=0;

case (dll_hdr_scale)
    2'b00, 2'b01: 
    begin
        if (ca_hdr_inc==1) begin
            update_sig=1;
        end
        else
        update_sig=0;
    end
    2'b10:     
    begin
        if (ca_hdr_inc_reg==4) begin
            update_sig=1;
        end
        else
        update_sig=0;
    end
    2'b11: 
    begin
        if (ca_hdr_inc_reg==16) begin
            update_sig=1;
        end
        else
        update_sig=0;
    end 
endcase

case (present_state)
    IDLE: 
    begin
      if (dll_init==1) begin
        next_state=INIT;
      end 
      else
      next_state=IDLE; 
    end
    INIT: 
    begin
    if (dll_init==1) begin
           next_state=INIT; 
     end
     else
    next_state=INCR;
    creds_rcv_hdr_init_en=1;
    creds_alloc_hdr_init_en=1;
    end
    INCR: 
    begin
        if ((creds_rcv_hdr==creds_alloc_hdr)&&(update_sig==1)) begin
            next_state=UPDATE;
        end
     else if ((creds_rcv_hdr==creds_alloc_hdr)) begin
        next_state=UPDATE_COND;      
     end
     else
     next_state=INCR;
    end
    UPDATE_COND:
    begin
        if (update_sig==1) begin
            next_state=UPDATE;
        end
        else
        next_state=UPDATE_COND;
    end
    UPDATE:
    begin
        if ((creds_rcv_hdr==creds_alloc_hdr)&&(update_sig==1)) begin
            next_state=UPDATE;
        end
        else if (creds_rcv_hdr==creds_alloc_hdr) begin
            next_state=UPDATE_COND;
        end
        else
        next_state=INCR;

        hdr_update=1;
    end
    default:
    next_state=IDLE;
endcase

if(((ca_hdr_inc==1)&&dll_hdr_scale==2'b00) ||((ca_hdr_inc==1)&&dll_hdr_scale==2'b01) ||((ca_hdr_inc_reg==4)&&dll_hdr_scale==2'b10) ||((ca_hdr_inc_reg==16)&&dll_hdr_scale==2'b11)==1)
begin
    ca_hdr_inc_en=1;
end
else ca_hdr_inc_en=0;

if(((cr_hdr_inc==1)&&dll_hdr_scale==2'b00) ||((cr_hdr_inc==1)&&dll_hdr_scale==2'b01) ||((cr_hdr_inc_reg==4)&&dll_hdr_scale==2'b10) ||((cr_hdr_inc_reg==16)&&dll_hdr_scale==2'b11)==1)
begin
cr_hdr_inc_en=1;
end
else
cr_hdr_inc_en=0;

end

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        creds_rcv_hdr<=0;
        creds_alloc_hdr<=0;
        cr_hdr_inc_reg<=0;
        ca_hdr_inc_reg<=0;
    end
    else 
    begin
    if (dll_init==1) begin
        creds_rcv_hdr<=0;
    end 
    else if (cr_hdr_inc_en==1) begin
        creds_rcv_hdr<=creds_rcv_hdr+1;
    end

    if (dll_init==1) begin
        creds_alloc_hdr<=HDR_FIFO_DEPTH;
    end
    else if (ca_hdr_inc_en==1) begin
        creds_alloc_hdr<=creds_alloc_hdr+1;
    end

    if ((cr_hdr_inc==1)) begin
        cr_hdr_inc_reg<=cr_hdr_inc_reg+1;
    end
    if ((ca_hdr_inc==1)) begin
        ca_hdr_inc_reg<=ca_hdr_inc_reg+1;
    end
    if (ca_hdr_inc_reg==4 && dll_hdr_scale==2'b10) begin
        ca_hdr_inc_reg<=0;
    end
    else if (ca_hdr_inc_reg==16 && dll_hdr_scale=='b11) begin
        ca_hdr_inc_reg<=0;
    end

    if (cr_hdr_inc_reg==4 && dll_hdr_scale==2'b10) begin
        cr_hdr_inc_reg<=0;
    end
    else if (cr_hdr_inc_reg==16 && dll_hdr_scale=='b11) begin
        cr_hdr_inc_reg<=0;
    end
    end
end

endmodule