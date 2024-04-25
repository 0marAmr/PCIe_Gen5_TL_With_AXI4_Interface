/* Module Name	: Master_Interface              */
/* Written By	: Ahmady                     	*/
/* Date			: 27-03-2024		*/
/* Version		: V_1			*/
/* Updates		: -			*/
/* Dependencies	: -				*/
/* Used			: -			*/
// `timescale 1ns/1ps
interface Master_Interface #(
)(
);
    import axi_slave_package::*;
    B_Channel_Slv_t B_Channel_Slv;  // B Channel Slave  outputs
    B_Channel_Msr_t B_Channel_Msr;  // B Channel Master outputs
    R_Channel_Slv_t R_Channel_Slv;  // R Channel Slave  outputs
    R_Channel_Msr_t R_Channel_Msr;  // R Channel Master outputs


    // Master
    modport MASTER (
        input   B_Channel_Slv,
                R_Channel_Slv,

        output  B_Channel_Msr,
                R_Channel_Msr
    );

    modport SLAVE (
        input   B_Channel_Msr,
                R_Channel_Msr,

        output  B_Channel_Slv,
                R_Channel_Slv
    );


    // Master
    // modport MASTER (
    //     input   B_Channel.BID,
    //             B_Channel.BVALID,
    //             B_Channel.BRESP,

    //             R_Channel.RID,
    //             R_Channel.RVALID,
    //             R_Channel.RDATA,
    //             R_Channel.RRESP,
    //             R_Channel.RLAST,

    //     output  B_Channel.BREADY,
    //             R_Channel.RREADY
    // );

    // Slave
    // modport SLAVE (
    //     output  B_Channel.BID,
    //             B_Channel.BVALID,
    //             B_Channel.BRESP,
                
    //             R_Channel.RID,
    //             R_Channel.RVALID,
    //             R_Channel.RDATA,
    //             R_Channel.RRESP
    //             R_Channel.RLAST,

    //     input   B_Channel.BREADY,
    //             R_Channel.RREADY
    // );

    
endinterface: Master_Interface
