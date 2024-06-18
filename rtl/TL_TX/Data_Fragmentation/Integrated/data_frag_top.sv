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
import Fragmentation_Package::*;
import axi_slave_package::*; 

module data_frag_Top ( 
            //  Global Signals 
                input bit                                           clk ,
                input bit                                           arst,
            //  TLP Buffer with Arbiter Interface (Write Port)
                buffer_frag_interface.buffer_arbiter               Src_buffer_if,
            // DLL Interface
                Fragmentation_Interface.FRAGMENTATION_DLL           _dll_if
                // input  logic                                       Halt_1,
                // input  logic                                       Halt_2,
                // input  logic                                       Throttle,
                // output logic                                       sop,
                // output logic                                       eop,
                // output logic                                       TLP_valid,
                // output valid_bytes_encoding                        Valid_Bytes,
                // output logic [DLL_LENGTH_WIDTH - 1 : 0]            Length,
                // output logic [DLL_TLP_WIDTH - 1 : 0]               TLP
);


/* Instantiations */
/********* Interfaces *********/
    Fragmentation_Interface #(
    ) Frag_if ();

    buffer_frag_interface buffer_if ();

/********* Modules *********/
// TLP Buffer Fragmentation 
    buffer_frag u_buffer_frag ( 
        .clk(clk),
        .arst(arst),
        ._Src_if(Src_buffer_if),
        ._Dist_if(Frag_if.TLP_FIFO_FRAGMENTATION)
    ); 
    
    Frag #(
    ) u_Frag (
        .clk(clk), 
        .arst(arst),
        // TLP Buffer Interface
        ._tlp_fifo_if(Frag_if.FRAGMENTATION_TLP_FIFO),    
        // DLL Interface
        ._dll_if(_dll_if),
        // .Halt_1(Halt_1),
        // .Halt_2(Halt_2),
        // .Throttle(Throttle),
        // .sop(sop),
        // .eop(eop),
        // .TLP_valid(TLP_valid),
        // .Valid_Bytes(Valid_Bytes),
        // .Length(Length),
        // .TLP(TLP),
        // ECRC Interface
        ._ecrc_if(Frag_if.FRAGMENTATION_ECRC)
    );

    ECRC #(
    ) u_ECRC (
        .clk(clk), 
        .arst(arst),
        ._if(Frag_if.ECRC_FRAGMENTATION) 
    ); 



// Power management  (Will be updated Later --> update the ports of this module and higher hierarchy)


endmodule 

