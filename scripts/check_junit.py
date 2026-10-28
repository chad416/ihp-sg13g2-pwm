"""Summarise a cocotb run and exit non-zero on any failure.

Usage: check_junit.py <results.xml> [cocotb.log]
With the log, also totals the scoreboard lines ("N cycles compared, M errors").
"""

import re
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
n = fails = 0
for tc in root.iter("testcase"):
    n += 1
    failed = tc.find("failure") is not None or tc.find("error") is not None
    fails += failed
    print(f"{'FAIL' if failed else 'PASS'}  {tc.get('name'):<28} wall={float(tc.get('time', 0)):.1f} s")
print(f"\n{n - fails}/{n} tests passed")

if len(sys.argv) > 2:
    text = open(sys.argv[2], encoding="utf-8", errors="replace").read()
    sb = [(int(c), int(e)) for c, e in re.findall(r"scoreboard: (\d+) cycles compared, (\d+) errors", text)]
    print(f"scoreboard: {sum(c for c, _ in sb)} clock cycles compared against the model "
          f"in {len(sb)} tests, {sum(e for _, e in sb)} mismatches")
    cov = re.search(r"Bins covered: .*", text)
    if cov:
        print(f"functional coverage: {cov.group(0)}")
sys.exit(1 if fails or n == 0 else 0)
