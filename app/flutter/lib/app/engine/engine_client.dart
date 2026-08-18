import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:video_translator/app/engine/media_inspection.dart';

const _protocolVersion = '1.0';

typedef WorkerStarter = Future<Process> Function();

bool isValidIpcEnvelope(Object? value) {
  if (value is! Map<String, dynamic> ||
      value['jsonrpc'] != '2.0' ||
      value['protocolVersion'] != _protocolVersion) {
    return false;
  }

  final keys = value.keys.toSet();
  final id = value['id'];
  final validId = (id is String && id.isNotEmpty) || (id is int && id is! bool);
  if (value.containsKey('method')) {
    if (value['method'] is! String ||
        (value['method'] as String).isEmpty ||
        (value.containsKey('params') &&
            value['params'] is! Map &&
            value['params'] is! List)) {
      return false;
    }
    return value.containsKey('id')
        ? validId &&
              keys.every(
                (key) =>
                    key == 'jsonrpc' ||
                    key == 'protocolVersion' ||
                    key == 'id' ||
                    key == 'method' ||
                    key == 'params',
              )
        : keys.every(
            (key) =>
                key == 'jsonrpc' ||
                key == 'protocolVersion' ||
                key == 'method' ||
                key == 'params',
          );
  }

  if (value.containsKey('result')) {
    return validId &&
        !value.containsKey('error') &&
        keys.every(
          (key) =>
              key == 'jsonrpc' ||
              key == 'protocolVersion' ||
              key == 'id' ||
              key == 'result',
        );
  }

  final error = value['error'];
  return value.containsKey('id') &&
      (id == null || validId) &&
      error is Map<String, dynamic> &&
      error['code'] is int &&
      error['code'] is! bool &&
      error['message'] is String &&
      (error['message'] as String).isNotEmpty &&
      error.keys.every(
        (key) => key == 'code' || key == 'message' || key == 'data',
      ) &&
      keys.every(
        (key) =>
            key == 'jsonrpc' ||
            key == 'protocolVersion' ||
            key == 'id' ||
            key == 'error',
      );
}

class EngineInfo {
  const EngineInfo({
    required this.engineVersion,
    required this.protocolVersion,
  });

  final String engineVersion;
  final String protocolVersion;

  factory EngineInfo.fromJson(Map<String, Object?> json) {
    final engineVersion = json['engineVersion'];
    final protocolVersion = json['protocolVersion'];
    if (engineVersion is! String || protocolVersion is! String) {
      throw const EngineProtocolException('Invalid engine.getInfo result.');
    }
    return EngineInfo(
      engineVersion: engineVersion,
      protocolVersion: protocolVersion,
    );
  }
}

class EngineProtocolException implements Exception {
  const EngineProtocolException(this.message);

  final String message;

  @override
  String toString() => message;
}

class EngineRpcException implements Exception {
  const EngineRpcException(this.code, this.message, {this.data});

  final int code;
  final String message;
  final Map<String, Object?>? data;

  @override
  String toString() => 'JSON-RPC $code: $message';
}

class EngineClient {
  EngineClient({
    WorkerStarter? startWorker,
    this.requestTimeout = const Duration(seconds: 5),
  }) : _startWorker = startWorker ?? _startDefaultWorker;

  final WorkerStarter _startWorker;
  final Duration requestTimeout;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  final StreamController<Object> _failures =
      StreamController<Object>.broadcast();
  int _nextRequestId = 0;
  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  bool _stopping = false;

  Stream<Object> get failures => _failures.stream;

  static Future<Process> _startDefaultWorker() {
    final executable = Platform.isWindows ? 'python' : 'python3';
    return Process.start(executable, const [
      '-m',
      'video_translator_engine.worker',
    ]);
  }

  Future<void> start() async {
    if (_process != null) {
      return;
    }

    final process = await _startWorker();
    _process = process;
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleFrame, onError: _fail);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((_) {}, onError: _fail);
    unawaited(process.exitCode.then(_handleExit));
  }

  Future<EngineInfo> getInfo() async {
    final result = await request('engine.getInfo');
    return EngineInfo.fromJson(result);
  }

  /// Inspects one source path through the existing path-only media IPC method.
  Future<MediaInspectionMetadata> inspectMedia(String sourcePath) async {
    try {
      final result = await request(
        'media.inspect',
        params: {'sourcePath': sourcePath},
      );
      final metadata = result['metadata'];
      if (result.length != 1 || metadata is! Map<String, dynamic>) {
        throw const EngineProtocolException('Invalid media.inspect result.');
      }
      return MediaInspectionMetadata.fromJson(
        Map<String, Object?>.from(metadata),
      );
    } on EngineRpcException catch (error) {
      try {
        throw MediaInspectionException.fromResponse(
          responseCode: error.code,
          data: error.data,
        );
      } on FormatException {
        throw error;
      }
    }
  }

  Future<Map<String, Object?>> request(
    String method, {
    Map<String, Object?>? params,
  }) {
    final process = _process;
    if (process == null) {
      return Future.error(
        const EngineProtocolException('Engine is not running.'),
      );
    }

    final id = ++_nextRequestId;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    final message = <String, Object?>{
      'jsonrpc': '2.0',
      'protocolVersion': _protocolVersion,
      'id': id,
      'method': method,
      'params': ?params,
    };

    try {
      process.stdin.write('${jsonEncode(message)}\n');
    } on Object catch (error) {
      _pending.remove(id);
      completer.completeError(error);
      return completer.future;
    }

    Timer(requestTimeout, () {
      if (_pending.remove(id) != null && !completer.isCompleted) {
        completer.completeError(
          EngineProtocolException('Timed out waiting for $method.'),
        );
      }
    });
    return completer.future;
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) {
      return;
    }

    _stopping = true;
    try {
      await request('engine.shutdown');
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on Object {
      process.kill();
    } finally {
      await _disposeProcess();
      _stopping = false;
    }
  }

  void _handleFrame(String frame) {
    if (frame.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(frame);
      if (!isValidIpcEnvelope(decoded)) {
        throw const EngineProtocolException('Malformed engine protocol frame.');
      }
      final message = Map<String, Object?>.from(decoded);
      final id = message['id'];
      if (id is! int) {
        return;
      }
      final completer = _pending.remove(id);
      if (completer == null) {
        return;
      }
      final error = message['error'];
      if (error is Map<String, dynamic>) {
        final code = error['code'];
        final text = error['message'];
        if (code is! int || text is! String) {
          throw const EngineProtocolException(
            'Malformed engine error response.',
          );
        }
        final data = error['data'];
        completer.completeError(
          EngineRpcException(
            code,
            text,
            data: data is Map<String, dynamic>
                ? Map<String, Object?>.from(data)
                : null,
          ),
        );
        return;
      }
      final result = message['result'];
      if (result is! Map<String, dynamic>) {
        throw const EngineProtocolException(
          'Malformed engine result response.',
        );
      }
      completer.complete(Map<String, Object?>.from(result));
    } on Object catch (error) {
      _fail(error);
    }
  }

  void _handleExit(int exitCode) {
    if (!_stopping) {
      _fail(EngineProtocolException('Engine exited unexpectedly ($exitCode).'));
    }
  }

  void _fail(Object error) {
    if (_process == null) {
      return;
    }
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
    _failures.add(error);
    _process?.kill();
    unawaited(_disposeProcess());
  }

  Future<void> _disposeProcess() async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _process = null;
  }

  Future<void> dispose() async {
    await stop();
    await _failures.close();
  }
}
