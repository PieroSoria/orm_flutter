import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '_generate_bindings.dart';

void applyMigrationsWithErrorPointer(
  Status Function(Pointer<Pointer<Char>>) applyMigrations,
) {
  final errorPtr = malloc<Pointer<Char>>();
  try {
    final status = applyMigrations(errorPtr);
    if (status != Status.ok) {
      final message = errorPtr.value.cast<Utf8>().toDartString();
      throw StateError(message);
    }
  } finally {
    malloc.free(errorPtr);
  }
}
