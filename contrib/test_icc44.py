#!/usr/bin/env python3
"""Build and inspect a small ICC v4.4 PQ display profile."""

import argparse
import itertools
import struct
import subprocess
import tempfile
from pathlib import Path


TI3_HEADER = """CTI3

DESCRIPTOR "ICC v4.4 smoke display"
ORIGINATOR "ArgyllCMS"
DEVICE_CLASS "DISPLAY"
COLOR_REP "RGB_XYZ"
LUMINANCE_XYZ_CDM2 "95.05 100.0 108.88"
NORMALIZED_TO_Y_100 "YES"

NUMBER_OF_FIELDS 7
BEGIN_DATA_FORMAT
SAMPLE_ID RGB_R RGB_G RGB_B XYZ_X XYZ_Y XYZ_Z
END_DATA_FORMAT

NUMBER_OF_SETS {count}
BEGIN_DATA
"""


def make_ti3() -> str:
    rows = []
    levels = (0.0, 33.3333, 66.6667, 100.0)
    for sample, (red, green, blue) in enumerate(itertools.product(levels, repeat=3), 1):
        r, g, b = ((value / 100.0) ** 2.2 for value in (red, green, blue))
        x = 100.0 * (0.4124 * r + 0.3576 * g + 0.1805 * b)
        y = 100.0 * (0.2126 * r + 0.7152 * g + 0.0722 * b)
        z = 100.0 * (0.0193 * r + 0.1192 * g + 0.9505 * b)
        rows.append(
            f"{sample} {red:.4f} {green:.4f} {blue:.4f} {x:.6f} {y:.6f} {z:.6f}"
        )
    return TI3_HEADER.format(count=len(rows)) + "\n".join(rows) + "\nEND_DATA\n"


def tags(data: bytes):
    count = struct.unpack_from(">I", data, 128)[0]
    result = {}
    for index in range(count):
        pos = 132 + 12 * index
        signature = data[pos : pos + 4].decode("ascii")
        result[signature] = struct.unpack_from(">II", data, pos + 4)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--colprof", type=Path, required=True)
    args = parser.parse_args()
    colprof = args.colprof.resolve()

    with tempfile.TemporaryDirectory(prefix="argyll-icc44-") as directory:
        base = Path(directory) / "smoke"
        base.with_suffix(".ti3").write_text(make_ti3(), encoding="ascii")
        subprocess.run(
            [str(colprof), "-4", "-aX", "-ql", "-D", "ICC v4.4 smoke", str(base)],
            check=True,
        )
        data = base.with_suffix(".icc").read_bytes()
        assert data[8:12] == bytes.fromhex("04400000"), "profile is not ICC v4.4"
        table = tags(data)
        for signature in ("desc", "cprt", "cicp"):
            assert signature in table, f"missing {signature} tag"
        for signature in ("desc", "cprt"):
            offset, _ = table[signature]
            assert data[offset : offset + 4] == b"mluc", f"{signature} is not MLUC"
            assert struct.unpack_from(">I", data, offset + 24)[0] == 28
        offset, size = table["cicp"]
        assert size == 12
        assert data[offset : offset + 12] == b"cicp\0\0\0\0\x09\x10\x00\x01"
        assert table["B2A0"] == table["B2A1"], "single-intent B2A1 is not aliased"

        gamut_base = Path(directory) / "gamut"
        gamut_base.with_suffix(".ti3").write_text(make_ti3(), encoding="ascii")
        subprocess.run(
            [
                str(colprof), "-4", "-aX", "-ql", "-s", "20",
                "-D", "ICC v4.4 perceptual smoke", str(gamut_base),
            ],
            check=True,
        )
        gamut_data = gamut_base.with_suffix(".icc").read_bytes()
        gamut_tags = tags(gamut_data)
        assert gamut_tags["B2A0"] != gamut_tags["B2A1"], (
            "independently gamut-mapped perceptual B2A0 was incorrectly aliased"
        )
        print("ICC v4.4 MLUC and CICP smoke test passed")


if __name__ == "__main__":
    main()
