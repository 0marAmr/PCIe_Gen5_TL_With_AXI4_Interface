/* -----------------------------------------------------------------------------
   Copyright (c) 2024 PCIe V5 graduation project
   -----------------------------------------------------------------------------
   FILE NAME :      tl_rx_fc_data
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
module tl_rx_fc_data #(
    parameter PAYLOAD_IN_CREDS=9,
    DATA_FIELD_SIZE=12,
    DATA_FIFO_DEPTH = 2**7
) (
    input wire [PAYLOAD_IN_CREDS-1:0] data_buffer_out,
    input wire [PAYLOAD_IN_CREDS-1:0] data_buffer_in,
    input wire cr_data_inc,
    input wire ca_data_inc,
    //input wire [1:0] ca_data_inc_value, // 8 6 4 2 
    input wire dll_init,
    input wire clk,
    input wire rst,
    input wire [1:0] typ,
    input wire [2:0] max_payload,

    output reg [DATA_FIELD_SIZE-1:0] creds_alloc_data,
    output reg [DATA_FIELD_SIZE-1:0] creds_rcv_data,
    output wire [1:0] dll_data_scale,
    output reg data_update
);

reg [9:0] max_payload_creds;

reg [DATA_FIELD_SIZE-1:0]   creds_rcv_data_inv;
reg [DATA_FIELD_SIZE-1:0]   total_creds_rcv_data_cmpl;
wire [DATA_FIELD_SIZE-1:0]   creds_rcv_data_cmpl;
wire [DATA_FIELD_SIZE-1:0]   total_result;
wire [DATA_FIELD_SIZE-1:0]   result;

generate
    case (DATA_FIELD_SIZE)
        12:begin
            assign dll_data_scale=2'b00;
            assign creds_rcv_data_cmpl=total_creds_rcv_data_cmpl[11:0];
            assign total_result=creds_alloc_data+creds_rcv_data_cmpl;
            assign result=total_result[11:0];
        end
        14:begin
            assign dll_data_scale=2'b10;
            assign creds_rcv_data_cmpl=total_creds_rcv_data_cmpl[13:0];
            assign total_result=creds_alloc_data+creds_rcv_data_cmpl;
            assign result=total_result[13:0];
        end
        16:begin
            assign dll_data_scale=2'b11;
            assign creds_rcv_data_cmpl=total_creds_rcv_data_cmpl[15:0];
            assign total_result=creds_alloc_data+creds_rcv_data_cmpl;
            assign result=total_result[15:0]; 
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

reg dll_data_init_en;
reg creds_rcv_data_init_en;
reg update_cond_sig;
reg update_sig;
reg [4:0] ca_data_inc_reg;
reg [4:0] cr_data_inc_reg;
reg cr_data_inc_en;
reg ca_data_inc_en;

always @(posedge clk or negedge rst)
begin
if (!rst)
present_state<=IDLE;
else
present_state<=next_state;
end

always @(*) begin
dll_data_init_en=0;
creds_rcv_data_init_en=0;
data_update=0;
creds_rcv_data_inv=~creds_rcv_data;
total_creds_rcv_data_cmpl=creds_rcv_data_inv+1;
case (max_payload)
    3'b010: max_payload_creds=32;
    3'b011: max_payload_creds=64;
    3'b100: max_payload_creds=128;
    3'b101: max_payload_creds=256;
    default:max_payload_creds=8;
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
        creds_rcv_data_init_en=1;
        dll_data_init_en=1;
    
    end
    INCR: 
    begin
    if ((update_cond_sig==1)&&(update_sig==1)) begin
        next_state=UPDATE;
    end
    else if (update_cond_sig==1) begin
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
        if ((update_cond_sig==1)&&(update_sig==1)) begin
            next_state=UPDATE;
        end
        else if (update_cond_sig==1) begin
            next_state=UPDATE_COND;
        end
        else
        next_state=INCR;

        data_update=1;
    end
    default:
    next_state=IDLE;
endcase
end

always @(*) begin    
if (present_state==1) begin
    update_cond_sig=0;
end
else
begin
case (typ)
    2'b00: 
    begin
        if (result<max_payload_creds) begin
            update_cond_sig=1;
        end
          else
    update_cond_sig=0;
    end
    2'b01: 
    begin
      if (creds_rcv_data==creds_alloc_data) begin
        update_cond_sig=1;
      end
      else
      update_cond_sig=0;
    end
    2'b10: 
    begin
        if (result<max_payload_creds) begin
            update_cond_sig=1;
        end
         else
    update_cond_sig=0;
    end
   
    default: update_cond_sig=0;
endcase
end
case (typ)
2'b00:
begin
    if (ca_data_inc==1) begin
        update_sig=1;
    end
    else
    update_sig=0;
end
2'b01:
begin
    case (dll_data_scale)
    2'b00: 
    begin
        if (ca_data_inc==1) begin
            update_sig=1;
        end
        else
        update_sig=0;
    end
    2'b01: 
    begin
        if (ca_data_inc==1) begin
            update_sig=1;
        end
        else
        update_sig=0;
    end
    2'b10: 
    begin
        if (ca_data_inc_reg==4) begin
            update_sig=1;
        end
        else
        update_sig=0;
    end
    2'b11: 
    begin
        if (ca_data_inc_reg==16) begin
            update_sig=1;
        end
        else
        update_sig=0;
    end
    endcase
end
2'b10:
if (ca_data_inc==1) begin
    update_sig=1;
end
else
update_sig=0;
default:
update_sig=0;
endcase
if ((typ==2'b00&&ca_data_inc==1) ||(typ==2'b10&&ca_data_inc==1) ||(typ==2'b01&&dll_data_scale==2'b00&&ca_data_inc==1) ||(typ==2'b01&&dll_data_scale==2'b01&&ca_data_inc==1) ||(typ==2'b01&&dll_data_scale==2'b10&&ca_data_inc_reg==4) ||(typ==2'b01&&dll_data_scale==2'b11&&ca_data_inc_reg==16) ==1)
begin
    ca_data_inc_en=1;
end
else
ca_data_inc_en=0;
if ((typ==2'b00&&cr_data_inc==1) ||(typ==2'b10&&cr_data_inc==1) ||(typ==2'b01&&dll_data_scale==2'b00&&cr_data_inc==1) ||(typ==2'b01&&dll_data_scale==2'b01&&cr_data_inc==1) ||(typ==2'b01&&dll_data_scale==2'b10&&cr_data_inc_reg==4) ||(typ==2'b01&&dll_data_scale==2'b11&&cr_data_inc_reg==16) ==1)
begin
    cr_data_inc_en=1;
end
else
cr_data_inc_en=0;
end

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        creds_rcv_data<=0;
        creds_alloc_data<=0;
        ca_data_inc_reg<=0;
        cr_data_inc_reg<=0;
    end
    else
    begin
        if (dll_init==1) begin
            creds_alloc_data<= DATA_FIFO_DEPTH*2;
        end
        else if ((ca_data_inc_en==1&&typ==2'b00)||(ca_data_inc_en==1&&typ==2'b10)) begin
            creds_alloc_data<=creds_alloc_data+data_buffer_out;
            end
        else if (ca_data_inc_en==1&&typ==2'b01) begin
            creds_alloc_data<=creds_alloc_data+1;
        end
        if (dll_init==1) begin
            creds_rcv_data<=0;
        end
        else if (((cr_data_inc_en==1)&&(typ==2'b00))||(cr_data_inc_en==1&&typ==2'b10)) begin
            creds_rcv_data<=creds_rcv_data+data_buffer_in;
        end
        else if (cr_data_inc_en==1&&typ==2'b01) begin
            creds_rcv_data<=creds_rcv_data+1;
        end

        if (ca_data_inc==1&&typ==2'b01) begin
            ca_data_inc_reg<=ca_data_inc_reg+1;
        end
        if (cr_data_inc==1&&typ==2'b01) begin
            cr_data_inc_reg<=cr_data_inc_reg+1;
        end
        if (ca_data_inc_reg==4&&dll_data_scale==2'b10&&typ==2'b01) begin
            ca_data_inc_reg<=0;
        end
        if (ca_data_inc_reg==16&&dll_data_scale==2'b11&&typ==2'b01) begin
            ca_data_inc_reg<=0;
        end
        if (cr_data_inc_reg==4&&dll_data_scale==2'b10&&typ==2'b01) begin
            cr_data_inc_reg<=0;
        end
        if (cr_data_inc_reg==16&&dll_data_scale==2'b11&&typ==2'b01) begin
            cr_data_inc_reg<=0;
        end
        end
        end
endmodule