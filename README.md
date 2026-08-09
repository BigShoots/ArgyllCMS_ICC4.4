# ArgyllCMS ICC v4.4 and iccMAX work

This fork extends ArgyllCMS 3.5.0 for HDR profile experiments while preserving
the normal ArgyllCMS profile path. Its current production feature is an
opt-in ICC v4.4 RGB display profile with Rec. 2020 PQ full-range CICP metadata.

The default `colprof` output remains ICC v2.2. Existing commands do not change
unless `-4` is supplied.

## ICC v4.4 PQ mode

Build ArgyllCMS using its normal Jam build:

```sh
jam -q -fJambase -j 8
```

Create an XYZ cLUT plus matrix display profile:

```sh
profile/colprof -4 -aX -qm -D "HDR display" display
```

`display.ti3` must be an RGB display characterization. The `-4` option is
rejected for non-display and non-RGB profiles.

The resulting profile contains:

- ICC header version 4.4
- `desc` and `cprt` encoded as `multiLocalizedUnicodeType`
- a 12-byte `cicp` tag containing `9/16/0/1`
- Rec. 2020 colour primaries coding, ST 2084 PQ transfer, RGB identity matrix
  coefficients and full range
- the normal measured Argyll AToB and BToA transforms
- B2A1 linked to the single colourimetric B2A0 transform when no independent
  perceptual transform exists

The CICP tag declares the coding used by the HDR profile pipeline. It does not
replace the measured display primaries, turn arbitrary SDR measurements into
HDR measurements, or rewrite Argyll's fitted transform. The v4.4 and v2.2
control profiles therefore remain directly comparable.

When `colprof` creates an independently gamut-mapped perceptual B2A0, that
table is not aliased over B2A1. The media-relative and perceptual intents stay
separate.

See [README-ICC44.md](README-ICC44.md) for the focused command reference and
validation details.

## Validation

After building, run:

```sh
python3 contrib/test_icc44.py --colprof profile/colprof
```

The smoke test checks:

- the v4.4 header
- MLUC `desc` and `cprt` tags
- exact CICP bytes `9/16/0/1`
- B2A0 and B2A1 aliasing for a single-intent profile
- separation of B2A0 and B2A1 when a perceptual gamut map is requested

For independent format validation, use the ICC reference implementation:

```sh
iccDumpProfile -v --read 100 display.icc ALL
```

Argyll private measurement tags can be reported as unknown by a generic ICC
validator. Those warnings are separate from validation of the v4.4 header,
MLUC, CICP and transform tags.

## KWin compatibility

KWin 6.7.4 does not consume CICP metadata by itself. The matching
`BigShoots/kwin_HDR_ICC_Fixed` fork parses CICP `9/16/0/1` and selects a
Rec. 2020 PQ profile encoding. On unpatched KWin, adding CICP alone does not
change the hard-coded gamma 2.2 HDR profile path.

For the patched KDE cLUT path, VCGT is optional. If it is included, build the
B2A transform from measurements with the VCGT effect removed so that KWin's
sequential B2A and VCGT stages reproduce the intended correction once. If the
B2A transform already contains the full neutral correction, omit VCGT.

## iccMAX status

iccMAX is ICC v5, not ICC v4.4. Changing a profile header to version 5 is not
a valid iccMAX implementation.

The [iccmax](iccmax/README.md) directory currently defines and validates an
export boundary between Argyll fitting and a future ICC reference `iccDEV`
serializer. It can produce a versioned JSON request and validate a backend's
output, but this repository does not yet contain the required v5 MPE
serializer. iccMAX export is therefore staged development work, not a finished
`colprof` output mode.

## ARM builds

The repository retains the ARM cross-build work used by PGenerator+. The
native ICC v4.4 changes and the ARM fork must remain synchronized so
`colprof -4` produces the same profile structure on both architectures.

The ARM helper builds a headless runtime containing `spotread`, `chartread`,
`colprof`, `ccxxmake` and `oeminst`. See the scripts under `tools/` for the
cross-toolchain and sysroot options. Interactive `dispcal` and `dispread` are
outside that reduced runtime.

## Branches

- `feature/icc44-cicp` contains the native ICC v4.4 work.
- The matching `ArgyllCMS_ARM` repository carries the synchronized ARM branch.
- iccMAX work remains behind the explicit export boundary until a conforming
  v5 serializer and reference validation are available.

This repository is based on ArgyllCMS 3.5.0. Refer to the upstream ArgyllCMS
documentation for general profiling options and instrument support.
