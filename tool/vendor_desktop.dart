// Maintainer command: downloads the binaries shipped inside this plugin.
// Applications never need to run this command.
import 'dart:io';

import 'package:crypto/crypto.dart';

const commit = '361e86d0ea4987e9f53a565309b3eed797a6bcbd';
const targets = [
  'darwin',
  'darwin-arm64',
  'windows',
  'debian-openssl-3.0.x',
  'linux-arm64-openssl-3.0.x',
  'linux-musl-openssl-3.0.x',
  'linux-musl-arm64-openssl-3.0.x',
];

Future<void> main(List<String> args) async {
  final selected = args.isEmpty ? targets : args;
  for (final target in selected) {
    if (!targets.contains(target)) {
      throw ArgumentError('Unsupported target: $target');
    }
  }
  final client = HttpClient();
  try {
    for (final target in selected) {
      await Future.wait(['query-engine', 'schema-engine'].map((engine) async {
        final name = '$engine${target == 'windows' ? '.exe' : ''}';
        final uri = Uri.parse(
            'https://binaries.prisma.sh/all_commits/$commit/$target/$name.gz');
        final response = await (await client.getUrl(uri)).close();
        if (response.statusCode != 200) {
          throw HttpException('HTTP ${response.statusCode}', uri: uri);
        }
        final compressed = await response
            .fold<List<int>>([], (all, chunk) => all..addAll(chunk));
        final checksumResponse =
            await (await client.getUrl(Uri.parse('$uri.sha256'))).close();
        if (checksumResponse.statusCode != 200) {
          throw StateError('Missing checksum for $uri');
        }
        final checksum =
            (await checksumResponse.transform(SystemEncoding().decoder).join())
                .trim()
                .split(RegExp(r'\s+'))
                .first;
        if (sha256.convert(compressed).toString() != checksum) {
          throw StateError('Checksum mismatch: $uri');
        }
        final file = File('desktop/engines/$target/prisma-$name');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(gzip.decode(compressed), flush: true);
        if (!Platform.isWindows) {
          final chmod = await Process.run('chmod', ['755', file.path]);
          if (chmod.exitCode != 0) throw StateError('${chmod.stderr}');
        }
        stdout.writeln('Vendored $target/$name');
      }));
    }
    if (Platform.isMacOS &&
        selected.contains('darwin') &&
        selected.contains('darwin-arm64')) {
      final destination =
          Directory('macos/orm_flutter/Sources/orm_flutter/Engines');
      await destination.create(recursive: true);
      await File('desktop/PRISMA_LICENSE')
          .copy('${destination.path}/PRISMA_LICENSE');
      for (final engine in ['query-engine', 'schema-engine']) {
        final output = '${destination.path}/prisma-$engine';
        final lipo = await Process.run('/usr/bin/lipo', [
          '-create',
          'desktop/engines/darwin/prisma-$engine',
          'desktop/engines/darwin-arm64/prisma-$engine',
          '-output',
          output
        ]);
        if (lipo.exitCode != 0) throw StateError('${lipo.stderr}');
        final signature = await Process.run('/usr/bin/codesign', [
          '--force',
          '--sign',
          '-',
          '--entitlements',
          'macos/Engine.entitlements',
          output
        ]);
        if (signature.exitCode != 0) throw StateError('${signature.stderr}');
        stdout.writeln('Created signed universal macOS $engine');
      }
    }
  } finally {
    client.close();
  }
}
