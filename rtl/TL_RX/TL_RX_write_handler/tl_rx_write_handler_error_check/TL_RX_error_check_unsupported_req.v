module TL_RX_error_Check_ur #(
    ADDRESS_WIDTH = 64
) (
    input wire [ADDRESS_WIDTH-1:0] address,
    input wire [7:0] msg_code,
    input wire [2:0] compl_status,
    input wire EP,
    input wire ur_en,
    input wire [2:0] typ,
    input wire address_typ,     //0 for 32 - 1 for 64
    input wire read_write,      //read_write =0 for read and 1 for write
    input wire [31:0] bar0,
    input wire [31:0] bar1,
    input wire [31:0] bar2,
    input wire [31:0] bar3,
    input wire [31:0] bar4,
    input wire [31:0] bar5,
    input wire io_space_en_config,
    input wire memory_space_en_config,

    output reg ur_error

);

    localparam  MEMORY = 3'b000,
                IO = 3'b001,
                COMPLETION= 3'b010,
                CONFIGURATION = 3'b011,
                MESSAGE = 3'b100;

  localparam  code1=8'b0000_0000, 
              code2=8'b0001_0000,
              code3=8'b0001_0010,
              code4=8'b0001_????,
              code5=8'b0010_0???,
              code6=8'b0011_00??,
              code7=8'b0100_????,
              code8=8'b0101_0000,
              code9=8'b0111_111?;

    reg         valid_msg_code;
    reg         valid_typ;
    reg         valid_compl_status;
    reg [31:0]  io_bar;
    reg [31:0]  mem_32_bar;
    //reg [31:0] mem_64_bar;
    reg [23:0]  io_initial_address;
    reg [19:0]  mem_32_initial_address;
    reg [37:0]  mem_64_initial_address;
    reg         io_valid_range;
    reg         mem_32_valid_range;
    reg         mem_64_valid_range;


    localparam  status1 = 3'b000,
                status2 = 3'b001,
                status3 = 3'b010,
                status4 = 3'b100;
          

  always @(*) begin
    case (msg_code)
      code1: valid_msg_code =1;
      code2: valid_msg_code =1;
      code3: valid_msg_code =1;
      code4: valid_msg_code =1;
      code5: valid_msg_code =1;
      code6: valid_msg_code =1;
      code7: valid_msg_code =1;
      code8: valid_msg_code =1;
      code9: valid_msg_code =1;
      default: valid_msg_code =0;
    endcase

    case (typ)
          3'b000: valid_typ=1;
          3'b001: valid_typ=1;
          3'b010: valid_typ=1;
          3'b011: valid_typ=1;
          3'b100: valid_typ=1;
          default: valid_typ=0;
    endcase
  case (compl_status)
    3'b000: valid_compl_status=1;
    3'b001: valid_compl_status=1;
    3'b010: valid_compl_status=1;
    3'b100: valid_compl_status=1;
    default: valid_compl_status=0;
  endcase
    // determining IO BAR

    if (bar0[0]==1) begin
      io_bar=bar0;
    end
    else if (bar1[0]==1) begin
      io_bar=bar1;
    end 
    else if (bar2[0]==1) begin
      io_bar=bar2;
    end 
    else if (bar3[0]==1) begin
      io_bar=bar3;
    end
    else if (bar4[0]==1) begin
      io_bar=bar4;
    end
    else if (bar5[0]==1) begin
      io_bar=bar5;
    end
    else
    io_bar=0;

  // determining io valid address range
  io_initial_address= io_bar[31:8];
    if ((address< io_initial_address) || (address> (io_initial_address +2**8))) begin
      io_valid_range =0;
    end
    else
    io_valid_range =1;

    //determining 32bit memory BAR
    if (bar0[0]==0 && (bar0[2:1]==2'b00)) begin
      mem_32_bar=bar0;
    end
    else if (bar1[0]==0 && (bar1[2:1]==2'b00)) begin
      mem_32_bar=bar1;
    end
    else if (bar2[0]==0 && (bar2[2:1]==2'b00)) begin
      mem_32_bar=bar2;
    end
    else if (bar3[0]==0 && (bar3[2:1]==2'b00)) begin
      mem_32_bar=bar3;
    end
    else if (bar4[0]==0 && (bar4[2:1]==2'b00)) begin
      mem_32_bar=bar4;
    end
    else if (bar5[0]==0 && (bar5[2:1]==2'b00)) begin
      mem_32_bar=bar5;
    end
    else
    mem_32_bar=0;
    // determining mem_32 valid address range
    mem_32_initial_address= mem_32_bar[31:12];
    if ((address< mem_32_initial_address) || (address> (mem_32_initial_address +2**12))) begin
      mem_32_valid_range =0;
    end
    else
    mem_32_valid_range =1;

    //determining 64bit memory BAR
    if (bar0[0]==0 && (bar0[2:1]==2'b10)) begin
      mem_64_initial_address={bar1,bar0[31:26]};
    end
    else if (bar1[0]==0 && (bar1[2:1]==2'b10)) begin
      mem_64_initial_address={bar2,bar1[31:26]};
    end
    else if (bar2[0]==0 && (bar2[2:1]==2'b10)) begin
      mem_64_initial_address={bar3,bar2[31:26]};
    end
    else if (bar3[0]==0 && (bar3[2:1]==2'b10)) begin
      mem_64_initial_address={bar4,bar3[31:26]};
    end
    else if (bar4[0]==0 && (bar4[2:1]==2'b10)) begin
      mem_64_initial_address={bar5,bar4[31:26]};
    end
    //else if (bar5[0]==0 && (bar5[2:1]==2'b10)) begin
      //mem_64_bar=bar5;
    //end
    else
    mem_64_initial_address=0;
    
    // determining mem_32 valid address range
    if ((address< mem_64_initial_address) || (address> (mem_64_initial_address +2**26))) begin
      mem_64_valid_range =0;
    end
    else
    mem_64_valid_range =1;
  end

  always @(*) begin
    if (ur_en==1) begin
      if (valid_typ==0) begin
        ur_error=1;
      end
      else if (typ == COMPLETION && valid_compl_status == 0) begin
        ur_error=1;
      end
      else if (typ == MESSAGE && valid_msg_code ==0) begin
        ur_error=1;
      end
      else if (typ==IO && io_space_en_config==0) begin
        ur_error=1;
      end
      else if (typ==MEMORY && memory_space_en_config==0) begin
        ur_error=1;
      end
      else if ((typ== IO && EP==1) || (typ== MEMORY && read_write==0 && EP==1) || (typ==CONFIGURATION && EP==1)) begin
        ur_error=1;
      end
      else if (typ==IO && io_valid_range==0 ) begin
          ur_error=1;
        end
      else if (typ==MEMORY && address_typ==0 && mem_32_valid_range==0) begin
        ur_error=1;
      end
      else if (typ==MEMORY && address_typ==1 && mem_64_valid_range==0) begin
        ur_error=1;
      end
      else
      ur_error=0;
    end  
    else
    ur_error=0;
  end 
endmodule