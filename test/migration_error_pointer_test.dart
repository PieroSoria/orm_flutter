import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orm_flutter/src/_generate_bindings.dart';
import 'package:orm_flutter/src/migration_error_pointer.dart';

final class _ErrorStringPointer extends Struct {
  external Pointer<Char> value;
}

void main() {
  test('migration error is propagated as StateError', () {
    final nativeMessage = 'table already exists'.toNativeUtf8();
    addTearDown(() => malloc.free(nativeMessage));

    expect(
      () => applyMigrationsWithErrorPointer((errorPtr) {
        errorPtr.cast<_ErrorStringPointer>().ref.value = nativeMessage.cast();
        return Status.err;
      }),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'table already exists',
        ),
      ),
    );
  });

  test('successful migration completes without an error', () {
    expect(
      () => applyMigrationsWithErrorPointer((_) => Status.ok),
      returnsNormally,
    );
  });
}
