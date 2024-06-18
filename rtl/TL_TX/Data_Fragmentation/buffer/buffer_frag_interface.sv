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
import Fragmentation_Package::*;
import axi_slave_package::*; 


// Define the interface of buffer used in data fragmentation
interface buffer_frag_interface;
    logic                               wr_en       ; 
    logic     			                empty   ;
    logic [WR_DATA_WIDTH - 1 : 0]       data_in     ; 
    logic [NO_LOC_WR_WIDTH - 1 : 0]     no_loc_wr   ;
    
        
    modport buffer_arbiter (
        input       wr_en,
                    data_in,
                    no_loc_wr,

        output      empty
    );

    modport arbiter_buffer (
        output      wr_en,
                    data_in,
                    no_loc_wr,

        input       empty
    );





endinterface : buffer_frag_interface
