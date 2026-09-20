import 'dart:io';
import 'dart:typed_data';

const _runProcessPath = 'lib/src/utils/run_process.dart';
const _msvcPath = 'lib/src/native_toolchain/msvc.dart';

Future<void> main() async {
  final root = Directory.current;
  final archive = File(
    '${root.path}${Platform.pathSeparator}third_party${Platform.pathSeparator}'
    'provenance${Platform.pathSeparator}native_toolchain_c-0.18.0.tar.gz',
  );
  final vendor = Directory(
    '${root.path}${Platform.pathSeparator}third_party${Platform.pathSeparator}'
    'native_toolchain_c',
  );
  final temporary = await Directory.systemTemp.createTemp(
    'startrail-native-toolchain-',
  );
  try {
    final extraction = await Process.run('tar', [
      '-xzf',
      archive.path,
      '-C',
      temporary.path,
    ]);
    if (extraction.exitCode != 0) {
      throw StateError('Unable to extract native_toolchain_c archive');
    }

    final upstreamFiles = await _files(temporary);
    final vendorFiles = await _files(vendor);
    if (!_sameStrings(upstreamFiles.keys, vendorFiles.keys)) {
      throw StateError('Vendored native_toolchain_c file set differs');
    }

    for (final path in upstreamFiles.keys) {
      final upstream = await upstreamFiles[path]!.readAsBytes();
      final actual = await vendorFiles[path]!.readAsBytes();
      final Uint8List expected;
      if (path == _runProcessPath) {
        expected = _patchedRunProcess(upstream);
      } else if (path == _msvcPath) {
        expected = _patchedMsvc(upstream);
      } else {
        expected = upstream;
      }
      if (!_sameBytes(expected, actual)) {
        throw StateError('Unexpected native_toolchain_c change: $path');
      }
    }
    stdout.writeln(
      'native_toolchain_c matches upstream plus approved UTF-8 patch',
    );
  } finally {
    await temporary.delete(recursive: true);
  }
}

Uint8List _patchedRunProcess(Uint8List bytes) {
  var source = String.fromCharCodes(bytes);
  source = _replaceOnce(
    source,
    "import 'dart:async';\n",
    "import 'dart:async';\nimport 'dart:convert';\n",
  );
  source = _replaceOnce(
    source,
    '  bool throwOnUnexpectedExitCode = false,\n',
    '  bool throwOnUnexpectedExitCode = false,\n'
        '  Encoding outputEncoding = systemEncoding,\n',
  );
  if ('systemEncoding.decode(data)'.allMatches(source).length != 2) {
    throw StateError('Unexpected upstream process decoder');
  }
  source = source.replaceAll(
    'systemEncoding.decode(data)',
    'outputEncoding.decode(data)',
  );
  return Uint8List.fromList(source.codeUnits);
}

Uint8List _patchedMsvc(Uint8List bytes) {
  final source = String.fromCharCodes(bytes);
  const anchor = '        logger: logger,\n';
  return Uint8List.fromList(
    _replaceOnce(
      source,
      anchor,
      "${anchor}        outputEncoding: utf8,\n",
    ).codeUnits,
  );
}

String _replaceOnce(String source, String before, String after) {
  if (before.allMatches(source).length != 1) {
    throw StateError('Unexpected upstream patch anchor');
  }
  return source.replaceFirst(before, after);
}

Future<Map<String, File>> _files(Directory directory) async {
  final result = <String, File>{};
  await for (final entity in directory.list(
    recursive: true,
    followLinks: true,
  )) {
    if (entity is! File) continue;
    final relative = entity.path
        .substring(directory.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    result[relative] = entity;
  }
  return result;
}

bool _sameStrings(Iterable<String> left, Iterable<String> right) {
  final a = left.toList()..sort();
  final b = right.toList()..sort();
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
