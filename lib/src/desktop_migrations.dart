import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_orm/dart_orm.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'desktop_assets.dart';
import 'desktop_datasource.dart';

Future<void> applyDesktopMigrations({
  required String schema,
  required Datasources datasources,
  required PrismaClientOptions options,
  required String path,
  AssetBundle? bundle,
}) async {
  final assets = bundle ?? rootBundle;
  final prefix = p.posix.normalize(path.replaceAll('\\', '/'));
  final manifest = await AssetManifest.loadFromAssetBundle(assets);
  final files = manifest
      .listAssets()
      .where((a) => a.startsWith('$prefix/'))
      .toList()
    ..sort();
  if (!files.contains('$prefix/migration_lock.toml')) {
    throw ArgumentError(
        'Missing $prefix/migration_lock.toml in Flutter assets');
  }
  final temporary = await Directory.systemTemp.createTemp('orm-migrations-');
  Process? process;
  StreamSubscription<String>? output;
  StreamSubscription<String>? errors;
  final result = Completer<void>();
  final diagnostics = StringBuffer();
  try {
    final migrations = Directory(p.join(temporary.path, 'migrations'));
    await migrations.create();
    final migrationDirectories = <Map<String, Object>>[];
    for (final asset in files) {
      final relative = asset.substring(prefix.length + 1);
      if (p.posix.isAbsolute(relative) || relative.split('/').contains('..')) {
        throw ArgumentError('Invalid migration asset: $asset');
      }
      final file = File(p.join(migrations.path, relative));
      await file.parent.create(recursive: true);
      final data = await assets.load(asset);
      await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      if (p.posix.basename(relative) == 'migration.sql') {
        migrationDirectories.add({
          'path': p.posix.dirname(relative),
          'migrationFile': {
            'path': 'migration.sql',
            'content': {'tag': 'ok', 'value': await file.readAsString()}
          },
        });
      }
    }
    final schemaFile = File(p.join(temporary.path, 'schema.prisma'));
    // Resolve each datasource exactly as the query engine does, then embed its
    // URL in the temporary schema for older schema-engine versions as well.
    var resolvedSchema = schema;
    for (final entry in datasources.entries) {
      final url = options.datasourceUrl ??
          options.datasources?[entry.key] ??
          (entry.value.type == DatasourceType.url
              ? entry.value.value
              : Prisma.env(entry.value.value) ??
                  Platform.environment[entry.value.value]);
      if (url == null) throw StateError('Missing datasource ${entry.key}');
      final validated = desktopDatasourceUrl(url);
      final block =
          RegExp('datasource\\s+${RegExp.escape(entry.key)}\\s*\\{[^}]*\\}');
      resolvedSchema = resolvedSchema.replaceAllMapped(
          block,
          (m) => m[0]!.replaceAll(
                RegExp(r'\burl\s*=\s*(env\([^)]*\)|"(?:[^"\\]|\\.)*")'),
                'url = ${jsonEncode(validated)}',
              ));
    }
    await schemaFile.writeAsString(resolvedSchema);
    final executable = await resolveDesktopEngine('schema-engine');
    process = await Process.start(
        executable.path, ['--datamodels', schemaFile.path],
        environment: Map<String, String>.from(Prisma.environment));
    final running = process;
    void fail(Object error) {
      if (!result.isCompleted) result.completeError(error);
    }

    errors = running.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (diagnostics.length < 16000) diagnostics.writeln(line);
    });
    output = running.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      try {
        final message = jsonDecode(line) as Map;
        if (message['method'] != null && message['id'] != null) {
          running.stdin.writeln(jsonEncode({
            'jsonrpc': '2.0',
            'id': message['id'],
            if (message['method'] == 'print')
              'result': <String, Object>{}
            else
              'error': {'code': -32601, 'message': 'Unsupported callback'}
          }));
        } else if (message['id'] == 1) {
          if (message.containsKey('error')) {
            fail(StateError(
                'Migration failed: ${jsonEncode(message['error'])}'));
          } else if (!result.isCompleted) {
            result.complete();
          }
        }
      } catch (error) {
        fail(error);
      }
    }, onError: fail);
    unawaited(running.exitCode.then((code) {
      fail(StateError('Schema engine exited ($code): $diagnostics'));
    }));
    running.stdin.writeln(jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'applyMigrations',
      'params': {
        'migrationsDirectoryPath': migrations.path,
        'migrationsList': {
          'baseDir': migrations.path,
          'lockfile': {
            'path': 'migration_lock.toml',
            'content':
                await File(p.join(migrations.path, 'migration_lock.toml'))
                    .readAsString()
          },
          'shadowDbInitScript': '',
          'migrationDirectories': migrationDirectories
        },
        'filters': {'externalTables': [], 'externalEnums': []},
      }
    }));
    await result.future.timeout(const Duration(minutes: 5));
  } finally {
    process?.kill();
    if (process != null) {
      final running = process;
      await running.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
        running.kill(ProcessSignal.sigkill);
        return -1;
      });
    }
    await output?.cancel();
    await errors?.cancel();
    await temporary.delete(recursive: true);
  }
}
