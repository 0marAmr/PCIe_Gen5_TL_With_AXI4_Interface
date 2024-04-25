# Close Previous Simulation
quit -sim 

####################### Ahmady Files #######################
    vlog -work work {../../../Arbiter/Package/Tx_Arbiter_Package.sv}
    vlog -work work {../../../Arbiter/Flow_Control/Tx_FC_Interface.sv}
    vlog -work work {../../../Arbiter/Flow_Control/Tx_FC.sv}

####################### Compile Top Design and its TB #######################
    vlog -work work {../../../Arbiter/Flow_Control/Tx_FC_Top.sv}

####################### Run Simulation #######################
    vsim -novopt -sv_seed random work.Tx_FC_Top
    do {Tx_FC.do}
    
run -all