import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../zxing_dart_bindings_generated.dart' as native;
import '../models.dart';
import 'backend.dart';

// Isolate.run serializes its closure arguments before work begins. Returning
// the same list here avoids an additional eager full-frame copy on native; the
// helper-isolate message and the FFI input allocation are the two unavoidable
// ownership boundaries in this milestone. Callers must not mutate a frame
// while its Future is outstanding.
Uint8List snapshotBytes(Uint8List bytes) => bytes;

Future<ZxingBackend> loadBackend() async {
  final abiVersion = native.zxd_abi_version();
  if (abiVersion != native.ZXD_ABI_VERSION) {
    throw StateError(
      'zxing_dart ABI mismatch: Dart expects ${native.ZXD_ABI_VERSION}, '
      'native asset provides $abiVersion',
    );
  }
  final buildInfoPointer = native.zxd_build_info();
  if (buildInfoPointer.address == 0) {
    throw StateError('zxing_dart native asset returned null build info');
  }
  return _NativeBackend(
    ZxingCapabilities(
      runtime: ZxingRuntime.native,
      abiVersion: abiVersion,
      buildInfo: buildInfoPointer.cast<Utf8>().toDartString(),
      canReadBarcodes: true,
      canEncodeAztec: true,
    ),
  );
}

final class _NativeBackend implements ZxingBackend {
  const _NativeBackend(this.capabilities);

  @override
  final ZxingCapabilities capabilities;

  @override
  Future<BarcodeResult?> readBarcode(
    Uint8List pixels, {
    required int width,
    required int height,
    required int rowStride,
    required BarcodePixelFormat pixelFormat,
    required int formatsMask,
    required bool tryHarder,
  }) => Isolate.run(
    () => _readOnHelperIsolate(
      pixels,
      width,
      height,
      rowStride,
      pixelFormat,
      formatsMask,
      tryHarder,
    ),
  );

  @override
  Future<BarcodeMatrix> encodeAztec(
    Uint8List asciiPayload, {
    required int eccLevel,
  }) => Isolate.run(() => _encodeOnHelperIsolate(asciiPayload, eccLevel));
}

BarcodeResult? _readOnHelperIsolate(
  Uint8List pixels,
  int width,
  int height,
  int rowStride,
  BarcodePixelFormat pixelFormat,
  int formatsMask,
  bool tryHarder,
) {
  final input = malloc<Uint8>(pixels.length);
  final output = calloc<native.zxd_read_result>();
  try {
    input.asTypedList(pixels.length).setAll(0, pixels);
    final status = native.zxd_read(
      input,
      pixels.length,
      width,
      height,
      rowStride,
      pixelFormat.nativeValue,
      formatsMask,
      tryHarder ? 1 : 0,
      output,
    );
    if (status == native.ZXD_NOT_FOUND) return null;
    _throwForStatus(status, operation: 'read barcode');

    final result = output.ref;
    if (result.text.address == 0 ||
        (result.bytes_len != 0 && result.bytes.address == 0)) {
      throw const ZxingException(
        4,
        'Native asset returned an invalid read result',
      );
    }
    final bytes = result.bytes_len == 0
        ? Uint8List(0)
        : result.bytes.asTypedList(result.bytes_len);
    final corners = [
      for (var index = 0; index < 8; index++) result.corners[index],
    ];
    return BarcodeResult(
      bytes: bytes,
      text: result.text.cast<Utf8>().toDartString(),
      nativeFormat: result.format,
      position: BarcodePosition(
        topLeft: BarcodePoint(corners[0], corners[1]),
        topRight: BarcodePoint(corners[2], corners[3]),
        bottomRight: BarcodePoint(corners[4], corners[5]),
        bottomLeft: BarcodePoint(corners[6], corners[7]),
      ),
    );
  } finally {
    native.zxd_read_result_release(output);
    calloc.free(output);
    malloc.free(input);
  }
}

BarcodeMatrix _encodeOnHelperIsolate(Uint8List asciiPayload, int eccLevel) {
  final input = malloc<Uint8>(asciiPayload.length);
  final output = calloc<native.zxd_matrix>();
  try {
    input.asTypedList(asciiPayload.length).setAll(0, asciiPayload);
    final status = native.zxd_encode_aztec(
      input,
      asciiPayload.length,
      eccLevel,
      output,
    );
    _throwForStatus(status, operation: 'encode Aztec');

    final matrix = output.ref;
    if (matrix.width == 0 || matrix.height == 0 || matrix.bits.address == 0) {
      throw const ZxingException(4, 'Native asset returned an invalid matrix');
    }
    final rowStride = (matrix.width + 7) ~/ 8;
    final length = rowStride * matrix.height;
    return BarcodeMatrix(
      width: matrix.width,
      height: matrix.height,
      bits: matrix.bits.asTypedList(length),
    );
  } finally {
    native.zxd_matrix_release(output);
    calloc.free(output);
    malloc.free(input);
  }
}

void _throwForStatus(int status, {required String operation}) {
  if (status == native.ZXD_OK) return;
  final message = switch (status) {
    native.ZXD_NOT_FOUND => 'No barcode found',
    native.ZXD_INVALID_ARGUMENT => 'Native asset rejected an argument',
    native.ZXD_ENCODE_ERROR => 'zxing-cpp could not encode the payload',
    native.ZXD_INTERNAL_ERROR => 'Unexpected failure inside zxing-cpp',
    _ => 'Unknown native status',
  };
  throw ZxingException(status, 'Failed to $operation: $message');
}
