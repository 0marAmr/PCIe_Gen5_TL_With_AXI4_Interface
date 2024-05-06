/********************************************************************/
/* Module Name	: data_fragmentation_package.sv                     */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 27-03-2024					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: Data Fragmentation                                */
/* Summary:  This file includes the parameter and data type
definiton inside the data fragmentation block                       */
/********************************************************************/

package data_frag_package ;
    parameter   DW                      = 4  * 8   ,          /* DW ---> Data Width in bits      */
                HDR_WIDTH               = 4  * DW  , 
                DATA_WIDTH              = 32 * DW  ;        
    parameter   Buffer_WIDTH            = 4 * DW   ,
                Buffer_DEPTH            = ((1024 + 4) / 4 )    , // 257 locations
                ADDR_WIDTH              = $clog2 (Buffer_DEPTH) , // 9 BITS 
				NO_LOC_WR_WIDTH 		= 4 , // $clog2((32+4)/4) = 4 bits //  1001 = 9 is the Max. No of loc. write
				WR_DATA_WIDTH  			= (36) * DW , // Size of Data in is HDR + 32 dw Data
                Buffer_ADDR_WIDTH       = $clog2(Buffer_DEPTH)      ;
    parameter   COUNT_WIDTH             = 9 ;  // $clog2(257) // No. bits represented no. loc. stored
                
                        
        // ecrc parametr                 
    parameter   DATA_ECRC_IN_WIDTH      = 8 * DW                   ,
                DATA_ECRC_OUT_WIDTH     = 1 * DW                   ,
                ECRC_LENGTH_WIDTH       = 4                        , // Length of Valid Data in DW
                POLY_WIDTH 		        = 32                       ; // Polynomial Order (for PCIe 32-bits 0x04C11DB7) 

                
    
                

endpackage : data_frag_package