import 'package:dart_orm/dart_orm.dart';
import 'package:path/path.dart' as p;

/// SQLite paths must remain absolute when passed to a temporary schema file.
/// A new database is valid: Prisma creates it when applying migrations.
String desktopDatasourceUrl(String url) {
  if (!url.startsWith('file:')) return Prisma.validateDatasourceURL(url);
  final filename = url.substring(5);
  if (filename.isEmpty) throw ArgumentError('SQLite URL needs a file path');
  if (filename == ':memory:') return url;
  return 'file:${p.normalize(p.absolute(filename))}';
}
