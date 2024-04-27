

#add wave -noupdate -group my_uvm_tb
#add wave -noupdate -group my_uvm_tb -radix hexadecimal /my_uvm_tb/*

# add wave -noupdate -group my_uvm_tb/grayscale_inst
# add wave -noupdate -group my_uvm_tb/grayscale_inst -radix hexadecimal /my_uvm_tb/grayscale_inst/*

# add wave -noupdate -group my_uvm_tb/grayscale_inst/grayscale_inst
# add wave -noupdate -group my_uvm_tb/grayscale_inst/grayscale_inst -radix hexadecimal /my_uvm_tb/grayscale_inst/grayscale_inst/*

# add wave -noupdate -group my_uvm_tb/grayscale_inst/fifo_in_inst
# add wave -noupdate -group my_uvm_tb/grayscale_inst/fifo_in_inst -radix hexadecimal /my_uvm_tb/grayscale_inst/fifo_in_inst/*

# add wave -noupdate -group my_uvm_tb/grayscale_inst/fifo_out_inst
# add wave -noupdate -group my_uvm_tb/grayscale_inst/fifo_out_inst -radix hexadecimal /my_uvm_tb/grayscale_inst/fifo_out_inst/*

add wave -position insertpoint sim:/my_uvm_tb/grayscale_inst/sober_inst/*
add wave -position insertpoint  \
sim:/my_uvm_tb/grayscale_inst/sober_inst/register__array

add wave -position insertpoint  \
{sim:/my_uvm_tb/grayscale_inst/sober_inst/register__array[5]}
add wave -position insertpoint  \
{sim:/my_uvm_tb/grayscale_inst/sober_inst/register__array[4]}
add wave -position insertpoint  \
{sim:/my_uvm_tb/grayscale_inst/sober_inst/register__array[3]}
add wave -position insertpoint  \
{sim:/my_uvm_tb/grayscale_inst/sober_inst/register__array[2]}
add wave -position insertpoint  \
{sim:/my_uvm_tb/grayscale_inst/sober_inst/register__array[1]}
add wave -position insertpoint  \
{sim:/my_uvm_tb/grayscale_inst/sober_inst/register__array[0]}


add wave -position insertpoint sim:/my_uvm_tb/grayscale_inst/fifo_out_inst/*
add wave -position insertpoint  \
sim:/my_uvm_tb/grayscale_inst/fifo_out_inst/fifo_buf