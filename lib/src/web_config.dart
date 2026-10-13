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
  /// In a Flutter web build, the zxing_dart build hook installs the worker,
  /// loader, generated module, and Wasm binary in
  /// `web/native_prebuilt/zxing_dart/`, which is the default (native_prebuilt
  /// ADR 002). Other browser embedders serve the four files same-origin, as
  /// siblings, and set this URI. The query `v=<webRuntimeVersion>` is added
  /// unless the URI has a `v` query. Set before the first operation.
  static Uri? workerUri;
}
