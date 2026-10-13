/// Checks the upstream source pins and the build profile in
/// native_artifacts/manifest.json.
library;

import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final manifestFile = File('${root.path}/native_artifacts/manifest.json');
  final manifest = jsonDecode(await manifestFile.readAsString());
  if (manifest is! Map<String, Object?> || manifest['schema'] != 1) {
    throw const FormatException('Unsupported artifact manifest');
  }
  final sources = manifest['sources'];
  if (manifest['profile'] != 5 ||
      sources is! Map<String, Object?> ||
      sources.length != 2 ||
      sources['zxing-cpp'] != '287c85df6f961c8efbfb5ffd736cd9457b8b890e' ||
      sources['zint'] != '55541e139e62b9209b71cd9b0ba9010cec28b1d9') {
    throw const FormatException('Unexpected production source/build profile');
  }

  if (manifest.containsKey('artifacts')) {
    throw const FormatException(
      'Native libraries belong in native_artifacts/prebuilt.json.',
    );
  }
  if (manifest.containsKey('web')) {
    throw const FormatException(
      'Web files belong in native_artifacts/web.json (native_prebuilt '
      'ADR 002). native_prebuilt:check verifies them.',
    );
  }
  stdout.writeln('OK sources and profile');
}
