import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/engine/media_inspection.dart';
import 'package:video_translator/features/project/project_draft.dart';

typedef MediaInspectionRequester = Future<MediaInspectionMetadata> Function(
  String sourcePath,
);

sealed class MediaInspectionState {
  const MediaInspectionState();

  ProjectSourceReference? get source;
}

final class MediaInspectionIdle extends MediaInspectionState {
  const MediaInspectionIdle();

  @override
  ProjectSourceReference? get source => null;

  @override
  bool operator ==(Object other) => other is MediaInspectionIdle;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class MediaInspectionLoading extends MediaInspectionState {
  const MediaInspectionLoading(this.source);

  @override
  final ProjectSourceReference source;

  @override
  bool operator ==(Object other) =>
      other is MediaInspectionLoading && other.source == source;

  @override
  int get hashCode => Object.hash(runtimeType, source);
}

final class MediaInspectionSuccess extends MediaInspectionState {
  const MediaInspectionSuccess({required this.source, required this.metadata});

  @override
  final ProjectSourceReference source;
  final MediaInspectionMetadata metadata;

  @override
  bool operator ==(Object other) =>
      other is MediaInspectionSuccess &&
      other.source == source &&
      other.metadata == metadata;

  @override
  int get hashCode => Object.hash(runtimeType, source, metadata);
}

enum MediaInspectionFailureKind {
  sourceNotFound,
  sourceNotReadable,
  unsupportedMedia,
  metadataUnavailable,
  audioStreamMissing,
  toolUnavailable,
  unknown,
}

/// A safe, user-facing inspection error that never includes a source path.
final class MediaInspectionFailure {
  const MediaInspectionFailure({required this.kind, required this.retryable});

  final MediaInspectionFailureKind kind;
  final bool retryable;

  String get message => switch (kind) {
    MediaInspectionFailureKind.sourceNotFound =>
      'The selected video is no longer available. Choose it again.',
    MediaInspectionFailureKind.sourceNotReadable => 'The selected video cannot be read. Check its permissions and choose it again.',
    MediaInspectionFailureKind.unsupportedMedia =>
      'This file is not a supported media format. Choose a different video.',
    MediaInspectionFailureKind.metadataUnavailable => 'Media details could not be read for this video. Choose a different video.',
    MediaInspectionFailureKind.audioStreamMissing =>
      'This video has no audio stream and cannot be translated.',
    MediaInspectionFailureKind.toolUnavailable => 'The media inspection tool is unavailable. Repair or reinstall the application.',
    MediaInspectionFailureKind.unknown =>
      'Media details could not be inspected. Please try again.',
  };

  @override
  bool operator ==(Object other) =>
      other is MediaInspectionFailure &&
      other.kind == kind &&
      other.retryable == retryable;

  @override
  int get hashCode => Object.hash(kind, retryable);
}

final class MediaInspectionError extends MediaInspectionState {
  const MediaInspectionError({required this.source, required this.error});

  @override
  final ProjectSourceReference source;
  final MediaInspectionFailure error;

  @override
  bool operator ==(Object other) =>
      other is MediaInspectionError &&
      other.source == source &&
      other.error == error;

  @override
  int get hashCode => Object.hash(runtimeType, source, error);
}

/// Coordinates source inspection without changing project setup state.
final class MediaInspectionCubit extends Cubit<MediaInspectionState> {
  MediaInspectionCubit({required this.inspectMedia})
    : super(const MediaInspectionIdle());

  final MediaInspectionRequester inspectMedia;

  Future<void> inspect(ProjectSourceReference source) async {
    if (state is MediaInspectionLoading && state.source == source) {
      return;
    }

    emit(MediaInspectionLoading(source));
    try {
      final metadata = await inspectMedia(source.path);
      if (!isClosed &&
          state is MediaInspectionLoading &&
          state.source == source) {
        emit(MediaInspectionSuccess(source: source, metadata: metadata));
      }
    } on MediaInspectionException catch (error) {
      if (!isClosed &&
          state is MediaInspectionLoading &&
          state.source == source) {
        emit(
          MediaInspectionError(
            source: source,
            error: MediaInspectionFailure(
              kind: _failureKind(error),
              retryable: error.retryable,
            ),
          ),
        );
      }
    } on Object {
      if (!isClosed &&
          state is MediaInspectionLoading &&
          state.source == source) {
        emit(
          MediaInspectionError(
            source: source,
            error: const MediaInspectionFailure(
              kind: MediaInspectionFailureKind.unknown,
              retryable: false,
            ),
          ),
        );
      }
    }
  }

  void clear() => emit(const MediaInspectionIdle());

  MediaInspectionFailureKind _failureKind(MediaInspectionException error) {
    return switch (error.code) {
      'media.source_not_found' => MediaInspectionFailureKind.sourceNotFound,
      'media.source_not_readable' =>
        MediaInspectionFailureKind.sourceNotReadable,
      'media.unsupported_media' => MediaInspectionFailureKind.unsupportedMedia,
      'media.metadata_unavailable' =>
        MediaInspectionFailureKind.metadataUnavailable,
      'media.audio_stream_missing' =>
        MediaInspectionFailureKind.audioStreamMissing,
      'media.ffprobe_unsupported_platform' ||
      'media.ffprobe_unavailable' => MediaInspectionFailureKind.toolUnavailable,
      _ => MediaInspectionFailureKind.unknown,
    };
  }
}
