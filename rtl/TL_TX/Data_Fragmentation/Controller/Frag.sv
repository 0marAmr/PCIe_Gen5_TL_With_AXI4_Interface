/********************************************/
/* Module Name	: Fragmentation             */
/* Written By	: Mohamed Khaled Alahmady   */
/* Date			: 10-05-2024		        */
/* Version		: V1			            */
/* Updates		: -			                */
/* Dependencies	: -				            */
/* Used			: -			                */
/********************************************/
import Fragmentation_Package::*;

module Frag #(
)(
    input bit clk,
    input bit arst,
    // Interface with TLP FIFO
    Fragmentation_Interface.FRAGMENTATION_TLP_FIFO      _tlp_fifo_if,
    // Interface with DLL
    Fragmentation_Interface.FRAGMENTATION_DLL           _dll_if,
    // input  logic                                       Halt_1,
    // input  logic                                       Halt_2,
    // input  logic                                       Throttle,
    // output logic                                       sop,
    // output logic                                       eop,
    // output logic [DLL_LENGTH_WIDTH - 1 : 0]            Length,
    // output logic                                       TLP_valid,
    // output valid_bytes_encoding                        Valid_Bytes,
    // output logic [DLL_TLP_WIDTH - 1 : 0]               TLP,
    // Interface with ECRC
    Fragmentation_Interface.FRAGMENTATION_ECRC          _ecrc_if
);

/* Packages */
import axi_slave_package::*;

/* Parameters */

/* Useful Functions */
// function to translate from number of DW to Bytes
function  valid_bytes_encoding Calc_Bytes(
    input logic [1:0]           valid_locations,
    input logic                 ecrc_gen
);
    case (valid_locations)
        2'b00: begin
            return (ecrc_gen ? DW2: DW1);
        end 
        2'b01: begin
            return (ecrc_gen ? DW3: DW2);
        end
        2'b10: begin
            return (ecrc_gen ? DW4: DW3);
        end 
        2'b11: begin
            return (ecrc_gen ? DW5: DW4);
        end
    endcase
endfunction

// function to translate from number of DW to Bytes
function  logic [10:0] Calc_Length(
    input logic [2:0]       fmt,
    input logic [9:0]       Length,
    input logic             ecrc_gen
);
    case (fmt)
       3'b000 :  begin
            return (ecrc_gen) ? 4 : 3;
       end
       3'b001 :  begin
            return (ecrc_gen) ? 5 : 4;
       end
       3'b010 :  begin
            return (ecrc_gen) ? 4 + Length : 3 + Length;
       end
       3'b011 :  begin
            return (ecrc_gen) ? 5 + Length: 4 + Length;
       end
        default: begin
            return 0;            
        end 
    endcase
endfunction

