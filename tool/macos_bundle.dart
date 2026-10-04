import 'dart:convert';
import 'dart:io';

/// Install the build step while preserving existing Xcode settings.
Future<void> configureMacosBundle() async {
  final project = File('macos/Runner.xcodeproj/project.pbxproj');
  if (!await project.exists()) return;
  const phaseId = 'A7D08DBA77F94F1683A84501';
  var contents = await project.readAsString();
  const phaseName = 'Embed Prisma engines';
  if (!contents.contains('/* $phaseName */')) {
    const command = r'/bin/sh "$PROJECT_DIR/Flutter/PrismaEngines.sh"';
    final phase = '''
\t\t$phaseId /* $phaseName */ = {
\t\t\tisa = PBXShellScriptBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ();
\t\t\tinputPaths = ();
\t\t\tname = "$phaseName";
\t\t\toutputPaths = ();
\t\t\talwaysOutOfDate = 1;
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t\tshellPath = /bin/sh;
\t\t\tshellScript = ${jsonEncode(command)};
\t\t};
''';
    const section = '/* Begin PBXShellScriptBuildPhase section */';
    final runner = RegExp(
        r'(/\* Runner \*/ = \{\s*isa = PBXNativeTarget;[\s\S]*?buildPhases = \([\s\S]*?)(\n\s*\);)');
    if (!contents.contains(section) || !runner.hasMatch(contents)) {
      throw StateError(
          'Cannot find the Runner build phases in ${project.path}. '
          'Add macos/Flutter/PrismaEngines.sh as a Runner build phase manually.');
    }
    contents = contents.replaceFirst(section, '$section\n$phase');
    contents = contents.replaceFirstMapped(
        runner, (m) => '${m[1]}\n\t\t\t\t$phaseId /* $phaseName */,${m[2]}');
    await project.writeAsString(contents);
  }
  final script = File('macos/Flutter/PrismaEngines.sh');
  await script.parent.create(recursive: true);
  await script.writeAsString(r'''#!/bin/sh
set -eu
engine_source="$PROJECT_DIR/../prisma/engines"
engine_destination="$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH"
mkdir -p "$engine_destination"
for engine in query-engine schema-engine; do
  cp "$engine_source/$engine" "$engine_destination/prisma-$engine"
  chmod 755 "$engine_destination/prisma-$engine"
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --entitlements "$PROJECT_DIR/Flutter/PrismaEngine.entitlements" "$engine_destination/prisma-$engine"
done
''');
  await File('macos/Flutter/PrismaEngine.entitlements')
      .writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.inherit</key><true/>
</dict></plist>
''');
  for (final name in ['DebugProfile.entitlements', 'Release.entitlements']) {
    final file = File('macos/Runner/$name');
    if (!await file.exists()) continue;
    var xml = await file.readAsString();
    for (final key in [
      'com.apple.security.network.client',
      'com.apple.security.network.server'
    ]) {
      final existing =
          RegExp('<key>${RegExp.escape(key)}</key>\\s*<(?:true|false)\\s*/>');
      if (existing.hasMatch(xml)) {
        xml = xml.replaceFirst(existing, '<key>$key</key><true/>');
      } else {
        xml = xml.replaceFirst('</dict>', '<key>$key</key><true/>\n</dict>');
      }
    }
    await file.writeAsString(xml);
  }
  stdout.writeln(
      'Configured macOS bundle: signed Prisma executables and network entitlements.');
}
