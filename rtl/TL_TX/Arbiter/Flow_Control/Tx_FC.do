onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix unsigned /Tx_FC_Top/clk
add wave -noupdate -radix unsigned /Tx_FC_Top/arst
add wave -noupdate -expand -group {FC_Arbiter_if
} -radix unsigned /Tx_FC_Top/Tx_FC_if/PTLP_2
add wave -noupdate -expand -group {FC_Arbiter_if
} -radix unsigned /Tx_FC_Top/Tx_FC_if/PTLP_1
add wave -noupdate -expand -group {FC_Arbiter_if
} /Tx_FC_Top/Tx_FC_if/Command_2
add wave -noupdate -expand -group {FC_Arbiter_if
} /Tx_FC_Top/Tx_FC_if/Command_1
add wave -noupdate -expand -group {FC_Arbiter_if
} -radix unsigned /Tx_FC_Top/Tx_FC_if/Result
add wave -noupdate -expand -group CC_Registers -radix unsigned /Tx_FC_Top/u_Tx_FC/CC_Posted_Hdr
add wave -noupdate -expand -group CC_Registers -radix unsigned /Tx_FC_Top/u_Tx_FC/CC_Posted_Data
add wave -noupdate -expand -group CC_Registers -radix unsigned /Tx_FC_Top/u_Tx_FC/CC_NonPosted_Hdr
add wave -noupdate -expand -group CC_Registers -radix unsigned /Tx_FC_Top/u_Tx_FC/CC_NonPosted_Data
add wave -noupdate -expand -group CC_Registers -radix unsigned /Tx_FC_Top/u_Tx_FC/CC_Completion_Hdr
add wave -noupdate -expand -group CC_Registers -radix unsigned /Tx_FC_Top/u_Tx_FC/CC_Completion_Data
add wave -noupdate -expand -group CL_Registers -radix unsigned /Tx_FC_Top/u_Tx_FC/CL_Posted_Hdr
add wave -noupdate -expand -group CL_Registers -radix unsigned /Tx_FC_Top/u_Tx_FC/CL_Posted_Data
add wave -noupdate -expand -group CL_Registers -radix unsigned /Tx_FC_Top/u_Tx_FC/CL_NonPosted_Hdr
add wave -noupdate -expand -group CL_Registers -radix unsigned /Tx_FC_Top/u_Tx_FC/CL_NonPosted_Data
add wave -noupdate -expand -group CL_Registers -radix unsigned /Tx_FC_Top/u_Tx_FC/CL_Completion_Hdr
add wave -noupdate -expand -group CL_Registers -radix unsigned /Tx_FC_Top/u_Tx_FC/CL_Completion_Data
add wave -noupdate -expand -group PTLP_Conv -radix unsigned /Tx_FC_Top/u_Tx_FC/FC_PTLP_Conv/PTLP
add wave -noupdate -expand -group PTLP_Conv -radix unsigned /Tx_FC_Top/u_Tx_FC/FC_PTLP_Conv/FC_PTLP_Conv
add wave -noupdate -expand -group {DLL Interface} /Tx_FC_Top/u_Tx_FC/TypeFC
add wave -noupdate -expand -group {DLL Interface} /Tx_FC_Top/u_Tx_FC/HdrFC
add wave -noupdate -expand -group {DLL Interface} /Tx_FC_Top/u_Tx_FC/DataFC
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {247 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 209
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
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {95 ps}
