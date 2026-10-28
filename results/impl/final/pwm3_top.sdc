###############################################################################
# Created by write_sdc
###############################################################################
current_design pwm3_top
###############################################################################
# Timing Constraints
###############################################################################
create_clock -name clk_i -period 10.0000 [get_ports {clk_i}]
set_clock_transition 0.1500 [get_clocks {clk_i}]
set_clock_uncertainty 0.2500 clk_i
set_propagated_clock [get_clocks {clk_i}]
set_input_delay 2.0000 -clock [get_clocks {clk_i}] -add_delay [get_ports {fault_i}]
set_input_delay 2.0000 -clock [get_clocks {clk_i}] -add_delay [get_ports {rst_ni}]
set_input_delay 2.0000 -clock [get_clocks {clk_i}] -add_delay [get_ports {spi_cs_ni}]
set_input_delay 2.0000 -clock [get_clocks {clk_i}] -add_delay [get_ports {spi_mosi_i}]
set_input_delay 2.0000 -clock [get_clocks {clk_i}] -add_delay [get_ports {spi_sclk_i}]
set_output_delay 2.0000 -clock [get_clocks {clk_i}] -add_delay [get_ports {pwm_h_o[0]}]
set_output_delay 2.0000 -clock [get_clocks {clk_i}] -add_delay [get_ports {pwm_h_o[1]}]
set_output_delay 2.0000 -clock [get_clocks {clk_i}] -add_delay [get_ports {pwm_h_o[2]}]
set_output_delay 2.0000 -clock [get_clocks {clk_i}] -add_delay [get_ports {pwm_l_o[0]}]
set_output_delay 2.0000 -clock [get_clocks {clk_i}] -add_delay [get_ports {pwm_l_o[1]}]
set_output_delay 2.0000 -clock [get_clocks {clk_i}] -add_delay [get_ports {pwm_l_o[2]}]
set_output_delay 2.0000 -clock [get_clocks {clk_i}] -add_delay [get_ports {spi_miso_o}]
set_output_delay 2.0000 -clock [get_clocks {clk_i}] -add_delay [get_ports {spi_miso_oe_o}]
set_output_delay 2.0000 -clock [get_clocks {clk_i}] -add_delay [get_ports {sync_o}]
###############################################################################
# Environment
###############################################################################
set_load -pin_load 0.0060 [get_ports {spi_miso_o}]
set_load -pin_load 0.0060 [get_ports {spi_miso_oe_o}]
set_load -pin_load 0.0060 [get_ports {sync_o}]
set_load -pin_load 0.0060 [get_ports {pwm_h_o[2]}]
set_load -pin_load 0.0060 [get_ports {pwm_h_o[1]}]
set_load -pin_load 0.0060 [get_ports {pwm_h_o[0]}]
set_load -pin_load 0.0060 [get_ports {pwm_l_o[2]}]
set_load -pin_load 0.0060 [get_ports {pwm_l_o[1]}]
set_load -pin_load 0.0060 [get_ports {pwm_l_o[0]}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {clk_i}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {fault_i}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {rst_ni}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {spi_cs_ni}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {spi_mosi_i}]
set_driving_cell -lib_cell sg13g2_buf_4 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {spi_sclk_i}]
set_timing_derate -early 0.9500
set_timing_derate -late 1.0500
###############################################################################
# Design Rules
###############################################################################
set_max_fanout 10.0000 [current_design]
