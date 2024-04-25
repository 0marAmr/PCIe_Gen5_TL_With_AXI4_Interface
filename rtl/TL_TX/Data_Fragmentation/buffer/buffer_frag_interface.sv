/********************************************************************/
/* Module Name	: buffer_fragmentation.sv                     	    */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 27-03-2024					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: -							                        */
/* Summary:  This file includes interface of data fragementation    */
/********************************************************************/



// Define the interface of buffer used in data fragmentation

interface buffer_frag_interface ();
    logic                           wr_en       ; 
    logic [Buffer_DEPTH - 1 : 0]    empty_loc   ;
    logic [Buffer_WIDTH - 1 : 0]    data_in     ; 
    logic [Buffer_DEPTH - 1 : 0]    no_loc_wr   ;
    
    logic [Buffer_WIDTH - 1 : 0]    data_out    ;
    logic                           rd_en       ; 
    logic                           empty_buffer; 

        
    modport buffer (
            input   wr_en,
                    empty_loc,
                    data_in,
                    no_loc_wr,
    
            output  data_out,
                    rd_en,
                    empty_buffer  
    );
    
    modport arbiter_buffer (
        output      wr_en,
                    data_in,
                    no_loc_wr,

        input       empty_loc

);





endinterface : buffer_frag_interface
