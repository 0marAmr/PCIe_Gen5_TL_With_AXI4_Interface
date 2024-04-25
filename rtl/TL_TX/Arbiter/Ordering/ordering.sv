/********************************************************************/
/* Module Name	: ordering.sv                    		    */
/* Written By	: Mohamed Aladdin Mohamed                           */
/* Date			: 10-04-2024			            */
/* Version		: V1					    */
/* Updates		: -					    */
/* Dependencies	: -						    */
/* Used			: in Arbiter Modules                        */
/* Summary:  This file includes the rules for ordering model 
inside PCIe with respect the axi ordering rules                      */
/********************************************************************/
// Modify the module 

// import package
import Tx_Arbiter_Package::*;

// Module
module ordering (

        ordering_if.ORDERING_ARBITER_IF _if 
);

assign IDO_set = _if.first_IDO && _if.second_IDO ; 
assign RO_set = _if.first_RO && _if.second_RO ;


always_comb begin
    case (_if.second_trans)
        No_Req : begin 
                _if.ordering_result = FALSE ; 
        end 
        Posted_Req : begin
                case (_if.first_trans)  
                        No_Req : begin 
                                _if.ordering_result = FALSE ;
                        end 
                        Posted_Req : begin 
                                    if (RO_set) begin 
                                        _if.ordering_result = TRUE ;
                                    end 
                                    else if (IDO_set) begin 
                                        if (_if.first_trans_ID != _if.second_trans_ID) begin 
                                                _if.ordering_result = TRUE ;
                                        end 
                                        else begin 
                                                _if.ordering_result = FALSE ;
                                        end 
                                    end 
                                    else 
                                    _if.ordering_result = FALSE ;                   
                        end 
                        Non_Posted_Req : begin 
                                        _if.ordering_result = TRUE ;
                        end 
                        Comp : begin 
                                        _if.ordering_result = TRUE ;       
                        end
        endcase 
end 
        Non_Posted_Req : begin
                case (_if.first_trans)  
                        No_Req : begin 
                                _if.ordering_result = FALSE ;
                        end 
                        Posted_Req : begin 
                                if (RO_set) begin 
                                        _if.ordering_result = TRUE ;
                                    end 
                                    else if (IDO_set) begin 
                                        if (_if.first_trans_ID != _if.second_trans_ID) begin 
                                                _if.ordering_result = TRUE ;
                                        end 
                                        else begin 
                                                _if.ordering_result = FALSE ;
                                        end 
                                    end 
                                    else 
                                    _if.ordering_result = FALSE ;  
                        end 
                        Non_Posted_Req : begin 
                                _if.ordering_result = TRUE ;
                        end 
                        Comp : begin 
                                _if.ordering_result = TRUE ;
                        end      
        endcase
end 
        Comp : begin 
                case (_if.first_trans)  
                        No_Req : begin 
                                _if.ordering_result = FALSE ;
                        end 
                        Posted_Req : begin 
                                if (RO_set) begin 
                                        _if.ordering_result = TRUE ;
                                    end
                                else if ((_if.comp_typ == 3'b001) || (_if.comp_typ == 3'b010)) begin 
                                        _if.ordering_result = TRUE ;
                                    end
                                else if (IDO_set) begin 
                                        if (_if.first_trans_ID != _if.second_trans_ID) begin 
                                                _if.ordering_result = TRUE ;
                                        end 
                                        else begin 
                                                _if.ordering_result = FALSE ;
                                        end 
                                    end 
                                
                                else begin  
                                    _if.ordering_result = FALSE ; 
                                    end 
                        end 
                        Non_Posted_Req : begin 
                                _if.ordering_result = TRUE ;
                        end 
                        Comp : begin
                                if (_if.first_trans_ID != _if.second_trans_ID) begin 
                                        _if.ordering_result = TRUE ;
                                end 
                                else begin 
                                        _if.ordering_result = FALSE ; 
                                end       
                        end 
        endcase
end 
    endcase
end

endmodule 
