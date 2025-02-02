onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /dual_port_ram_tb/u_Request_Recorder/clk
add wave -noupdate /dual_port_ram_tb/u_Request_Recorder/ARESTn
add wave -noupdate /dual_port_ram_tb/__if/req_wr_en
add wave -noupdate -radix unsigned /dual_port_ram_tb/__if/req_wr_addr
add wave -noupdate -radix hexadecimal -childformat {{{/dual_port_ram_tb/__if/req_wr_data[4]} -radix hexadecimal} {{/dual_port_ram_tb/__if/req_wr_data[3]} -radix hexadecimal} {{/dual_port_ram_tb/__if/req_wr_data[2]} -radix hexadecimal} {{/dual_port_ram_tb/__if/req_wr_data[1]} -radix hexadecimal} {{/dual_port_ram_tb/__if/req_wr_data[0]} -radix hexadecimal}} -subitemconfig {{/dual_port_ram_tb/__if/req_wr_data[4]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/__if/req_wr_data[3]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/__if/req_wr_data[2]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/__if/req_wr_data[1]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/__if/req_wr_data[0]} {-height 15 -radix hexadecimal}} /dual_port_ram_tb/__if/req_wr_data
add wave -noupdate -radix unsigned /dual_port_ram_tb/__if/req_rd_addr
add wave -noupdate -radix hexadecimal -childformat {{{/dual_port_ram_tb/__if/req_rd_data[4]} -radix hexadecimal} {{/dual_port_ram_tb/__if/req_rd_data[3]} -radix hexadecimal} {{/dual_port_ram_tb/__if/req_rd_data[2]} -radix hexadecimal} {{/dual_port_ram_tb/__if/req_rd_data[1]} -radix hexadecimal} {{/dual_port_ram_tb/__if/req_rd_data[0]} -radix hexadecimal}} -subitemconfig {{/dual_port_ram_tb/__if/req_rd_data[4]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/__if/req_rd_data[3]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/__if/req_rd_data[2]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/__if/req_rd_data[1]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/__if/req_rd_data[0]} {-height 15 -radix hexadecimal}} /dual_port_ram_tb/__if/req_rd_data
add wave -noupdate /dual_port_ram_tb/__if/resp_wr_en
add wave -noupdate -radix unsigned /dual_port_ram_tb/__if/resp_wr_addr
add wave -noupdate -radix hexadecimal /dual_port_ram_tb/__if/resp_wr_data
add wave -noupdate -radix unsigned /dual_port_ram_tb/__if/resp_rd_addr
add wave -noupdate -radix hexadecimal -childformat {{{/dual_port_ram_tb/__if/resp_rd_data[4]} -radix hexadecimal} {{/dual_port_ram_tb/__if/resp_rd_data[3]} -radix hexadecimal} {{/dual_port_ram_tb/__if/resp_rd_data[2]} -radix hexadecimal} {{/dual_port_ram_tb/__if/resp_rd_data[1]} -radix hexadecimal} {{/dual_port_ram_tb/__if/resp_rd_data[0]} -radix hexadecimal}} -subitemconfig {{/dual_port_ram_tb/__if/resp_rd_data[4]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/__if/resp_rd_data[3]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/__if/resp_rd_data[2]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/__if/resp_rd_data[1]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/__if/resp_rd_data[0]} {-height 15 -radix hexadecimal}} /dual_port_ram_tb/__if/resp_rd_data
add wave -noupdate -radix hexadecimal -childformat {{{/dual_port_ram_tb/u_Request_Recorder/MEM[0]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[1]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[2]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[3]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[4]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[5]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[6]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[7]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[8]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[9]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[10]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[11]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[12]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[13]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[14]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[15]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[16]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[17]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[18]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[19]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[20]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[21]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[22]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[23]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[24]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[25]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[26]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[27]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[28]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[29]} -radix hexadecimal} {{/dual_port_ram_tb/u_Request_Recorder/MEM[30]} -radix hexadecimal}} -expand -subitemconfig {{/dual_port_ram_tb/u_Request_Recorder/MEM[0]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[1]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[2]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[3]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[4]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[5]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[6]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[7]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[8]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[9]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[10]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[11]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[12]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[13]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[14]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[15]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[16]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[17]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[18]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[19]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[20]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[21]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[22]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[23]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[24]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[25]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[26]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[27]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[28]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[29]} {-height 15 -radix hexadecimal} {/dual_port_ram_tb/u_Request_Recorder/MEM[30]} {-height 15 -radix hexadecimal}} /dual_port_ram_tb/u_Request_Recorder/MEM
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {29892 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ms
update
WaveRestoreZoom {0 ps} {231 ns}
