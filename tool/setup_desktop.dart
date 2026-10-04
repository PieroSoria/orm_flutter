// Run from the Flutter application directory:
// dart run /path/to/orm_flutter/tool/setup_desktop.dart <target> [engine-commit]
import 'dart:convert';
import 'dart:io';

import 'macos_bundle.dart';

const defaultCommit = '361e86d0ea4987e9f53a565309b3eed797a6bcbd';

Future<void> main(List<String> args) async {
  if (args.isEmpty ||
      args.length > 2 ||
      !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(args[0])) {
    stderr.writeln(
        'Usage: setup_desktop.dart <Prisma binary target> [engine commit]');
    exitCode = 64;
    return;
  }
  final target = args[0];
  final commit = args.length == 2 ? args[1] : defaultCommit;
  if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(commit)) {
    throw ArgumentError('Expected a 40-character engine commit');
  }
  final destination = Directory('prisma/engines');
  await destination.create(recursive: true);
  final staging = await destination.createTemp('download-');
  final client = HttpClient();
  try {
    for (final engine in ['query-engine', 'schema-engine']) {
      final filename = '$engine${target == 'windows' ? '.exe' : ''}';
      final url = Uri.parse(
          'https://binaries.prisma.sh/all_commits/$commit/$target/$filename.gz');
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('Engine download returned ${response.statusCode}',
            uri: url);
      }
      final compressed = await response
          .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
      final file = File('${staging.path}/$filename');
      await file.writeAsBytes(gzip.decode(compressed), flush: true);
      if (!Platform.isWindows) {
        final permission = await Process.run('chmod', ['755', file.path]);
        if (permission.exitCode != 0) throw StateError('${permission.stderr}');
      }
      stdout.writeln('Downloaded $filename ($target, $commit)');
    }
    for (final engine in ['query-engine', 'schema-engine']) {
      final filename = '$engine${target == 'windows' ? '.exe' : ''}';
      final targetFile = File('${destination.path}/$filename');
      if (await targetFile.exists()) await targetFile.delete();
      await File('${staging.path}/$filename').rename(targetFile.path);
    }
    if (target.startsWith('darwin')) await configureMacosBundle();
    await File('${destination.path}/target.json')
        .writeAsString(jsonEncode({'target': target, 'commit': commit}));
  } finally {
    client.close();
    await staging.delete(recursive: true);
  }
}
