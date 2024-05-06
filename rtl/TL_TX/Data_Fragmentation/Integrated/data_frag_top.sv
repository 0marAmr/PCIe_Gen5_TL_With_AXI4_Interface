/********************************************************************/
/* Module Name	: data_frag_Top.sv                                  */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 1-05-2024 					                    */
/* Version		: V1							                    */
/* Updates		: -								                    */
/* Dependencies	: -								                    */
/* Used			: this integration between all Data Fragmentation   */
/*                Blocks (ECRC - Buffer - FSM)                      */
/********************************************************************/
// import the defined package for arbiter 
import Tx_Arbiter_Package::*;
import data_frag_package::*;
import axi_slave_package::*; 

module data_frag_Top ( 
            //  Global Signals 
                    input bit                       clk ,
                    input bit                       arst,
            //  Buffer fragmentation 
                    output logic                     start_fragment , 
                    output logic                     Buffer_Ready , 
                    buffer_frag_interface            frag_if
);

// TLP Buffer Fragmentation 
    buffer_frag u_buffer_frag ( 
        .clk(clk),
        .arst(arst),
        ._if(frag_if),
        .Buffer_Ready(Buffer_Ready),
        .start_fragment(start_fragment)
    ); 

// Data Fragmentation 




// ECRC block 



// Power management  (Will be updated Later --> update the ports of this module and higher hierarchy)


endmodule 

