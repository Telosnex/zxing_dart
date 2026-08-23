import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';
import 'dart:typed_data';

import '../models.dart';
import '../web_config.dart';
import 'backend.dart';

/// Must match ZXD_ABI_VERSION and zxing_dart_loader.mjs.
const _abiVersion = 2;

const _flutterAssetWorkerUrl =
    'assets/packages/zxing_dart/web/zxing_dart_worker.mjs';

/// Copy at API-call time into JavaScript-owned memory. Transferring the result
/// can detach this private snapshot without detaching the caller's Uint8List.
Uint8List snapshotBytes(Uint8List bytes) => bytes.toJS.slice().toDart;

Future<ZxingBackend> loadBackend() async {
  final workerCount = ZxingDartWeb.workerCount;
  if (workerCount < 1 || workerCount > 4) {
    throw RangeError.range(workerCount, 1, 4, 'ZxingDartWeb.workerCount');
  }
  final configuredUri =
      ZxingDartWeb.workerUri ?? Uri.parse(_flutterAssetWorkerUrl);
  final workerUrl = Uri.parse(
    _documentBaseUri,
  ).resolveUri(configuredUri).toString();
  final workers = <_WebWorkerBackend>[];
  try {
    for (var index = 0; index < workerCount; index++) {
      workers.add(_WebWorkerBackend(workerUrl));
    }
    final capabilities = await Future.wait(
      workers.map((worker) => worker.initialize()),
    );
    final expected = capabilities.first;
    for (final actual in capabilities) {
      if (actual.abiVersion != expected.abiVersion ||
          actual.buildInfo != expected.buildInfo) {
        throw StateError('zxing_dart Workers returned different capabilities');
      }
    }
    return _WebPoolBackend(workerUrl, expected, workers);
  } on Object {
    for (final worker in workers) {
      worker.terminate();
    }
    rethrow;
  }
}

/// Bounded pool of independent single-operation Wasm runtimes. A failed Worker
/// is removed and replaced without replaying its operation (replaying a frame
/// behind the caller's back would make cancellation and timing surprising).
final class _WebPoolBackend implements ZxingBackend {
  _WebPoolBackend(
    this._workerUrl,
    this._capabilities,
    List<_WebWorkerBackend> workers,
  ) : _workers = workers.toSet(),
      _idleWorkers = Queue.of(workers) {
    for (final worker in workers) {
      worker.onIdleFailure = _handleIdleFailure;
    }
  }

  final String _workerUrl;
  final ZxingCapabilities _capabilities;
  final Set<_WebWorkerBackend> _workers;
  final Queue<_WebWorkerBackend> _idleWorkers;
  final Queue<_QueuedOperation<Object?>> _operations = Queue();
  int _replacementsInProgress = 0;
  ZxingException? _terminalError;

  @override
  ZxingCapabilities get capabilities => _capabilities;

  @override
  Future<BarcodeResult?> readBarcode(
    Uint8List pixels, {
    required int width,
    required int height,
    required int rowStride,
    required BarcodePixelFormat pixelFormat,
    required int formatsMask,
    required bool tryHarder,
  }) => _enqueue(
    (worker) => worker.readBarcode(
      pixels,
      width: width,
      height: height,
      rowStride: rowStride,
      pixelFormat: pixelFormat,
      formatsMask: formatsMask,
      tryHarder: tryHarder,
    ),
  );

  @override
  Future<BarcodeMatrix> encodeAztec(
    Uint8List asciiPayload, {
    required int errorCorrectionPercent,
  }) => _enqueue(
    (worker) => worker.encodeAztec(
      asciiPayload,
      errorCorrectionPercent: errorCorrectionPercent,
    ),
  );

  Future<T> _enqueue<T>(
    Future<T> Function(_WebWorkerBackend worker) operation,
  ) {
    final terminalError = _terminalError;
    if (terminalError != null) return Future.error(terminalError);
    final queued = _QueuedOperation<T>(operation);
    _operations.add(queued as _QueuedOperation<Object?>);
    _pump();
    return queued.future;
  }

  void _pump() {
    while (_idleWorkers.isNotEmpty && _operations.isNotEmpty) {
      final worker = _idleWorkers.removeFirst();
      final operation = _operations.removeFirst();
      unawaited(_dispatch(worker, operation));
    }
  }

  Future<void> _dispatch(
    _WebWorkerBackend worker,
    _QueuedOperation<Object?> operation,
  ) async {
    try {
      operation.complete(await operation.run(worker));
      _idleWorkers.add(worker);
    } on _WorkerFailure catch (failure, stackTrace) {
      operation.completeError(failure.error, stackTrace);
      _removeFailedWorker(worker);
    } on Object catch (error, stackTrace) {
      // A codec/status error does not poison the Worker.
      operation.completeError(error, stackTrace);
      _idleWorkers.add(worker);
    }
    _pump();
  }

  void _handleIdleFailure(_WebWorkerBackend worker, ZxingException error) {
    _removeFailedWorker(worker);
    _pump();
  }

