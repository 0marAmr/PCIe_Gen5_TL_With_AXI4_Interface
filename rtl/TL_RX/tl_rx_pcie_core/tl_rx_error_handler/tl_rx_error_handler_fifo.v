module tl_rx_error_hndling_fifo #(
    parameter REQ_WIDTH=16,
    TAG_WIDTH=8,
    FIFO_DEPTH=8,
    FIFO_DATA_WIDTH=27,
    MSG_WIDTH=128

) (
    input wire                       clk,
    input wire                       rst,
    input wire [REQ_WIDTH-1:0]       req_id,
    input wire [TAG_WIDTH-1:0]       tag,
    input wire [1:0]                 msg_decode,
    input wire                       cpl_en,
    input wire                       write_ptr_incr,  // write msg info to report this error by sending it to tx 
    input wire                       msg_trans_en,
    input wire                       read_ptr_incr,   // ready signal from tx_side indicating that they sent a msg and able to receive another one to send it and also depending that completion sent with this msg (if there) is sent 
    output reg [MSG_WIDTH-1:0]       tlp_msg,
    output reg                       ur_cpl_valid,
    output reg                       empty_flag
);

reg full_flag;
reg [3:0] write_ptr;
reg [3:0] read_ptr;
reg [FIFO_DATA_WIDTH-1:0] write_data;
reg [FIFO_DATA_WIDTH-1:0] read_data;
reg [31:0] tlp_msg_dw0;
reg [31:0] tlp_msg_dw1;
reg [31:0] tlp_msg_dw2;
reg [31:0] tlp_msg_dw3;
reg [7:0] msg_code;

wire [2:0] write_addr = write_ptr[2:0]; 
wire [2:0] read_addr =  read_ptr[2:0]; 

reg [FIFO_DATA_WIDTH-1:0] msg_cpl_fifo [0:FIFO_DEPTH-1];

integer i;
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        for (i=0;i<FIFO_DEPTH;i=i+1) begin
            msg_cpl_fifo[i]<=0;
        end
    end
else if (write_ptr_incr==1 && full_flag==0) begin
        msg_cpl_fifo[write_addr]<=write_data;
    end
end

always @(*) begin
    read_data=msg_cpl_fifo[read_addr];
    write_data={req_id,tag,msg_decode,cpl_en};

    if (write_ptr==read_ptr) begin
        empty_flag=1;
    end
    else
    empty_flag=0;

    if ((write_addr==read_addr)&&(write_ptr[3]!= read_ptr[3])) begin
        full_flag=1;
    end
    else
    full_flag=0;
end

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        write_ptr<=0;
        read_ptr<=0;
    end
    else begin
        if (write_ptr_incr == 1 && full_flag==0) begin
            write_ptr<=write_ptr+1;
        end
        if (read_ptr_incr == 1 && empty_flag==0) begin
            read_ptr<=read_ptr+1;
        end
    end
end



//********************* message decode *********************//
always @(*) begin
    case (read_data[2:1])
       2'b00 : msg_code=8'b0011_0000;  // correctable 
       2'b01 : msg_code=8'b0011_0001;  // non-fatal
       2'b10 : msg_code=8'b0000_0000;  // default value
       2'b11 : msg_code=8'b0011_0011;  //fatal
    endcase

    tlp_msg_dw0=32'b0011_0000_0000_0000_0000_0000_0000_0000;
    tlp_msg_dw1={read_data[26:3],msg_code};
    tlp_msg_dw2=32'b0;
    tlp_msg_dw3=32'b0;

   if (msg_trans_en==1) begin
        tlp_msg={tlp_msg_dw0,tlp_msg_dw1,tlp_msg_dw2,tlp_msg_dw3};
        ur_cpl_valid=read_data[0];
   end
   else begin
        tlp_msg=0;
        ur_cpl_valid=0;
   end
end
endmodule