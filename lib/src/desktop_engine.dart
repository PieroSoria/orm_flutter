import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:io' show Process;

import 'package:oxy/oxy.dart';

import 'package:dart_orm/dart_orm.dart';
import 'desktop_assets.dart';
import 'desktop_datasource.dart';

class BinaryEngine extends Engine {
  BinaryEngine({
    required super.schema,
    required super.datasources,
    required super.options,
  });

  late Uri _endpoint;
  Future<void> Function()? _stopCallback;
  Future<void>? _startingFuture;
  Client _client = Client(ClientOptions());

  @override
  Future<void> start() async {
    if (_stopCallback != null) return;
    if (_startingFuture != null) {
      return await _startingFuture;
    }

    final completer = Completer<void>();
    _startingFuture = completer.future;

    try {
      final (endpoint, stop) = await createServer();
      _endpoint = endpoint;
      _stopCallback = stop;
      completer.complete();
    } catch (e, stack) {
      _stopCallback = null;
      completer.completeError(e, stack);
    } finally {
      _startingFuture = null;
    }
    return completer.future;
  }

  @override
  Future<void> stop() async {
    await _stopCallback?.call();
    _stopCallback = null;
    _client.close();
    _client = Client(ClientOptions());
  }

  @override
  Future<Map> request(
    JsonQuery query, {
    TransactionHeaders? headers,
    Transaction? transaction,
  }) async {
    headers ??= TransactionHeaders();
    await start();

    if (transaction != null) {
      headers.set('x-transaction-id', transaction.id);
    }

    final response = await _client.post(
      _endpoint,
      headers: headers.headers,
      body: jsonEncode(query.toJson()),
    );
    final result = await response.json();

    return switch (result) {
      {'data': final Map data} => deserializeJsonResponse(data),
      {'errors': final Iterable errors} => throwErrors(errors),
      _ => throw PrismaClientUnknownRequestError(message: json.encode(result)),
    };
  }

  @override
  Future<void> commitTransaction({
    required TransactionHeaders headers,
    required Transaction transaction,
  }) async {
    await start();

    final response = await _client.post(
      _endpoint.resolve('/transaction/${transaction.id}/commit'),
      headers: headers.headers,
    );
    final result = await response.json();

    return switch (result) {
      {'errors': final Iterable errors} => throwErrors(errors),
      _ => null,
    };
  }

  @override
  Future<void> rollbackTransaction({
    required TransactionHeaders headers,
    required Transaction transaction,
  }) async {
    await start();

    final response = await _client.post(
      _endpoint.resolve('/transaction/${transaction.id}/rollback'),
      headers: headers.headers,
    );
    final result = await response.json();

    return switch (result) {
      {'errors': final Iterable errors} => throw Exception(errors),
      _ => null,
    };
  }

  @override
  Future<Transaction> startTransaction({
    required TransactionHeaders headers,
    int maxWait = 2000,
    int timeout = 5000,
    TransactionIsolationLevel? isolationLevel,
  }) async {
    await start();

    final response = await _client.post(
      _endpoint.resolve('/transaction/start'),
      headers: headers.headers,
      body: jsonEncode({
        'max_wait': maxWait,
        'timeout': timeout,
        if (isolationLevel != null) 'isolation_level': isolationLevel.name,
      }),
    );
    final result = await response.json();

    return switch (result) {
      {'id': final String id} => Transaction(id),
      {'errors': final Iterable errors} => throwErrors(errors),
      _ => throw PrismaClientUnknownRequestError(
          message: json.encode(PrismaClientUnknownRequestError),
        ),
    };
  }

  @override
  Future metrics({
    Map<String, String>? globalLabels,
    required MetricsFormat format,
  }) async {
    await start();

    final response = await _client.post(
      _endpoint.replace(
        path: '/metrics',
        queryParameters: {'format': format.name},
      ),
      body: jsonEncode(globalLabels),
    );

    return switch (format) {
      MetricsFormat.json => response.json(),
      MetricsFormat.prometheus => response.text(),
    };
  }
}

extension on BinaryEngine {
  Future<io.File> findQueryEngine() => resolveDesktopEngine('query-engine');

