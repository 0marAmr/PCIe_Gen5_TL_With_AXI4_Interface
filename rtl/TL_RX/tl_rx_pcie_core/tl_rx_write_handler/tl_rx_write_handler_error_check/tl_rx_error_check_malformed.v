module tl_rx_error_check_malformed #(
    parameter DATA_WIDTH=10

)(
    input wire [2:0]            last_byte,
    input wire [2:0]            last_rcv_data,
    input wire                  eop,
    input wire                  i_rcv_done,    
    input wire [DATA_WIDTH-1:0] Length,
    input wire [2:0]            typ,
    input wire [1:0]            Attr,
    input wire [1:0]            AT,
    input wire [2:0]            TC,
    input wire [2:0]            max_payload_config,
    input wire                  malformed_en,
    output reg                  malformed_error
);
    reg valid_typ;
    reg max_payload_valid;

    localparam [2:0] MEMORY = 3'b000,
                IO = 3'b001,
                COMPLETION= 3'b010,
                CONFIGURATION = 3'b011,
                MESSAGE = 3'b100;

    localparam [2:0]    MAX_PAYLOAD_128_DW = 3'b010,
                        MAX_PAYLOAD_256_DW = 3'b011,
                        MAX_PAYLOAD_512_DW = 3'b100,
                        MAX_PAYLOAD_1024_DW = 3'b101;
                        
    always @(*) begin
        case (typ)
            MEMORY:         valid_typ=1;
            IO:             valid_typ=1;
            CONFIGURATION:  valid_typ=1;
            COMPLETION:     valid_typ=1;
            MESSAGE:        valid_typ=1;
            default:        valid_typ=0;
        endcase

        case (max_payload_config)
            MAX_PAYLOAD_128_DW: 
            begin
                if(Length>128) begin
                max_payload_valid=0;
            end 
            else
            max_payload_valid=1;
            end
            MAX_PAYLOAD_256_DW: 
            begin
                if(Length>256) begin
                max_payload_valid=0;
            end 
            else
            max_payload_valid=1;
            end
            MAX_PAYLOAD_512_DW: 
            begin
                if(Length>512) begin
                max_payload_valid=0;
            end 
            else
            max_payload_valid=1;
            end
            MAX_PAYLOAD_1024_DW: 
            begin
                if(Length>1024) begin
                max_payload_valid=0;
            end 
            else
            max_payload_valid=1;
            end
            default: 
            begin
                if (Length>32) begin
                    max_payload_valid=0;
                end
                else
                max_payload_valid=1;
            end
        endcase
    end

    always @(*) begin
        if (malformed_en==1) begin
            if (last_rcv_data != last_byte) begin
                malformed_error=1;
            end
            else if (eop != i_rcv_done) begin
                malformed_error=1;
            end
            else if (valid_typ==0) begin
                malformed_error=1;
            end
            else if (TC!=0 || Attr!= 2'b00 || AT!= 2'b00) begin  // update for multi virtual channel support
                malformed_error=1;
            end
            else if ((typ== IO && Length!=1) || (typ== CONFIGURATION && Length!=1)) begin
                malformed_error=1;
            end
            else if (max_payload_valid==0)
            begin
                malformed_error=1;
            end
            else 
            malformed_error=0;
        end
        else
        malformed_error=0;
    end   
endmodule