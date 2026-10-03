import 'dart:ffi';
import 'dart:io';

import '_generate_bindings.dart';

DynamicLibrary get _dl {
  if (Platform.isIOS) {
    // Try open SPM generated library.
    try {
      return DynamicLibrary.open('orm-flutter.framework/orm-flutter');

      // Fallback open podspec defined library.
    } catch (_) {
      return DynamicLibrary.open('orm_flutter_ios.framework/orm_flutter_ios');
    }
  } else if (Platform.isAndroid) {
    return DynamicLibrary.open("liborm_flutter_android.so");
  }

  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    // For desktop platforms, FFI bindings are not used when using BinaryEngine.
    // Return a dummy library to avoid throwing if bindings are accidentally accessed.
    return DynamicLibrary.process();
  }

  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

final bindings = QueryEngineBindings(_dl);
