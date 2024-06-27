
####################################################################################
# Constraints
#--
#
# 0. Design Compiler variables
#
# 1. Master Clock Definitions
#
# 2. Generated Clock Definitions
#
# 3. Clock Uncertainties
#
# 4. Clock Latencies 
#
# 5. Clock Relationships
#
# 6. #set input/output delay on ports
#
# 7. Driving cells
#
# 8. Output load

####################################################################################
           #########################################################
                  #### Section 0 : DC Variables ####
           #########################################################
#################################################################################### 

# Prevent assign statements in the generated netlist (must be applied before compile command)
set_fix_multiple_port_nets -all -buffer_constants -feedthroughs

#################################################################################### 
           #########################################################
                  #### Section 1 : Clock Definition ####
           #########################################################
#################################################################################### 
# 1. Master Clock Definitions 
# 2. Generated Clock Definitions
# 3. Clock Latencies
# 4. Clock Uncertainties
# 4. Clock Transitions
####################################################################################

set CLK_NAME i_clk
set CLK_PER 8
set CLK_SETUP_SKEW 0.1
set CLK_HOLD_SKEW  0.1
set CLK_LAT 0
set CLK_RISE 0.05
set CLK_FALL 0.05

create_clock -name $CLK_NAME -period $CLK_PER -waveform "0 [expr $CLK_PER/2]" [get_ports i_pcie_clk]
create_clock -name $CLK_NAME -period $CLK_PER -waveform "0 [expr $CLK_PER/2]" [get_ports i_axi_clk]
set_clock_uncertainty -setup $CLK_SETUP_SKEW [get_clocks $CLK_NAME]
set_clock_uncertainty -hold $CLK_HOLD_SKEW  [get_clocks $CLK_NAME]
set_clock_transition -rise $CLK_RISE  [get_clocks $CLK_NAME]
set_clock_transition -fall $CLK_FALL  [get_clocks $CLK_NAME]
set_clock_latency $CLK_LAT [get_clocks $CLK_NAME]

set_dont_touch_network {i_pcie_clk i_axi_clk i_pcie_n_rst i_axi_n_rst}

####################################################################################
           #########################################################
                  #### Section 2 : Area and Power constraints ####
           #########################################################
####################################################################################
#set_max_area 0
#set_max_dynamic_power 0
#set_max_leakage_power 0


####################################################################################
           #########################################################
             #### Section 3 : #set input/output delay on ports ####
           #########################################################
####################################################################################

set in_delay  [expr 0.2*$CLK_PER]
set out_delay [expr 0.2*$CLK_PER]

#Constrain Input Paths

############ Config Space Interface ############
set_input_delay $in_delay -clock $CLK_NAME [get_port i_cfg_ecrc_chk_en]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_cfg_memory_space_en]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_cfg_io_space_en]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_cfg_max_payload_size]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_cfg_BARs]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_cfg_space_data]
 #/*Error Handler*/#
set_input_delay $in_delay -clock $CLK_NAME [get_port i_cfg_uc_status_reg]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_cfg_uc_severity_reg]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_cfg_uc_mask_reg]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_cfg_command_reg_serr_en]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_cfg_command_reg_parity_err_resp]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_cfg_device_ctrl_reg]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_cfg_advisory_nf_err_mask]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_cfg_first_err_ptr]


############ TL TX Arbiter Interface - Read Handler: Msg-Cpl Generator ############
set_input_delay $in_delay -clock $CLK_NAME [get_port i_tx_core_cpl_ack]

############ TL TX Arbiter Interface - Master Completion Generator ############
set_input_delay $in_delay -clock $CLK_NAME [get_port i_tx_m_cpl_arbiter_ready]

############ DLL-RX TLP Interface  ############
set_input_delay $in_delay -clock $CLK_NAME [get_port i_dll_rx_sop]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_dll_rx_tlp]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_dll_rx_eop]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_dll_rx_last_dw]


############ DLL-TX Flow Control Interface  ############
set_input_delay $in_delay -clock $CLK_NAME [get_port i_dll_ctrl_fc_init]

############ AXI Slave (Application) Interface ############
set_input_delay $in_delay -clock $CLK_NAME [get_port i_s_AWREADY]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_s_WREADY]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_s_BVALID]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_s_BID]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_s_BRESP]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_s_ARREADY]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_s_RID]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_s_RRESP]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_s_RLAST]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_s_RVALID]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_R_CHANNEL_data]
set_input_delay $in_delay -clock $CLK_NAME [get_port i_slave_ready]


