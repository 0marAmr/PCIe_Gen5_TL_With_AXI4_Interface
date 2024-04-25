/********************************************************************/
/* Module Name	: rd_atop.sv                       		            */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 29-03-2024					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: -							                        */
/* Summary:  This file includes the mapping operation between axi
            and pcie for read requests                              
   Will be Added: - Respond for cases which can't happen to assert   
   signals of BR Channel to indicate in ERR                         
                  - Add Messages Supported                          */
/********************************************************************/

   /*
        Question: - How to restore Addr[1:0] of Memrd, due to first_DW_BE is constant and doesn't depend on 
        addr[1:0].
                  - Ensure the status of IOrd
                  - Ensure TH in MEMrd IOrd is set 1 or not mandatory 
   */


   // Import package 
import axi_slave_package::*;
   module rd_atop (     
    // enable for this block
    input bit rd_atop_en,

    // Global Signal 
    //input bit CLK , ARESTn ,

    // interface with FIFO of Read request (AR )
    input logic   [ARFIFO_WIDTH - 1 : 0] ARFIFO_DATA,   // it is a read location from ar fifo 

    input logic   [REQUESTER_ID_WIDTH - 1 : 0] Requester_ID,  // it will be hardwired in top module, coming from CFG space

    output tlp_header_t axi_rdreq_hdr,  // generated header of request, the data type if tlp_header (struct cover 4 DW of Header including all fields)

    Request_Recorder_if.request_recorder_wrreqport recorder_if,

    output logic                                   axi_rdreq_hdr_valid,

    input  logic                                   axi_req_rd_grant 

);

// // Import package 
// import axi_slave_package::*;


        // Internal Signals used to store actual No. of DW
            logic [LAST_BYTE_EN_WIDTH  : 0]  no_of_dw_in_beat,no_of_dw;

            logic [ARUSER_WIDTH - 1 : 0] ARUSER ;
            logic [AxBURST_WIDTH - 1 : 0] ARBURST;
            logic [AxSIZE_WIDTH - 1 : 0 ]  ARSIZE ;
            logic [$clog2(AXI_MAX_NUM_TRANSFERS)  - 1 : 0] ARLEN;
            logic [ADDR_WIDTH - 1 : 0] ARADDR ;
            logic [$clog2(ARFIFO_DEPTH) - 1 : 0] ARID ; 

// function to map ID to Tag Uniquely 
function  [TAG_WIDTH - 2:0] generate_tag;
input [$clog2(AWFIFO_DEPTH) - 1 :0] id;
begin

    if (TAG_WIDTH - ($clog2(AWFIFO_DEPTH)) > 1'b1 ) begin
        // Generate a unique 7-bit tag value based on the (4 or 5 or 6) -bit ID input
        generate_tag[$clog2(AWFIFO_DEPTH) - 1 :0] = id;
        generate_tag[TAG_WIDTH - 2 :$clog2(AWFIFO_DEPTH)] = {{4'b1, id} ^ 8'b10101010};
    end
    else  begin
        generate_tag[TAG_WIDTH - 2 :0] = id;
    end
end
endfunction

// Assign statements

assign ARUSER   = ARFIFO_DATA[ARUSER_WIDTH - 1                                                                                                             : 0                                                                                                  ] ; // ARUSER from data read from AR FIFO
assign ARBURST  = ARFIFO_DATA[ARUSER_WIDTH - 1  + AxBURST_WIDTH                                                                                            : ARUSER_WIDTH                                                                                        ] ;         
assign ARSIZE = ARFIFO_DATA[ARUSER_WIDTH + AxBURST_WIDTH - 1 + AxSIZE_WIDTH                                                                                : ARUSER_WIDTH + AxBURST_WIDTH                                                                         ] ; 
assign ARLEN  = ARFIFO_DATA[ARUSER_WIDTH + AxBURST_WIDTH + AxSIZE_WIDTH - 1 + $clog2(AXI_MAX_NUM_TRANSFERS)                                                : AxBURST_WIDTH + ARUSER_WIDTH + AxSIZE_WIDTH                                                         ] ;
assign ARADDR   = ARFIFO_DATA[AxBURST_WIDTH + ARUSER_WIDTH + AxSIZE_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS) - 1 + ADDR_WIDTH                                 : AxBURST_WIDTH + ARUSER_WIDTH + AxSIZE_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS)                                     ] ; 
assign ARID    = ARFIFO_DATA[AxBURST_WIDTH + ARUSER_WIDTH + AxSIZE_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS) + ADDR_WIDTH + $clog2(ARFIFO_DEPTH) - 1           : AxBURST_WIDTH + ARUSER_WIDTH + AxSIZE_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS) + ADDR_WIDTH  ] ;