  String createOverwriteDatasourcesString() {
    Map<String, String> overwriteDatasources = this.datasources.map((
      name,
      datasource,
    ) {
      if (options.datasourceUrl != null) {
        return MapEntry(
          name,
          desktopDatasourceUrl(options.datasourceUrl!),
        );
      }

      if (options.datasources?.containsKey(name) == true) {
        return MapEntry(
          name,
          desktopDatasourceUrl(options.datasources![name]!),
        );
      }

      final url = switch (datasource) {
        Datasource(type: DatasourceType.url, value: final url) => url,
        Datasource(type: DatasourceType.environment, value: final name) =>
          Prisma.env(name).or(
            () => throw PrismaClientInitializationError(
              errorCode: "P1013",
              message: 'The environment variable "$name" does not exist',
            ),
          ),
      };

      return MapEntry(name, desktopDatasourceUrl(url));
    });

    Map<String, String> generateDatasourceItem(MapEntry<String, String> e) {
      if (e.value.startsWith('prisma://')) {
        throw PrismaClientInitializationError(
          errorCode: 'P1013',
          message:
              'The binary engine does not support Prisma Proxy connection URL',
        );
      }

      return {'name': e.key, 'url': e.value};
    }

    final datasources =
        overwriteDatasources.entries.map(generateDatasourceItem).toList();

    return base64.encode(utf8.encode(json.encode(datasources)));
  }

  Iterable<String> createQueryEngineArgs() sync* {
    yield '--enable-metrics';
    yield '--enable-raw-queries';
    yield* ['--engine-protocol', 'json'];
    yield* ['--port', '0'];
  }

  Map<String, String> createQueryEngineEnvironment() {
    final environment = Map<String, String>.from(Prisma.environment);

    if (options.logEmitter.definition.any((e) => e.$1 == LogLevel.query)) {
      environment['LOG_QUERIES'] = 'true';
    }

    if (!Prisma.envAsBoolean('NO_COLOR') &&
        options.errorFormat == ErrorFormat.pretty) {
      environment['CLICOLOR_FORCE'] = "1";
    }

    environment['RUST_BACKTRACE'] = Prisma.env('RUST_BACKTRACE').or(() => '1');
    environment['RUST_LOG'] = Prisma.env(
      'RUST_LOG',
    ).or(() => LogLevel.info.name);
    environment['OVERWRITE_DATASOURCES'] = createOverwriteDatasourcesString();
    environment['PRISMA_DML'] = base64.encode(utf8.encode(schema));

    return environment;
  }

  Future<(Uri, Future<void> Function())> createServer() async {
    final executable = (await findQueryEngine()).absolute.path;
    final arguments = createQueryEngineArgs().toList();
    final environment = createQueryEngineEnvironment();
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: io.Directory.current.path,
      includeParentEnvironment: false,
      environment: environment,
    );

    Object? startupError;
    int? exitCode;
    final diagnostics = StringBuffer();
    unawaited(process.exitCode.then((code) => exitCode = code));
    final stderrSubscription = process.stderr.byline().listen((event) {
      if (diagnostics.length < 16000) diagnostics.writeln(event);
      final payload = tryParseJSON(event);
      if (payload
          case {
            'error_code': final String errorCode,
            'message': final String message,
          }) {
        process.kill();
        startupError = PrismaClientInitializationError(
          message: message,
          errorCode: errorCode,
        );
      }
    });

    Uri? endpoint;
    final stdoutSubscription = process.stdout.byline().listen((event) {
      final payload = tryParseJSON(event);
      tryCompleteEndpoint(payload, (uri) => endpoint = uri);

      if (payload case {'span': true, 'spans': final List _}) {
        // Spans are tracing metadata, not engine log events.
        return;
      }

      final (level, engineEvent) = createEngineEvent(payload);
      if (level == LogLevel.error &&
          engineEvent is LogEvent &&
          engineEvent.message.contains('fatal error')) {
        process.kill();
        startupError = PrismaClientRustPanicError(message: engineEvent.message);
      }

      options.logEmitter.emit(level, engineEvent);
    });

