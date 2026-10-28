#!/usr/bin/env bash
# Record the versions of every tool used, so results can be reproduced.
v() { printf '%-14s %s\n' "$1" "$(eval "$2" 2>&1 | head -n1)"; }
echo "container      ${IIC_OSIC_TOOLS_VERSION:-unknown} (hpretl/iic-osic-tools)"
v verilator  "verilator --version"
v iverilog   "iverilog -V | head -n1"
v cocotb     "cocotb-config --version"
v python     "python3 --version"
v yosys      "yosys -V"
v sby        "sby --version"
v yices      "yices-smt2 --version"
v librelane  "librelane --version"
v openroad   "openroad -version -no_init"
v klayout    "klayout -v"
v netgen     "netgen -batch quit </dev/null | grep -i 'netgen' "
v magic      "magic --version"
v ihp-pdk    "echo IHP-Open-PDK ihp-sg13g2 commit \$(cat \$PDK_ROOT/ihp-sg13g2/COMMIT)"