  void _removeFailedWorker(_WebWorkerBackend worker) {
    if (!_workers.remove(worker)) return;
    _idleWorkers.remove(worker);
    worker.terminate();
    unawaited(_replaceWorker());
  }

  Future<void> _replaceWorker() async {
    _replacementsInProgress++;
    _WebWorkerBackend? replacement;
    try {
      replacement = _WebWorkerBackend(_workerUrl);
      final capabilities = await replacement.initialize();
      if (capabilities.abiVersion != _capabilities.abiVersion ||
          capabilities.buildInfo != _capabilities.buildInfo) {
        throw StateError(
          'replacement zxing_dart Worker returned different capabilities',
        );
      }
      replacement.onIdleFailure = _handleIdleFailure;
      _workers.add(replacement);
      _idleWorkers.add(replacement);
    } on Object catch (error) {
      replacement?.terminate();
      if (_workers.isEmpty && _replacementsInProgress == 1) {
        _terminalError = ZxingException(
          -2,
          'zxing_dart has no live Workers after replacement failed: $error',
        );
      }
    } finally {
      _replacementsInProgress--;
    }
    if (_workers.isEmpty && _replacementsInProgress == 0) {
      _terminalError ??= const ZxingException(
        -2,
        'zxing_dart has no live Workers',
      );
      _failQueued(_terminalError!);
    }
    _pump();
  }

  void _failQueued(ZxingException error) {
    while (_operations.isNotEmpty) {
      _operations.removeFirst().completeError(error, StackTrace.current);
    }
  }
}

final class _QueuedOperation<T> {
  _QueuedOperation(this._operation);

  final Future<T> Function(_WebWorkerBackend worker) _operation;
  final Completer<T> _completer = Completer<T>();

  Future<T> get future => _completer.future;
  Future<T> run(_WebWorkerBackend worker) => _operation(worker);
  void complete(Object? value) => _completer.complete(value as T);
  void completeError(Object error, StackTrace stackTrace) =>
      _completer.completeError(error, stackTrace);
}

final class _WorkerFailure implements Exception {
  const _WorkerFailure(this.error);
  final ZxingException error;
}

final class _WebWorkerBackend implements ZxingBackend {
  _WebWorkerBackend(this._workerUrl)
    : _worker = _Worker(_workerUrl, _WorkerOptions(type: 'module')) {
    _worker.onmessage = _handleMessage.toJS;
    _worker.onerror = _handleError.toJS;
  }

  final String _workerUrl;
  final _Worker _worker;
  final _pending = <int, Completer<JSObject>>{};
  int _nextRequestId = 0;
  bool _terminated = false;
  late final ZxingCapabilities _capabilities;
  void Function(_WebWorkerBackend worker, ZxingException error)? onIdleFailure;

  Future<ZxingCapabilities> initialize() async {
    try {
      final result = _CapabilitiesResult.wrap(
        await _request(
          (id) => _WorkerRequest(id: id, operation: 'capabilities'),
        ),
      );
      if (result.abiVersion != _abiVersion) {
        throw StateError(
          'zxing_dart ABI mismatch: Dart expects $_abiVersion, Wasm module '
          'provides ${result.abiVersion}',
        );
      }
      return _capabilities = ZxingCapabilities(
        runtime: ZxingRuntime.webAssembly,
        abiVersion: result.abiVersion,
        buildInfo: result.buildInfo,
        canReadBarcodes: true,
        canEncodeAztec: true,
      );
    } on _WorkerFailure catch (failure) {
      throw failure.error;
    }
  }

  @override
  ZxingCapabilities get capabilities => _capabilities;

  @override
  Future<BarcodeResult?> readBarcode(
    Uint8List pixels, {
    required int width,
    required int height,
    required int rowStride,
    required BarcodePixelFormat pixelFormat,
    required int formatsMask,
    required bool tryHarder,
  }) async {
    final buffer = _transferableBuffer(pixels);
    final result = _ReadResult.wrap(
      await _request(
        (id) => _WorkerRequest(
          id: id,
          operation: 'readBarcode',
          pixels: buffer,
          width: width,
          height: height,
          rowStride: rowStride,
          pixelFormat: pixelFormat.nativeValue,
          formatsMask: formatsMask,
          tryHarder: tryHarder,
        ),
        transfer: buffer,
      ),
    );
    if (!result.found) return null;
    final bytes = result.bytes;
    final text = result.text;
    final nativeFormat = result.nativeFormat;
    final corners = result.corners;
    if (bytes == null ||
        text == null ||
        nativeFormat == null ||
        corners == null ||
        corners.length != 8) {
      throw const ZxingException(-1, 'Wasm Worker returned invalid read data');
    }
    final points = [for (final value in corners.toDart) value.toDartInt];
    return BarcodeResult(
      bytes: bytes.toDart,
      text: text,
      nativeFormat: nativeFormat,
      position: BarcodePosition(
        topLeft: BarcodePoint(points[0], points[1]),
        topRight: BarcodePoint(points[2], points[3]),
        bottomRight: BarcodePoint(points[4], points[5]),
        bottomLeft: BarcodePoint(points[6], points[7]),
      ),
    );
  }

