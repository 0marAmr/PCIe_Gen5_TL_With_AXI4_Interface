################################# Define Top Module #################################
    set design data_frag_top

################################# Set Search Path ###################################
    set_app_var search_path /home/ICer/Desktop/Final-Project/SAED32_2012-12-25/lib/stdcell_hvt/db_nldm
    # /home/ICer/Desktop/AUC_ASIC_Final/lib
    set_app_var target_library	"saed32hvt_ff0p95v125c.db" # "saed90nm_max_lth.db"
    set_app_var link_library	"* $target_library"
 
################################# Create Work Directory #############################
    sh rm -rf work
    sh mkdir -p work
    define_design_lib work -path ./work

################################# Read Files ######################
    ################################# Packages ########################
        analyze -library WORK -format sverilog ../../../Arbiter/Package/Tx_Arbiter_Package.sv
        analyze -library WORK -format sverilog ../../../AXI/Slave_Package/axi_slave_package.sv
        analyze -library WORK -format sverilog ../../../Data_Fragmentation/package/Fragmentation_Package.sv

    ################################# AXI ########################
        # analyze -library WORK -format sverilog ../../../AXI/Slave_Bridge/Slave_Requester_Recorder/Request_Recorder_if.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Internal_Response/Slave_Internal_Response_if.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Request_Path/Push_Fsms/axi_if.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave_FIFOs/Sync_FIFO_Interface.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Response_Path/Push_FSM/Up_Down_Counter/Up_Down_Counter_Interface.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Response_Path/Pop_FSM/Master_Interface.sv


        # analyze -library WORK -format sverilog ../../../AXI/Slave_Bridge/Slave_Requester_Recorder/Request_Recorder.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Request_Path/Push_Fsms/axi_slave_fsm_wr.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Request_Path/Push_Fsms/axi_slave_fsm_rd.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave_FIFOs/Sync_FIFO.sv


        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Request_Path/Pop_Fsms/fifo_pop_wr.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Request_Path/Pop_Fsms/fifo_pop_rd.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave_Bridge/A2P_Mapper/wr_atop.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave_Bridge/A2P_Mapper/rd_atop.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Response_Path/Push_FSM/Up_Down_Counter/Up_Down_Counter.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Response_Path/Push_FSM/Response_Push_FSM.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Response_Path/Pop_FSM/Response_Pop_FSM.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave_Bridge/P2A_Mapper/P2A_Interface.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave_Bridge/P2A_Mapper/P2A.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave_Bridge/Slave_Requester_Recorder/wr_interface_mux.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Internal_Response/slave_internal_response_rd_mux.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Internal_Response/slave_internal_response_wr_mux.sv


        # analyze -library WORK -format sverilog ../../../AXI/Slave_Top/Slave_Top.sv

        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Request_Path/Push_Fsms/axi_slave_fsm_tb.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Response_Path/Push_FSM/Up_Down_Counter/Up_Down_Counter_tb.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave/Slave_Response_Path/Push_FSM/Up_Down_Counter/Up_Down_Counter_Top.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave_Bridge/Slave_Requester_Recorder/dual_port_ram_tb.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave_Package/axi_slave_package.sv
        # analyze -library WORK -format sverilog ../../../AXI/Slave_Top/TestBench/Slave_tb.sv

    ################################# Arbiter ########################
        # analyze -library WORK -format sverilog ../../../Arbiter/Sequence_recorder/Tx_Arbiter_Interface.sv
        # analyze -library WORK -format sverilog ../../../Arbiter/Flow_Control/Tx_FC_Interface.sv
        # analyze -library WORK -format sverilog ../../../Arbiter/Ordering/ordering_if.sv

        # analyze -library WORK -format sverilog ../../../Arbiter/Sequence_recorder/Tx_Arbiter.sv
        # analyze -library WORK -format sverilog ../../../Arbiter/Flow_Control/Tx_FC.sv
        # analyze -library WORK -format sverilog ../../../Arbiter/Sequence_recorder/Sequence_Recorder.sv
        # analyze -library WORK -format sverilog ../../../Arbiter/Ordering/ordering.sv
        # analyze -library WORK -format sverilog ../../../Arbiter/Controller/arbiter_fsm.sv

        # analyze -library WORK -format sverilog ../../../Arbiter/Intgerated/arbiter_Top.sv

    ################################# Fragmentation ########################
        analyze -library WORK -format sverilog ../../../Data_Fragmentation/buffer/buffer_frag_interface.sv
        analyze -library WORK -format sverilog ../../../Data_Fragmentation/Controller/Fragmentation_Interface.sv
        analyze -library WORK -format sverilog ../../../Data_Fragmentation/buffer/buffer_frag.sv
        analyze -library WORK -format sverilog ../../../Data_Fragmentation/ECRC/ECRC.sv
        analyze -library WORK -format sverilog ../../../Data_Fragmentation/Controller/Frag.sv
        
        analyze -library WORK -format sverilog ../../../Data_Fragmentation/Integrated/data_frag_top.sv


        # analyze -library WORK -format sverilog ../../../Data_Fragmentation/buffer/buffer_frag_tb.sv
        # analyze -library WORK -format sverilog ../../../Data_Fragmentation/Controller/Fragmentation.sv
        # analyze -library WORK -format sverilog ../../../Data_Fragmentation/Controller/Fragmentation_Top.sv
        # analyze -library WORK -format sverilog ../../../Data_Fragmentation/ECRC/ecrc_if.sv
        # analyze -library WORK -format sverilog ../../../Data_Fragmentation/Fragmentation_Top.sv
        # analyze -library WORK -format sverilog ../../../Data_Fragmentation/package/Fragmentation_Package.sv
        # analyze -library WORK -format sverilog ../../../Data_Fragmentation/TLP_Buffer/buffer_frag.sv
        # analyze -library WORK -format sverilog ../../../Data_Fragmentation/TLP_Buffer/buffer_frag_interface.sv
        # analyze -library WORK -format sverilog ../../../pcie_tl.sv
        # analyze -library WORK -format sverilog ../../../tb.sv
        # analyze -library WORK -format sverilog ../../../TX_Top/tl_tx.sv
        # analyze -library WORK -format sverilog ../../../TX_Top/tl_tx_tb.sv


    ################################# Top Design ########################
    # analyze -library WORK -format sverilog ../../../TX_Top/tl_tx.sv


