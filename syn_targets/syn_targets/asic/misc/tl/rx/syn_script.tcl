########################### Define Top Module ############################
                                                   
set top_module tl_rx

##################### Define Working Library Directory ######################
                                                   
define_design_lib work -path ./work

################## Design Compiler Library Files #setup ######################

puts "###########################################"
puts "#      #setting Design Libraries           #"
puts "###########################################"

set PROJECT_PATH  /home/IC/PCIe-V5/rtl
set LIB_PATH      /home/IC/tsmc_fb_cl013g_sc/aci/sc-m

# Libraries Path
lappend search_path $LIB_PATH/synopsys
# TL Rx Paths
lappend search_path $PROJECT_PATH/pcie_tl/Rx/packages
lappend search_path $PROJECT_PATH/pcie_tl/Rx/rtl
lappend search_path $PROJECT_PATH/pcie_tl/Rx/rtl/axi_interface
lappend search_path $PROJECT_PATH/pcie_tl/Rx/rtl/master_bridge
lappend search_path $PROJECT_PATH/pcie_tl/Rx/rtl/master_bridge/async_fifo
lappend search_path $PROJECT_PATH/pcie_tl/Rx/rtl/pcie_core
lappend search_path $PROJECT_PATH/pcie_tl/Rx/rtl/pcie_core/cpl_gen
lappend search_path $PROJECT_PATH/pcie_tl/Rx/rtl/pcie_core/error_handler
lappend search_path $PROJECT_PATH/pcie_tl/Rx/rtl/pcie_core/fc
lappend search_path $PROJECT_PATH/pcie_tl/Rx/rtl/pcie_core/read_handler
lappend search_path $PROJECT_PATH/pcie_tl/Rx/rtl/pcie_core/read_handler/read_request
lappend search_path $PROJECT_PATH/pcie_tl/Rx/rtl/pcie_core/read_handler/msg_cpl_gen
lappend search_path $PROJECT_PATH/pcie_tl/Rx/rtl/pcie_core/vc
lappend search_path $PROJECT_PATH/pcie_tl/Rx/rtl/pcie_core/write_handler
lappend search_path $PROJECT_PATH/pcie_tl/Rx/rtl/pcie_core/write_handler/error_check
# TL Tx Paths
#continue here ...

set SSLIB "scmetro_tsmc_cl013g_rvt_ss_1p08v_125c.db"
set TTLIB "scmetro_tsmc_cl013g_rvt_tt_1p2v_25c.db"
set FFLIB "scmetro_tsmc_cl013g_rvt_ff_1p32v_m40c.db"

## Standard Cell libraries 
set target_library [list $SSLIB $TTLIB $FFLIB]

## Standard Cell & Hard Macros libraries 
set link_library [list * $SSLIB $TTLIB $FFLIB]  

######################## Reading RTL Files #################################
set verilog_fmt verilog
set sverilog_fmt sverilog

puts "#####################################################################"
puts "############################ TL Rx FILES ############################"
puts "#####################################################################"

