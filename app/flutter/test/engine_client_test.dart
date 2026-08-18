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
    for (final fixture in _jsonFixtures(contractRoot.resolve('media/invalid/'))) {
      final message = _readJson(fixture) as Map<String, dynamic>;
      expect(isValidIpcEnvelope(message), isTrue, reason: fixture.path);
      expect(_isMediaInspectionMessage(message), isFalse, reason: fixture.path);
    }
  });

  test(
    'spawns the real worker for the getInfo and shutdown handshake',
    () async {
      final client = EngineClient(
        startWorker: () => Process.start(
          Platform.isWindows ? 'python' : 'python3',
          const ['-m', 'video_translator_engine.worker'],
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
        metadata.keys.toSet().containsAll(
          const {'durationMicroseconds', 'streams', 'hasAudio'},
        ) &&
        metadata.length == 3 &&
        metadata['durationMicroseconds'] is int &&
        metadata['durationMicroseconds'] is! bool &&
        metadata['streams'] is List &&
        (metadata['streams'] as List).isNotEmpty &&
        metadata['hasAudio'] is bool;
  }

  final error = message['error'];
  if (error is! Map<String, dynamic> || error['data'] is! Map<String, dynamic>) {
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