################################# Analyze and Elaborate Design ######################
# read_file -format verilog regfile.v
# analyze -library work -format verilog ../../../rtl/${design}.v
elaborate $design -library work

################################# Check Design #####################################
current_design $design
check_design

################################# Read Cons File ###################################
# source  -echo -verbose /home/ICer/Desktop/AUC_ASIC_Final/syn/Syn_Cons.tcl

################################## Link Design ######################################
link

################################## multi driven ports ###############################
# set_fix_multiple_port_nets -all

################################## Compile ##########################################
compile -map_effort medium

################################## Reports ##########################################
sh rm -rf report
sh mkdir -p report
report_area 			> ./report/synth_area.rpt
report_cell 			> ./report/synth_cells.rpt
report_qor  			> ./report/synth_qor.rpt
report_resources 		> ./report/synth_resources.rpt
report_timing -max_paths 10 	> ./report/synth_timing_setup.rpt 
# report_timing -min_paths 10 	> ./report/synth_timing_hold.rpt 

################################## Write SDC File ####################################
sh rm -rf output
sh mkdir -p output 
write_sdc  output/${design}.sdc 

define_name_rules  no_case -case_insensitive
change_names -rule no_case -hierarchy
change_names -rule verilog -hierarchy
set verilogout_no_tri	 true
set verilogout_equation  false

################################## Write Netlist #####################################
write -hierarchy -format verilog -output output/${design}.v 
write -f ddc -hierarchy -output output/${design}.ddc  
# start_gui
# exit