#Constrain Output Paths

############ Config Space Interface ############
set_output_delay $out_delay -clock $CLK_NAME [get_port o_cfg_ecrc_chk_capable]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_cfg_write_en]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_cfg_write_data]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_cfg_address]
 #/*Error Handler*/#
set_output_delay $out_delay -clock $CLK_NAME [get_port o_cfg_status_reg]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_cfg_master_data_parity_err]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_cfg_device_status_reg]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_cfg_advisory_nf_err_status]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_cfg_uc_status_reg]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_cfg_multiple_hdr_capable]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_cfg_first_err_ptr]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_cfg_hdr_log_en]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_cfg_hdr]

############ TL_TX Interface ############
set_output_delay $out_delay -clock $CLK_NAME [get_port o_device_bdf]

############ TL TX Arbiter Interface - Master Completion Generator ############
set_output_delay $out_delay -clock $CLK_NAME [get_port o_tx_m_cpl_valid]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_tx_m_cpl_hdr]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_tx_m_cpl_data]


############ TL TX Arbiter Interface - Read Handler: Msg-Cpl Generator ############
set_output_delay $out_delay -clock $CLK_NAME [get_port o_tx_core_cpl_hdr]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_tx_core_cpl_data]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_tx_core_msg]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_tx_core_ctrl]

############  DLL-RX TLP Interface ############
set_output_delay $out_delay -clock $CLK_NAME [get_port o_dll_rx_tlp_discard]

############  -DLL-TX Flow Control Interface  ############
set_output_delay $out_delay -clock $CLK_NAME [get_port o_dll_tx_fc_hdr_creds]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_dll_tx_fc_data_creds]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_dll_tx_fc_type]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_dll_tx_fc_creds_valid]

############  -AXI Slave (Application) Interface ############
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_AWID]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_AWADDR]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_AWLEN]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_AWSIZE]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_AWBURST]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_AWPROT]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_AWVALID]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_WVALID]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_WLAST]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_WSTRB]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_WDATA]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_BREADY]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_ARID]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_ARADDR]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_ARLEN]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_ARSIZE]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_ARBURST]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_ARPROT]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_ARVALID]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_s_RREADY]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_vc_cpl_data]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_vc_cpl_hdr]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_slave_cpl_vaild]
set_output_delay $out_delay -clock $CLK_NAME [get_port o_slave_cpl_valid_data]


####################################################################################
           #########################################################
                  #### Section 4 : Driving cells ####
           #########################################################
####################################################################################

############ Config Space Interface ############
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_cfg_ecrc_chk_en]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_cfg_memory_space_en]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_cfg_io_space_en]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_cfg_max_payload_size]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_cfg_BARs]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_cfg_space_data]
 #/*Error Handler*/#
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_cfg_uc_status_reg]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_cfg_uc_severity_reg]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_cfg_uc_mask_reg]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_cfg_command_reg_serr_en]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_cfg_command_reg_parity_err_resp]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_cfg_device_ctrl_reg]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_cfg_advisory_nf_err_mask]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_cfg_first_err_ptr]

############ TL TX Arbiter Interface - Read Handler: Msg-Cpl Generator ############
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_tx_core_cpl_ack]

############ TL TX Arbiter Interface - Master Completion Generator ############
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_tx_m_cpl_arbiter_ready]

############ DLL-RX TLP Interface  ############
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_dll_rx_sop]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_dll_rx_tlp]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_dll_rx_eop]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_dll_rx_last_dw]


############ DLL-TX Flow Control Interface  ############
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_dll_ctrl_fc_init]

############ AXI Slave (Application) Interface ############
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_s_AWREADY]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_s_WREADY]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_s_BVALID]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_s_BID]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_s_BRESP]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_s_ARREADY]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_s_RID]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_s_RRESP]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_s_RLAST]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_s_RVALID]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_R_CHANNEL_data]
set_driving_cell -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c -lib_cell BUFX2M -pin Y [get_port i_slave_ready]

##################################################################

####################################################################################
           #########################################################
                  #### Section 5 : Output load ####
           #########################################################
####################################################################################

