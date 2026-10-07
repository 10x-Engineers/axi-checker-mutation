#!/usr/bin/env python3
"""Print IHI 0022 Issue L Part A chapters A1-A6 as plain text, for tools/gen_checker.py.

    pip install pypdf
    python3 tools/spec_text.py IHI0022L.pdf > axi_A1-A6.txt

The spec is Arm's and is not redistributed here: download it (free) from
https://developer.arm.com/documentation/ihi0022/l/ . Page numbers are the printed ones;
A1-A6 is pages 21-121 of Issue L (pass --pages for another issue).
"""

import argparse
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf")
    ap.add_argument("--pages", default="21-121", help="first-last, 1-based, inclusive")
    args = ap.parse_args()
    try:
        from pypdf import PdfReader
    except ImportError:
        sys.exit("pip install pypdf")
    first, last = (int(x) for x in args.pages.split("-"))
    reader = PdfReader(args.pdf)
    for i in range(first - 1, min(last, len(reader.pages))):
        sys.stdout.write(reader.pages[i].extract_text() or "")
        sys.stdout.write("\n\f")


if __name__ == "__main__":
    main()
