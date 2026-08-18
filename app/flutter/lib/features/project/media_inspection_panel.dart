import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/engine/media_inspection.dart';
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
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Media details',
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.sm),
            Text('Inspecting media details...'),
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
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Media details',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            _DetailRow(
              label: 'Duration',
              value: _formatDuration(metadata.duration),
            ),
            _DetailRow(
              label: 'Audio',
              value: metadata.hasAudio ? 'Present' : 'Not present',
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Streams', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            for (final stream in metadata.streams)
              Text(
                _streamLabel(stream),
                key: Key('media-stream-${stream.index}'),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final paddedMinutes = minutes.toString().padLeft(2, '0');
    final paddedSeconds = seconds.toString().padLeft(2, '0');
    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$paddedMinutes:$paddedSeconds'
        : '$paddedMinutes:$paddedSeconds';
  }

  static String _streamLabel(MediaStreamMetadata stream) {
    final dimensions = stream.dimensions;
    final size = dimensions == null
        ? ''
        : ' · ${dimensions.width} × ${dimensions.height}';
    return '${_kindLabel(stream.kind)} #${stream.index} · ${stream.codec}$size';
  }

  static String _kindLabel(MediaStreamKind kind) => switch (kind) {
    MediaStreamKind.video => 'Video',
    MediaStreamKind.audio => 'Audio',
    MediaStreamKind.subtitle => 'Subtitle',
    MediaStreamKind.data => 'Data',
    MediaStreamKind.attachment => 'Attachment',
    MediaStreamKind.unknown => 'Unknown',
  };
}

class _InspectionError extends StatelessWidget {
  const _InspectionError({required this.error});

  final MediaInspectionFailure error;

  @override
  Widget build(BuildContext context) {
    return Card(
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text('$label: $value'),
    );
  }
}
