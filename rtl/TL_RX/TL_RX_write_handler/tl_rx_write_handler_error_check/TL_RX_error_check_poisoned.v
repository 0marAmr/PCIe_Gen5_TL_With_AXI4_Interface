module TL_RX_error_check_poisoned (
    input wire EP,
    input wire poisoned_en,
    output reg poisoned_error
);
    always @(*) begin
        if (poisoned_en==1) begin
            if (EP==1) begin
                poisoned_error=1;
            end
            else begin
                poisoned_error=0;
            end
        end
        else begin
            poisoned_error=0;
        end
    end   
endmodule
