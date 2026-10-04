import 'dart:convert';
import 'dart:io';

import 'package:dart_orm/dart_orm.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orm_flutter/orm_flutter.dart';

class MigrationBundle extends CachingAssetBundle {
  final files = <String, String>{
    'prisma/migrations/migration_lock.toml': 'provider = "sqlite"',
    'prisma/migrations/20260101000000_init/migration.sql':
        'CREATE TABLE "Note" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "text" TEXT NOT NULL);',
  };
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        for (final key in files.keys)
          key: [
            {'asset': key}
          ],
      })!;
    }
    final content = files[key];
    if (content == null) throw StateError('Missing asset $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(content)));
  }
}

class NetworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  NetworkBinding();
  final available =
      Platform.environment.containsKey('PRISMA_QUERY_ENGINE_BINARY') &&
          Platform.environment.containsKey('PRISMA_SCHEMA_ENGINE_BINARY');
  test('invalid engine schema reports initialization failure', () async {
    final engine = LibraryEngine(
      datasources: {},
      options: PrismaClientOptions(
          errorFormat: ErrorFormat.minimal, logEmitter: LogEmitter({})),
      schema: 'invalid schema',
    );
    try {
      await expectLater(
          engine.start(), throwsA(isA<PrismaClientInitializationError>()));
    } finally {
      await engine.stop();
    }
  }, skip: !available);
  test('desktop migrates twice, queries, transactions, and restarts', () async {
    final temporary = await Directory.systemTemp.createTemp('orm-test-');
    final engine = LibraryEngine(
      datasources: {
        'db': const Datasource(DatasourceType.environment, 'DATABASE_URL')
      },
      options: PrismaClientOptions(
          datasourceUrl: 'file:${temporary.path}/test.db',
          errorFormat: ErrorFormat.minimal,
          logEmitter: LogEmitter({})),
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
    const find =
        JsonQuery(modelName: 'Note', action: JsonQueryAction.findMany, query: {
      'arguments': {},
      'selection': {'id': true, 'text': true}
    });
    JsonQuery create(String text) =>
        JsonQuery(modelName: 'Note', action: JsonQueryAction.createOne, query: {
          'arguments': {
            'data': {'text': text}
          },
          'selection': {'id': true, 'text': true}
        });
    try {
      await engine.applyMigrations(
          path: 'prisma/migrations', bundle: MigrationBundle());
      await engine.applyMigrations(
          path: 'prisma/migrations', bundle: MigrationBundle());
      await Future.wait([engine.start(), engine.start()]);
      await engine.request(create('saved'));
      final headers = TransactionHeaders();
      final tx = await engine.startTransaction(headers: headers);
      await engine.request(create('rolled back'), transaction: tx);
      await engine.rollbackTransaction(headers: headers, transaction: tx);
      final rows = await engine.request(find);
      expect((rows['findManyNote'] as Iterable).length, 1);
      final committed = await engine.startTransaction(headers: headers);
      await engine.request(create('committed'), transaction: committed);
      await engine.commitTransaction(headers: headers, transaction: committed);
      expect(
          ((await engine.request(find))['findManyNote'] as Iterable).length, 2);
      final beforeRestart = await engine.request(find);
      await engine.stop();
      await engine.start();
      expect((await engine.request(find))['findManyNote'],
          beforeRestart['findManyNote']);
      final invalid = MigrationBundle();
      invalid.files['prisma/migrations/20260102000000_bad/migration.sql'] =
          'THIS IS NOT SQL;';
      await expectLater(
          engine.applyMigrations(path: 'prisma/migrations', bundle: invalid),
          throwsStateError);
    } finally {
      await engine.stop();
      await temporary.delete(recursive: true);
    }
  },
      skip: !available
          ? 'Set both PRISMA_*_ENGINE_BINARY variables to run real integration tests'
          : false);
}
