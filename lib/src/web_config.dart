/// Browser-only configuration for [ZxingDart].
///
/// Native platforms ignore these settings.
abstract final class ZxingDartWeb {
  /// Number of module Workers in the browser pool, from 1 through 4.
  ///
  /// Each Worker owns one independent zxing-cpp Wasm runtime and processes one
  /// operation at a time. One is sufficient for camera scanning; increasing
  /// this is useful for applications that concurrently process still images.
  /// Set this before the first [ZxingDart] call.
  static int workerCount = 1;

  /// Override the URL of `zxing_dart_worker.mjs`.
  ///
  /// Flutter web bundles the worker, loader, generated module, and Wasm binary
  /// under `assets/packages/zxing_dart/web/`, which is the default. Plain Dart
  /// browser embedders should serve `lib/web/` same-origin and set this URI.
  /// All four files must remain siblings. Set before the first operation.
  static Uri? workerUri;
}
