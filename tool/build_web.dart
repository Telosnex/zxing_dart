/// Builds the pinned zxing-cpp and the zxing_dart shim as one Emscripten ES
/// module: zxing_dart_module.mjs and zxing_dart_module.wasm in --out.
///
/// The release workflow runs it in the pinned emscripten/emsdk image
/// (native_prebuilt ADR 002 D10). For a local build, activate the Emscripten
/// SDK, or put it at ../emsdk, then install the files with
///
///     dart run tool/build_web.dart --out /tmp/zxd_web
///     dart run native_prebuilt:web install-dev --from /tmp/zxd_web
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

const _usage =
    'dart run tool/build_web.dart --out <dir> [--work <dir>]\n'
    '  --out   Directory for the two generated files. It must be empty or '
    'hold only these files.\n'
    '  --work  CMake build directory. Default: build/web.';

const _outputs = ['zxing_dart_module.mjs', 'zxing_dart_module.wasm'];

/// The exports of the C ABI, and the malloc and free that the loader uses.
const _exportedFunctions = [
  '_malloc',
  '_free',
  '_zxd_abi_version',
  '_zxd_build_info',
  '_zxd_read',
  '_zxd_read_result_release',
  '_zxd_encode_aztec',
  '_zxd_encode',
  '_zxd_matrix_release',
];

Future<void> main(List<String> args) async {
  final options = _parse(args);
  final root = Directory.fromUri(Platform.script.resolve('..')).absolute.path;
  final out = Directory(options['out']!).absolute;
  final work = Directory(options['work'] ?? '$root/build/web').absolute;

  if (await out.exists()) {
    final others = [
      await for (final entity in out.list())
        if (!_outputs.contains(
          entity.uri.pathSegments.lastWhere((s) => s != ''),
        ))
          entity.path,
    ];
    if (others.isNotEmpty) {
      _fail('--out holds other files: ${others.join(', ')}');
    }
  }
  await out.create(recursive: true);

  final emsdkEnv = await _emsdkEnvironment(root);
  Future<void> run(List<String> command) =>
      _run(command, workingDirectory: root, emsdkEnv: emsdkEnv);

  await run(['bash', 'tool/fetch_zxing.sh']);
  final thirdParty =
      Platform.environment['ZXD_THIRD_PARTY'] ?? '$root/third_party';

  // Exception catching is required: zxing-cpp uses exceptions for malformed
  // and unencodable inputs, and the C ABI promises that none cross it.
  await run([
    'emcmake',
    'cmake',
    '-S',
    root,
    '-B',
    work.path,
    '-DCMAKE_BUILD_TYPE=Release',
    '-DCMAKE_CXX_FLAGS_RELEASE=-O3 -DNDEBUG -fexceptions',
    '-DZXD_BUILD_TESTS=OFF',
    '-DZXD_ZXING_SOURCE=$thirdParty/zxing-cpp',
  ]);
  await run([
    'cmake',
    '--build',
    work.path,
    '--target',
    'ZXing',
    '-j',
    '${Platform.numberOfProcessors}',
  ]);

  final zxingLib = '${work.path}/third_party/zxing-cpp/core/libZXing.a';
  if (!File(zxingLib).existsSync()) {
    _fail('Expected zxing-cpp archive not found: $zxingLib');
  }
  await run([
    'em++',
    '$root/src/zxing_dart.cpp',
    zxingLib,
    '-I$root/src',
    '-I$thirdParty/zxing-cpp/core/src',
    '-I${work.path}/third_party/zxing-cpp/core',
    '-std=c++20',
    '-O3',
    '-DNDEBUG',
    '-fexceptions',
    '--no-entry',
    '-sDISABLE_EXCEPTION_CATCHING=0',
    '-sMODULARIZE=1',
    '-sEXPORT_ES6=1',
    '-sENVIRONMENT=web,worker,node',
    '-sALLOW_MEMORY_GROWTH=1',
    '-sFILESYSTEM=0',
    '-sEXPORTED_FUNCTIONS=${_exportedFunctions.join(',')}',
    '-sEXPORTED_RUNTIME_METHODS=UTF8ToString,HEAPU8',
    '-o',
    '${out.path}/${_outputs.first}',
  ]);

  stdout.writeln('Built:');
  for (final name in _outputs) {
    final file = File('${out.path}/$name');
    if (!file.existsSync()) _fail('Expected output not found: ${file.path}');
    final bytes = await file.readAsBytes();
    stdout.writeln('  ${sha256.convert(bytes)}  ${bytes.length}  $name');
  }
}

Map<String, String> _parse(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') {
      stdout.writeln(_usage);
      exit(0);
    }
    final name = switch (arg) {
      '--out' => 'out',
      '--work' => 'work',
      _ => _fail('Unknown argument: $arg\n$_usage'),
    };
    if (i + 1 == args.length) _fail('$arg needs a value.\n$_usage');
    options[name] = args[++i];
  }
  if (options['out'] == null) _fail('Pass --out.\n$_usage');
  return options;
}

/// Null if em++ is on the PATH, else the path of ../emsdk/emsdk_env.sh,
/// which each command then sources.
Future<String?> _emsdkEnvironment(String root) async {
  final probe = await Process.run('bash', ['-c', 'command -v em++']);
  if (probe.exitCode == 0) return null;
  final env = File('$root/../emsdk/emsdk_env.sh');
  if (env.existsSync()) return env.absolute.path;
  _fail(
    'em++ not found. Activate the Emscripten SDK, or put it at '
    '${env.parent.path}.',
  );
}

Future<void> _run(
  List<String> command, {
  required String workingDirectory,
  required String? emsdkEnv,
}) async {
  stdout.writeln('+ ${command.join(' ')}');
  final process = await Process.start(
    emsdkEnv == null ? command.first : 'bash',
    emsdkEnv == null
        ? command.skip(1).toList()
        : [
            '-c',
            'source "\$0" > /dev/null && exec "\$@"',
            emsdkEnv,
            ...command,
          ],
    workingDirectory: workingDirectory,
    environment: {if (emsdkEnv != null) 'EMSDK_QUIET': '1'},
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) _fail('${command.first} failed with exit code $code.');
}

Never _fail(String message) {
  stderr.writeln('build_web: $message');
  exit(1);
}