############ Config Space Interface ############
set_load 0.01 [get_port o_cfg_ecrc_chk_capable]
set_load 0.01 [get_port o_cfg_write_en]
set_load 0.01 [get_port o_cfg_write_data]
set_load 0.01 [get_port o_cfg_address]
 #/*Error Handler*/#
set_load 0.01 [get_port o_cfg_status_reg]
set_load 0.01 [get_port o_cfg_master_data_parity_err]
set_load 0.01 [get_port o_cfg_device_status_reg]
set_load 0.01 [get_port o_cfg_advisory_nf_err_status]
set_load 0.01 [get_port o_cfg_uc_status_reg]
set_load 0.01 [get_port o_cfg_multiple_hdr_capable]
set_load 0.01 [get_port o_cfg_first_err_ptr]
set_load 0.01 [get_port o_cfg_hdr_log_en]
set_load 0.01 [get_port o_cfg_hdr]

############ TL_TX Interface ############
set_load 0.01 [get_port o_device_bdf]

############ TL TX Arbiter Interface - Master Completion Generator ############
set_load 0.01 [get_port o_tx_m_cpl_valid]
set_load 0.01 [get_port o_tx_m_cpl_hdr]
set_load 0.01 [get_port o_tx_m_cpl_data]

############ TL TX Arbiter Interface - Read Handler: Msg-Cpl Generator ############
set_load 0.01 [get_port o_tx_core_cpl_hdr]
set_load 0.01 [get_port o_tx_core_cpl_data]
set_load 0.01 [get_port o_tx_core_msg]
set_load 0.01 [get_port o_tx_core_ctrl]

############  DLL-RX TLP Interface ############
set_load 0.01 [get_port o_dll_rx_tlp_discard]

############  -DLL-TX Flow Control Interface  ############
set_load 0.01 [get_port o_dll_tx_fc_hdr_creds]
set_load 0.01 [get_port o_dll_tx_fc_data_creds]
set_load 0.01 [get_port o_dll_tx_fc_type]
set_load 0.01 [get_port o_dll_tx_fc_creds_valid]

############  -AXI Slave (Application) Interface ############
set_load 0.01 [get_port o_s_AWID]
set_load 0.01 [get_port o_s_AWADDR]
set_load 0.01 [get_port o_s_AWLEN]
set_load 0.01 [get_port o_s_AWSIZE]
set_load 0.01 [get_port o_s_AWBURST]
set_load 0.01 [get_port o_s_AWPROT]
set_load 0.01 [get_port o_s_AWVALID]
set_load 0.01 [get_port o_s_WVALID]
set_load 0.01 [get_port o_s_WLAST]
set_load 0.01 [get_port o_s_WSTRB]
set_load 0.01 [get_port o_s_WDATA]
set_load 0.01 [get_port o_s_BREADY]
set_load 0.01 [get_port o_s_ARID]
set_load 0.01 [get_port o_s_ARADDR]
set_load 0.01 [get_port o_s_ARLEN]
set_load 0.01 [get_port o_s_ARSIZE]
set_load 0.01 [get_port o_s_ARBURST]
set_load 0.01 [get_port o_s_ARPROT]
set_load 0.01 [get_port o_s_ARVALID]
set_load 0.01 [get_port o_s_RREADY]
set_load 0.01 [get_port o_vc_cpl_data]
set_load 0.01 [get_port o_vc_cpl_hdr]
set_load 0.01 [get_port o_slave_cpl_vaild]
set_load 0.01 [get_port o_slave_cpl_valid_data]

####################################################################################
           #########################################################
                 #### Section 6 : Operating Condition ####
           #########################################################
####################################################################################

# Define the Worst Library for Max(#setup) analysis
# Define the Best Library for Min(hold) analysis

set_operating_conditions -min_library "scmetro_tsmc_cl013g_rvt_ff_1p32v_m40c" -min "scmetro_tsmc_cl013g_rvt_ff_1p32v_m40c" -max_library "scmetro_tsmc_cl013g_rvt_ss_1p08v_125c" -max "scmetro_tsmc_cl013g_rvt_ss_1p08v_125c"

####################################################################################
           #########################################################
                  #### Section 7 : wireload Model ####
           #########################################################
####################################################################################

#set_wire_load_model -name tsmc13_wl30 -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c

####################################################################################
