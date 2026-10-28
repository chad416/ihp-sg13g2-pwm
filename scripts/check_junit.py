"""Summarise a cocotb JUnit results.xml and exit non-zero on any failure."""

import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
cases = root.iter("testcase")
n = fails = 0
for tc in cases:
    n += 1
    failed = tc.find("failure") is not None or tc.find("error") is not None
    fails += failed
    sim_ns = tc.get("sim_time_ns", "?")
    print(f"{'FAIL' if failed else 'PASS'}  {tc.get('name'):<28} sim_time={sim_ns} ns  "
          f"wall={float(tc.get('time', 0)):.1f} s")
print(f"\n{n - fails}/{n} tests passed")
sys.exit(1 if fails or n == 0 else 0)
