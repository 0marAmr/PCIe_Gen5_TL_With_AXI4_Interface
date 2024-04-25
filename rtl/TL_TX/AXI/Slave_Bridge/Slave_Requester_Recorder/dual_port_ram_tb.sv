/* Module Name	: dual_port_ram_tb.sv	        */
/* Written By	: Mohamed Aladdin             	*/
/* Date			: 04-04-2024					*/
/* Version		: V_1							*/
/* Updates		: -								*/
/* Dependencies	: -								*/
/* Used			: - 							*/
/* Summary : it is a simple testbench for dual  */
/*           Port Memory                        */
`timescale 1ns/1ps    

    module dual_port_ram_tb();
        
        // import the defined package for axi
        import axi_slave_package::*;

         // Object of interface 
        dual_port_ram_if __if();
        bit clk,rstn ; 
         // DUT Instantiation 
        Request_Recorder u_Request_Recorder (
        clk,
        rstn,
        __if,
        __if,
        __if,
        __if
        );

        // Clock Generation
        always begin 
            #(CLK_PERIOD/2) clk = ~ clk ;
        end
        
        //TestCases
        initial 
        begin 
            clk = 1'b0;
            rstn = 1'b0;
            #(CLK_PERIOD*2)
            rstn = 1'b1;
            #CLK_PERIOD
            
            
            // __if.req_wr_en = 1;
            // __if.req_wr_addr = 3;
            // __if.req_wr_data = 'h1ff;
        
        //#(CLK_PERIOD*2)
        
        
        repeat (2*DUAL_PORT_RAM_DIPTH) begin
        
        __if.req_wr_en = 1;
        __if.req_wr_addr = $urandom_range('hff ,'h00);
        __if.req_wr_data = $urandom_range('hff ,'h00);

        __if.req_rd_addr = $urandom_range('hff ,'h00);
        
        __if.resp_wr_en = 1;
        __if.resp_wr_addr = $urandom_range('hff ,'h00);
        __if.resp_wr_data =$urandom_range('hff ,'h00);

        __if.resp_rd_addr = $urandom_range('hff ,'h00);
        #(CLK_PERIOD*2);

        
        end
        
            $stop;
        end
endmodule 