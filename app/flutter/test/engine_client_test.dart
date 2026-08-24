import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/engine/engine_client.dart';

void main() {
  final contractRoot = Directory.current.parent.parent.uri.resolve(
    'shared/schemas/ipc/v1/fixtures/',
  );

  test('accepts and rejects the shared JSON-RPC envelope fixtures', () {
    for (final fixture in _jsonFixtures(contractRoot.resolve('valid/'))) {
      expect(
        isValidIpcEnvelope(_readJson(fixture)),
        isTrue,
        reason: fixture.path,
      );
    }
    for (final fixture in _jsonFixtures(contractRoot.resolve('invalid/'))) {
      expect(
        isValidIpcEnvelope(_readJson(fixture)),
        isFalse,
        reason: fixture.path,
      );
    }
  });

  test('matches the shared engine lifecycle and error fixtures', () {
    final validFixtures = _jsonFixtures(contractRoot.resolve('engine/valid/'));
    for (final fixture in validFixtures) {
      final message = _readJson(fixture) as Map<String, dynamic>;
      expect(isValidIpcEnvelope(message), isTrue, reason: fixture.path);
      if (message.containsKey('method')) {
        expect(message.containsKey('params'), isFalse, reason: fixture.path);
      } else if (message.containsKey('result')) {
        expect(
          message['result'],
          anyOf(
            equals({'engineVersion': '0.1.0', 'protocolVersion': '1.0'}),
            equals({'accepted': true}),
          ),
          reason: fixture.path,
        );
      } else {
        final data =
            (message['error'] as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        expect(data.keys, unorderedEquals(['engineCode', 'safeDetails']));
        expect(
          (data['safeDetails'] as Map<String, dynamic>).keys,
          unorderedEquals(['reason', 'retryable']),
        );
      }
    }

    final invalidGetInfo = _readJson(
      _jsonFixtures(contractRoot.resolve('engine/invalid/')).firstWhere(
        (file) => file.path.endsWith('engine-get-info-with-params.json'),
      ),
    ) as Map<String, dynamic>;
    expect(invalidGetInfo['params'], isNotNull);
  });

  test('matches the shared media-inspection fixtures', () {
    for (final fixture in _jsonFixtures(contractRoot.resolve('media/valid/'))) {
      final message = _readJson(fixture) as Map<String, dynamic>;
      expect(isValidIpcEnvelope(message), isTrue, reason: fixture.path);
      expect(_isMediaInspectionMessage(message), isTrue, reason: fixture.path);
    }
    for (final fixture in _jsonFixtures(
      contractRoot.resolve('media/invalid/'),
    )) {
      final message = _readJson(fixture) as Map<String, dynamic>;
      expect(isValidIpcEnvelope(message), isTrue, reason: fixture.path);
      expect(_isMediaInspectionMessage(message), isFalse, reason: fixture.path);
    }
  });

  test('matches the shared job-management fixtures', () {
    for (final fixture in _jsonFixtures(contractRoot.resolve('jobs/valid/'))) {
      final message = _readJson(fixture) as Map<String, dynamic>;
      expect(isValidIpcEnvelope(message), isTrue, reason: fixture.path);
      expect(_isJobManagementMessage(message), isTrue, reason: fixture.path);
    }
    for (final fixture in _jsonFixtures(
      contractRoot.resolve('jobs/invalid/'),
    )) {
      final message = _readJson(fixture) as Map<String, dynamic>;
      expect(isValidIpcEnvelope(message), isTrue, reason: fixture.path);
      expect(_isJobManagementMessage(message), isFalse, reason: fixture.path);
    }
  });

  test(
    'spawns the real worker for the getInfo and shutdown handshake',
    () async {
      final client = EngineClient(
        startWorker: () => Process.start(
          Platform.isWindows ? 'python' : 'python3',
          const ['-m', 'mint_lingo_engine.worker'],
        ),
      );
      addTearDown(client.dispose);

      await client.start();
      final info = await client.getInfo();

      expect(info.engineVersion, '0.1.0');
      expect(info.protocolVersion, '1.0');

      await client.stop();
    },
  );
}

List<File> _jsonFixtures(Uri directory) {
  return Directory.fromUri(directory)
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList();
}

Object? _readJson(File fixture) => jsonDecode(fixture.readAsStringSync());

bool _isMediaInspectionMessage(Map<String, dynamic> message) {
  if (message['method'] == 'media.inspect') {
    final params = message['params'];
    return params is Map<String, dynamic> &&
        params.keys.toSet().containsAll(const {'sourcePath'}) &&
        params.length == 1 &&
        params['sourcePath'] is String &&
        (params['sourcePath'] as String).isNotEmpty;
  }

  final result = message['result'];
  if (result is Map<String, dynamic>) {
    final metadata = result['metadata'];
    return result.length == 1 &&
        metadata is Map<String, dynamic> &&
        metadata.keys.toSet().containsAll(const {
          'durationMicroseconds',
          'streams',
          'hasAudio',
        }) &&
        metadata.length == 3 &&
        metadata['durationMicroseconds'] is int &&
        metadata['durationMicroseconds'] is! bool &&
        metadata['streams'] is List &&
        (metadata['streams'] as List).isNotEmpty &&
        metadata['hasAudio'] is bool;
  }

  final error = message['error'];
  if (error is! Map<String, dynamic> ||
      error['data'] is! Map<String, dynamic>) {
    return false;
  }
  final data = error['data'] as Map<String, dynamic>;
  if (error['code'] == -32010) {
    return data.length == 2 &&
        data.containsKey('mediaCode') &&
        data['retryable'] is bool;
  }
  return error['code'] == -32011 &&
      error['message'] == 'Media inspection tool is unavailable.' &&
      data.length == 2 &&
      data.containsKey('toolCode') &&
      data['retryable'] == false;
}

final _jobIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

bool _isJobManagementMessage(Map<String, dynamic> message) {
  bool isJobId(Object? value) =>
      value is String && _jobIdPattern.hasMatch(value);

  bool isJobState(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.length != 2 ||
        !value.containsKey('jobId') ||
        !value.containsKey('lifecycle')) {
      return false;
    }
    return isJobId(value['jobId']) &&
        const {
          'created',
          'running',
          'completed',
          'failed',
          'cancelled',
        }.contains(value['lifecycle']);
  }

  final method = message['method'];
  final params = message['params'];
  if (method == 'job.start') {
    return params is Map<String, dynamic> &&
        params.length == 2 &&
        params['workflowId'] is String &&
        (params['workflowId'] as String).isNotEmpty &&
        params['workflowPayload'] is Map;
  }
  if (method == 'job.cancel' || method == 'job.get') {
    return params is Map<String, dynamic> &&
        params.length == 1 &&
        isJobId(params['jobId']);
  }
  if (method == 'job.stateChanged') {
    return isJobState(params);
  }
  if (method == 'job.progress') {
    if (params is! Map<String, dynamic> ||
        params.length != 3 ||
        !isJobId(params['jobId']) ||
        params['stageId'] is! String ||
        (params['stageId'] as String).isEmpty) {
      return false;
    }
    final progress = params['progress'];
    if (progress is! Map<String, dynamic>) {
      return false;
    }
    if (progress['kind'] == 'indeterminate') {
      return progress.length == 1;
    }
    return progress.length == 3 &&
        progress['kind'] == 'determinate' &&
        progress['completedUnits'] is int &&
        progress['completedUnits'] is! bool &&
        progress['totalUnits'] is int &&
        progress['totalUnits'] is! bool &&
        (progress['totalUnits'] as int) > 0 &&
        (progress['completedUnits'] as int) >= 0 &&
        (progress['completedUnits'] as int) <= (progress['totalUnits'] as int);
  }

  final result = message['result'];
  if (result is Map<String, dynamic>) {
    if (result.length == 1 && result.containsKey('job')) {
      return isJobState(result['job']);
    }
    return result.length == 2 &&
        isJobId(result['jobId']) &&
        result['cancellationRequested'] == true;
  }

  final error = message['error'];
  if (error is! Map<String, dynamic> ||
      error['data'] is! Map<String, dynamic>) {
    return false;
  }
  final data = error['data'] as Map<String, dynamic>;
  if (error['code'] == -32020) {
    return error['message'] == 'Another job is already active.' &&
        data.length == 3 &&
        data['jobCode'] == 'job.active_job_conflict' &&
        data['retryable'] == false &&
        isJobId(data['activeJobId']);
  }
  return error['code'] == -32021 &&
      error['message'] == 'Job not found.' &&
      data.length == 2 &&
      data['jobCode'] == 'job.not_found' &&
      data['retryable'] == false;
}
