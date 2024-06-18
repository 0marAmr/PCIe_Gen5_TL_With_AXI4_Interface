# Close Previous Simulation
quit -sim 

####################### Packages ##########################
    vlog -work work {../../../AXI/Slave_Package/axi_slave_package.sv}
    vlog -work work {../../../Arbiter/Package/Tx_Arbiter_Package.sv}
    vlog -work work {../../../Data_Fragmentation/package/Fragmentation_Package.sv}
    

############################# Compile Arbiter ################################
    vlog -work work {../../../Data_Fragmentation/buffer/buffer_frag_interface.sv}
    vlog -work work {../../../Arbiter/Sequence_recorder/Tx_Arbiter_Interface.sv}
     vlog -work work {../../../Data_Fragmentation/Controller/Fragmentation_Interface.sv}
    vlog -work work {../../../Arbiter/Sequence_recorder/Tx_Arbiter.sv}
    vlog -work work {../../../Arbiter/Sequence_recorder/Sequence_Recorder.sv}

    vlog -work work {../../../Arbiter/Flow_Control/Tx_FC_Interface.sv}
    vlog -work work {../../../Arbiter/Flow_Control/Tx_FC.sv}

    vlog -work work {../../../Arbiter/Ordering/ordering_if.sv}
    vlog -work work {../../../Arbiter/Ordering/ordering.sv}
        
    vlog -work work {../../../Arbiter/Controller/arbiter_fsm.sv}
    vlog -work work {../../../Data_Fragmentation/buffer/buffer_frag.sv}


####################### Compile Top Design and its TB #######################
    vlog -work work {../../../Arbiter/Intgerated/arbiter_Top.sv}
    vlog -work work {../../../Arbiter/Intgerated/arbiter_Top_tb.sv}

####################### Run Simulation #######################
    vsim -novopt -sv_seed random work.arbiter_Top_tb
    do {Arbiter_waveform.do}
    
run -all