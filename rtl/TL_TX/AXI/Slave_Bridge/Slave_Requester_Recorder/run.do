quit -sim
vlog -work work {../../../AXI/Slave_Package/axi_slave_package.sv}
vlog -work work {../../../AXI/Slave_Bridge/Slave_Requester_Recorder/dual_port_ram_if.sv}
vlog -work work {../../../AXI/Slave_Bridge/Slave_Requester_Recorder/dual_port_ram.sv}
vlog -work work {../../../AXI/Slave_Bridge/Slave_Requester_Recorder/dual_port_ram_tb.sv}

vsim -novopt -sv_seed random work.dual_port_ram_tb
do {../../../AXI/Slave_Bridge/Slave_Requester_Recorder/wave.do}
    
run -all

