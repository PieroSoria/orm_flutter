# orm_flutter desktop example

This app runs real SQLite checks on launch: migrations twice, concurrent startup,
insertion, querying, transaction commit/rollback, and reconnection. It uses the
local orm_flutter package and engines shipped inside that package. No engine
assets, download command, executable environment variables, or custom Runner
build phase are needed. Each run creates and cleans up an isolated database.

On macOS:

```sh
cd example
flutter run -d macos
```

Run the native integration test with:

```sh
flutter test integration_test/desktop_test.dart -d macos
```

Success appears in the app and console:

```text
ORM_EXAMPLE: ALL CHECKS PASSED on macos
```

The app sandbox remains enabled in debug and release. Its network client and
server entitlements allow the engine's local HTTP connection. Only database
migration files are declared as assets.

For release validation, run `flutter run -d macos --release`.
