################################# Reset Design #################################
reset_design

################################# Create Clock  ################################
create_clock -name clk -period 1 [get_ports clk]

################################# Input/Output Delay  ##########################
set_input_delay  -max  0.3 -clock [get_clocks clk] [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay -max  0.3 -clock [get_clocks clk] [all_outputs]

################################# Tu model (skew, jitter, setup margin)#########
set_clock_uncertainty 0.04 [get_clocks]

################################# Netwrok Latency ##############################
set_clock_latency      0.04  [get_clocks clk]

################################# False Paths ##################################
set_false_path -hold -from [remove_from_collection [all_inputs] [get_ports clk]]
set_false_path -hold -to [all_outputs]

################################# WLM ##########################################
set_min_library  saed90nm_max_lth.db -min_version saed90nm_min_nt.db 
set_wire_load_model -name "8000" -library saed90nm_max_lth

# set_min_library  saed32hvt_ff0p95v125c.db -min_version saed90nm_min_nt.db
# set_wire_load_model -name "8000" -library saed32hvt_ff0p95v125c
# set_wire_load_mode enclosed

################################# Load Capacitance #############################
set_load -max [expr {2 * [load_of saed90nm_max_lth/NBUFFX8/INP]}] [all_outputs]
# set_load -max [expr {2 * [load_of saed32hvt_ff0p95v125c/NBUFFX8/INP]}] [all_outputs]

################################# Driving Cell #################################
set_driving_cell -no_design_rule -max -lib_cell TNBUFFX1 [remove_from_collection [all_inputs] [get_ports clk]]

################################# Comb Constraint ##############################
# create_clock -period 5 -name V_Clk
# set_input_delay -max 0.71 -clock V_Clk [get_ports wb_stb_i ]
# set_output_delay -max 1.14 -clock V_Clk [get_ports wb_ack_o]

################################# Path Groups ##############################
group_path -name INPUTS -from [remove_from_collection [all_inputs] [get_ports clk]]
group_path -name OUTPUTS -to [all_outputs]
group_path -name COMB -from [all_inputs] -to [all_outputs]


