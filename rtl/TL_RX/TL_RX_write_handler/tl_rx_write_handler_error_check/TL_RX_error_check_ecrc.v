module TL_RX_error_check_ecrc (
    input wire ecrc_en,
    input wire TD,
    input wire ecrc_check_en_config,
    input wire ecrc_error_check,
    output wire ecrc_error
);
    assign ecrc_enable=ecrc_en&& TD &&ecrc_check_en_config;
    assign ecrc_error = ecrc_enable ? ecrc_error_check:0;
    
endmodule