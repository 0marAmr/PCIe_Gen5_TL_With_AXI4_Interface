onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /Tx_Arbiter_Top/u_Tx_Arbiter/clk
add wave -noupdate /Tx_Arbiter_Top/u_Tx_Arbiter/arst
add wave -noupdate -expand -group A2P_1 /Tx_Arbiter_Top/A2P_1_if/Valid
add wave -noupdate -expand -group A2P_2 /Tx_Arbiter_Top/A2P_2_if/Valid
add wave -noupdate -expand -group Master /Tx_Arbiter_Top/Master_if/Valid
add wave -noupdate -expand -group Rx_Router /Tx_Arbiter_Top/Rx_Router_if/Valid
add wave -noupdate -expand -group Sequence_Recorder -radix unsigned /Tx_Arbiter_Top/Sequence_Recorder_if/rd_mode
add wave -noupdate -expand -group Sequence_Recorder -radix unsigned /Tx_Arbiter_Top/Sequence_Recorder_if/wr_mode
add wave -noupdate -expand -group Sequence_Recorder /Tx_Arbiter_Top/Sequence_Recorder_if/rd_en
add wave -noupdate -expand -group Sequence_Recorder /Tx_Arbiter_Top/Sequence_Recorder_if/wr_en
add wave -noupdate -expand -group Sequence_Recorder /Tx_Arbiter_Top/Sequence_Recorder_if/rd_data_1
add wave -noupdate -expand -group Sequence_Recorder /Tx_Arbiter_Top/Sequence_Recorder_if/rd_data_2
add wave -noupdate -expand -group Sequence_Recorder /Tx_Arbiter_Top/Sequence_Recorder_if/wr_data_1
add wave -noupdate -expand -group Sequence_Recorder /Tx_Arbiter_Top/Sequence_Recorder_if/wr_data_2
add wave -noupdate -expand -group Sequence_Recorder /Tx_Arbiter_Top/Sequence_Recorder_if/wr_data_3
add wave -noupdate -expand -group Sequence_Recorder /Tx_Arbiter_Top/Sequence_Recorder_if/wr_data_4
add wave -noupdate -expand -group Sequence_Recorder /Tx_Arbiter_Top/Sequence_Recorder_if/empty
add wave -noupdate -expand -group Sequence_Recorder /Tx_Arbiter_Top/Sequence_Recorder_if/full
add wave -noupdate -expand -group Sequence_Recorder -radix unsigned /Tx_Arbiter_Top/Sequence_Recorder_if/available
add wave -noupdate -expand -group Sequence_Recorder -radix unsigned /Tx_Arbiter_Top/u_Sequence_Recorder/wr_ptr
add wave -noupdate -expand -group Sequence_Recorder -radix unsigned /Tx_Arbiter_Top/u_Sequence_Recorder/rd_ptr
add wave -noupdate -expand -group Sequence_Recorder -radixenum numeric -expand /Tx_Arbiter_Top/u_Sequence_Recorder/MEM
add wave -noupdate -expand -group Valid_Positive_Edge /Tx_Arbiter_Top/u_Tx_Arbiter/A2P_1_pe_valid
add wave -noupdate -expand -group Valid_Positive_Edge /Tx_Arbiter_Top/u_Tx_Arbiter/A2P_2_pe_valid
add wave -noupdate -expand -group Valid_Positive_Edge /Tx_Arbiter_Top/u_Tx_Arbiter/Master_pe_valid
add wave -noupdate -expand -group Valid_Positive_Edge /Tx_Arbiter_Top/u_Tx_Arbiter/Rx_Router_pe_valid
add wave -noupdate -group Valid_Delayed_Version /Tx_Arbiter_Top/u_Tx_Arbiter/Rx_Router_delayed_valid
add wave -noupdate -group Valid_Delayed_Version /Tx_Arbiter_Top/u_Tx_Arbiter/Master_delayed_valid
add wave -noupdate -group Valid_Delayed_Version /Tx_Arbiter_Top/u_Tx_Arbiter/A2P_2_delayed_valid
add wave -noupdate -group Valid_Delayed_Version /Tx_Arbiter_Top/u_Tx_Arbiter/A2P_1_delayed_valid
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {27 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 202
configure wave -valuecolwidth 120
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
WaveRestoreZoom {0 ps} {82 ps}
