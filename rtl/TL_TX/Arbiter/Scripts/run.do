# Close Previous Simulation
quit -sim 

####################### Ahmady Files #######################
    vlog -work work {../../../Arbiter/Package/Tx_Arbiter_Package.sv}
    vlog -work work {../../../Arbiter/Controller/Tx_Arbiter_Interface.sv}
    vlog -work work {../../../Arbiter/Controller/Sequence_Recorder.sv}
    vlog -work work {../../../Arbiter/Controller/Tx_Arbiter.sv}

####################### Compile Top Design and its TB #######################
    vlog -work work {../../../Arbiter/Controller/Tx_Arbiter_Top.sv}

####################### Run Simulation #######################
# 2176572149, 3477034145
    vsim -novopt -sv_seed random work.Tx_Arbiter_Top
    do {Tx_Arbiter.do}
    
run -all