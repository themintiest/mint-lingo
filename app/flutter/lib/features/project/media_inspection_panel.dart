import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/engine/media_inspection.dart';
import 'package:video_translator/app/theme/app_radius.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/features/project/media_inspection_cubit.dart';
import 'package:video_translator/features/project/project_draft.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

class MediaInspectionPanel extends StatelessWidget {
  const MediaInspectionPanel({required this.source, super.key});

  final ProjectSourceReference? source;

  @override
  Widget build(BuildContext context) {
    final selectedSource = source;
    if (selectedSource == null) {
      return const SizedBox.shrink();
    }

    return BlocBuilder<MediaInspectionCubit, MediaInspectionState>(
      builder: (context, state) {
        final content = switch (state) {
          MediaInspectionLoading() => const _InspectionLoading(),
          MediaInspectionSuccess(:final metadata) => _InspectionDetails(
            metadata: metadata,
          ),
          MediaInspectionError(:final error) => _InspectionError(error: error),
          MediaInspectionIdle() => _InspectionPrompt(source: selectedSource),
        };
        if (state.source != selectedSource) {
          return _InspectionPrompt(source: selectedSource);
        }
        return content;
      },
    );
  }
}

class _InspectionPrompt extends StatelessWidget {
  const _InspectionPrompt({required this.source});

  final ProjectSourceReference source;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Card(
      key: const Key('media-inspection-prompt'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _MediaDetailsHeader(),
            const SizedBox(height: AppSpacing.xs),
            Text(localizations.inspectMediaPrompt),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.read<MediaInspectionCubit>().inspect(source),
                icon: const Icon(Icons.info_outline),
                label: Text(localizations.inspectVideo),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectionLoading extends StatelessWidget {
  const _InspectionLoading();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Card(
      key: const Key('media-inspection-loading'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _MediaDetailsHeader(),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  localizations.inspectingMediaDetails,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectionDetails extends StatelessWidget {
  const _InspectionDetails({required this.metadata});

  final MediaInspectionMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Card(
      key: const Key('media-inspection-details'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _MediaDetailsHeader(),
            const SizedBox(height: AppSpacing.md),
            _MediaFacts(metadata: metadata),
            const Divider(height: AppSpacing.lg),
            Text(
              localizations.streams,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final stream in metadata.streams)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _StreamDetail(stream: stream),
              ),
          ],
        ),
      ),
    );
  }
}

class _MediaDetailsHeader extends StatelessWidget {
  const _MediaDetailsHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Icon(Icons.perm_media_outlined, color: colorScheme.primary),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          localizations.mediaDetails,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _MediaFacts extends StatelessWidget {
  const _MediaFacts({required this.metadata});

  final MediaInspectionMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final duration = _MediaFact(
      key: const Key('media-detail-duration'),
      icon: Icons.schedule_outlined,
      label: localizations.duration,
      value: _formatDuration(metadata.duration),
    );
    final audio = _MediaFact(
      key: const Key('media-detail-audio'),
      icon: Icons.graphic_eq_outlined,
      label: localizations.audio,
      value: metadata.hasAudio
          ? localizations.audioPresent
          : localizations.audioNotPresent,
      isPositive: metadata.hasAudio,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 320) {
          return Column(
            children: [
              duration,
              const SizedBox(height: AppSpacing.sm),
              audio,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: duration),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: audio),
          ],
        );
      },
    );
  }
}

class _MediaFact extends StatelessWidget {
  const _MediaFact({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.isPositive = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final valueColor = isPositive
        ? colorScheme.tertiary
        : colorScheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(color: valueColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreamDetail extends StatelessWidget {
  const _StreamDetail({required this.stream});

  final MediaStreamMetadata stream;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: Key('media-stream-${stream.index}'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(
              _streamIcon(stream.kind),
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(_streamLabel(stream, AppLocalizations.of(context))),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectionError extends StatelessWidget {
  const _InspectionError({required this.error});

  final MediaInspectionFailure error;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Card(
      key: const Key('media-inspection-error'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizations.unableToInspectMedia,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(_inspectionErrorMessage(error, localizations)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  final paddedMinutes = minutes.toString().padLeft(2, '0');
  final paddedSeconds = seconds.toString().padLeft(2, '0');
  return hours > 0
      ? '${hours.toString().padLeft(2, '0')}:$paddedMinutes:$paddedSeconds'
      : '$paddedMinutes:$paddedSeconds';
}

String _streamLabel(
  MediaStreamMetadata stream,
  AppLocalizations localizations,
) {
  final dimensions = stream.dimensions;
  final size = dimensions == null
      ? ''
      : ' · ${dimensions.width} × ${dimensions.height}';
  return '${_kindLabel(stream.kind, localizations)} '
      '#${stream.index} · ${stream.codec}$size';
}

IconData _streamIcon(MediaStreamKind kind) => switch (kind) {
  MediaStreamKind.video => Icons.videocam_outlined,
  MediaStreamKind.audio => Icons.graphic_eq_outlined,
  MediaStreamKind.subtitle => Icons.subtitles_outlined,
  MediaStreamKind.data => Icons.data_object_outlined,
  MediaStreamKind.attachment => Icons.attach_file_outlined,
  MediaStreamKind.unknown => Icons.help_outline,
};

String _kindLabel(MediaStreamKind kind, AppLocalizations localizations) =>
    switch (kind) {
      MediaStreamKind.video => localizations.mediaStreamVideo,
      MediaStreamKind.audio => localizations.mediaStreamAudio,
      MediaStreamKind.subtitle => localizations.mediaStreamSubtitle,
      MediaStreamKind.data => localizations.mediaStreamData,
      MediaStreamKind.attachment => localizations.mediaStreamAttachment,
      MediaStreamKind.unknown => localizations.mediaStreamUnknown,
    };

String _inspectionErrorMessage(
  MediaInspectionFailure error,
  AppLocalizations localizations,
) => switch (error.kind) {
  MediaInspectionFailureKind.sourceNotFound =>
    localizations.mediaErrorSourceNotFound,
  MediaInspectionFailureKind.sourceNotReadable =>
    localizations.mediaErrorSourceNotReadable,
  MediaInspectionFailureKind.unsupportedMedia =>
    localizations.mediaErrorUnsupported,
  MediaInspectionFailureKind.metadataUnavailable =>
    localizations.mediaErrorMetadataUnavailable,
  MediaInspectionFailureKind.audioStreamMissing =>
    localizations.mediaErrorAudioMissing,
  MediaInspectionFailureKind.toolUnavailable =>
    localizations.mediaErrorToolUnavailable,
  MediaInspectionFailureKind.unknown => localizations.mediaErrorUnknown,
};
