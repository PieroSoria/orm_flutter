import 'dart:io';

import 'package:dart_orm/dart_orm.dart';
import 'package:flutter/material.dart';
import 'package:orm_flutter/orm_flutter.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: DesktopDemo()));
}

class DesktopDemo extends StatefulWidget {
  const DesktopDemo({super.key});
  @override
  State<DesktopDemo> createState() => _DesktopDemoState();
}

class _DesktopDemoState extends State<DesktopDemo> {
  final messages = <String>[];
  bool finished = false;
  @override
  void initState() {
    super.initState();
    runChecks();
  }

  void report(String message) {
    debugPrint('ORM_EXAMPLE: $message');
    if (mounted) setState(() => messages.add(message));
  }

  Future<void> runChecks() async {
    final support = await getApplicationSupportDirectory();
    final temporary = await support.createTemp('desktop-check-');
    final engine = LibraryEngine(
      datasources: {
        'db': const Datasource(DatasourceType.environment, 'DATABASE_URL'),
      },
      options: PrismaClientOptions(
        datasourceUrl: 'file:${temporary.path}/example.sqlite',
        errorFormat: ErrorFormat.minimal,
        logEmitter: LogEmitter({}),
      ),
      schema: '''datasource db {
  provider = "sqlite"
  url = env("DATABASE_URL")
}
model Note {
  id Int @id @default(autoincrement())
  text String
}
''',
    );
    const find = JsonQuery(
      modelName: 'Note',
      action: JsonQueryAction.findMany,
      query: {
        'arguments': {},
        'selection': {'id': true, 'text': true},
      },
    );
    JsonQuery create(String text) => JsonQuery(
      modelName: 'Note',
      action: JsonQueryAction.createOne,
      query: {
        'arguments': {
          'data': {'text': text},
        },
        'selection': {'id': true, 'text': true},
      },
    );
    try {
      await engine.applyMigrations(path: 'prisma/migrations');
      await engine.applyMigrations(path: 'prisma/migrations');
      report('PASS: bundled schema engine and migrations (twice)');
      await Future.wait([engine.start(), engine.start()]);
      await engine.request(create('Hello from macOS'));
      report('PASS: concurrent connection and insert');
      final headers = TransactionHeaders();
      final rollback = await engine.startTransaction(headers: headers);
      await engine.request(create('rollback'), transaction: rollback);
      await engine.rollbackTransaction(headers: headers, transaction: rollback);
      final commit = await engine.startTransaction(headers: headers);
      await engine.request(create('commit'), transaction: commit);
      await engine.commitTransaction(headers: headers, transaction: commit);
      final rows = (await engine.request(find))['findManyNote'] as Iterable;
      if (rows.length != 2) {
        throw StateError('Expected 2 notes, got ${rows.length}');
      }
      report('PASS: query, commit and rollback');
      await engine.stop();
      await engine.start();
      final restored = (await engine.request(find))['findManyNote'] as Iterable;
      if (restored.length != 2) {
        throw StateError('Data missing after reconnect');
      }
      report('PASS: reconnect and persistent data');
      report('ALL CHECKS PASSED on ${Platform.operatingSystem}');
    } catch (error, stack) {
      report('FAILED: $error');
      debugPrintStack(stackTrace: stack);
    } finally {
      await engine.stop();
      await temporary.delete(recursive: true);
      if (mounted) setState(() => finished = true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('orm_flutter desktop checks')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!finished) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          for (final message in messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SelectableText(message),
            ),
        ],
      ),
    ),
  );
}
