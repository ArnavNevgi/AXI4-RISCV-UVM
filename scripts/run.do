transcript on

vlib work
vmap work work

vlog -sv axi_pkg.sv
vlog -sv axi_if.sv
vlog -sv axi_master.sv
vlog -sv axi_ifdummytb.sv

vsim -voptargs=+acc tb

add wave -radix hex sim:/tb/intf/aw_valid
add wave -radix hex sim:/tb/intf/aw_ready
add wave -radix hex sim:/tb/intf/aw

add wave -radix hex sim:/tb/intf/w_valid
add wave -radix hex sim:/tb/intf/w_ready
add wave -radix hex sim:/tb/intf/w

add wave -radix hex sim:/tb/intf/b_valid
add wave -radix hex sim:/tb/intf/b_ready
add wave -radix hex sim:/tb/intf/b

add wave -radix hex sim:/tb/intf/ar_valid
add wave -radix hex sim:/tb/intf/ar_ready
add wave -radix hex sim:/tb/intf/ar

add wave -radix hex sim:/tb/intf/r_valid
add wave -radix hex sim:/tb/intf/r_ready
add wave -radix hex sim:/tb/intf/r

add wave -radix unsigned sim:/tb/master_inst/state
add wave -radix unsigned sim:/tb/master_inst/beat_cnt
add wave -radix unsigned sim:/tb/master_inst/burst_len

run -all