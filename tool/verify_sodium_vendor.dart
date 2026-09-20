import 'dart:io';
import 'dart:typed_data';

const _patchedPath = 'lib/src/hooks/sodium_builder/windows_builder.dart';

Future<void> main() async {
  final root = Directory.current;
  final archive = File(
    '${root.path}${Platform.pathSeparator}third_party${Platform.pathSeparator}'
    'provenance${Platform.pathSeparator}sodium-4.0.2+1.tar.gz',
  );
  final vendor = Directory(
    '${root.path}${Platform.pathSeparator}third_party${Platform.pathSeparator}sodium',
  );
  final temporary = await Directory.systemTemp.createTemp('startrail-sodium-');
  try {
    final extraction = await Process.run('tar', [
      '-xzf',
      archive.path,
      '-C',
      temporary.path,
    ]);
    if (extraction.exitCode != 0) {
      throw StateError('Unable to extract sodium provenance archive');
    }

    final upstreamFiles = await _files(temporary);
    final vendorFiles = await _files(vendor);
    if (!_sameStrings(upstreamFiles.keys, vendorFiles.keys)) {
      throw StateError('Vendored sodium file set differs from upstream');
    }

    for (final path in upstreamFiles.keys) {
      final upstream = await upstreamFiles[path]!.readAsBytes();
      final actual = await vendorFiles[path]!.readAsBytes();
      if (path == _patchedPath) {
        final source = String.fromCharCodes(upstream);
        const anchor = "            'json',\n";
        if (anchor.allMatches(source).length != 1) {
          throw StateError('Unexpected upstream vswhere argument block');
        }
        final expected = Uint8List.fromList(
          source
              .replaceFirst(anchor, "$anchor            '-utf8',\n")
              .codeUnits,
        );
        if (!_sameBytes(expected, actual)) {
          throw StateError('Sodium patch differs from approved single line');
        }
      } else if (!_sameBytes(upstream, actual)) {
        throw StateError('Unexpected sodium vendor change: $path');
      }
    }
    stdout.writeln('sodium vendor matches upstream plus approved -utf8 line');
  } finally {
    await temporary.delete(recursive: true);
  }
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
