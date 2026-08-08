# Staged iccMAX export boundary

iccMAX is ICC v5. It is not another spelling of ICC v4.4 and is not written by
Argyll's legacy `icclib` serializer.

The extended-range interoperability specification requires a display profile
with the `xrng` subclass, subclass version 2.0, and v5
`multiProcessElementType` AToB1 and BToA1 transforms. It also requires the
media white point, custom-to-standard PCC, standard-to-custom PCC and spectral
viewing-condition tags. Relabelling an ICC v2 or v4 LUT profile as version 5 is
not valid.

`argyll-iccmax-export.py` defines the process boundary between Argyll fitting
and a v5-aware serializer. It records the measured TI3, an Argyll control ICC,
absolute luminance and CICP values in a versioned JSON request. A backend must
translate the measured transforms to v5 MPEs and serialize them with the ICC
reference `iccDEV` library. The bridge then rejects output that is not an ICC
v5 `mntr`/`xrng` profile.

Request-only mode is useful while developing an iccDEV backend:

```sh
python3 iccmax/argyll-iccmax-export.py \
  --source-icc display.icc --ti3 display.ti3 \
  --media-white-cdm2 203 --output display-iccmax.icc \
  --request-only request.json
```

Backend mode uses an executable that accepts two arguments, the JSON request
path and output ICC path:

```sh
python3 iccmax/argyll-iccmax-export.py \
  --source-icc display.icc --ti3 display.ti3 \
  --media-white-cdm2 203 --output display-iccmax.icc \
  --backend /path/to/argyll-iccdev-exporter
```

The backend contract intentionally remains independent of `colprof -4`.
Future iccMAX CLI integration should invoke this boundary as a distinct mode,
not pass `-4` or mutate a v4 profile header.
