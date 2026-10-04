import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:orm_flutter_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled desktop engines work inside the installed application', (
    tester,
  ) async {
    expect(Platform.environment['PRISMA_QUERY_ENGINE_BINARY'], isNull);
    expect(Platform.environment['PRISMA_SCHEMA_ENGINE_BINARY'], isNull);
    if (Platform.isMacOS) {
      final paths = await const MethodChannel('orm_flutter/desktop')
          .invokeMapMethod<String, String>('enginePaths');
      for (final engine in ['query-engine', 'schema-engine']) {
        expect(paths?[engine], contains('.app/Contents/'));
        expect(await File(paths![engine]!).exists(), isTrue);
      }
    }
    app.main();
    await tester.pumpAndSettle(
      const Duration(seconds: 1),
      EnginePhase.sendSemanticsUpdate,
      const Duration(minutes: 2),
    );
    expect(find.textContaining('ALL CHECKS PASSED'), findsOneWidget);
    expect(find.textContaining('FAILED:'), findsNothing);
  });
}
