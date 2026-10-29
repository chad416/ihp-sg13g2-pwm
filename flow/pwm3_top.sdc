# pwm3_top timing constraints, used for place-and-route and for signoff STA
# (PNR_SDC_FILE / SIGNOFF_SDC_FILE in config.json).
#
# The numbers are the IHP SG13G2 defaults of LibreLane's generic SDC. They are
# written out here so that the constraints are part of the design and can be
# reviewed, instead of being generated implicitly.

set period $::env(CLOCK_PERIOD)

# --- Clock -------------------------------------------------------------------
create_clock -name clk_i -period $period [get_ports clk_i]
# Jitter plus margin. It applies to hold as well as setup, which is conservative
# for hold and costs hold buffers (DESIGN.md section 5.2).
set_clock_uncertainty 0.25 [get_clocks clk_i]
set_clock_transition 0.15 [get_clocks clk_i]
# Flat +/-5 % on-chip-variation derate; the open PDK has no AOCV/POCV tables.
set_timing_derate -early 0.95
set_timing_derate -late 1.05
# Ideal clock before CTS, propagated clock afterwards.
if { [info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS) } {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}

# --- Inputs ------------------------------------------------------------------
# rst_ni, fault_i and the SPI pins are asynchronous to clk_i. Each one drives
# only the first flop of a 2-flop synchroniser (rtl/pwm_sync2.v), so no
# functional path depends on its arrival time and there is no clock-domain
# crossing to constrain. They still get a 20 % input-delay budget instead of a
# false path: that keeps the pin-to-synchroniser wires short and bounds the
# skew between SCLK, MOSI and CS, which the oversampled SPI slave relies on.
set async_inputs [get_ports {rst_ni fault_i spi_sclk_i spi_cs_ni spi_mosi_i}]
set_input_delay [expr {0.2 * $period}] -clock clk_i $async_inputs
set_driving_cell -lib_cell sg13g2_buf_4 -pin X [all_inputs]

# --- Outputs -----------------------------------------------------------------
# Every output is driven directly by a flop. 20 % of the period is left for the
# wiring and the receiving logic at the next level of integration.
set_output_delay [expr {0.2 * $period}] -clock clk_i [all_outputs]
set_load 0.006 [all_outputs]

# --- Design rules ------------------------------------------------------------
set_max_fanout 10 [current_design]
