@TestOn('vm')
library;

import 'dart:io';

import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:test/test.dart';

void main() {
  late Directory fixture;
  late SourceKey original;

  setUp(() async {
    original = await computeSourceKey(Directory.current.uri);
    fixture = await Directory.systemTemp.createTemp('zxing_source_key_');
    for (final source in original.files) {
      final copy = File.fromUri(fixture.uri.resolve(source.path));
      await copy.parent.create(recursive: true);
      await File.fromUri(source.uri).copy(copy.path);
    }
  });
  tearDown(() => fixture.delete(recursive: true));

  Future<void> write(String path, String contents) async {
    final file = File.fromUri(fixture.uri.resolve(path));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  test('source key covers the entire native build recipe', () {
    expect(
      original.files.map((f) => f.path),
      containsAll([
        'CMakeLists.txt',
        'hook/build.dart',
        'native_artifacts/source_excludes.txt',
        'pubspec.yaml',
        'src/zxing_dart.cpp',
        'src/exports_windows.def',
        'tool/build_native_artifact.sh',
        'tool/fetch_zxing.sh',
        'tool/install_build_toolchain.sh',
      ]),
    );
  });

  test('Git checkout and non-Git package have identical keys', () async {
    final unpacked = await computeSourceKey(fixture.uri);
    expect(unpacked.usedGit, isFalse);
    expect(unpacked.key, original.key);
  });

  test(
    'web, release metadata and fetched/generated files do not change key',
    () async {
      for (final path in [
        'lib/web/zxing_dart_module.wasm',
        'native_artifacts/prebuilt.json',
        'native_artifacts/manifest.json',
        'third_party/zxing-cpp/core/generated.cpp',
        'build/native_artifacts/macos-arm64/libzxing_dart.dylib',
        '.github/workflows/native_release.yml',
      ]) {
        await write(path, 'not a native build input');
      }
      expect((await computeSourceKey(fixture.uri)).key, original.key);
    },
  );

  test(
    'native source or toolchain recipe changes invalidate release',
    () async {
      for (final path in [
        'src/zxing_dart.cpp',
        'tool/install_build_toolchain.sh',
      ]) {
        final file = File.fromUri(fixture.uri.resolve(path));
        final saved = await file.readAsBytes();
        await write(path, 'changed');
        expect((await computeSourceKey(fixture.uri)).key, isNot(original.key));
        await file.writeAsBytes(saved);
      }
    },
  );
}
