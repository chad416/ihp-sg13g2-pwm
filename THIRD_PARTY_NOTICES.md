# Third-party notices

The RTL, testbench, formal properties, scripts and documentation in this
repository are MIT licensed (see [LICENSE](LICENSE)).

Some generated files in `results/` contain or are derived from the
**IHP-Open-PDK** (SG13G2), Copyright 2024-2025 IHP PDK Authors, licensed under the
Apache License, Version 2.0. A copy of that licence is in
[LICENSES/Apache-2.0.txt](LICENSES/Apache-2.0.txt). Source:
https://github.com/IHP-GmbH/IHP-Open-PDK (commit recorded in
`results/tool_versions.txt`).

| File | What it contains from the PDK |
|---|---|
| `results/impl/final/pwm3_top.gds` | Layout of the `sg13g2_stdcell` standard cells (placed and routed by the flow) |
| `results/layout_pwm3_top.png`, `docs/screenshots/layout_*.png` | Renders of that GDS with the PDK's KLayout layer properties |
| `results/impl/final/pwm3_top.nl.v` | Instances of `sg13g2_stdcell` cells (cell and pin names only) |
| `results/impl/drc_klayout/*` | Rule names and descriptions of the PDK's KLayout DRC deck |

No PDK files are modified or redistributed on their own. The open-source tools
used by the flow (LibreLane, Yosys, OpenROAD, KLayout, Magic, Netgen, Icarus
Verilog, Verilator, cocotb, SymbiYosys) are not included in this repository; they
come with the `hpretl/iic-osic-tools` container under their own licences.
