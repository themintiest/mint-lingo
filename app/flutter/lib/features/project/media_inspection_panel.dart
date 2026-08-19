import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/engine/media_inspection.dart';
import 'package:video_translator/app/theme/app_radius.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/features/project/media_inspection_cubit.dart';
import 'package:video_translator/features/project/project_draft.dart';

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
          return SelectionArea(
            child: _InspectionPrompt(source: selectedSource),
          );
        }
        return SelectionArea(child: content);
      },
    );
  }
}

class _InspectionPrompt extends StatelessWidget {
  const _InspectionPrompt({required this.source});

  final ProjectSourceReference source;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('media-inspection-prompt'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _MediaDetailsHeader(),
            const SizedBox(height: AppSpacing.xs),
            const Text('Inspect this video to confirm its media details.'),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.read<MediaInspectionCubit>().inspect(source),
                icon: const Icon(Icons.info_outline),
                label: const Text('Inspect video'),
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
                  'Inspecting media details...',
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
            Text('Streams', style: Theme.of(context).textTheme.labelLarge),
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
        Text('Media details', style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _MediaFacts extends StatelessWidget {
  const _MediaFacts({required this.metadata});

  final MediaInspectionMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final duration = _MediaFact(
      key: const Key('media-detail-duration'),
      icon: Icons.schedule_outlined,
      label: 'Duration',
      value: _formatDuration(metadata.duration),
    );
    final audio = _MediaFact(
      key: const Key('media-detail-audio'),
      icon: Icons.graphic_eq_outlined,
      label: 'Audio',
      value: metadata.hasAudio ? 'Present' : 'Not present',
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
            Expanded(child: Text(_streamLabel(stream))),
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
                    'Unable to inspect media',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(error.message),
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

String _streamLabel(MediaStreamMetadata stream) {
  final dimensions = stream.dimensions;
  final size = dimensions == null
      ? ''
      : ' · ${dimensions.width} × ${dimensions.height}';
  return '${_kindLabel(stream.kind)} #${stream.index} · ${stream.codec}$size';
}

IconData _streamIcon(MediaStreamKind kind) => switch (kind) {
  MediaStreamKind.video => Icons.videocam_outlined,
  MediaStreamKind.audio => Icons.graphic_eq_outlined,
  MediaStreamKind.subtitle => Icons.subtitles_outlined,
  MediaStreamKind.data => Icons.data_object_outlined,
  MediaStreamKind.attachment => Icons.attach_file_outlined,
  MediaStreamKind.unknown => Icons.help_outline,
};

String _kindLabel(MediaStreamKind kind) => switch (kind) {
  MediaStreamKind.video => 'Video',
  MediaStreamKind.audio => 'Audio',
  MediaStreamKind.subtitle => 'Subtitle',
  MediaStreamKind.data => 'Data',
  MediaStreamKind.attachment => 'Attachment',
  MediaStreamKind.unknown => 'Unknown',
};
