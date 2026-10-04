---
title: Flutter Integration
---

# Flutter Integration

Prisma ORM for Dart allows you to integrate it in Flutter Project.

## Platform Support

| Platform | Support | Nots                     |
| -------- | ------- | ------------------------ |
| iOS      | ✅      |                          |
| Android  | ✅      |                          |
| macOS    | ✅      | Bundled binary engines |
| Linux    | ✅      | Bundled binary engines |
| Windows  | ✅      | Bundled binary engines |
| Web      | ❌      | No plans at the moment   |

## Desktop setup (macOS, Windows and Linux)

Desktop uses Prisma's process-based query engine and schema engine. No native
Flutter plugin registration is needed. Download the binaries **from your Flutter
application directory** before building:

```sh
# Apple Silicon macOS
dart run orm_flutter:setup_desktop darwin-arm64
# Intel macOS
dart run orm_flutter:setup_desktop darwin
# Windows x64
dart run orm_flutter:setup_desktop windows
# Linux x64, Debian/Ubuntu with OpenSSL 3
dart run orm_flutter:setup_desktop debian-openssl-3.0.x
# Linux ARM64 with OpenSSL 3
dart run orm_flutter:setup_desktop linux-arm64-openssl-3.0.x
# Alpine Linux x64 with OpenSSL 3
dart run orm_flutter:setup_desktop linux-musl-openssl-3.0.x
```

Choose the target for the **destination system**, including its architecture,
libc and OpenSSL version. Run setup separately before each platform build;
`prisma/engines` contains one target at a time. The default engine commit is
`361e86d0ea4987e9f53a565309b3eed797a6bcbd`, matching the previous macOS binary.
An optional second argument selects another compatible Prisma engine commit.
Use the same commit for the query and schema engines and a compatible generated
client. These engines use the legacy JSON protocol; Prisma 7's query compiler is
not a drop-in replacement.

Add these assets to the application's `pubspec.yaml`:

```yaml
flutter:
  assets:
    - prisma/engines/
    - prisma/migrations/
    - prisma/migrations/20260101000000_init/ # each migration directory
```

Use `LibraryEngine` normally, including `applyMigrations`. Desktop migrations
run through the schema engine, preserving Prisma's migration history and errors.
Use an absolute SQLite datasource URL in a writable application support directory.
New database files are created by migrations. Migrations must finish before the
first query. Missing engines or migration assets throw an actionable error.

Executables are resolved from `PRISMA_QUERY_ENGINE_BINARY` and
`PRISMA_SCHEMA_ENGINE_BINARY` first, then alongside the application executable
(or macOS `Contents/Resources`), then local development directories, and finally
Flutter assets. Assets are extracted into application support storage under their
SHA-256 digest; Unix execution permissions are set automatically. This works when
the application launches outside the source directory.

For a signed/notarized macOS release, place and sign both engines as nested
executables in `Contents/Resources` before signing the app. Name them
`prisma-query-engine` and `prisma-schema-engine`. A sandboxed macOS app needs
outgoing **and incoming** network entitlements for the engine's local HTTP server;
its child executables must be signed/configured to inherit the app sandbox.
Validate the final signed bundle on the destination machine. Windows uses `.exe`
for both engines; Linux needs the system libraries matching the selected target.

The desktop integration test exercises SQLite migrations twice, queries,
transaction commit/rollback, concurrent startup and reconnection. Set both
`PRISMA_*_ENGINE_BINARY` environment variables to run it. The GitHub Actions
workflow runs it on macOS, Windows and Linux.

## Mobile FFI Database Support

| Database             | Suppoprt | Notes                    |
| -------------------- | -------- | ------------------------ |
| Sqlite               | ✅       |                          |
| MySQL/MariaDB        | ❌       | Prisma C-ABI not support |
| PostgreSQL           | ❌       | Prisma C-ABI not support |
| MongoDB              | ❌       | Prisma C-ABI not support |
| Microsoft SQL Server | ❌       | Prisma C-ABI not support |
| CockroachDB          | ❌       | Prisma C-ABI not support |

