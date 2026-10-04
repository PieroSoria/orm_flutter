import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/macos_bundle.dart';

void main() {
  test('macOS setup installs one build phase and retains the sandbox',
      () async {
    final directory = await Directory.systemTemp.createTemp('orm-bundle-test-');
    final previous = Directory.current;
    Directory.current = directory;
    try {
      final project = File('macos/Runner.xcodeproj/project.pbxproj');
      await project.parent.create(recursive: true);
      await project
          .writeAsString('''/* Begin PBXShellScriptBuildPhase section */
/* End PBXShellScriptBuildPhase section */
123456789012345678901234 /* Runner */ = {
 isa = PBXNativeTarget;
 buildPhases = (
 );
};
''');
      final entitlement = File('macos/Runner/DebugProfile.entitlements');
      await entitlement.parent.create(recursive: true);
      await entitlement.writeAsString('''<plist><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><false/>
<key>custom.setting</key><true/>
</dict></plist>''');
      await configureMacosBundle();
      final first = await project.readAsString();
      await configureMacosBundle();
      expect(await project.readAsString(), first);
      expect(first, contains('shellScript = "/bin/sh'));
      expect(first,
          contains('A7D08DBA77F94F1683A84501 /* Embed Prisma engines */,'));
      final xml = await entitlement.readAsString();
      expect(xml, contains('<key>com.apple.security.app-sandbox</key><true/>'));
      expect(xml, contains('<key>custom.setting</key><true/>'));
      expect(
          xml, contains('<key>com.apple.security.network.client</key><true/>'));
      expect(
          xml, contains('<key>com.apple.security.network.server</key><true/>'));
      expect(
          await File('macos/Flutter/PrismaEngine.entitlements').readAsString(),
          contains('<key>com.apple.security.inherit</key><true/>'));
    } finally {
      Directory.current = previous;
      await directory.delete(recursive: true);
    }
  });
}
