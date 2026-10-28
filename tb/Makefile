# cocotb simulation of pwm3_top (Icarus Verilog).
#   make            -- run all tests
#   make PWM3_SEED=1 PWM3_RANDOM_CFGS=500   -- other seed / longer random run

SIM ?= icarus
TOPLEVEL_LANG = verilog
RTL_DIR = $(abspath ../rtl)

VERILOG_SOURCES = $(RTL_DIR)/pwm_sync2.v $(RTL_DIR)/pwm_spi_slave.v \
                  $(RTL_DIR)/pwm_regs.v $(RTL_DIR)/pwm_timebase.v \
                  $(RTL_DIR)/pwm_deadtime.v $(RTL_DIR)/pwm3_top.v

# cocotb >= 2.0 names
COCOTB_TOPLEVEL = pwm3_top
COCOTB_TEST_MODULES = test_pwm3
# cocotb 1.x names (harmless on 2.x)
TOPLEVEL = pwm3_top
MODULE = test_pwm3

COMPILE_ARGS += -g2012 -Wall
WAVES ?= 0

export PWM3_SEED ?= 20261028
export PWM3_RANDOM_CFGS ?= 120
export PWM3_COV_REPORT ?= $(abspath ../results/sim/coverage_report.txt)

include $(shell cocotb-config --makefiles)/Makefile.sim