## Installation

You should first read the [Installation Documentation](./index.md#installation), and [Setup Prisma ORM](./setup.md) of the `orm` package.

Now, let’s install the `orm_flutter` package, you can use the command line:

```bash
flutter pub add orm_flutter
```

Or edit your Flutter project’s `pubspce.yaml` file:

```yaml
dependencies:
  orm_flutter: latest
```

## Integration

Set your generator engine type to `flutter` in your Prisma schema (`schema.prisma`):

```prisma
generator client {
  provider   = "dart run orm"
  output     = "../lib/_generated_prisma_client"
  engineType = "flutter" // [!code focus]
}
```

## Migrations

Unlike server-side, databases in Flutter are not typically handled by you in the Prisma CLI before building.

### Create migration file

::: code-group

```bash [Bun.js]
bun prisma migrate dev
```

```bash [NPM]
npx prisma migrate dev
```

```bash [pnpm]
pnpx prisma migrate dev
```

:::

> Notes: By default it is created in the `prisma/migrations/` folder.

### Set migration files to flutter assets

Now, let's edit your `pubspec.yaml`:

```yaml
flutter:
  assets:
    - prisma/migrations/ # Migrations root dir
    - prisma/migrations/<dir>/ # Set first migration files dir
    # ... More assets
```

> Notes: Each migration folder generated using the `prisma migrate dev` command needs to be added.

### Run migration

```dart
final engine = prisma.$engine as LibraryEngine;

await engine.applyMigrations(
     path: 'prisma/migrations/', // You define in `flutter.assets` migrations root dir
);
```

> Notes:
>
> In addition to using `flutter.assets`, you can customize `AssetBundle` to achieve:
>
> ```dart
> await engine.applyMigrations(
>   path: '<Your migration dir prefix>',
>   bundle: <You custon bundle>,
> );
> ```
>
> **Also, `engine.applyMigrations` may throw exceptions. This is usually caused by your destructive changes to the migration files, and you should handle this yourself. The most common method is to delete the database file after throwing the exception, and then rerun the migration.**
>
> If you are adding a new migration, there will be almost no problems.

## Complete integration example

In this Example, we will install these packages:

- [`path`](https://pub.dev/packages/path)
- [`path_provider`](https://pub.dev/packages/path_provider)

We install the database in the `<Application Support Directory>/database.sqlite` location and then use `flutter.assets` to run the migration

::: code-group

```dart [lib/prisma.dart]
import 'package:flutter/widgets.dart';
import 'package:orm_flutter/orm_flutter.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '_generated_prisma_client/client.dart';

late final PrismaClient prisma;

Future<void> initPrismaClient() async {
  WidgetsFlutterBinding.ensureInitialized();

  final supportDir = await getApplicationSupportDirectory();
  final database = join(supportDir.path, 'database.sqlite.db');

  prisma = PrismaClient(datasourceUrl: 'file:$database');
  final engine = switch (prisma.$engine) {
    LibraryEngine engine => engine,
    _ => null,
  };

  await prisma.$connect();
  await engine?.applyMigrations(path: 'prisma/migrations');
}

```

```dart [lib/main.dart]
import 'prisma.dart';

Future<void> main() async {
     await initPrismaClient();

     // ...
}
```

:::

## Example App

We provide you with a demo App that integrates Prisma ORM in Flutter 👉 [Flutter with ORM](https://github.com/medz/prisma-dart/tree/main/examples/flutter_with_orm)

## FAQ

### Error (Xcode): Undefined symbol: `prisma_*`

This is due to a library compilation failure, which will persist even if you download a new fixed version.

Solution: Run the command:

```bash
flutter clean
```

### Other unknown error solutions:

Most problems can be solved by using the following combination of commands:

```bash
flutter clean # Clean flutter cache files
flutter pub get # Reinstall deps
<bun/npx/pnpx/yarn> prisma generate # Regenerate prisma client
```