    Future<void> stop() async {
      process.kill();
      await stderrSubscription.cancel();
      await stdoutSubscription.cancel();
      await process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
        process.kill(io.ProcessSignal.sigkill);
        return -1;
      });
    }

    for (int count = 0;; count++) {
      options.logEmitter.emit(
        LogLevel.info,
        LogEvent(
          timestamp: DateTime.now(),
          target: 'prisma:client',
          message:
              'Whether the engine has started for the ${count + 1} th time.',
        ),
      );

      if (startupError != null || exitCode != null) {
        await stop();
        throw startupError ??
            PrismaClientInitializationError(
              message: 'Query engine exited ($exitCode): $diagnostics',
            );
      }
      if (endpoint != null) break;
      if (count >= 10) {
        await stop();
        throw PrismaClientInitializationError(
          message: 'Engine startup failed.',
        );
      }

      await Future.delayed(Duration(milliseconds: 300 * count));
    }

    for (int count = 0;; count++) {
      options.logEmitter.emit(
        LogLevel.info,
        LogEvent(
          timestamp: DateTime.now(),
          target: 'prisma:client',
          message: 'Whether the engine has ready for the ${count + 1} th time.',
        ),
      );

      try {
        final response = await _client.get(endpoint!.replace(path: '/status'));
        final result = await response.json();
        if (result case {"status": "ok"}) {
          break;
        }
      } catch (_) {}

      if (count >= 10) {
        await stop();
        throw PrismaClientInitializationError(
          message: 'Engine startup failed.',
        );
      }

      await Future.delayed(Duration(milliseconds: 300 * count));
    }

    return (endpoint!, stop);
  }

  (LogLevel, EngineEvent) createEngineEvent(Object? payload) {
    if (payload
        case {
          'timestamp': final String timestamp,
          'target': final String target,
          'fields': {
            'query': final String query,
            'params': final String params,
            'duration': final num duration,
          },
        }) {
      final event = QueryEvent(
        timestamp: DateTime.parse(timestamp),
        target: target,
        query: query,
        params: params,
        duration: Duration(milliseconds: duration.toInt()),
      );

      return (LogLevel.query, event);
    } else if (payload
        case {
          'timestamp': final String timestamp,
          'target': final String target,
          'level': final String rawLogLevel,
          'fields': {'message': final String message},
        }) {
      final level = LogLevel.values.firstWhere(
        (e) => e.name.toLowerCase() == rawLogLevel.toLowerCase(),
        orElse: () => LogLevel.warn,
      );
      final event = LogEvent(
        timestamp: DateTime.parse(timestamp),
        target: target,
        message: message,
      );

      return (level, event);
    }

    return (
      LogLevel.warn,
      LogEvent(
        target: 'prisma:client:engines:binary',
        timestamp: DateTime.now(),
        message: 'Parse event fail, raw event: ${json.encode(payload)}',
      ),
    );
  }

  void tryCompleteEndpoint(Object? payload, void Function(Uri) setter) {
    if (payload
        case {
          'level': 'INFO',
          'target': 'query_engine::server',
          'fields': {
            'message': final String message,
            'ip': final String ip,
            'port': final String port,
          },
        }
        when message.startsWith('Started query engine http server') &&
            ip.isNotEmpty &&
            port.isNotEmpty) {
      final endpoint = Uri.http('$ip:$port');

      setter(endpoint);
    }
  }

  Object? tryParseJSON(String encoded) {
    try {
      return json.decode(encoded);
    } catch (e) {
      return null;
    }
  }

  Never throwErrors(Iterable errors) {
    if (errors.length == 1) {
      throw switch (errors.single) {
        Map payload => throwPrismaKnowError(payload),
        Object message => throw PrismaClientUnknownRequestError(
            message: json.encode(message),
          ),
        _ => throw PrismaClientUnknownRequestError(
            message: json.encode(errors),
          ),
      };
    }

    throw PrismaClientUnknownRequestError(message: json.encode(errors));
  }

  Never throwPrismaKnowError(Map payload) {
    final userFacingError = payload['user_facing_error'];

    if (userFacingError
        case {
          'error_code': final String errorCode,
          'message': final String message,
        }) {
      throw PrismaClientKnownRequestError(
        code: errorCode,
        message: message,
        meta: switch (userFacingError['meta']) {
          Map meta => meta.map((k, v) => MapEntry(k.toString(), v)),
          _ => null,
        },
      );
    }

    throw PrismaClientUnknownRequestError(message: payload['error']!);
  }
}

extension<T> on T? {
  T or(T Function() fn) {
    if (this != null) return this as T;
    return fn();
  }
}

extension on Stream<List<int>> {
  Stream<String> byline() =>
      transform(utf8.decoder).transform(const LineSplitter());
}
