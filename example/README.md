# orm_flutter desktop example

This app runs real SQLite checks on launch: migration application twice, concurrent
startup, insertion, querying, transaction commit/rollback, and reconnection. It
uses the local orm_flutter package and bundled Prisma engines, without environment
variable overrides. Each run uses and cleans up an isolated database.

On Apple Silicon macOS:

```sh
cd example
flutter pub get
dart run ../bin/setup_desktop.dart darwin-arm64
flutter run -d macos
```

Use `darwin` for Intel macOS. The setup command downloads both engines and configures
Xcode to embed and sign them as executables inside the app bundle. The sandbox
remains enabled in debug and release. The engine files are ignored by Git; download
them before building. Success appears in the app and console as:

```text
ORM_EXAMPLE: ALL CHECKS PASSED on macos
```

For release validation, run `flutter run -d macos --release`.
