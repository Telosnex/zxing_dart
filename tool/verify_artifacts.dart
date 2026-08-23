import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main() async {
  final root = Directory.current;
  final manifestFile = File('${root.path}/native_artifacts/manifest.json');
  final manifest = jsonDecode(await manifestFile.readAsString());
  if (manifest is! Map<String, Object?> || manifest['schema'] != 1) {
    throw const FormatException('Unsupported artifact manifest');
  }

  final checks = <({String label, File file, String expected})>[];
  final native = manifest['artifacts'];
  if (native is! Map<String, Object?>) {
    throw const FormatException('Missing native artifacts');
  }
  for (final MapEntry(key: target, value: encoded) in native.entries) {
    if (encoded case {'path': final String path, 'sha256': final String hash}) {
      checks.add((
        label: target,
        file: File('${root.path}/native_artifacts/$path'),
        expected: hash,
      ));
    } else {
      throw FormatException('Malformed native artifact: $target');
    }
  }

  final web = manifest['web'];
  if (web is! Map<String, Object?>) throw const FormatException('Missing web');
  for (final MapEntry(key: name, value: encoded) in web.entries) {
    if (encoded case {'path': final String path, 'sha256': final String hash}) {
      checks.add((
        label: 'web/$name',
        file: File('${root.path}/$path'),
        expected: hash,
      ));
    } else {
      throw FormatException('Malformed web artifact: $name');
    }
  }

  var failed = false;
  for (final check in checks) {
    if (!await check.file.exists()) {
      stderr.writeln('MISSING ${check.label}: ${check.file.path}');
      failed = true;
      continue;
    }
    final actual = sha256.convert(await check.file.readAsBytes()).toString();
    if (actual != check.expected) {
      stderr.writeln(
        'MISMATCH ${check.label}: expected ${check.expected}, got $actual',
      );
      failed = true;
    } else {
      stdout.writeln('OK ${check.label} $actual');
    }
  }
  if (failed) exitCode = 1;
}
