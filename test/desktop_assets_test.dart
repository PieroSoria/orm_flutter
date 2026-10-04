import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orm_flutter/src/desktop_assets.dart';
import 'package:orm_flutter/src/desktop_datasource.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class SupportPath extends PathProviderPlatform {
  SupportPath(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('new SQLite database keeps an absolute path', () {
    final url = desktopDatasourceUrl('file:new.db');
    expect(url, 'file:${Directory.current.path}/new.db');
    expect(File(url.substring(5)).isAbsolute, isTrue);
  });
  test(
      'extracts assets, reuses them, repairs corrupt copies, and sets permissions',
      () async {
    final temp = await Directory.systemTemp.createTemp('orm-assets-test-');
    final originalDirectory = Directory.current;
    final originalProvider = PathProviderPlatform.instance;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final payload = Uint8List.fromList([1, 2, 3, 4]);
    final asset =
        'prisma/engines/query-engine${Platform.isWindows ? '.exe' : ''}';
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final name = const StringCodec().decodeMessage(message);
      return name == asset ? ByteData.sublistView(payload) : null;
    });
    PathProviderPlatform.instance = SupportPath(temp.path);
    Directory.current = temp;
    try {
      final file = await resolveDesktopEngine('query-engine');
      expect(await file.readAsBytes(), payload);
      final modified = await file.lastModified();
      expect((await resolveDesktopEngine('query-engine')).path, file.path);
      expect(await file.lastModified(), modified);
      await file.writeAsBytes([9]);
      await resolveDesktopEngine('query-engine');
      expect(await file.readAsBytes(), payload);
      if (!Platform.isWindows) {
        expect((await file.stat()).mode & 0x40, isNonZero);
      }
    } finally {
      Directory.current = originalDirectory;
      PathProviderPlatform.instance = originalProvider;
      messenger.setMockMessageHandler('flutter/assets', null);
      rootBundle.clear();
      await temp.delete(recursive: true);
    }
  }, skip: Platform.environment.containsKey('PRISMA_QUERY_ENGINE_BINARY'));
}
