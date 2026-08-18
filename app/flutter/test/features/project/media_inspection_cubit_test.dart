import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/engine/media_inspection.dart';
import 'package:video_translator/features/project/media_inspection_cubit.dart';
import 'package:video_translator/features/project/project_draft.dart';

void main() {
  const source = ProjectSourceReference(
    path: '/videos/source.mp4',
    fileName: 'source.mp4',
  );

  final metadata = MediaInspectionMetadata(
    duration: const Duration(seconds: 95, milliseconds: 500),
    streams: const [
      MediaStreamMetadata(
        index: 0,
        kind: MediaStreamKind.video,
        codec: 'h264',
        dimensions: MediaDimensions(width: 1920, height: 1080),
      ),
      MediaStreamMetadata(index: 1, kind: MediaStreamKind.audio, codec: 'aac'),
    ],
    hasAudio: true,
  );

  test(
    'emits loading then normalized metadata for the selected source',
    () async {
      final cubit = MediaInspectionCubit(inspectMedia: (_) async => metadata);
      addTearDown(cubit.close);

      final states = expectLater(
        cubit.stream,
        emitsInOrder([
          const MediaInspectionLoading(source),
          MediaInspectionSuccess(source: source, metadata: metadata),
        ]),
      );

      await cubit.inspect(source);

      await states;
      expect(
        cubit.state,
        MediaInspectionSuccess(source: source, metadata: metadata),
      );
    },
  );

  test('maps a structured validation error to a safe failure state', () async {
    final cubit = MediaInspectionCubit(
      inspectMedia: (_) async => throw const MediaInspectionException(
        type: MediaInspectionErrorType.validation,
        code: 'media.audio_stream_missing',
        retryable: false,
      ),
    );
    addTearDown(cubit.close);

    await cubit.inspect(source);

    final state = cubit.state as MediaInspectionError;
    expect(state.error.kind, MediaInspectionFailureKind.audioStreamMissing);
    expect(state.error.message, contains('no audio stream'));
    expect(state.error.message, isNot(contains(source.path)));
  });

  test(
    'maps structured media-tool errors without exposing a source path',
    () async {
      final cubit = MediaInspectionCubit(
        inspectMedia: (_) async => throw const MediaInspectionException(
          type: MediaInspectionErrorType.tool,
          code: 'media.ffprobe_unavailable',
          retryable: false,
        ),
      );
      addTearDown(cubit.close);

      await cubit.inspect(source);

      final state = cubit.state as MediaInspectionError;
      expect(state.error.kind, MediaInspectionFailureKind.toolUnavailable);
      expect(state.error.message, contains('tool is unavailable'));
      expect(state.error.message, isNot(contains(source.path)));
    },
  );

  test(
    'clears the last inspection without changing project setup state',
    () async {
      final cubit = MediaInspectionCubit(inspectMedia: (_) async => metadata);
      addTearDown(cubit.close);

      await cubit.inspect(source);
      cubit.clear();

      expect(cubit.state, const MediaInspectionIdle());
    },
  );
}
