/* Module Name	: Sync_FIFO_Interface			*/
/* Written By	: Ahmady                     	        */
/* Date			: 27-03-2024			*/
/* Version		: V_1	        		*/
/* Updates		: -				*/
/* Dependencies	: -	        			*/
/* Used			: -	         		*/
//`timescale 1ns/1ps
interface Sync_FIFO_Interface #(
    parameter   DATA_WIDTH      = 8,
                FIFO_DEPTH      = 4,
                ADDR_WIDTH      = $clog2(FIFO_DEPTH) 
);
    logic [DATA_WIDTH - 1 : 0]  FIFO_wr_data;
    logic [DATA_WIDTH - 1 : 0]  FIFO_rd_data;
    logic                       FIFO_wr_en;
    logic                       FIFO_rd_en;
    logic                       FIFO_full;
    logic                       FIFO_empty;
    logic [ADDR_WIDTH  : 0]     FIFO_available;

    // DUT (Whole FIFO interface with source and dist)
    modport DUT (
        input   FIFO_rd_en,
                FIFO_wr_en,
                FIFO_wr_data,

        output  FIFO_rd_data,
                FIFO_full,
                FIFO_empty,
                FIFO_available
    );

    // TB
    modport TB (
        output  FIFO_rd_en,
                FIFO_wr_en,
                FIFO_wr_data,    

        input   FIFO_rd_data,
                FIFO_full,
                FIFO_empty,
                FIFO_available
    );

    // interface for FIFO to connect with Source
    modport FIFO_SOURCE (
        input   FIFO_wr_en,
                FIFO_wr_data,

        output FIFO_full,
               FIFO_available
    );

    // interface for Source to connect with FIFO
    modport SOURCE_FIFO (
        input   FIFO_full,
                FIFO_available,

        output  FIFO_wr_en,
                FIFO_wr_data    
    );

    // interface for FIFO to connect with Dist
    modport FIFO_DIST (
        input   FIFO_rd_en,

        output FIFO_rd_data,
               FIFO_empty
    );

    // interface for Dist to connect with FIFO
    modport DIST_FIFO (
        input   FIFO_empty,
                FIFO_rd_data,

        output  FIFO_rd_en
    );

endinterface: Sync_FIFO_Interface