// function to formulate Message passed to ECRC
function  logic [ECRC_MESSAGE_WIDTH - 1 : 0] Formulate_Message(
    input logic [1:0]                           valid_locations,
    input logic [TLP_FIFO_WIDTH - 1 : 0]        rd_data_1,
    input logic [TLP_FIFO_WIDTH - 1 : 0]        rd_data_2,
    input logic                                 second_tlp
);
    if(second_tlp == 1'b0) begin
        case (valid_locations)
            2'b00 : begin
                return {
                        rd_data_1[(TLP_FIFO_WIDTH - 1) : TLP_FIFO_WIDTH - (1 * DOUBLE_WORD)], 
                        {(ECRC_MESSAGE_WIDTH - (1 * DOUBLE_WORD)){1'b0}}
                };
        end
            2'b01 : begin
                return {
                        rd_data_1[TLP_FIFO_WIDTH - 1 : TLP_FIFO_WIDTH - (2 * DOUBLE_WORD)], 
                        {(ECRC_MESSAGE_WIDTH - (2 * DOUBLE_WORD)){1'b0}}
                };
        end
            2'b10 : begin
                return {
                        rd_data_1[TLP_FIFO_WIDTH - 1 : TLP_FIFO_WIDTH - (3 * DOUBLE_WORD)], 
                        {(ECRC_MESSAGE_WIDTH - (3 * DOUBLE_WORD)){1'b0}}
                };
        end
            2'b11 : begin
                return {
                        rd_data_1[TLP_FIFO_WIDTH - 1 : TLP_FIFO_WIDTH - (4 * DOUBLE_WORD)], 
                        {(ECRC_MESSAGE_WIDTH - (4 * DOUBLE_WORD)){1'b0}}
                };
        end
        endcase
    end
    else begin
        case (valid_locations)
            2'b00 : begin
                return {
                        rd_data_1[TLP_FIFO_WIDTH - 1 : 2], 
                        rd_data_2[(TLP_FIFO_WIDTH - 1) : TLP_FIFO_WIDTH - (1 * DOUBLE_WORD)], 
                        {(ECRC_MESSAGE_WIDTH - (5 * DOUBLE_WORD)){1'b0}}
                };
        end
            2'b01 : begin
                return {
                        rd_data_1[TLP_FIFO_WIDTH - 1 : 2], 
                        rd_data_2[TLP_FIFO_WIDTH - 1 : TLP_FIFO_WIDTH - (2 * DOUBLE_WORD)], 
                        {(ECRC_MESSAGE_WIDTH - (6 * DOUBLE_WORD)){1'b0}}
                };
        end
            2'b10 : begin
                return {
                        rd_data_1[TLP_FIFO_WIDTH - 1 : 2], 
                        rd_data_2[TLP_FIFO_WIDTH - 1 : TLP_FIFO_WIDTH - (3 * DOUBLE_WORD)], 
                        {(ECRC_MESSAGE_WIDTH - (7 * DOUBLE_WORD)){1'b0}}
                };
        end
            2'b11 : begin
                return {
                        rd_data_1[TLP_FIFO_WIDTH - 1 : 2], 
                        rd_data_2[TLP_FIFO_WIDTH - 1 : TLP_FIFO_WIDTH - (4 * DOUBLE_WORD)], 
                        {(ECRC_MESSAGE_WIDTH - (8 * DOUBLE_WORD)){1'b0}}
                };
        end
        endcase        
    end
endfunction

// function to formulate _dll_if.TLP passed to DLL
function  logic [ECRC_MESSAGE_WIDTH - 1 : 0] Formulate_TLP(
    input logic [1:0]                           valid_locations,  
    input logic [TLP_FIFO_WIDTH - 1 : 0]        rd_data_1,
    input logic [TLP_FIFO_WIDTH - 1 : 0]        rd_data_2,
    input logic                                 second_tlp,
    input logic [ECRC_POLY_WIDTH - 1 : 0]       ecrc_Result,
    input                                       put_ecrc
);
    if (second_tlp == 1'b0) begin
        case (valid_locations)
            2'b00 : begin
                return {
                        rd_data_1[TLP_FIFO_WIDTH - 1 : TLP_FIFO_WIDTH - (1 * DOUBLE_WORD)], 
                        (put_ecrc ? ecrc_Result : 32'b0),
                        {(ECRC_MESSAGE_WIDTH - (2 * DOUBLE_WORD)){1'b0}}
                };
        end
            2'b01 : begin
                return {
                        rd_data_1[TLP_FIFO_WIDTH - 1 : TLP_FIFO_WIDTH - (2 * DOUBLE_WORD)], 
                        (put_ecrc ? ecrc_Result : 32'b0),
                        {(ECRC_MESSAGE_WIDTH - (3 * DOUBLE_WORD)){1'b0}}
                };
        end
            2'b10 : begin
                return {
                        rd_data_1[TLP_FIFO_WIDTH - 1 : TLP_FIFO_WIDTH - (3 * DOUBLE_WORD)], 
                        (put_ecrc ? ecrc_Result : 32'b0),
                        {(ECRC_MESSAGE_WIDTH - (4 * DOUBLE_WORD)){1'b0}}
                };
        end
            2'b11 : begin
                return {
                        rd_data_1[TLP_FIFO_WIDTH - 1 : TLP_FIFO_WIDTH - (4 * DOUBLE_WORD)], 
                        (put_ecrc ? ecrc_Result : 32'b0),
                        {(ECRC_MESSAGE_WIDTH - (5 * DOUBLE_WORD)){1'b0}}
                };
        end
        endcase
    end
    else begin
        case (valid_locations)
            2'b00 : begin
                return {
                        rd_data_1[TLP_FIFO_WIDTH - 1 : 2], 
                        rd_data_2[TLP_FIFO_WIDTH - 1 : TLP_FIFO_WIDTH - (1 * DOUBLE_WORD)], 
                        (put_ecrc ? ecrc_Result : 32'b0),
                        {(ECRC_MESSAGE_WIDTH - (6 * DOUBLE_WORD)){1'b0}}
                };
            end
            2'b01 : begin
                return {
                        rd_data_1[TLP_FIFO_WIDTH - 1 : 2], 
                        rd_data_2[TLP_FIFO_WIDTH - 1 : TLP_FIFO_WIDTH - (2 * DOUBLE_WORD)], 
                        (put_ecrc ? ecrc_Result : 32'b0),
                        {(ECRC_MESSAGE_WIDTH - (7 * DOUBLE_WORD)){1'b0}}
                };
            end
            2'b10 : begin
                return {
                        rd_data_1[TLP_FIFO_WIDTH - 1 : 2], 
                        rd_data_2[TLP_FIFO_WIDTH - 1 : TLP_FIFO_WIDTH - (3 * DOUBLE_WORD)], 
                        (put_ecrc ? ecrc_Result : 32'b0),
                        {(ECRC_MESSAGE_WIDTH - (8 * DOUBLE_WORD)){1'b0}}
                };
            end
            2'b11 : begin
                return {
                        rd_data_1[TLP_FIFO_WIDTH - 1 : 2], 
                        rd_data_2[TLP_FIFO_WIDTH - 1 : 2]
                };
            end
        endcase        
    end
endfunction

/* Internal Signals */
frag_state_t state;
frag_state_t next; 
logic        ecrc_gen;  // this signal store the TD bit of the TLP
logic [10:0] Length_temp;    // store Length of HDR + Data
logic        temp;

// DLL Signals
valid_bytes_encoding                        Valid_Bytes_reg;
logic [DLL_LENGTH_WIDTH - 1 : 0]            Length_reg;
logic [DLL_TLP_WIDTH - 1 : 0]               TLP_reg;

/* Assign Statements */

/* Always Blocks */
// State Register
always_ff @(posedge clk or negedge arst) begin : State_FF
    if (!arst) begin
        state           <= FRAG_IDLE;
        Length_temp     <= 0; 
        ecrc_gen        <= 1'b0;
        temp            <= 1'b0;
        Valid_Bytes_reg <= DW0;
        Length_reg      <= '0;
        TLP_reg         <= '0;
    end
    else begin
        state           <= next; 
        if (state == FRAG_READ_1) begin
            Valid_Bytes_reg <= _dll_if.Valid_Bytes;
            Length_reg      <= _dll_if.Length;
            TLP_reg         <= _dll_if.TLP;
        end
        else if (state == FRAG_READ_2) begin
            Valid_Bytes_reg <= _dll_if.Valid_Bytes;
            Length_reg      <= _dll_if.Length;
            TLP_reg         <= _dll_if.TLP;

            Length_temp     <= Calc_Length(_tlp_fifo_if.rd_data_1[FMT_END_LOC : FMT_START_LOC], _tlp_fifo_if.rd_data_1[LENGTH_END_LOC:LENGTH_START_LOC], _tlp_fifo_if.rd_data_1[TD_LOC]);
            ecrc_gen        <= _tlp_fifo_if.rd_data_1[TD_LOC];
            if (_tlp_fifo_if.Count == 1)
                temp        <= 1'b0;
            else if (_tlp_fifo_if.Count > 1)
                temp        <= 1'b1;
        end
        else if (state == FRAG_LOOP) begin
            if (_tlp_fifo_if.Count == 1)
                temp        <= 1'b0;
            else if (_tlp_fifo_if.Count > 1)
                temp        <= 1'b1;            
        end
    end
end

// Next State Decoder
always_comb begin : Next_State_Decoder
    next        = FRAG_IDLE;
    case (state) 
    FRAG_IDLE: begin
        if (_dll_if.Halt_1 || _dll_if.Halt_2) begin
            next = FRAG_IDLE;
        end
        // check number of locations in "TLP FIFO"
        // FRAG_IDLE >> FRAG_READ_1
        else if (_tlp_fifo_if.Count == 1) begin
            next    = FRAG_READ_1;
        end
        // FRAG_IDLE >> FRAG_READ_2
        else if (_tlp_fifo_if.Count > 1) begin
            next    = FRAG_READ_2;            
        end
        // FRAG_IDLE >> FRAG_IDLE
        else begin
            next    = FRAG_IDLE;
        end
    end
    FRAG_READ_1: begin
        if (_dll_if.Halt_2) begin
            // FRAG_READ_1 >> FRAG_WAIT_1
            next    = FRAG_WAIT_1;                        
        end
        else begin
            // FRAG_READ_1 >> FRAG_IDLE
            next    = FRAG_IDLE;                        
        end
    end
    FRAG_READ_2: begin
        if (_dll_if.Halt_2 || (_dll_if.Halt_1 && _tlp_fifo_if.Count > 0) || (_dll_if.Halt_1 && (_tlp_fifo_if.Count == 0) && _tlp_fifo_if.rd_data_1[TD_LOC] && (_tlp_fifo_if.rd_data_1[1:0] == 2'b11) && (_tlp_fifo_if.rd_data_2[1:0] == 2'b11))) begin
            // FRAG_READ_2 >> FRAG_WAIT_1
            next    = FRAG_WAIT_1;                        
        end
        // FRAG_READ_2 >> FRAG_ECRC
        // need extra cycle for generating ecrc if all 8 DW have valid data
        else if ((_tlp_fifo_if.Count == 0) && _tlp_fifo_if.rd_data_1[TD_LOC] && (_tlp_fifo_if.rd_data_1[1:0] == 2'b11) && (_tlp_fifo_if.rd_data_2[1:0] == 2'b11)) begin
            next    = FRAG_ECRC;
        end
        // FRAG_READ_2 >> FRAG_IDLE
        else if (_tlp_fifo_if.Count == 0) begin
            next    = FRAG_IDLE;            
        end
        // FRAG_READ_2 >> FRAG_LOOP
        else if (_tlp_fifo_if.Count > 0) begin
            next    = FRAG_LOOP;
        end
        // FRAG_READ_2 >> FRAG_READ_2 (couldn't happen)
        else begin
            next    = FRAG_READ_2;            
        end
    end
    FRAG_LOOP: begin
            // FRAG_LOOP >> FRAG_ECRC
        // need extra cycle for generating ecrc if all 8 DW have valid data
        if ((_tlp_fifo_if.Count == 0) && ecrc_gen && (_tlp_fifo_if.rd_data_1[1:0] == 2'b11) && (_tlp_fifo_if.rd_data_2[1:0] == 2'b11)) begin
            next    = FRAG_ECRC;
        end
        // FRAG_LOOP >> FRAG_IDLE
        else if (_tlp_fifo_if.Count == 0) begin
            next    = FRAG_IDLE;            
        end
        // FRAG_LOOP >> FRAG_READ_2
        else begin
            next    = FRAG_LOOP;            
        end
    end
    FRAG_ECRC: begin
        // FRAG_ECRC >> FRAG_IDLE
        if (_tlp_fifo_if.Count == 1) begin
            next    = FRAG_READ_1;
        end
        // FRAG_ECRC >> FRAG_READ_2
        else if (_tlp_fifo_if.Count > 1) begin
            next    = FRAG_READ_2;            
        end
        // FRAG_ECRC >> FRAG_IDLE
        else begin
            next    = FRAG_IDLE;
        end
    end
    FRAG_WAIT_1: begin
        if (!(_dll_if.Halt_2 || _dll_if.Halt_1)) begin
            next = FRAG_DUMMY;            
        end
        else begin
            next = FRAG_WAIT_1;
        end
    end
    FRAG_DUMMY: begin
        if(_tlp_fifo_if.Count > 0) begin
            next    = FRAG_LOOP;        
        end
        else if ((_tlp_fifo_if.Count == 0) && _tlp_fifo_if.rd_data_1[TD_LOC] && (_tlp_fifo_if.rd_data_2[1:0] == 2'b11)) begin
            next    = FRAG_ECRC;        
        end
        else begin
            next    = FRAG_IDLE;                    
        end
    end
    default: begin
        next = FRAG_IDLE;
    end
    endcase 
end 

always_comb begin : Output_Decoder
    /* Default Values */
    // TLP FIFO
    _tlp_fifo_if.rd_en      = 1'b0;
    _tlp_fifo_if.rd_mode    = '0;

    // DLL
    _dll_if.sop             = 1'b0;
    _dll_if.eop             = 1'b0;
    _dll_if.TLP_valid       = 1'b0;
    _dll_if.Valid_Bytes     = DW0;
    _dll_if.Length          = '0;
    _dll_if.TLP             = '0;

    // ECRC
    _ecrc_if.ecrc_Message   = '0;
    _ecrc_if.ecrc_Length    = '0;
    _ecrc_if.ecrc_Seed      = '0;
    _ecrc_if.ecrc_EN        = 1'b0;
    _ecrc_if.ecrc_Seed_Load = 1'b0;

    case (state) 
    FRAG_IDLE: begin
        // check number of locations in "TLP FIFO"
        // FRAG_IDLE >> FRAG_READ_1
        if ((_tlp_fifo_if.Count == 1) && !(_dll_if.Halt_1 || _dll_if.Halt_2)) begin
            _tlp_fifo_if.rd_en      = 1'b1;
            _tlp_fifo_if.rd_mode    = 1'b0;
        end
        // FRAG_IDLE >> FRAG_READ_2
        else if ((_tlp_fifo_if.Count > 1) && !(_dll_if.Halt_1 || _dll_if.Halt_2)) begin
            _tlp_fifo_if.rd_en      = 1'b1;
            _tlp_fifo_if.rd_mode    = 1'b1;
        end
    end
    FRAG_READ_1: begin
        // FRAG_READ_1 >> FRAG_IDLE
        if (_tlp_fifo_if.rd_data_1[TD_LOC]) begin
            _ecrc_if.ecrc_Message   = Formulate_Message(_tlp_fifo_if.rd_data_1[1:0], _tlp_fifo_if.rd_data_1, '0, 1'b0);
            _ecrc_if.ecrc_Length    = _tlp_fifo_if.rd_data_1[1:0] + 1;
            _ecrc_if.ecrc_Seed      = '1;
            _ecrc_if.ecrc_EN        = 1'b1;
            _ecrc_if.ecrc_Seed_Load = 1'b1;            
            _dll_if.TLP             = Formulate_TLP(_tlp_fifo_if.rd_data_1[1:0], _tlp_fifo_if.rd_data_1, 128'b0, 1'b0, _ecrc_if.ecrc_Result_comb, 1'b1);            
        end
        else begin
            _dll_if.TLP             = Formulate_TLP(_tlp_fifo_if.rd_data_1[1:0], _tlp_fifo_if.rd_data_1, 128'b0, 1'b0, 32'b0, 1'b0);            
        end
        
        _dll_if.sop             = 1'b1;
        _dll_if.eop             = 1'b1;
        _dll_if.TLP_valid       = 1'b1;

        _dll_if.Valid_Bytes     = Calc_Bytes(_tlp_fifo_if.rd_data_1[1:0], _tlp_fifo_if.rd_data_1[TD_LOC]);
        _dll_if.Length          = Calc_Length(_tlp_fifo_if.rd_data_1[FMT_END_LOC : FMT_START_LOC], _tlp_fifo_if.rd_data_1[LENGTH_END_LOC:LENGTH_START_LOC], _tlp_fifo_if.rd_data_1[TD_LOC]);
    end
    FRAG_READ_2: begin
        // FRAG_READ_2 >> FRAG_ECRC
        // need extra cycle for generating ecrc if all 8 DW have valid data
        if ((_tlp_fifo_if.Count == 0) && _tlp_fifo_if.rd_data_1[TD_LOC] && (_tlp_fifo_if.rd_data_2[1:0] == 2'b11)) begin
            _ecrc_if.ecrc_Message   = Formulate_Message(_tlp_fifo_if.rd_data_2[1:0], _tlp_fifo_if.rd_data_1, _tlp_fifo_if.rd_data_2, 1'b1);
            _ecrc_if.ecrc_Length    = 8;
            _ecrc_if.ecrc_Seed      = '1;
            _ecrc_if.ecrc_EN        = 1'b1;
            _ecrc_if.ecrc_Seed_Load = 1'b1;            

            _dll_if.TLP             = {_tlp_fifo_if.rd_data_1[TLP_FIFO_WIDTH - 1 : 2], _tlp_fifo_if.rd_data_2[TLP_FIFO_WIDTH - 1 : 2]};
            
            _dll_if.sop             = 1'b1;
            _dll_if.eop             = 1'b0;
            _dll_if.TLP_valid       = 1'b1;

            _dll_if.Valid_Bytes     = DW8;
            _dll_if.Length          = 9;
        end
        // FRAG_READ_2 >> FRAG_IDLE
        else if (_tlp_fifo_if.Count == 0) begin
            if (_tlp_fifo_if.rd_data_1[TD_LOC]) begin
                _ecrc_if.ecrc_Message   = Formulate_Message(_tlp_fifo_if.rd_data_2[1:0], _tlp_fifo_if.rd_data_1, _tlp_fifo_if.rd_data_2, 1'b1);
                _ecrc_if.ecrc_Length    = _tlp_fifo_if.rd_data_2[1:0] + 1;
                _ecrc_if.ecrc_Seed      = '1;
                _ecrc_if.ecrc_EN        = 1'b1;
                _ecrc_if.ecrc_Seed_Load = 1'b1;            
                _dll_if.TLP             = Formulate_TLP(_tlp_fifo_if.rd_data_2[1:0], _tlp_fifo_if.rd_data_1, _tlp_fifo_if.rd_data_2, 1'b1, _ecrc_if.ecrc_Result_comb, 1'b1);            
            end
            else begin
                _dll_if.TLP             = Formulate_TLP(_tlp_fifo_if.rd_data_2[1:0], _tlp_fifo_if.rd_data_1, _tlp_fifo_if.rd_data_2, 1'b1, 32'b0, 1'b0);            
            end

            _dll_if.sop             = 1'b1;
            _dll_if.eop             = 1'b1;
            _dll_if.TLP_valid       = 1'b1;

            _dll_if.Valid_Bytes     = valid_bytes_encoding'((4 + ((_tlp_fifo_if.rd_data_2[1:0] + 1) + (_tlp_fifo_if.rd_data_1[TD_LOC] ? 1 : 0))) * 4 - 1);
            _dll_if.Length          = Calc_Length(_tlp_fifo_if.rd_data_1[FMT_END_LOC : FMT_START_LOC], _tlp_fifo_if.rd_data_1[LENGTH_END_LOC:LENGTH_START_LOC], _tlp_fifo_if.rd_data_1[TD_LOC]);
        end
        // FRAG_READ_2 >> FRAG_LOOP (read 1 location)
        else if (_tlp_fifo_if.Count == 1) begin
            if (_tlp_fifo_if.rd_data_1[TD_LOC]) begin
                _ecrc_if.ecrc_Message   = {_tlp_fifo_if.rd_data_1[TLP_FIFO_WIDTH - 1 : 2], _tlp_fifo_if.rd_data_2[TLP_FIFO_WIDTH - 1 : 2]};
                _ecrc_if.ecrc_Length    = 8;
                _ecrc_if.ecrc_Seed      = _ecrc_if.ecrc_Result_reg;
                _ecrc_if.ecrc_EN        = 1'b1;
                _ecrc_if.ecrc_Seed_Load = 1'b1;            
            end


            _tlp_fifo_if.rd_en      = (_dll_if.Halt_1 || _dll_if.Halt_2) ? 1'b0 : 1'b1;
            _tlp_fifo_if.rd_mode    = (_dll_if.Halt_1 || _dll_if.Halt_2) ? 1'b0 : 1'b0;

            _dll_if.sop             = 1'b1;
            _dll_if.eop             = 1'b0;
            _dll_if.TLP_valid       = 1'b1;

            _dll_if.Valid_Bytes     = DW8;
            _dll_if.Length          = Calc_Length(_tlp_fifo_if.rd_data_1[FMT_END_LOC : FMT_START_LOC], _tlp_fifo_if.rd_data_1[LENGTH_END_LOC:LENGTH_START_LOC], _tlp_fifo_if.rd_data_1[TD_LOC]);
            _dll_if.TLP             = {_tlp_fifo_if.rd_data_1[TLP_FIFO_WIDTH - 1 : 2], _tlp_fifo_if.rd_data_2[TLP_FIFO_WIDTH - 1 : 2]};            
        end
        // FRAG_READ_2 >> FRAG_LOOP (read 2 location)
        else if (_tlp_fifo_if.Count > 1) begin
            if (_tlp_fifo_if.rd_data_1[TD_LOC]) begin
                _ecrc_if.ecrc_Message   = {_tlp_fifo_if.rd_data_1[TLP_FIFO_WIDTH - 1 : 2], _tlp_fifo_if.rd_data_2[TLP_FIFO_WIDTH - 1 : 2]};
                _ecrc_if.ecrc_Length    = 8;
                _ecrc_if.ecrc_Seed      = _ecrc_if.ecrc_Result_reg;
                _ecrc_if.ecrc_EN        = 1'b1;
                _ecrc_if.ecrc_Seed_Load = 1'b1;            
            end

            _tlp_fifo_if.rd_en      = (_dll_if.Halt_1 || _dll_if.Halt_2) ? 1'b0 : 1'b1;
            _tlp_fifo_if.rd_mode    = (_dll_if.Halt_1 || _dll_if.Halt_2) ? 1'b0 : 1'b1;

            _dll_if.sop             = 1'b1;
            _dll_if.eop             = 1'b0;
            _dll_if.TLP_valid       = 1'b1;

            _dll_if.Valid_Bytes     = DW8;
            _dll_if.Length          = Calc_Length(_tlp_fifo_if.rd_data_1[FMT_END_LOC : FMT_START_LOC], _tlp_fifo_if.rd_data_1[LENGTH_END_LOC:LENGTH_START_LOC], _tlp_fifo_if.rd_data_1[TD_LOC]);
            _dll_if.TLP             = {_tlp_fifo_if.rd_data_1[TLP_FIFO_WIDTH - 1 : 2], _tlp_fifo_if.rd_data_2[TLP_FIFO_WIDTH - 1 : 2]};            
        end
        // FRAG_READ_2 >> FRAG_READ_2 (couldn't happen)
        else begin
        end
    end
    FRAG_LOOP: begin
        // FRAG_LOOP >> FRAG_ECRC
        // need extra cycle for generating ecrc if all 8 DW have valid data
        if ((_tlp_fifo_if.Count == 0) && ecrc_gen && (_tlp_fifo_if.rd_data_1[1:0] == 2'b11) && (_tlp_fifo_if.rd_data_2[1:0] == 2'b11)) begin
            _ecrc_if.ecrc_Message   = Formulate_Message(_tlp_fifo_if.rd_data_2[1:0], _tlp_fifo_if.rd_data_1, _tlp_fifo_if.rd_data_2, 1'b1);
            _ecrc_if.ecrc_Length    = 8;
            _ecrc_if.ecrc_Seed      = _ecrc_if.ecrc_Result_reg;
            _ecrc_if.ecrc_EN        = 1'b1;
            _ecrc_if.ecrc_Seed_Load = 1'b1;            

            _dll_if.TLP             = {_tlp_fifo_if.rd_data_1[TLP_FIFO_WIDTH - 1 : 2], _tlp_fifo_if.rd_data_2[TLP_FIFO_WIDTH - 1 : 2]};


            _dll_if.sop             = 1'b0;
            _dll_if.eop             = 1'b0;
            _dll_if.TLP_valid       = 1'b1;

            _dll_if.Valid_Bytes     = DW8;
            _dll_if.Length          = Length_temp;
        end
        // FRAG_LOOP >> FRAG_IDLE
        else if (_tlp_fifo_if.Count == 0) begin
            if (ecrc_gen) begin
                _ecrc_if.ecrc_Message   = (temp) ? Formulate_Message(_tlp_fifo_if.rd_data_2[1:0], _tlp_fifo_if.rd_data_1, _tlp_fifo_if.rd_data_2, 1'b1) : Formulate_Message(_tlp_fifo_if.rd_data_1[1:0], _tlp_fifo_if.rd_data_1, 128'b0, 1'b0);
                _ecrc_if.ecrc_Length    = (temp) ? (_tlp_fifo_if.rd_data_2[1:0] + 1) : (_tlp_fifo_if.rd_data_1[1:0] + 1);
                _ecrc_if.ecrc_Seed      = _ecrc_if.ecrc_Result_reg;
                _ecrc_if.ecrc_EN        = 1'b1;
                _ecrc_if.ecrc_Seed_Load = 1'b1;            
                _dll_if.TLP             = (temp) ? Formulate_TLP(_tlp_fifo_if.rd_data_2[1:0], _tlp_fifo_if.rd_data_1, _tlp_fifo_if.rd_data_2, 1'b1, _ecrc_if.ecrc_Result_comb, 1'b1) : Formulate_TLP(_tlp_fifo_if.rd_data_1[1:0], _tlp_fifo_if.rd_data_1, 128'b0, 1'b0, _ecrc_if.ecrc_Result_comb, 1'b1);            
            end
            else begin
                _dll_if.TLP             = (temp) ? Formulate_TLP(_tlp_fifo_if.rd_data_2[1:0], _tlp_fifo_if.rd_data_1, _tlp_fifo_if.rd_data_2, 1'b1, 32'b0, 1'b0) : Formulate_TLP(_tlp_fifo_if.rd_data_1[1:0], _tlp_fifo_if.rd_data_1, 128'b0, 1'b0, 32'b0, 1'b0);            
            end


            _dll_if.sop             = 1'b0;
            _dll_if.eop             = 1'b1;
            _dll_if.TLP_valid       = 1'b1;
            _dll_if.Valid_Bytes     = (temp) ?  valid_bytes_encoding'((4 + ((_tlp_fifo_if.rd_data_2[1:0] + 1) + (ecrc_gen ? 1 : 0))) * 4 - 1) : valid_bytes_encoding'((((_tlp_fifo_if.rd_data_1[1:0] + 1) + (ecrc_gen ? 1 : 0)))*4 - 1);
            _dll_if.Length          = Length_temp;
        end
        // FRAG_LOOP >> FRAG_LOOP (read 1 location)
        else if (_tlp_fifo_if.Count == 1) begin
            if (ecrc_gen) begin
                _ecrc_if.ecrc_Message   = {_tlp_fifo_if.rd_data_1[TLP_FIFO_WIDTH - 1 : 2], _tlp_fifo_if.rd_data_2[TLP_FIFO_WIDTH - 1 : 2]};
                _ecrc_if.ecrc_Length    = 8;
                _ecrc_if.ecrc_Seed      = _ecrc_if.ecrc_Result_reg;
                _ecrc_if.ecrc_EN        = 1'b1;
                _ecrc_if.ecrc_Seed_Load = 1'b1;            
            end

            _tlp_fifo_if.rd_en      = 1'b1;
            _tlp_fifo_if.rd_mode    = 1'b0;

            _dll_if.sop             = 1'b0;
            _dll_if.eop             = 1'b0;
            _dll_if.TLP_valid       = 1'b1;

            _dll_if.Valid_Bytes     = DW8;
            _dll_if.Length          = Length_temp;
            _dll_if.TLP             = {_tlp_fifo_if.rd_data_1[TLP_FIFO_WIDTH - 1 : 2], _tlp_fifo_if.rd_data_2[TLP_FIFO_WIDTH - 1 : 2]};            
        end
        // FRAG_LOOP >> FRAG_LOOP (read 2 location)
        else if (_tlp_fifo_if.Count > 1) begin
            if (ecrc_gen) begin
                _ecrc_if.ecrc_Message   = {_tlp_fifo_if.rd_data_1[TLP_FIFO_WIDTH - 1 : 2], _tlp_fifo_if.rd_data_2[TLP_FIFO_WIDTH - 1 : 2]};
                _ecrc_if.ecrc_Length    = 8;
                _ecrc_if.ecrc_Seed      = _ecrc_if.ecrc_Result_reg;
                _ecrc_if.ecrc_EN        = 1'b1;
                _ecrc_if.ecrc_Seed_Load = 1'b1;            
            end

            _tlp_fifo_if.rd_en      = 1'b1;
            _tlp_fifo_if.rd_mode    = 1'b1;

            _dll_if.sop             = 1'b0;
            _dll_if.eop             = 1'b0;
            _dll_if.TLP_valid       = 1'b1;

            _dll_if.Valid_Bytes     = DW8;
            _dll_if.Length          = Length_temp;
            _dll_if.TLP             = {_tlp_fifo_if.rd_data_1[TLP_FIFO_WIDTH - 1 : 2], _tlp_fifo_if.rd_data_2[TLP_FIFO_WIDTH - 1 : 2]};            
        end
        else begin
        end
    end
    FRAG_ECRC: begin
        // FRAG_ECRC >> FRAG_IDLE
        _dll_if.sop             = 1'b0;
        _dll_if.eop             = 1'b1;
        _dll_if.TLP_valid       = 1'b1;

        _dll_if.Valid_Bytes     = DW1;
        _dll_if.Length          = Length_temp;

        _dll_if.TLP             = {_ecrc_if.ecrc_Result_reg, 224'b0};
        // check number of locations in "TLP FIFO"
        // FRAG_ECRC >> FRAG_READ_1
        if ((_tlp_fifo_if.Count == 1) && !(_dll_if.Halt_1 || _dll_if.Halt_2)) begin
            _tlp_fifo_if.rd_en      = 1'b1;
            _tlp_fifo_if.rd_mode    = 1'b0;
        end
        // FRAG_ECRC >> FRAG_READ_2
        else if ((_tlp_fifo_if.Count > 1) && !(_dll_if.Halt_1 || _dll_if.Halt_2)) begin
            _tlp_fifo_if.rd_en      = 1'b1;
            _tlp_fifo_if.rd_mode    = 1'b1;
        end
    end
    FRAG_WAIT_1: begin
        if (_dll_if.Halt_2) begin
            _dll_if.sop             = 1'b0;
            _dll_if.eop             = 1'b0;
            _dll_if.TLP_valid       = 1'b0;            
        end
    end
    FRAG_DUMMY: begin
        // FRAG_DUMMY >> FRAG_IDLE
        _dll_if.sop             = 1'b1;
        _dll_if.TLP_valid       = 1'b1;

        _dll_if.Valid_Bytes     = Valid_Bytes_reg;
        _dll_if.Length          = Length_reg;
        _dll_if.TLP             = TLP_reg;


        if ((_tlp_fifo_if.Count == 0) && _tlp_fifo_if.rd_data_1[TD_LOC] && (_tlp_fifo_if.rd_data_2[1:0] == 2'b11)) begin
            _dll_if.eop             = 1'b0;
        end
        // FRAG_READ_2 >> FRAG_LOOP (read 1 location)
        else if (_tlp_fifo_if.Count == 1) begin
            _tlp_fifo_if.rd_en      = 1'b1;
            _tlp_fifo_if.rd_mode    = 1'b0;
            _dll_if.eop             = 1'b0;
        end
        // FRAG_READ_2 >> FRAG_LOOP (read 2 location)
        else if (_tlp_fifo_if.Count > 1) begin
            _tlp_fifo_if.rd_en      = 1'b1;
            _tlp_fifo_if.rd_mode    = 1'b1;
            _dll_if.eop             = 1'b0;
        end
        else begin
            _dll_if.eop             = 1'b1;
        end

    end
    default: begin
    end
    endcase 
end 

endmodule: Frag
/*********** END_OF_FILE ***********/
