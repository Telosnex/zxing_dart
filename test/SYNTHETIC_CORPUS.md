# Synthetic camera corpus v1

A deterministic, recipe-driven acquisition corpus for the Telosnex pairing
symbol—not a directory of opaque screenshots.

## Oracles

The suite has three independently useful source profiles:

1. **Production writer:** the full 119-byte `tnx2:` pairing envelope encoded by
   pinned zxing-cpp at default ECC.
2. **Independent writer:** the same envelope encoded by the separately pinned
   pure-Dart `barcode` 2.2.9 Aztec implementation, then decoded by zxing-cpp.
   The two implementations currently produce bit-identical canonical modules;
   the important independence is that the second matrix never calls our C ABI
   writer.
3. **Compact/high-ECC:** a short envelope encoded at ECC level 8, proving that
   transform behavior is not accidentally specific to the 41×41 production
   matrix.

Every positive result must be byte-exact, text-exact, Aztec-formatted, and have
nondegenerate in-frame geometry centered on the rendered object. Negative
scenes must return `null`, never a false payload.

## v1 scenes

The primary manifest contains 40 stable IDs:

- clean baseline;
- 9 rotations, including exact 90°/180°/270° and arbitrary angles;
- 3 projective/oblique views;
- 3 acquisition distances/module resolutions;
- 2 defocus levels and horizontal motion blur;
- low contrast + sensor noise, underexposure, uneven lighting, vignette;
- edge/corner glare;
- display-capture moiré;
- RGBA and BGRA planes with independently poisoned row padding;
- 10 seeded compound scenes combining perspective, lighting, blur, glare,
  noise, and/or moiré;
- blank, random-noise, and finder-destroyed negatives.

The hard subset applies 10 of those transforms to each alternate writer/ECC
profile, for **60 decode tasks per backend**. Pixels are inverse-projected from
modules through a homography with fixed four-sample photosite integration, then
optical/sensor effects are applied in luminance space. The generator has no
canvas, image codec, global RNG, or checked-in raster dependency.

This is a regression/conformance model, not a claim that synthetic noise has the
same distribution as every physical camera. Real capture fixtures should be
added alongside it when available; they should not replace reproducible recipes.

## Reproduce one failure

```bash
dart run tool/render_synthetic_case.dart --list
dart run tool/render_synthetic_case.dart v1/glare-edge /tmp/glare.pgm
```

The lossless PGM includes the case ID and opens in Preview, ImageMagick, ffmpeg,
and most image viewers. Case IDs include the recipe major version; recipe
changes that invalidate acquisition thresholds require `v2`, not silent golden
movement.

## Execution matrix

`tool/test_all.sh` runs the same corpus through:

- native Dart VM / FFI / helper isolate;
- Chrome dart2js / Wasm Worker;
- Chrome dart2wasm / Wasm Worker;
- Safari dart2js / Wasm Worker.

The existing Linux and Windows Dart-container gates can run it unchanged. iOS
Simulator and Android runtime scripts currently execute the ABI smoke/fuzz
suite; app-level camera adapters can consume these generated planes in their
integration tests.

## Malformed boundary corpus

`native_test/smoke_test.cpp` additionally sends 6,144 deterministic hostile
calls directly through the C ABI:

- 4,096 overflow-shaped dimensions/strides over a tiny allocation;
- 1,024 valid random padded planes;
- the same 1,024 descriptors truncated by exactly one byte.

`tool/test_native_sanitizers.sh` runs that boundary corpus plus positive
round-trips under AddressSanitizer and UndefinedBehaviorSanitizer.
