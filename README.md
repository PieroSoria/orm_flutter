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

## Desktop integration (macOS, Windows and Linux)

Desktop engines are shipped **inside orm_flutter** and included automatically by
Flutter's native plugin build. Applications do not need to download engines,
declare `prisma/engines/` assets, set executable paths, or add an Xcode build phase.
Use `LibraryEngine` and `applyMigrations` normally; declare only your migration
assets. Apply migrations before the first connection/query, and use an absolute
SQLite path in a writable application support directory.

| Platform | Included targets | Packaging |
| --- | --- | --- |
| macOS | Intel and Apple Silicon (universal binaries) | Swift Package Manager resource bundle, or CocoaPods framework resource bundle |
| Windows | x64 | CMake installs both `.exe` files beside the application |
| Linux | x64/ARM64, glibc or musl, OpenSSL 3 | CMake chooses the target and installs both executables in `lib/` |

macOS executes the signed engines directly inside the app bundle. A sandboxed
application must enable `com.apple.security.network.client` and
`com.apple.security.network.server` in both its debug and release entitlements,
because the query engine communicates through a local HTTP server. The plugin
does not disable or modify the application sandbox. For distribution, validate
your signing identity and notarization of the final bundle, including the nested
engine executables. CocoaPods signs the resource engines during its build;
Swift Package Manager uses the signed universal executables shipped in the package.

Linux needs OpenSSL 3 installed. Alpine selects the musl variant; other supported
distributions select glibc. Cross-builds can choose `ORM_FLUTTER_LINUX_TARGET` in
CMake explicitly. If Flutter installs the bundled files without execute permission,
the runtime copies them to application support storage under their SHA-256 digest
and sets Unix execution permissions without modifying the installed app directory.
Older OpenSSL versions and Windows ARM64 are not included.

The optional `PRISMA_QUERY_ENGINE_BINARY` and `PRISMA_SCHEMA_ENGINE_BINARY`
environment variables override the bundled engines for advanced setups and tests.
Legacy application assets remain a fallback. Applications that previously ran
`setup_desktop` can remove the old `Embed Prisma engines` Runner build phase and
engine asset entry; neither is required by this version.

Engine binaries use commit `361e86d0ea4987e9f53a565309b3eed797a6bcbd`, matching the
previous query engine and the legacy Prisma JSON protocol. Maintainers can refresh
the shipped binaries with `dart run tool/vendor_desktop.dart` on macOS. It verifies
Prisma CDN SHA-256 checksums and generates signed universal macOS engines. This is
a package maintenance command; applications do not run it. Prisma's Apache 2.0
license is included in `desktop/PRISMA_LICENSE`.

The [desktop example](example/README.md) tests packaged engines in a real Flutter
application, including migrations, commit/rollback and reconnection.

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