  @override
  Future<BarcodeMatrix> encodeAztec(
    Uint8List asciiPayload, {
    required int errorCorrectionPercent,
  }) async {
    final buffer = _transferableBuffer(asciiPayload);
    final result = _MatrixResult.wrap(
      await _request(
        (id) => _WorkerRequest(
          id: id,
          operation: 'encodeAztec',
          payload: buffer,
          errorCorrectionPercent: errorCorrectionPercent,
        ),
        transfer: buffer,
      ),
    );
    return BarcodeMatrix(
      width: result.width,
      height: result.height,
      bits: result.bits.toDart,
    );
  }

  void terminate([ZxingException? error]) {
    if (_terminated) return;
    _terminated = true;
    _worker.terminate();
    _failAllPending(
      _WorkerFailure(
        error ??
            const ZxingException(
              -2,
              'zxing_dart Worker terminated during initialization',
            ),
      ),
    );
  }

  Future<JSObject> _request(
    _WorkerRequest Function(int id) build, {
    JSArrayBuffer? transfer,
  }) {
    if (_terminated) {
      return Future.error(
        const _WorkerFailure(
          ZxingException(-2, 'zxing_dart Worker terminated unexpectedly'),
        ),
      );
    }
    if (_pending.isNotEmpty) {
      throw StateError('zxing_dart Worker received concurrent operations');
    }
    final id = _nextRequestId++;
    final completer = Completer<JSObject>();
    _pending[id] = completer;
    try {
      _worker.postMessage(
        build(id),
        (transfer == null ? const <JSObject>[] : <JSObject>[transfer]).toJS,
      );
    } on Object catch (error, stackTrace) {
      _pending.remove(id);
      completer.completeError(
        _WorkerFailure(
          ZxingException(-2, 'zxing_dart Worker postMessage failed: $error'),
        ),
        stackTrace,
      );
    }
    return completer.future;
  }

  void _handleMessage(_MessageEvent event) {
    final response = _WorkerResponse.wrap(event.data);
    final completer = _pending.remove(response.id);
    if (completer == null) return;
    final error = response.error;
    if (error != null) {
      completer.completeError(
        ZxingException(
          error.status ?? -1,
          error.message ?? 'Unknown zxing_dart Worker error',
        ),
      );
      return;
    }
    final result = response.result;
    if (result == null) {
      completer.completeError(
        const ZxingException(-1, 'zxing_dart Worker returned no result'),
      );
      return;
    }
    completer.complete(result);
  }

  void _handleError(_ErrorEvent event) {
    final detail = event.message;
    final error = ZxingException(
      -2,
      'zxing_dart Worker failed to load from $_workerUrl'
      '${detail == null || detail.isEmpty ? '' : ': $detail'}. Flutter web '
      'apps bundle it automatically; other embedders must serve '
      'package:zxing_dart/web/ and set ZxingDartWeb.workerUri.',
    );
    final wasIdle = _pending.isEmpty;
    terminate(error);
    if (wasIdle) onIdleFailure?.call(this, error);
  }

  void _failAllPending(Object error) {
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(error);
    }
  }
}

JSArrayBuffer _transferableBuffer(Uint8List bytes) => bytes.toJS.buffer;

extension _JSUint8ArrayToBuffer on JSUint8Array {
  external JSArrayBuffer get buffer;
  external JSUint8Array slice();
}

@JS('document.baseURI')
external String get _documentBaseUri;

extension type _WorkerOptions._(JSObject _) implements JSObject {
  external factory _WorkerOptions({String type});
}

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external _Worker(String scriptURL, _WorkerOptions options);
  external void postMessage(JSAny? message, JSArray<JSObject> transfer);
  external set onmessage(JSFunction value);
  external set onerror(JSFunction value);
  external void terminate();
}

extension type _MessageEvent._(JSObject _) implements JSObject {
  external JSObject get data;
}

extension type _ErrorEvent._(JSObject _) implements JSObject {
  external String? get message;
}

extension type _WorkerRequest._(JSObject _) implements JSObject {
  external factory _WorkerRequest({
    int id,
    String operation,
    JSArrayBuffer pixels,
    JSArrayBuffer payload,
    int width,
    int height,
    int rowStride,
    int pixelFormat,
    int formatsMask,
    bool tryHarder,
    int errorCorrectionPercent,
  });
}

extension type _WorkerResponse.wrap(JSObject _) implements JSObject {
  external int get id;
  external JSObject? get result;
  external _WorkerError? get error;
}

extension type _WorkerError._(JSObject _) implements JSObject {
  external int? get status;
  external String? get message;
}

extension type _CapabilitiesResult.wrap(JSObject _) implements JSObject {
  external int get abiVersion;
  external String get buildInfo;
}

extension type _ReadResult.wrap(JSObject _) implements JSObject {
  external bool get found;
  external JSUint8Array? get bytes;
  external String? get text;
  external int? get nativeFormat;
  external JSArray<JSNumber>? get corners;
}

extension type _MatrixResult.wrap(JSObject _) implements JSObject {
  external int get width;
  external int get height;
  external JSUint8Array get bits;
}
