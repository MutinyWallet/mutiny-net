#!/usr/bin/env python3
"""Compute the signalling nVersion for a Bitcoin Inquisition deployment.

A "heretical" deployment activates when one block in the current 432-block
signet period has `nVersion == signal_activate`, where:

    binana_id       = ((year % 32) << 22) | ((number % 16384) << 8) | (revision % 256)
    signal_activate = VERSIONBITS_TOP_ACTIVE (0x60000000) | binana_id
    signal_abandon  = VERSIONBITS_TOP_ABANDON (0x40000000) | binana_id

The (year, number, revision) tuple comes from the deployment's
`src/binana/<name>.json` file in the bitcoin-inquisition source tree.

Usage:
    calc_nversion.py YEAR NUMBER REVISION
    calc_nversion.py path/to/binana/foo.json
"""

import json
import sys

VERSIONBITS_TOP_ACTIVE = 0x60000000
VERSIONBITS_TOP_ABANDON = 0x40000000


def binana_id(year: int, number: int, revision: int) -> int:
    return ((year % 32) << 22) | ((number % 16384) << 8) | (revision % 256)


def main(argv: list[str]) -> int:
    if len(argv) == 2:
        with open(argv[1]) as f:
            data = json.load(f)
        year, number, revision = data["binana"]
        name = data.get("deployment", "?")
    elif len(argv) == 4:
        year, number, revision = (int(x) for x in argv[1:])
        name = "?"
    else:
        print(__doc__, file=sys.stderr)
        return 2

    bid = binana_id(year, number, revision)
    activate = VERSIONBITS_TOP_ACTIVE | bid
    abandon = VERSIONBITS_TOP_ABANDON | bid

    print(f"deployment:      {name}")
    print(f"binana:          [{year}, {number}, {revision}]")
    print(f"binana_id:       0x{bid:08x}")
    print(f"signal_activate: 0x{activate:08x}")
    print(f"signal_abandon:  0x{abandon:08x}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