always_comb 
begin 
    /*  There is not any request */  
    axi_rdreq_hdr_valid = 1'b0;
    axi_rdreq_hdr   = 'd0 ;

    if (rd_atop_en)
        begin 

            if (ARUSER[2:0] == 3'b0_01 || ARUSER[2:0] == 3'b1_01 )
        begin 
            // Calculating Length 
        no_of_dw_in_beat   = (1'b1 << ARSIZE) >> 2'b10; 
        case (ARSIZE)                                                                   
                'd0 : begin 
                            // Here Each Beat is 1 Byte -->  so to calc. no. of DW via no. beats using the following location
                            no_of_dw =  (ARLEN+1'b1)  >> 2 ; // # DW = ARLEN * 1 / 4
                            // There are 3 Choices for answer (3/4 = 0 ; 5/4 = 1 ; 4/4 = 1)
                            if (no_of_dw  == 'b0)   // Here ARLEN < 4 (bytes) ---> so we have 1 DW  AND LAST_DW_EN is the ARLEN itself
                            begin
                                axi_rdreq_hdr.Length = 1'b1;
                            end
                            else if (ARLEN + 1'b1 - (no_of_dw << 2)  == 1'b0 ) begin // Here ARLEN is factor of 4 ---> Length is division, last_DW is all ones
                                axi_rdreq_hdr.Length = no_of_dw; 
                            end
                            else begin                  // Here the case of ARLEN is 5 for example , so we need to Length = 2 DW and Last Byte 0001
                                axi_rdreq_hdr.Length = no_of_dw + 1'b1 ;
                            end
                end 
                'd1 : begin 
                    // Here Each Beat is 2 Byte -->  so to calc. no. of DW via no. beats using the following location
                    no_of_dw =  ((ARLEN+1'b1) ) >> 1 ; // # DW = ARLEN * 2 / 4
                    // There are 3 Choices for answer (1/2 = 0 ; 3/2 = 1 ; 2/2 = 1)
                    if (no_of_dw  == 'b0)   // Here ARLEN < 2 (bytes) ---> so we have 1 DW  
                    begin
                        axi_rdreq_hdr.Length = 1'b1;
                    end
                    else if (ARLEN + 1'b1 - (no_of_dw << 1)  == 'b0 ) begin // Here ARLEN is factor of 2 ---> Length is division
                        axi_rdreq_hdr.Length = no_of_dw; 
                    end
                    else begin                  // Here the case of ARLEN is 3 for example , so we need to Length = 2 DW 
                        axi_rdreq_hdr.Length = no_of_dw + 1'b1 ;
                    end
                end 
                'd2 : begin 
                    // Here Each Beat is 4 Byte, so no_dw_of_beat = 1
                    axi_rdreq_hdr.Length     = (ARLEN+1'b1)     ; 
                    
                end 
                'd3 : begin 
                    // Here Each Beat is 8 Byte, so no_dw_of_beat = 2
                    axi_rdreq_hdr.Length = ((ARLEN+1'b1) ) * 2  ;  
                end
                'd4 : begin 
                    // Here Each Beat is 16 Byte, so no_dw_of_beat = 4 
                    axi_rdreq_hdr.Length = ((ARLEN+1'b1) ) * 4 ; 
                end 
                'd5 : begin
                    axi_rdreq_hdr.Length = ((ARLEN+1'b1) ) * 8 ;
                end 
                'd6 : begin
                    axi_rdreq_hdr.Length =((ARLEN+1'b1)) * 16 ;
                end 
                'd7 : begin 
                    axi_rdreq_hdr.Length =((ARLEN+1'b1) ) * 32 ;
                    end    
            endcase
    end 
            casez (ARUSER) 
                'b????_????_0_00: begin   /*  Default        -  No Request*/
                        axi_rdreq_hdr_valid = 1'b0;
                        axi_rdreq_hdr   = 'd0 ;
                end
                'b????_????_0_01: begin   /*  32-bit Address -  Memrd Request */

                    // Enable mapper
                        axi_rdreq_hdr_valid     = 1'b1;

                    // Starting Formulation Header
            
                        axi_rdreq_hdr.FMT   = TLP_FMT_3DW ; 
                        axi_rdreq_hdr.TYP   = 'b0_0000;
                        axi_rdreq_hdr.T9    = 1'b0 ;
                        axi_rdreq_hdr.TC    ='b000 ;
                        axi_rdreq_hdr.T8    = 1'b0 ;
                        axi_rdreq_hdr.ATTR  = 1'b1 ;
                        axi_rdreq_hdr.LN    = 1'b0 ;
                        axi_rdreq_hdr.TH    = 1'b1 ;   // Defined at specification page. 117
                        axi_rdreq_hdr.TD    = 1'b0 ;
                        axi_rdreq_hdr.EP    = 1'b0 ;
                        axi_rdreq_hdr.Attr  = 'b10  ;
                        axi_rdreq_hdr.AT    = 'b0  ;

                        axi_rdreq_hdr.Requester_ID = Requester_ID ;
                    
                    // Tag is 8 bits wide, so MSB is 1'b0 for Write and  1'b1 for Read
                        axi_rdreq_hdr.Tag          = {1'b1 , generate_tag(ARID)};

                    /* 
                            Note. There is a note in calculation LAST_DW_BE and FIRST_DW_BE (Defined at specification page. 117)
                                    - So Calc. Length first 
                                    - if Length = 1 DW  --> LAST_DW_BE = 'b1111  ; FIRST_DW_BE = 'b0000
                                                > 1 DW  --> LAST_DW_BE = 'b1111  ;  FIRST_DW_BE = 'b1111
                    */
                    
                        // Calc. Last_DW_BE and First_DW_BE
                        if (axi_rdreq_hdr.Length == 1'b1)
                            begin 
                                axi_rdreq_hdr.last_DW_BE    = 'b0000 ;
                                axi_rdreq_hdr.first_DW_BE   = 'b1111 ;
                            end 
                        else begin 
                                axi_rdreq_hdr.last_DW_BE    = 'b1111 ;
                                axi_rdreq_hdr.first_DW_BE   = 'b1111 ;
                        end 

                    // Calculating Lower Address and Higher Address
                    axi_rdreq_hdr.Higher_Address [1:0]  = 2'b00 ;  // Reserved - PH is 00 not supported
                    axi_rdreq_hdr.Higher_Address [31:2] = ARADDR [31:2] ;
                    axi_rdreq_hdr.Lower_Address         = 'd0;
                    axi_rdreq_hdr.PH                    = 'd0;
            
                end
                'b????_????_0_10: begin   /*  32-bit Address -  IO rd Req.*/
                    
                    // Enable mapper
                    axi_rdreq_hdr_valid     = 1'b1;

                    // Starting Formulation Header
                        axi_rdreq_hdr.FMT   = TLP_FMT_3DW; 
                        axi_rdreq_hdr.TYP   = 'b0_0010;
                        axi_rdreq_hdr.T9    = 1'b0 ;
                        axi_rdreq_hdr.TC    ='b000 ;
                        axi_rdreq_hdr.T8    = 1'b0 ;
                        axi_rdreq_hdr.ATTR  = 1'b1 ;
                        axi_rdreq_hdr.LN    = 1'b0 ;
                        axi_rdreq_hdr.TH    = 1'b1 ;  // Defined at specification page. 117
                        axi_rdreq_hdr.TD    = 1'b0 ;
                        axi_rdreq_hdr.EP    = 1'b0 ;
                        axi_rdreq_hdr.Attr  = 'b10  ;
                        axi_rdreq_hdr.AT    = 'b0  ;

                        axi_rdreq_hdr.Length = 'd1 ;
                        axi_rdreq_hdr.Requester_ID = Requester_ID ;

                        // Tag is 8 bits wide, so MSB is 1'b0 for Write and  1'b1 for Read
                        axi_rdreq_hdr.Tag          = {1'b1 , generate_tag(ARID)}; 
                        
                        axi_rdreq_hdr.last_DW_BE = 'd0 ;
                        
                        // Calculating FIRST_DW_BE   
                        case (ARADDR[1:0])
                            'b00 : begin 
                                axi_rdreq_hdr.first_DW_BE = 4'b1111; 
                            end
                            'b01 : begin 
                                axi_rdreq_hdr.first_DW_BE = 4'b1110; 
                            end 
                            'b10 : begin 
                                axi_rdreq_hdr.first_DW_BE = 4'b1100; 
                            end 
                            'b11 : begin 
                                axi_rdreq_hdr.first_DW_BE = 4'b1000; 
                            end 
                        endcase                                
                        
                        // Calculating Lower Address and Higher Address
                        axi_rdreq_hdr.Higher_Address [1:0]  = 2'b00 ;  // Reserved - PH is 00 not supported
                        axi_rdreq_hdr.Higher_Address [31:2] = ARADDR [31:2] ;
                        axi_rdreq_hdr.Lower_Address         = 'd0;
                        axi_rdreq_hdr.PH                    = 'd0;




                end 
                'b????_????_0_11: begin   /*  Message */       
                    axi_rdreq_hdr_valid = 1'b0;
                    // add Msg HDR
                    axi_rdreq_hdr   = 'd0 ; 

                end 
                'b????_????_1_00: begin   /*  Nothing        -  No Request */  // {Add Feature of Respond in B Channel ERR}
                        axi_rdreq_hdr_valid = 1'b0;
                        axi_rdreq_hdr   = 'd0 ;
                end
                'b????_????_1_01: begin   /* 64-bit Address  -  Memrd Request*/
                    
                    // Enable mapper
                    axi_rdreq_hdr_valid     = 1'b1;

                    // Starting Formulation Header
                    
                        axi_rdreq_hdr.FMT   = TLP_FMT_4DW ; 
                        axi_rdreq_hdr.TYP   = 'b0_0000;
                        axi_rdreq_hdr.T9    = 1'b0 ;
                        axi_rdreq_hdr.TC    ='b000 ;
                        axi_rdreq_hdr.T8    = 1'b0 ;
                        axi_rdreq_hdr.ATTR  = 1'b1 ;
                        axi_rdreq_hdr.LN    = 1'b0 ;
                        axi_rdreq_hdr.TH    = 1'b1 ;
                        axi_rdreq_hdr.TD    = 1'b0 ;
                        axi_rdreq_hdr.EP    = 1'b0 ;
                        axi_rdreq_hdr.Attr  = 'b10  ;
                        axi_rdreq_hdr.AT    = 'b0  ;

                        axi_rdreq_hdr.Requester_ID = Requester_ID ;
                    
                    // Tag is 8 bits wide, so MSB is 1'b0 for Write and  1'b1 for Read
                        axi_rdreq_hdr.Tag          = {1'b1 , generate_tag(ARID)};
                                    
                    /* 
                            Note. There is a note in calculation LAST_DW_BE and FIRST_DW_BE (Defined at specification page. 117)
                                    - So Calc. Length first 
                                    - if Length = 1 DW  --> LAST_DW_BE = 'b1111  ; FIRST_DW_BE = 'b0000
                                                > 1 DW  --> LAST_DW_BE = 'b1111  ;  FIRST_DW_BE = 'b1111
                    */
                    // Calculating Length 
            

                        // Calc. Last_DW_BE and First_DW_BE
                        if (axi_rdreq_hdr.Length == 1'b1)
                            begin 
                                axi_rdreq_hdr.last_DW_BE    = 'b0000 ;
                                axi_rdreq_hdr.first_DW_BE   = 'b1111 ;
                            end 
                        else begin 
                                axi_rdreq_hdr.last_DW_BE    = 'b1111 ;
                                axi_rdreq_hdr.first_DW_BE   = 'b1111 ;
                        end 

                
                

                    // Calculating Lower Address and Higher Address
                    axi_rdreq_hdr.Higher_Address        = ARADDR [64:32] ; 
                    axi_rdreq_hdr.Lower_Address         = ARADDR [31:2];
                    axi_rdreq_hdr.PH                    = 2'b00;
            
                end
                'b????_????_1_10: begin   /* 64-bit Address   - IO wr --> Can't Happen*/ // {Add Feature for respond in B Channel ERR}
                    axi_rdreq_hdr_valid = 1'b0;
                    axi_rdreq_hdr   = 'd0 ;
                end 
                'b????_????_1_11: begin   /*  Nothing */
                    axi_rdreq_hdr_valid = 1'b0;
                    // add MSG HDR
                    axi_rdreq_hdr   = 'd0 ;

                end 
                default: begin 
                    axi_rdreq_hdr_valid = 1'b0;
                    axi_rdreq_hdr   = 'd0 ;
                end 
            endcase 
end 

    
end 

always_comb 
         begin 
            // Put Constraint on grant to be in one clk cycle
            if (axi_req_rd_grant)
                begin 
                    recorder_if.req_wr_en = 1'b1 ;
                    recorder_if.req_wr_addr = axi_rdreq_hdr.Tag;
                    recorder_if.req_wr_data = {ARID,1'b1};
                end              
            else 
                begin 
                    recorder_if.req_wr_en = 1'b0 ;
                    recorder_if.req_wr_addr = 'b0;
                    recorder_if.req_wr_data = 'b0;
                end 
        end 

endmodule 

