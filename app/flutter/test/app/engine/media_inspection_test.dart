import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/engine/media_inspection.dart';

void main() {
  test('parses normalized media metadata from the IPC result shape', () {
    final metadata = MediaInspectionMetadata.fromJson({
      'durationMicroseconds': 95500000,
      'streams': [
        {
          'index': 0,
          'kind': 'video',
          'codec': 'h264',
          'dimensions': {'width': 1920, 'height': 1080},
        },
        {'index': 1, 'kind': 'audio', 'codec': 'aac'},
      ],
      'hasAudio': true,
    });

    expect(metadata.duration, const Duration(seconds: 95, milliseconds: 500));
    expect(
      metadata.streams.singleWhere((stream) => stream.index == 0).dimensions,
      const MediaDimensions(width: 1920, height: 1080),
    );
    expect(metadata.hasAudio, isTrue);
  });

  test(
    'rejects media metadata whose audio flag conflicts with its streams',
    () {
      expect(
        () => MediaInspectionMetadata.fromJson({
          'durationMicroseconds': 0,
          'streams': [
            {
              'index': 0,
              'kind': 'video',
              'codec': 'h264',
              'dimensions': {'width': 1920, 'height': 1080},
            },
          ],
          'hasAudio': true,
        }),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
