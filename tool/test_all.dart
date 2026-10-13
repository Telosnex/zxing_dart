/// Runs the full test gate: analysis, artifact checks, the VM tests, and the
/// browser tests with dart2js and dart2wasm in Chrome, and with dart2js in
/// Safari on macOS (set ZXD_SKIP_SAFARI=1 to skip Safari).
///
/// The browser tests load the web files from lib/web/, so the generated files
/// are installed first (native_prebuilt ADR 002 D13):
///
///     dart run tool/test_all.dart                     # files of web.json
///     dart run tool/test_all.dart --web-from <dir>    # a local web build
library;

import 'dart:io';

Future<void> main(List<String> args) async {
  final webFrom = switch (args) {
    [] => null,
    ['--web-from', final dir] => dir,
    _ => _fail('Usage: dart run tool/test_all.dart [--web-from <dir>]'),
  };
  Directory.current = Directory.fromUri(Platform.script.resolve('..'));

  await _run(['analyze']);
  await _run(['run', 'tool/verify_artifacts.dart']);
  await _run(['run', 'native_prebuilt:check']);
  await _run([
    'run',
    'native_prebuilt:web',
    'install-dev',
    if (webFrom != null) ...['--from', webFrom],
  ]);
  await _run(['test', '-r', 'compact']);
  await _run([
    'test',
    '-p',
    'chrome',
    '--compiler',
    'dart2js',
    '-r',
    'compact',
  ]);
  // Each dart2wasm browser suite owns both the Dart test Wasm module and one
  // or more codec Wasm Workers. Serialize files to avoid Chrome
  // process-memory pressure hiding real results as generic "did not
  // complete" failures.
  await _run([
    'test',
    '-p',
    'chrome',
    '--compiler',
    'dart2wasm',
    '-j',
    '1',
    '-r',
    'compact',
  ]);
  // Serial: one Safari instance cannot reliably host several package:test
  // managers at once.
  if (Platform.isMacOS && Platform.environment['ZXD_SKIP_SAFARI'] != '1') {
    await _run([
      'test',
      '-p',
      'safari',
      '--compiler',
      'dart2js',
      '-j',
      '1',
      '-r',
      'compact',
    ]);
  }
}

Future<void> _run(List<String> args) async {
  stdout.writeln('+ dart ${args.join(' ')}');
  final process = await Process.start(
    Platform.resolvedExecutable,
    args,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) _fail('dart ${args.join(' ')} failed with exit code $code.');
}

Never _fail(String message) {
  stderr.writeln('test_all: $message');
  exit(1);
}
