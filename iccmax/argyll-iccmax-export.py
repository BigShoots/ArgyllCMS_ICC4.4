#!/usr/bin/env python3
"""Staged bridge from Argyll fitting data to an iccDEV v5 exporter."""

import argparse
import json
import struct
import subprocess
import tempfile
from pathlib import Path


def profile_header(path: Path):
    data = path.read_bytes()
    if len(data) < 132:
        raise ValueError(f"{path} is too small to be an ICC profile")
    declared = struct.unpack_from(">I", data, 0)[0]
    if declared != len(data) or data[36:40] != b"acsp":
        raise ValueError(f"{path} is not a structurally valid ICC profile")
    return data


def validate_iccmax(path: Path) -> None:
    data = profile_header(path)
    if data[8] != 5:
        raise ValueError("iccMAX backend did not produce an ICC v5 profile")
    if data[10:12] != b"\x02\x00":
        raise ValueError("iccMAX backend output is not extendedRange subclass version 2.0")
    if data[12:16] != b"mntr":
        raise ValueError("iccMAX backend output is not a display profile")
    # ICC v5 uses bytes 100..119 for spectral PCS/ranges and MCS, followed
    # by the device subclass at bytes 120..123.
    if data[120:124] != b"xrng":
        raise ValueError("iccMAX backend output is not extendedRange subclass xrng")
    count = struct.unpack_from(">I", data, 128)[0]
    signatures = {data[132 + 12 * index : 136 + 12 * index] for index in range(count)}
    required = {b"desc", b"cprt", b"A2B1", b"B2A1", b"wtpt", b"c2sp", b"s2cp", b"svcn"}
    missing = sorted(value.decode("ascii") for value in required - signatures)
    if missing:
        raise ValueError("iccMAX backend output is missing required tags: " + ", ".join(missing))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-icc", type=Path, required=True)
    parser.add_argument("--ti3", type=Path, required=True)
    parser.add_argument("--media-white-cdm2", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--backend", type=Path)
    parser.add_argument("--iccdev-dump", type=Path)
    parser.add_argument("--request-only", type=Path)
    parser.add_argument("--grid", type=int, default=33)
    args = parser.parse_args()

    if bool(args.backend) == bool(args.request_only):
        parser.error("select exactly one of --backend or --request-only")
    if args.backend and not args.iccdev_dump:
        parser.error("--backend requires --iccdev-dump")
    if args.media_white_cdm2 <= 0:
        parser.error("--media-white-cdm2 must be positive")
    if not 2 <= args.grid <= 65:
        parser.error("--grid must be between 2 and 65")

    profile_header(args.source_icc)
    ti3 = args.ti3.read_text(encoding="utf-8", errors="strict")
    if not ti3.lstrip().startswith("CTI3") or 'DEVICE_CLASS "DISPLAY"' not in ti3:
        raise ValueError("TI3 must contain RGB display measurements")

    request = {
        "schema": "org.argyllcms.iccmax-export-request",
        "version": 1,
        "profile": {
            "class": "mntr",
            "subclass": "xrng",
            "subclass_version": "2.0",
            "data_space": "RGB ",
            "pcs": "XYZ ",
        },
        "encoding": {
            "colour_primaries": 9,
            "transfer_characteristics": 16,
            "matrix_coefficients": 0,
            "video_full_range_flag": 1,
        },
        "fit": {
            "source_icc": str(args.source_icc.resolve()),
            "measurements_ti3": str(args.ti3.resolve()),
            "clut_grid_points": args.grid,
            "media_white_cdm2": args.media_white_cdm2,
        },
        "required_transforms": ["A2B1", "B2A1"],
        "serializer": "iccDEV",
    }

    if args.request_only:
        args.request_only.write_text(json.dumps(request, indent=2) + "\n", encoding="utf-8")
        return

    with tempfile.TemporaryDirectory(prefix="argyll-iccmax-") as directory:
        request_path = Path(directory) / "request.json"
        request_path.write_text(json.dumps(request, indent=2) + "\n", encoding="utf-8")
        subprocess.run(
            [str(args.backend.resolve()), str(request_path), str(args.output.resolve())],
            check=True,
        )
    validate_iccmax(args.output)
    subprocess.run(
        [
            str(args.iccdev_dump.resolve()), "-v", "--read", "1",
            str(args.output.resolve()), "ALL",
        ],
        check=True,
    )


if __name__ == "__main__":
    main()
