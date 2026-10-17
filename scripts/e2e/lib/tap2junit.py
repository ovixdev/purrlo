#!/usr/bin/env python3
"""Converts the TAP files written by run-all.sh into one JUnit XML report (standard library only).

Usage: tap2junit.py OUT.xml SCENARIO.tap [SCENARIO.tap ...]
"""

import re
import sys
import xml.etree.ElementTree as ET

RESULT = re.compile(r"^(ok|not ok) (\d+) - (.*)$")
PLAN = re.compile(r"^1\.\.(\d+)")


def suite_for(path):
    name = path.rsplit("/", 1)[-1].removesuffix(".tap")
    suite = ET.Element("testsuite", name=name)
    planned, cases, current = None, [], None
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if match := PLAN.match(line):
                planned = int(match.group(1))
            elif match := RESULT.match(line):
                current = ET.SubElement(suite, "testcase", classname=name, name=match.group(3))
                cases.append(current)
                if match.group(1) == "not ok":
                    ET.SubElement(current, "failure", message=match.group(3)).text = ""
            elif line.startswith("# ") and current is not None and len(current):
                current[0].text += line[2:] + "\n"
            elif line.startswith("Bail out!"):
                case = ET.SubElement(suite, "testcase", classname=name, name="bail out")
                ET.SubElement(case, "error", message=line).text = line
                cases.append(case)
    if planned is not None and planned != len([c for c in cases if c.get("name") != "bail out"]):
        case = ET.SubElement(suite, "testcase", classname=name, name="plan")
        ET.SubElement(case, "failure", message=f"planned {planned} tests, ran {len(cases)}")
        cases.append(case)
    failures = sum(1 for c in cases if c.find("failure") is not None)
    errors = sum(1 for c in cases if c.find("error") is not None)
    suite.set("tests", str(len(cases)))
    suite.set("failures", str(failures))
    suite.set("errors", str(errors))
    return suite


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    root = ET.Element("testsuites", name="Purrlo E2E")
    for path in sys.argv[2:]:
        root.append(suite_for(path))
    ET.indent(root)
    ET.ElementTree(root).write(sys.argv[1], encoding="utf-8", xml_declaration=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
