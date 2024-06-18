
# Close Previous Simulation
quit -sim 

####################### Alaa Files #######################
    # Compile Package First
    vlog -work work {../../../AXI/Slave_Package/axi_slave_package.sv}
    
    # Compile the dual port ram with its interface 
    vlog -work work {../../../AXI/Slave_Bridge/Slave_Requester_Recorder/Request_Recorder_if.sv}
    vlog -work work {../../../AXI/Slave_Bridge/Slave_Requester_Recorder/Request_Recorder.sv}
    
    vlog -work work {../../../AXI/Slave/Slave_Internal_Response/Slave_Internal_Response_if.sv}
    
    # Compile Slave Request Path: Push FSM 
    vlog -work work {../../../AXI/Slave/Slave_Request_Path/Push_Fsms/axi_if.sv}
    # Need to Compile P2A Interface Here because it is used inside PUSH FSM
    vlog -work work {../../../AXI/Slave/Slave_Request_Path/Push_Fsms/axi_slave_fsm_wr.sv}
    vlog -work work {../../../AXI/Slave/Slave_Request_Path/Push_Fsms/axi_slave_fsm_rd.sv}

    # Compile Requests FIFOs 
    vlog -work work {../../../AXI/Slave_FIFOs/Sync_FIFO_Interface.sv}
    vlog -work work {../../../AXI/Slave_FIFOs/Sync_FIFO.sv}

    # Compile Slave Request Path: Pop FSM 
    vlog -work work {../../../AXI/Slave/Slave_Request_Path/Pop_Fsms/fifo_pop_wr.sv}
    vlog -work work {../../../AXI/Slave/Slave_Request_Path/Pop_Fsms/fifo_pop_rd.sv}

    # Compile Slave Request Path: A2P Mapper 
    vlog -work work {../../../AXI/Slave_Bridge/A2P_Mapper/wr_atop.sv}
    vlog -work work {../../../AXI/Slave_Bridge/A2P_Mapper/rd_atop.sv}

####################### Ahmady Files #######################
    # Compile Slave Response Path: Up Down Counter
    vlog -work work {../../../AXI/Slave/Slave_Response_Path/Push_FSM/Up_Down_Counter/Up_Down_Counter_Interface.sv}
    vlog -work work {../../../AXI/Slave/Slave_Response_Path/Push_FSM/Up_Down_Counter/Up_Down_Counter.sv}

    # Compile Slave Response Path: Push FSM
    vlog -work work {../../../AXI/Slave/Slave_Response_Path/Push_FSM/Response_Push_FSM.sv}

    # Compile Slave Response Path: Pop FSM 
    vlog -work work {../../../AXI/Slave/Slave_Response_Path/Pop_FSM/Master_Interface.sv}
    vlog -work work {../../../AXI/Slave/Slave_Response_Path/Pop_FSM/Response_Pop_FSM.sv}

    # Compile Slave Response Path: P2A Mapper 
    vlog -work work {../../../AXI/Slave_Bridge/P2A_Mapper/P2A_Interface.sv}
    vlog -work work {../../../AXI/Slave_Bridge/P2A_Mapper/P2A.sv}
    
    # Compile Request Recorder Interface Mux
    vlog -work work {../../../AXI/Slave_Bridge/Slave_Requester_Recorder/wr_interface_mux.sv}
    
    # Compile Slave Internal Response Muxs
    vlog -work work {../../../AXI/Slave/Slave_Internal_Response/slave_internal_response_rd_mux.sv}
    vlog -work work {../../../AXI/Slave/Slave_Internal_Response/slave_internal_response_wr_mux.sv}

####################### Compile Top Design and its TB #######################
    vlog -work work {../../../AXI/Slave_Top/Slave_Top.sv}
    vlog -work work {../../../AXI/Slave_Top/TestBench/Slave_tb.sv}

####################### Run Simulation #######################
    vsim -novopt -sv_seed 2262425633 work.Slave_tb
     
    do {../waveform.do}

run -all