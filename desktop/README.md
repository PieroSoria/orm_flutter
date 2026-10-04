# Bundled Prisma engines

The executables in `engines/` are native Prisma engines from commit
`361e86d0ea4987e9f53a565309b3eed797a6bcbd`. Both query and schema engines use the
same commit. Applications obtain them through native plugin packaging; no
application download, engine assets, or runtime network access is needed.

Upstream distribution: https://binaries.prisma.sh/all_commits/
Upstream source: https://github.com/prisma/prisma-engines
License: Apache 2.0; see `PRISMA_LICENSE`.

Maintainers regenerate the binaries from the package root on macOS:

```sh
dart run tool/vendor_desktop.dart
```

The command verifies the compressed downloads against the upstream SHA-256
checksums. Temporary Intel/ARM64 macOS slices are ignored by Git. The signed
universal executables are shipped in
`macos/orm_flutter/Sources/orm_flutter/Engines/`, with child sandbox inheritance.

Included Linux targets require OpenSSL 3 and cover glibc and musl on x64 and
ARM64. Windows includes x64. Flutter/CMake copies only the appropriate pair into
an application's installation bundle. Future updates must keep the engine and
generated client protocol compatible.
