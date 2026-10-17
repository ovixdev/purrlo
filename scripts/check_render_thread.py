#!/usr/bin/env python3
"""NFR-3: no allocation, locks or Objective-C messaging on the audio render thread.

Walks the call graph of the AUHAL render callback in an optimised build of KeepAliveCore and fails on
any indirect call or any external callee outside a small allowlist of pure math and memory routines.
Deterministic on every macOS, unlike runtime allocation hooks.

Usage: check_render_thread.py <dir with KeepAliveCore .o files>
"""

import glob
import re
import subprocess
import sys

ROOT_SYMBOL = re.compile(r"renderSignal.*To$")  # the @convention(c) render callback
ALLOWED_EXTERNAL = {"_sin", "_sinf", "_bzero", "___bzero", "_memset", "_memcpy", "_memmove"}
FUNCTION = re.compile(r"^[0-9a-f]+ <(.+)>:$")
RELOCATION = re.compile(r"ARM64_RELOC_BRANCH26\s+(\S+)|X86_64_RELOC_BRANCH\s+(\S+)")
INDIRECT = re.compile(r"\s(blr|blraa|blraaz|blrab|blrabz)\s|\scallq?\s+\*")


def disassemble(path):
    """Returns {symbol: (callees, indirect call lines)} for one object file."""
    output = subprocess.run(
        ["xcrun", "objdump", "-d", "-r", "--no-show-raw-insn", path], check=True, capture_output=True, text=True
    ).stdout
    functions, current = {}, None
    for line in output.splitlines():
        if match := FUNCTION.match(line):
            current = match.group(1)
            functions[current] = (set(), [])
        elif current is not None:
            if match := RELOCATION.search(line):
                functions[current][0].add(match.group(1) or match.group(2))
            elif INDIRECT.search(line):
                functions[current][1].append(line.strip())
    return functions


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    functions = {}
    for path in sorted(glob.glob(f"{sys.argv[1]}/*.o")):
        functions.update(disassemble(path))
    roots = [name for name in functions if ROOT_SYMBOL.search(name)]
    if not roots:
        print("NFR-3 check failed: render callback symbol not found; was the engine renamed?")
        return 1

    problems, seen, queue = [], set(), list(roots)
    while queue:
        name = queue.pop()
        if name in seen:
            continue
        seen.add(name)
        callees, indirect = functions[name]
        problems += [f"indirect call in {name}: {line}" for line in indirect]
        for callee in sorted(callees):
            if callee in functions:
                queue.append(callee)
            elif callee not in ALLOWED_EXTERNAL:
                problems.append(f"{name} calls {callee}")

    if problems:
        print("NFR-3 check failed: the render thread reaches disallowed code:")
        print("\n".join(f"  {problem}" for problem in problems))
        return 1
    external = sorted({c for n in seen for c in functions[n][0] if c not in functions})
    print(f"NFR-3: render thread reaches {len(seen)} functions; external calls only {', '.join(external) or 'none'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
