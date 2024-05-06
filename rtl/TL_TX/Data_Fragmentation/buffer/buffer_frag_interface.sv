/********************************************************************/
/* Module Name	: buffer_fragmentation.sv                     	    */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 27-03-2024		                    */
/* Version		: V1			                    */
/* Updates		: -			                    */
/* Dependencies	: -				                    */
/* Used			: -	 	                            */
/* Summary:  This file includes interface of data fragementation    */
/********************************************************************/

// import package
import data_frag_package::*;

// Define the interface of buffer used in data fragmentation
interface buffer_frag_interface ();
    logic                          wr_en       ; 
    logic [COUNT_WIDTH - 1 : 0]    empty_loc   ;
    logic [WR_DATA_WIDTH - 1 : 0]   data_in     ; 
    logic [NO_LOC_WR_WIDTH - 1 : 0] no_loc_wr   ;
    
    
    // Signals for interfacing to DATA Fragmentation
    logic                           rd_en       ;  
    logic                           rd_mode     ;  // 0 for read one location -- and 1 for read 2 location
    logic [4* DW - 1 : 0 ]          rd_data_1   ;
    logic [4* DW - 1 : 0 ]          rd_data_2   ;    
    logic [COUNT_WIDTH - 1 : 0]     Count       ;  // COUNT WIDTH = 9 : Represent No. of Stored 

        
    modport buffer (
        input       wr_en,
                    data_in,
                    no_loc_wr,
                    rd_en,
                    rd_mode,
        output      rd_data_1,
                    rd_data_2,
                    empty_loc,
                    Count
    );

    modport buffer_tb (
        output       wr_en,
                    data_in,
                    no_loc_wr,
                    rd_en,
                    rd_mode,
        input      rd_data_1,
                    rd_data_2,
                    empty_loc,
                    Count
    );


    
    modport arbiter_buffer (
        output      wr_en,
                    data_in,
                    no_loc_wr,

        input       empty_loc

);





endinterface : buffer_frag_interface