#--------packages---------#
analyze -format $sverilog_fmt pcie_core_pkg.sv
analyze -format $sverilog_fmt axi_pkg.sv
#--------pcie_ core files---------#
# cpl_gen files
analyze -format $sverilog_fmt cpl_gen.sv
# error_ handler files
analyze -format $verilog_fmt cfg_space_reporter.v
analyze -format $verilog_fmt error_handler.v
analyze -format $verilog_fmt fifo.v
# fc files
analyze -format $verilog_fmt creds_conv.v
analyze -format $verilog_fmt fc.v
analyze -format $verilog_fmt fc_counters.v
analyze -format $verilog_fmt fc_data.v
analyze -format $verilog_fmt fc_hdr.v
# read_ handler file
analyze -format $verilog_fmt read_handler.v
# msg_cpl_gen
analyze -format $verilog_fmt msg_cpl_gen.v
analyze -format $verilog_fmt cfg_err_cpl_gen.v
analyze -format $verilog_fmt msg_cpl_fsm.v 
# read_request files
analyze -format $verilog_fmt read_request.v
analyze -format $verilog_fmt config_handle.v
analyze -format $verilog_fmt data_handle.v
analyze -format $verilog_fmt fsm.v
analyze -format $verilog_fmt rw_hdr.v
# read_completion files
analyze -format $verilog_fmt read_completion.v
# VC files
analyze -format $verilog_fmt buffer.v
analyze -format $verilog_fmt buffer_control.v
analyze -format $verilog_fmt data_buffer.v
analyze -format $verilog_fmt hdr_buffer.v
analyze -format $verilog_fmt sequence_buffer.v
analyze -format $verilog_fmt vc.v
# write_handler files
analyze -format $verilog_fmt ecrc_check.v
analyze -format $verilog_fmt tlp_processing.v
analyze -format $sverilog_fmt error_check.sv
# error check files
analyze -format $verilog_fmt malformed.v
analyze -format $verilog_fmt receiever_overflow.v
analyze -format $verilog_fmt receiver_overflow_top.v
analyze -format $verilog_fmt unexpected_cpl.v
analyze -format $verilog_fmt unsupported_req.v
analyze -format $sverilog_fmt write_handler.sv
# pcie_core top
analyze -format $sverilog_fmt pcie_core.sv
#-----------master_bridge files--------#
# async fifo files
analyze -format $verilog_fmt async_fifo.v
analyze -format $verilog_fmt bit_sync.v
analyze -format $verilog_fmt read.v
analyze -format $verilog_fmt storage.v
analyze -format $verilog_fmt write.v
analyze -format $sverilog_fmt r_channel_async_fifo.sv
# sync fifo
analyze -format $verilog_fmt mb_sync_fifo.v
# mapping blocks
analyze -format $sverilog_fmt axi_to_pcie_map.sv
analyze -format $sverilog_fmt master_bridge.sv
# master bridge top
analyze -format $sverilog_fmt pcie_to_axi_map.sv
#----------axi_interface-------#
analyze -format $sverilog_fmt request_control.sv
analyze -format $sverilog_fmt response_control.sv
analyze -format $sverilog_fmt strobe_decoder.sv
# axi master top
analyze -format $sverilog_fmt axi_master.sv
#------tl_rx top-----#
analyze -format $sverilog_fmt tl_rx.sv

elaborate -lib work tl_rx

###################### Defining toplevel ###################################

current_design $top_module

#################### Liniking All The Design Parts #########################
puts "###############################################"
puts "######## Liniking All The Design Parts ########"
puts "###############################################"

link 

#################### Liniking All The Design Parts #########################
puts "###############################################"
puts "######## checking design consistency ##########"
puts "###############################################"

check_design >> reports/tl_rx_check_design.rpt

#################### Define Design Constraints #########################
puts "###############################################"
puts "############ Design Constraints #### ##########"
puts "###############################################"


source -echo ./constraints.tcl

###################### Mapping and optimization ########################
puts "###############################################"
puts "########## Mapping & Optimization #############"
puts "###############################################"

#compile 
compile -map_effort high
#compile_ultra -no_auto_ungroup

#compile -ungroup_all 

#############################################################################
# Write out Design after initial compile
#############################################################################

#Avoid Writing assign statements in the netlist
change_name -hier -rule verilog

write_file -format verilog -hierarchy -output netlists/$top_module.ddc
write_file -format verilog -hierarchy -output netlists/$top_module.v
write_sdf  sdf/$top_module.sdf
write_sdc  -nosplit sdc/$top_module.sdc

####################### reporting ##########################################
report_area -hierarchy > reports/tl_rx_area.rpt
report_power -hierarchy > reports/tl_rx_power.rpt
report_timing -delay_type min -max_paths 200 > reports/tl_rx_hold.rpt
report_timing -delay_type max -max_paths 200 > reports/tl_rx_setup.rpt
report_clock -attributes > reports/tl_rx_clocks.rpt
report_constraint -all_violators -nosplit > reports/tl_rx_constraints.rpt


################# starting graphical user interface #######################

#gui_start

#exit
