# pwm3_top -- top-level make targets. Run inside the iic-osic-tools container
# (scripts/run_all.ps1 or scripts/run_all.sh start it for you).
#
#   make all      lint + sim + formal + flow + signoff summary
#   make lint     Verilator lint
#   make sim      cocotb regression (Icarus) + functional coverage
#   make formal   SymbiYosys proofs and covers
#   make flow     LibreLane RTL-to-GDS on IHP SG13G2 (incl. KLayout DRC, Netgen LVS)
#   make results  copy signoff reports + render the layout PNG into results/

SHELL := /bin/bash
.SHELLFLAGS := -eo pipefail -c
RTL := rtl/pwm_sync2.v rtl/pwm_spi_slave.v rtl/pwm_regs.v rtl/pwm_timebase.v \
       rtl/pwm_deadtime.v rtl/pwm3_top.v
RES := results

.PHONY: all lint sim formal flow results figures versions clean

all: versions lint sim formal flow results

# screenshots/figures only (needs results/sim/traces from 'make sim' and results/impl from 'make results')
figures:
	python3 scripts/make_figures.py

versions:
	@mkdir -p $(RES)
	@bash scripts/tool_versions.sh | tee $(RES)/tool_versions.txt

lint:
	@mkdir -p $(RES)/lint
	verilator --lint-only -Wall --top-module pwm3_top $(RTL) 2>&1 | tee $(RES)/lint/verilator_lint.log
	@echo "verilator lint: PASS (no warnings)" | tee -a $(RES)/lint/verilator_lint.log

sim:
	@mkdir -p $(RES)/sim
	$(MAKE) -C tb SIM=icarus 2>&1 | tee $(RES)/sim/cocotb.log
	@cp tb/results.xml $(RES)/sim/results.xml
	@python3 scripts/check_junit.py $(RES)/sim/results.xml $(RES)/sim/cocotb.log | tee $(RES)/sim/summary.txt
	bash scripts/sim_mutants.sh

formal:
	@mkdir -p $(RES)/formal
	cd formal && sby -f pwm_deadtime.sby
	cd formal && sby -f pwm3_top.sby
	@bash scripts/formal_summary.sh | tee $(RES)/formal/summary.txt
	bash scripts/formal_mutants.sh

flow:
	bash scripts/run_flow.sh

results:
	bash scripts/collect_results.sh
	python3 scripts/make_figures.py

clean:
	rm -rf tb/sim_build tb/results.xml tb/__pycache__ formal/pwm_deadtime formal/pwm_deadtime_* formal/pwm3_top formal/pwm3_top_* flow/runs
