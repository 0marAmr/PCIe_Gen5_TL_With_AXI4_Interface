/********************************************************************/
/* Module Name	: wr_atop.sv                            		    */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 29-03-2024					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: -							                        */
/* Summary:  This file includes the mapping operation between axi
            and pcie for read requests                              
            Will be Added: Respond for cases which can't happen to assert 
   signals of B Channel to indicate in ERR                           */
/********************************************************************/
// Import package 
   import axi_slave_package::*;
    module wr_atop (     
                    // enable for this block
                    input bit wr_atop_en,

                    // Global Signal 
                    //input bit CLK , rst ,

                    // interface with FIFO of write request (AW )
                    input logic   [AWFIFO_WIDTH - 1 : 0] AWFIFO_DATA,   // it is a read location from aw fifo 

                    input logic   [REQUESTER_ID_WIDTH - 1 : 0] Requester_ID,  // it will be hardwired in top module, coming from CFG space

                    output tlp_header_t axi_wrreq_hdr,  // generated header of request, the data type if tlp_header (struct cover 4 DW of Header including all fields)

                    //output logic [(AXI_MAX_NUM_BYTES * 8) - 1 : 0] axi_req_data ; 
                    
                    Request_Recorder_if.request_recorder_wrreqport recorder_if,

                    output logic                                   axi_wrreq_hdr_valid,
                    // Interface with Internal Response
                    // Slave_Internal_Response_if.AW_TO_B                resp_wr_mux_if,
                    // output logic                                    err_reporting_flag ,

                    input  logic                                   axi_req_wr_grant 

    );

            // // Import package 
            // import axi_slave_package::*;


    // always_comb begin
    //           case ({resp_wr_mux_if.BVALID,resp_wr_mux_if.BDONE }) 
    //             2'b00 : begin 
    //                 err_reporting_flag = 1'b1 ;
    //             end
    //             2'b10 : begin 
    //                 err_reporting_flag = 1'b0 ;
    //             end 
    //             2'b01 : begin 
    //                 err_reporting_flag = 1'b1 ;
    //             end 
    //             2'b11 : begin 
    //                 err_reporting_flag = 1'b1 ;
    //             end
    //         endcase 
    // end 
            

            // Internal Signals used to store actual No. of DW
            logic [LAST_BYTE_EN_WIDTH  : 0]  no_of_dw;
            logic [LAST_BYTE_EN_WIDTH  : 0]     no_of_dw_in_beat;

            logic [WSTRB_WIDTH - 1 : 0] WSTRB ;
            logic [AWUSER_WIDTH - 1 : 0] AWUser ;
            logic [AxBURST_WIDTH - 1 : 0] AWBurst;
            logic [AxSIZE_WIDTH - 1 : 0 ]  AWSize ;
            logic [$clog2(AXI_MAX_NUM_TRANSFERS)  - 1 : 0] AWLEN;
            logic [ADDR_WIDTH - 1 : 0] AWADDR ;
            logic [$clog2(AWFIFO_DEPTH) - 1 : 0] AWID ; 
            
            // function to map ID to Tag Uniquely 
            function  [TAG_WIDTH - 2:0] generate_tag;
                input [$clog2(AWFIFO_DEPTH) - 1 :0] id;
                begin

                    if (TAG_WIDTH - ($clog2(AWFIFO_DEPTH)) > 1'b1 ) begin
                        // Generate a unique 7-bit tag value based on the (4 or 5 or 6) -bit ID input
                        generate_tag[$clog2(AWFIFO_DEPTH) - 1 :0] = id;
                        generate_tag[TAG_WIDTH - 2 :$clog2(AWFIFO_DEPTH)] = {{4'b0, id} ^ 8'b10101010};
                    end
                    else  begin
                        generate_tag[TAG_WIDTH - 2 :0] = id;
                    end
                end
            endfunction
 
            // Assign statements
            
            

            assign WSTRB   = AWFIFO_DATA[WSTRB_WIDTH - 1                                                                                                               : 0                                                                                                  ] ;
            assign AWUser  = AWFIFO_DATA[AWUSER_WIDTH - 1  + WSTRB_WIDTH                                                                                               : WSTRB_WIDTH                                                                                        ] ;         // AWUSER from data read from AW FIFO
            assign AWBurst = AWFIFO_DATA[AWUSER_WIDTH + AxBURST_WIDTH - 1 + WSTRB_WIDTH                                                                                : AWUSER_WIDTH + WSTRB_WIDTH                                                                         ] ; 
            assign AWSize  = AWFIFO_DATA[AxBURST_WIDTH + AWUSER_WIDTH + AxSIZE_WIDTH - 1 + WSTRB_WIDTH                                                                 : AxBURST_WIDTH + AWUSER_WIDTH + WSTRB_WIDTH                                                         ] ;
            assign AWLEN   = AWFIFO_DATA[AxBURST_WIDTH + AWUSER_WIDTH + AxSIZE_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS) - 1 + WSTRB_WIDTH                                 : AxBURST_WIDTH + AWUSER_WIDTH + AxSIZE_WIDTH + WSTRB_WIDTH                                    ] ; 
            assign AWADDR  = AWFIFO_DATA[AxBURST_WIDTH + AWUSER_WIDTH + AxSIZE_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS) + ADDR_WIDTH - 1 + WSTRB_WIDTH                        : AxBURST_WIDTH + AWUSER_WIDTH + AxSIZE_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS) + WSTRB_WIDTH          ] ;
            assign AWID    = AWFIFO_DATA[AxBURST_WIDTH + AWUSER_WIDTH + AxSIZE_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS) + ADDR_WIDTH + $clog2(AWFIFO_DEPTH) - 1 + WSTRB_WIDTH : AxBURST_WIDTH + AWUSER_WIDTH + AxSIZE_WIDTH + $clog2(AXI_MAX_NUM_TRANSFERS) + ADDR_WIDTH + WSTRB_WIDTH ] ;
    always_comb
        begin 
                axi_wrreq_hdr_valid = 1'b0;
                axi_wrreq_hdr   = 'd0 ;
            if (wr_atop_en)
            begin
                no_of_dw_in_beat   = (1 << AWSize) >> 2; 
                    case (AWUser) 
                        3'b0_00: begin   /*  Default        -  No Request*/
                                axi_wrreq_hdr_valid = 1'b0;
                                axi_wrreq_hdr   = 'd0 ;
                        end
                        3'b0_01: begin   /*  32-bit Address -  MemWr Request */

                            // Enable mapper
                                axi_wrreq_hdr_valid     = 1'b1;

                            // Starting Formulation Header
                                axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA ; 
                                axi_wrreq_hdr.TYP   = 'b0_0000;
                                axi_wrreq_hdr.T9    = 1'b0 ;
                                axi_wrreq_hdr.TC    ='b000 ; //VC0
                                axi_wrreq_hdr.T8    = 1'b0 ;
                                axi_wrreq_hdr.ATTR  = 1'b1 ;
                                axi_wrreq_hdr.LN    = 1'b0 ;
                                axi_wrreq_hdr.TH    = 1'b0 ;
                                axi_wrreq_hdr.TD    = 1'b0 ;
                                axi_wrreq_hdr.EP    = 1'b0 ;
                                axi_wrreq_hdr.Attr  = 'b10  ;
                                axi_wrreq_hdr.AT    = 'b0  ;

                                axi_wrreq_hdr.Requester_ID = Requester_ID ;
                            
                            // Tag is 8 bits wide, so MSB is 1'b0 for Write and  1'b1 for Read
                                axi_wrreq_hdr.Tag          = {1'b0 , generate_tag(AWID)};
                                            
                            // Calculating Length Field and LAST_DW_BE
                                /*
                                                --> AWSIZE = 8 Byte  = 64 bit DATApath
                                                --> STRB is here 8 bits 
                                                    63 : 56 -  55 : 48 -  47 : 40 -  39:32 -  31:24 -  23:16 -  15:8 - 7:0 
                                                    STRB0= 8'b1111_1111  -- STRB1 = 8'b1111_1111 -- ...... -- STRB6= 8'b1111_1111 -- STRB7= 8'b0011_1111
                                                    
                                                    Examples:
                                                    Condition : in each beat more than 1 DW (2)
                                                    if (AWLEN = 7)
                                                    begin 
                                                                Length      = 14 DW = 7 * 2 = AWLEN * (AWSIZE / 4);How many DW in 1 beat =  (AWSIZE = # Bytes per Transfer / normalization Factor to DW = 4)
                                                                Last_DW_BE  = STRB7[7:4];
                                                                Slice for What ??
                                                                        each Beat represent x DW = 2
                                                                        I have n beats           = 7 
                                                                        so last DW is first or second ?? depending on STRB7 itself, if 0000_1000 so last DW is first
                                                                        so No. DW = (2 * 6) + (1 or 2)
                                                    end
                         
                                            */
                        //no_of_dw_in_beat   = (AWSize / 4) ;
  
                                // Calculating FIRST_DW_BE   
                            case (AWADDR[1:0])
                                'b00 : begin 
                                    axi_wrreq_hdr.first_DW_BE = 4'b1111; 
                                end
                                'b01 : begin 
                                    axi_wrreq_hdr.first_DW_BE = 4'b1110; 
                                end 
                                'b10 : begin 
                                    axi_wrreq_hdr.first_DW_BE = 4'b1100; 
                                end 
                                'b11 : begin 
                                    axi_wrreq_hdr.first_DW_BE = 4'b1000; 
                                end 
                            endcase

                            // Calculating Lower Address and Higher Address
                            axi_wrreq_hdr.Higher_Address [1:0]  = 2'b00 ;  // Reserved - PH is 00 not supported
                            axi_wrreq_hdr.Higher_Address [31:2] = AWADDR [31:2] ;
                            axi_wrreq_hdr.Lower_Address         = 'd0;
                            axi_wrreq_hdr.PH                    = 'd0;
                       
                        end
                        3'b0_10: begin   /*  32-bit Address -  IO Wr Req.*/ 
                            
                            // Enable mapper
                            axi_wrreq_hdr_valid     = 1'b1;

                            // Starting Formulation Header
        
                                axi_wrreq_hdr.FMT   = TLP_FMT_3DW_DATA ; 
                                axi_wrreq_hdr.TYP   = 'b0_0010;
                                axi_wrreq_hdr.T9    = 1'b0 ;
                                axi_wrreq_hdr.TC    ='b000 ;
                                axi_wrreq_hdr.T8    = 1'b0 ;
                                axi_wrreq_hdr.ATTR  = 1'b1 ;
                                axi_wrreq_hdr.LN    = 1'b0 ;
                                axi_wrreq_hdr.TH    = 1'b0 ;
                                axi_wrreq_hdr.TD    = 1'b0 ;
                                axi_wrreq_hdr.EP    = 1'b0 ;
                                axi_wrreq_hdr.Attr  = 'b10  ;
                                axi_wrreq_hdr.AT    = 'b0  ;

                                axi_wrreq_hdr.Length = 'd1 ;
                                axi_wrreq_hdr.Requester_ID = Requester_ID ;

                                // Tag is 8 bits wide, so MSB is 1'b0 for Write and  1'b1 for Read
                                axi_wrreq_hdr.Tag          = {1'b0 , generate_tag(AWID)}; 
                                
                                axi_wrreq_hdr.last_DW_BE = 'd0 ;
                                
                                // Calculating FIRST_DW_BE   
                                case (AWADDR[1:0])
                                    'b00 : begin 
                                        axi_wrreq_hdr.first_DW_BE = 4'b1111; 
                                    end
                                    'b01 : begin 
                                        axi_wrreq_hdr.first_DW_BE = 4'b1110; 
                                    end 
                                    'b10 : begin 
                                        axi_wrreq_hdr.first_DW_BE = 4'b1100; 
                                    end 
                                    'b11 : begin 
                                        axi_wrreq_hdr.first_DW_BE = 4'b1000; 
                                    end 
                                endcase                                
                                
                                // Calculating Lower Address and Higher Address
                                axi_wrreq_hdr.Higher_Address [1:0]  = 2'b00 ;  // Reserved - PH is 00 not supported
                                axi_wrreq_hdr.Higher_Address [31:2] = AWADDR [31:2] ;
                                axi_wrreq_hdr.Lower_Address         = 'd0;
                                axi_wrreq_hdr.PH                    = 'd0;




                        end 
                        3'b0_11: begin   /*  Nothing        -  No Request */  // {Add Feature of Respond in B Channel ERR}
                            axi_wrreq_hdr_valid = 1'b0;
                            axi_wrreq_hdr   = 'd0 ; 

                        end 
                        3'b1_00: begin   /*  Nothing        -  No Request */  // {Add Feature of Respond in B Channel ERR}
                                axi_wrreq_hdr_valid = 1'b0;
                                axi_wrreq_hdr   = 'd0 ;
                        end
                        3'b1_01: begin   /* 64-bit Address  -  MemWr Request*/
                            
                            // Enable mapper
                            axi_wrreq_hdr_valid     = 1'b1;

                            // Starting Formulation Header
        //                     TLP_FMT_3DW,            // 000
        // TLP_FMT_4DW,            // 001
        // TLP_FMT_3DW_DATA,       // 010
        // TLP_FMT_4DW_DATA,       // 011
        // TLP_PREFIX              // 100
                                axi_wrreq_hdr.FMT   = TLP_FMT_4DW_DATA ; 
                                axi_wrreq_hdr.TYP   = 'b0_0000;
                                axi_wrreq_hdr.T9    = 1'b0 ;
                                axi_wrreq_hdr.TC    ='b000 ;
                                axi_wrreq_hdr.T8    = 1'b0 ;
                                axi_wrreq_hdr.ATTR  = 1'b1 ;
                                axi_wrreq_hdr.LN    = 1'b0 ;
                                axi_wrreq_hdr.TH    = 1'b0 ;
                                axi_wrreq_hdr.TD    = 1'b0 ;
                                axi_wrreq_hdr.EP    = 1'b0 ;
                                axi_wrreq_hdr.Attr  = 'b10  ;
                                axi_wrreq_hdr.AT    = 'b0  ;

                                axi_wrreq_hdr.Requester_ID = Requester_ID ;
                            
                            // Tag is 8 bits wide, so MSB is 1'b0 for Write and  1'b1 for Read
                                axi_wrreq_hdr.Tag          = {1'b0 , generate_tag(AWID)};
                                            
                            // Calculating Length Field and LAST_DW_BE
                                /*
                                                --> AWSIZE = 8 Byte  = 64 bit DATABUS
                                                --> STRB is here 8 bits 
                                                    63 : 56 -  55 : 48 -  47 : 40 -  39:32 -  31:24 -  23:16 -  15:8 - 7:0 
                                                    STRB0= 8'b1111_1111  -- STRB1 = 8'b1111_1111 -- ...... -- STRB6= 8'b1111_1111 -- STRB7= 8'b0011_1111
                                                    
                                                    Examples:
                                                    Condition : in each beat more than 1 DW 
                                                    if (AWLEN = 7)
                                                    begin 
                                                                Length      = 16 DW = 7 * 2 = AWLEN * (AWSIZE / 4);How many DW in 1 beat =  (AWSIZE = # Bytes per Transfer / normalization Factor to DW = 4)
                                                                Last_DW_BE  = STRB7[7:4];
                                                                Slice for What ??
                                                                        each Beat represent x DW = 2
                                                                        I have n beats           = 7 
                                                                        so last DW is first or second ?? depending on STRB7 itself, if 0000_1000 so last DW is first
                                                                        so No. DW = (2 * 6) + (1 or 2)
                                                    end
                         
                                            */
                        //no_of_dw_in_beat   = (AWSize / 4) ;                                                                    
                       
                                   

                            // Calculating FIRST_DW_BE   
                            case (AWADDR[1:0])
                                'b00 : begin 
                                    axi_wrreq_hdr.first_DW_BE = 4'b1111; 
                                end
                                'b01 : begin 
                                    axi_wrreq_hdr.first_DW_BE = 4'b1110; 
                                end 
                                'b10 : begin 
                                    axi_wrreq_hdr.first_DW_BE = 4'b1100; 
                                end 
                                'b11 : begin 
                                    axi_wrreq_hdr.first_DW_BE = 4'b1000; 
                                end 
                            endcase

                            // Calculating Lower Address and Higher Address
                            axi_wrreq_hdr.Higher_Address        = AWADDR [64:32] ; 
                            axi_wrreq_hdr.Lower_Address         = AWADDR [31:2];
                            axi_wrreq_hdr.PH                    = 2'b00;
                       

                        end
                        3'b1_10: begin   /* 64-bit Adress   - IO wr --> Can't Happen*/ // {Add Feature for respond in B Channel ERR}
                            axi_wrreq_hdr_valid = 1'b0;
                            axi_wrreq_hdr   = 'd0 ;
                        end 
                        3'b1_11: begin  /*  Nothing - No Request */  // {Add Feature of Respond in B Channel ERR}
                            axi_wrreq_hdr_valid = 1'b0;
                            axi_wrreq_hdr   = 'd0 ;

                        end 
                    endcase 

                if (AWUser == 3'b0_01 || AWUser == 3'b1_01 ) begin 
                    case (AWSize)                                                                   
                        'd0 : begin 
                                    // Here Each Beat is 1 Byte -->  so to calc. no. of DW via no. beats using the following location
                                    no_of_dw =  (AWLEN+1'b1)  >> 2 ; // # DW = AWLEN * AWSIZE = AWLEN * 1 / 4
                                    // There are 3 Choices for answer (3/4 = 0 ; 5/4 = 1 ; 4/4 = 1)
                                    if (no_of_dw  == 'b0)   // Here AWLEN < 4 (bytes) ---> so we have 1 DW  AND LAST_DW_EN is the AWLEN itself
                                    begin
                                        axi_wrreq_hdr.Length = 1'b1;
                                    end
                                    else if (AWLEN + 1'b1 - (no_of_dw << 2)  == 'b0 ) begin // Here AWLEN is factor of 4 ---> Length is division, last_DW is all ones
                                        axi_wrreq_hdr.Length = no_of_dw; 
                                    end
                                    else begin                  // Here the case of AWLEN is 5 for example , so we need to Length = 2 DW and Last Byte 0001
                                        axi_wrreq_hdr.Length = no_of_dw + 1'b1 ;
                                    end

                                    if (axi_wrreq_hdr.Length != 1) begin 
                                        axi_wrreq_hdr.last_DW_BE = {3'b000 , WSTRB[0]};   // STRB in this case is 1 bit but physically the bus is 128 bit to include other cases
                                    end 
                                    else begin 
                                        axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                    end 
                        end 
                        'd1 : begin 
                            // Here Each Beat is 2 Byte -->  so to calc. no. of DW via no. beats using the following location
                            // axi_wrreq_hdr.last_DW_BE = {'b00 , WSTRB[1:0]};   // STRB in this case is 1 bit but physically the bus is 128 bit to include other cases
                            no_of_dw =  (AWLEN+1'b1 ) >> 1 ; // # DW = AWLEN * 2 / 4
                            // There are 3 Choices for answer (1/2 = 0 ; 3/2 = 1 ; 2/2 = 1)
                            if (no_of_dw  == 'b0)   // Here AWLEN < 2 (bytes) ---> so we have 1 DW  
                            begin
                                axi_wrreq_hdr.Length = 1'b1;
                            end
                            else if (AWLEN + 1'b1 - (no_of_dw << 1)  == 1'b0 ) begin // Here AWLEN is factor of 2 ---> Length is division
                                axi_wrreq_hdr.Length = no_of_dw; 
                            end
                            else begin                  // Here the case of AWLEN is 3 for example , so we need to Length = 2 DW 
                                axi_wrreq_hdr.Length = no_of_dw + 1'b1 ;
                            end

                            if (axi_wrreq_hdr.Length != 1'b1) begin 
                                axi_wrreq_hdr.last_DW_BE = {'b00 , WSTRB[1:0]};   // STRB in this case is 1 bit but physically the bus is 128 bit to include other cases
                            end 
                            else begin 
                                axi_wrreq_hdr.last_DW_BE = {4'b0000};
                            end 
                        end 
                        'd2 : begin 
                            // Here Each Beat is 4 Byte, so no_dw_of_beat = 1
                            // axi_wrreq_hdr.last_DW_BE = WSTRB[3:0];
                            axi_wrreq_hdr.Length     = AWLEN  + 1'b1   ; 
                            if (axi_wrreq_hdr.Length != 1'b1) begin 
                                axi_wrreq_hdr.last_DW_BE = WSTRB[3:0];
                            end 
                            else begin 
                                axi_wrreq_hdr.last_DW_BE = {4'b0000};
                            end 
                            
                        end 
                        'd3 : begin 
                            // Here Each Beat is 8 Byte, so no_dw_of_beat = 2 
                            if (WSTRB[7:4] == 4'b0000) begin 
                                axi_wrreq_hdr.Length = (AWLEN)  * 2 + 1 ;
                                /*
                                    1 beats 
                                    beat 2 DW 
                                    strb = 0000 _ 1111

                                    length 1 

                                */
                                if (axi_wrreq_hdr.Length != 1'b1) begin 
                                    axi_wrreq_hdr.last_DW_BE = WSTRB[3:0] ;
                                end 
                                else begin 
                                    axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                end 
                            end 
                            else begin 
                                axi_wrreq_hdr.Length = (AWLEN ) * 2  ;
                                if (axi_wrreq_hdr.Length != 1'b1) begin 
                                    axi_wrreq_hdr.last_DW_BE = WSTRB[7:4] ;
                                end 
                                else begin 
                                    axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                end 
                            end

                            
                            /*
                                awlen = 2 - awsize = 8 byte 
                                beat 1: AAAA _ BBBB
                                beat 2: xxxx - cccc - strb : 0000_1111
                                # Dw = 3 

                                Sol. DW = 4 
                                AAAA           
                                BBBB
                                cccc
                                xxxx

                            */
                        end
                        'd4 : begin 
                            // Here Each Beat is 16 Byte, so no_dw_of_beat = 4 
                            casez (WSTRB)
                                'b0000_0000_0000_????: begin 
                                                            axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 1;
                                                            if (axi_wrreq_hdr.Length != 1'b1) begin 
                                                                axi_wrreq_hdr.last_DW_BE = WSTRB[3:0] ;
                                                            end 
                                                            else begin 
                                                                axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                                            end 
                                end
                                'b0000_0000_????_????: begin 
                                                            axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 2;
                                                            if (axi_wrreq_hdr.Length != 1'b1) begin 
                                                                axi_wrreq_hdr.last_DW_BE = WSTRB[7:4] ;
                                                            end 
                                                            else begin 
                                                                axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                                            end                                             
                                                        end 
                                'b0000_????_????_????: begin 
                                                            axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 3;
                                                            if (axi_wrreq_hdr.Length != 1'b1) begin 
                                                                axi_wrreq_hdr.last_DW_BE = WSTRB[11:8] ;
                                                            end 
                                                            else begin 
                                                                axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                                            end   
                                                            
                                end
                                default: begin 
                                                            axi_wrreq_hdr.Length = (AWLEN ) * no_of_dw_in_beat ; 
                                                            if (axi_wrreq_hdr.Length != 1'b1) begin 
                                                                axi_wrreq_hdr.last_DW_BE = WSTRB[15:12] ;
                                                            end 
                                                            else begin 
                                                                axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                                            end   
                                end
                            endcase 

                        end 
                        'd5 : begin

                            casez (WSTRB)
                                'b0000_0000_0000_0000_0000_0000_0000_????: begin 
                                                            axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 1;
                                                            if (axi_wrreq_hdr.Length != 1'b1) begin 
                                                                axi_wrreq_hdr.last_DW_BE = WSTRB[3:0] ; 
                                                            end 
                                                            else begin 
                                                                axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                                            end   
                                end
                                'b0000_0000_0000_0000_0000_0000_????_????: begin 
                                                            axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 2;
                                                            if (axi_wrreq_hdr.Length != 1'b1) begin 
                                                                axi_wrreq_hdr.last_DW_BE = WSTRB[7:4] ; 
                                                            end 
                                                            else begin 
                                                                axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                                            end   
                                end
                                'b0000_0000_0000_0000_0000_????_????_????: begin 
                                                            axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 3;
                                                            if (axi_wrreq_hdr.Length != 1'b1) begin 
                                                                axi_wrreq_hdr.last_DW_BE = WSTRB[11:8] ;  
                                                            end 
                                                            else begin 
                                                                axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                                            end   
                                end
                                'b0000_0000_0000_0000_????_????_????_????: begin 
                                                            axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 4;
                                                            if (axi_wrreq_hdr.Length != 1'b1) begin 
                                                                axi_wrreq_hdr.last_DW_BE = WSTRB[15:12] ;  
                                                            end 
                                                            else begin 
                                                                axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                                            end   
                                end
                                'b0000_0000_0000_????_????_????_????_????: begin 
                                                            axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 5;
                                                            if (axi_wrreq_hdr.Length != 1'b1) begin 
                                                                axi_wrreq_hdr.last_DW_BE = WSTRB[19:16] ;  
                                                            end 
                                                            else begin 
                                                                axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                                            end   
                                end
                                'b0000_0000_????_????_????_????_????_????: begin 
                                                            axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 6;
                                                            if (axi_wrreq_hdr.Length != 1'b1) begin 
                                                                axi_wrreq_hdr.last_DW_BE = WSTRB[23:20] ;  
                                                            end 
                                                            else begin 
                                                                axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                                            end   
                                end
                                'b0000_????_????_????_????_????_????_????: begin 
                                                            axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 7;
                                                            if (axi_wrreq_hdr.Length != 1'b1) begin 
                                                                axi_wrreq_hdr.last_DW_BE = WSTRB[27:24] ;  
                                                            end 
                                                            else begin 
                                                                axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                                            end   
                                end
                                default: begin 
                                                            axi_wrreq_hdr.Length = (AWLEN ) * no_of_dw_in_beat ;
                                                            if (axi_wrreq_hdr.Length != 1'b1) begin 
                                                                axi_wrreq_hdr.last_DW_BE = WSTRB[31:28] ;
                                                            end 
                                                            else begin 
                                                                axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                                            end   
                                end
                            endcase

                        end 
                        'd6 : begin
                            casez (WSTRB)
                                    'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_????: begin 
                                                            axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 1;
                                                            if (axi_wrreq_hdr.Length != 1'b1) begin 
                                                                axi_wrreq_hdr.last_DW_BE = WSTRB[3:0] ; 
                                                            end 
                                                            else begin 
                                                                axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                                            end   
                                    end
                                    'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_????_????: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 2;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[7:4] ;
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end   
                                    end
                                    'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_????_????_????: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 3;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[11:8] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end  
                                    end
                                    'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_????_????_????_????: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 4;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[15:12] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end  
                                    end
                                    'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_????_????_????_????_????: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 5;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[19:16] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end  
                                    end
                                    'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_????_????_????_????_????_????: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 6;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[23:20] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end  
                                    end
                                    'b0000_0000_0000_0000_0000_0000_0000_0000_0000_????_????_????_????_????_????_????: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 7;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[27:24] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end  
                                    end
                                    'b0000_0000_0000_0000_0000_0000_0000_0000_????_????_????_????_????_????_????_????: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 8;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[31:28] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end  
                                    end
                                    'b0000_0000_0000_0000_0000_0000_0000_????_????_????_????_????_????_????_????_????: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 9;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[35:32] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end  
                                    end
                                    'b0000_0000_0000_0000_0000_0000_????_????_????_????_????_????_????_????_????_????: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 10;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[39:36] ;                                                    end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end  
                                         
                                    end
                                    'b0000_0000_0000_0000_0000_????_????_????_????_????_????_????_????_????_????_????: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 11;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[43:40] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end  
                                    end
                                    'b0000_0000_0000_0000_????_????_????_????_????_????_????_????_????_????_????_????: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 12;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[47:44] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    'b0000_0000_0000_????_????_????_????_????_????_????_????_????_????_????_????_????: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 13;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[51:48] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    'b0000_0000_????_????_????_????_????_????_????_????_????_????_????_????_????_????: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 14;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[55:52] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    'b0000_????_????_????_????_????_????_????_????_????_????_????_????_????_????_????: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 15;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[59:56] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    default: begin 
                                        axi_wrreq_hdr.Length =(AWLEN) * no_of_dw_in_beat ;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[63:60] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end 
                            endcase
                            end 
                        'd7 : begin 
                                casez(WSTRB)
                                    {124'b0,4'b?}: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 1;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[3:0] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {120'b0,8'b?}: begin 
                                        axi_wrreq_hdr.Length = AWLEN  * no_of_dw_in_beat + 2;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[7:4] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {116'b0,12'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 3;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[11:8] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {112'b0,16'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 4;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[15:12] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {108'b0,20'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 5;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[19:16] ;  
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {104'b0,24'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 6;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[23:20] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {100'b0,28'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 7;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[27:24] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {96'b0,32'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 8;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[31:28] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {92'b0,36'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 9;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[35:32] ;
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {88'b0,40'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 10;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[39:36] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {84'b0,44'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 11;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[43:40] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {80'b0,48'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 12;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[47:44] ;  
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {76'b0,52'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 13;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[51:48] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {72'b0,56'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 14;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[55:52] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {68'b0,60'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 15;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[59:56] ;
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {64'b0,64'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 16;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[63:60] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {60'b0,68'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 17;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[67:64] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {56'b0,72'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 18;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[71:68] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {52'b0,76'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 19;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[75:72] ;  
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {48'b0,80'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 20;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[79:76] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {44'b0,84'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 21;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[83:80] ;  
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {40'b0,88'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 22;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[87:84] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {36'b0,92'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 23;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[91:88] ;
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {32'b0,96'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 24;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[95:92] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {28'b0,100'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 25;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[99:96] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {24'b0,104'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 26;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[103:100] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {20'b0,108'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 27;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[107:104] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {16'b0,112'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 28;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[111:108] ;  
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {12'b0,116'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 29;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[115:112] ;   
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {8'b0,120'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 30;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[119:116] ;   
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    {4'b0,124'b?}: begin 
                                        axi_wrreq_hdr.Length =AWLEN  * no_of_dw_in_beat + 31;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[123:120] ; 
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end
                                    default: begin 
                                        axi_wrreq_hdr.Length =(AWLEN ) * no_of_dw_in_beat ;
                                        if (axi_wrreq_hdr.Length != 1'b1) begin 
                                            axi_wrreq_hdr.last_DW_BE = WSTRB[127:124] ;
                                        end 
                                        else begin 
                                            axi_wrreq_hdr.last_DW_BE = {4'b0000};
                                        end 
                                    end 

                                endcase

                        end 
                    endcase

                end 
                
                end  
        end 
        always_comb 
         begin 
            // Put Constraint on Arbiter to set grant to be in one clk cycle
            if (axi_req_wr_grant)
                begin 
                    recorder_if.req_wr_en = 1'b1 ;
                    recorder_if.req_wr_addr = axi_wrreq_hdr.Tag;
                    recorder_if.req_wr_data = {AWID,1'b1};
                end              
            else 
                begin 
                    recorder_if.req_wr_en = 1'b0 ;
                    recorder_if.req_wr_addr = 'b0;
                    recorder_if.req_wr_data = 'b0;
                end 
            end 

            // always_comb 
            //  begin 
            //        if (axi_req_wr_grant &&  )
            //  end 

    endmodule 

