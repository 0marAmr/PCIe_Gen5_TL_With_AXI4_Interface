# Close Previous Simulation
quit -sim 

####################### Ahmady Files #######################
    vlog -work work {../../../AXI/Slave_Package/axi_slave_package.sv}
    vlog -work work {../../../Arbiter/Package/Tx_Arbiter_Package.sv}
    vlog -work work {../../../Data_Fragmentation/package/Fragmentation_Package.sv}
    vlog -work work {../../../Data_Fragmentation/buffer/buffer_frag.sv}    
    vlog -work work {../../../Data_Fragmentation/buffer/buffer_frag_interface.sv}    
    vlog -work work {../../../Data_Fragmentation/ECRC/ECRC.sv}
    vlog -work work {../../../Data_Fragmentation/Controller/Fragmentation_Interface.sv}
    vlog -work work {../../../Data_Fragmentation/Controller/Frag.sv}


####################### Compile Top Design and its TB #######################
    vlog -work work {../../../Data_Fragmentation/Fragmentation_Top.sv}
    # vlog -work work {../../../Data_Fragmentation/Integrated/data_frag_top.sv}

####################### Run Simulation #######################
    vsim -novopt -sv_seed random work.Fragmentation_Top
    # vsim -novopt -sv_seed random work.data_frag_Top
    do {Frag.do}
    
run -all