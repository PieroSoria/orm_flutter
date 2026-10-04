import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolve an explicit executable, a bundled executable, or a Flutter asset.
/// The manifest target is chosen at build time (including architecture/OpenSSL).
Future<File> resolveDesktopEngine(String engine) async {
  final variable = engine == 'query-engine'
      ? 'PRISMA_QUERY_ENGINE_BINARY'
      : 'PRISMA_SCHEMA_ENGINE_BINARY';
  final override = Platform.environment[variable];
  if (override != null && override.isNotEmpty) {
    final file = File(override).absolute;
    if (!await file.exists()) {
      throw StateError('$variable does not exist: ${file.path}');
    }
    return file;
  }

  final names = [
    'prisma-$engine${Platform.isWindows ? '.exe' : ''}',
    if (!Platform.isWindows)
      'prisma-$engine-${Platform.isMacOS ? 'mac' : 'linux'}',
  ];
  final executableDir = p.dirname(Platform.resolvedExecutable);
  for (final dir in [
    executableDir,
    p.join(executableDir, '..', 'Resources'),
    Directory.current.path,
    p.join(Directory.current.path, 'prisma'),
    p.join(Directory.current.path, '.dart_tool'),
  ]) {
    for (final name in names) {
      final file = File(p.join(dir, name));
      if (await file.exists()) return file.absolute;
    }
  }

  final asset = 'prisma/engines/$engine${Platform.isWindows ? '.exe' : ''}';
  final ByteData data;
  try {
    data = await rootBundle.load(asset);
  } catch (error) {
    throw StateError('Missing $engine for ${Platform.operatingSystem}. '
        'Run tool/setup_desktop.dart and add prisma/engines/ to Flutter assets, '
        'or set $variable to an executable path. ($error)');
  }
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final digest = sha256.convert(bytes).toString();
  final support = await getApplicationSupportDirectory();
  final file =
      File(p.join(support.path, 'prisma-engines', digest, p.basename(asset)));
  await file.parent.create(recursive: true);
  if (!await file.exists() ||
      sha256.convert(await file.readAsBytes()).toString() != digest) {
    final temporary = await file.parent.createTemp('extract-');
    try {
      final staging = File(p.join(temporary.path, p.basename(asset)));
      await staging.writeAsBytes(bytes, flush: true);
      if (await file.exists()) await file.delete();
      await staging.rename(file.path);
    } finally {
      await temporary.delete(recursive: true);
    }
  }
  if (!Platform.isWindows) {
    final result = await Process.run('/bin/chmod', ['700', file.path]);
    if (result.exitCode != 0) {
      throw StateError('Cannot make $engine executable: ${result.stderr}');
    }
  }
  return file;
}
