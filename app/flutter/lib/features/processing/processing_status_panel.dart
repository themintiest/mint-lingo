import 'package:flutter/material.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/features/processing/processing_bloc.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

/// Resolves an opaque workflow stage to its workflow-owned localized label.
///
/// The shared panel neither stores nor interprets stage IDs. A concrete
/// workflow supplies this callback from its own localized presentation layer.
typedef ProcessingStageLabelBuilder = String Function(
  BuildContext context,
  String stageId,
);

/// Shared presentation for the normalized state of one processing job.
///
/// This widget is deliberately display-only. Its optional cancellation callback
/// lets a concrete workflow connect its own request path later, without this
/// presentation layer issuing RPC calls or deciding cancellation completion.
class ProcessingStatusPanel extends StatelessWidget {
  const ProcessingStatusPanel({
    super.key,
    required this.state,
    required this.stageLabelBuilder,
    this.onCancelRequested,
  });

  final ProcessingState state;
  final ProcessingStageLabelBuilder stageLabelBuilder;
  final ValueChanged<String>? onCancelRequested;

  @override
  Widget build(BuildContext context) => switch (state) {
    ProcessingIdle() => const SizedBox.shrink(),
    ProcessingActive() => _ActiveProcessingStatus(
      state: state as ProcessingActive,
      stageLabelBuilder: stageLabelBuilder,
      onCancelRequested: onCancelRequested,
    ),
    ProcessingTerminal() => _TerminalProcessingStatus(
      state: state as ProcessingTerminal,
    ),
    ProcessingRecovery() => _RecoveryProcessingStatus(
      state: state as ProcessingRecovery,
    ),
  };
}

class _ActiveProcessingStatus extends StatelessWidget {
  const _ActiveProcessingStatus({
    required this.state,
    required this.stageLabelBuilder,
    required this.onCancelRequested,
  });

  final ProcessingActive state;
  final ProcessingStageLabelBuilder stageLabelBuilder;
  final ValueChanged<String>? onCancelRequested;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final progress = state.progress;
    final stageLabel = state.stageId == null
        ? null
        : _stageLabel(context, state.stageId!);

    return Card(
      key: const Key('processing-status-active'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.processingStatusTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (stageLabel == null)
              _PreparingProgress(label: localizations.processingPreparing)
            else ...[
              Text(
                stageLabel,
                key: const Key('processing-status-stage'),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              _ProgressPresentation(progress: progress!),
            ],
            if (state.cancellationRequested) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                localizations.cancellationRequested,
                key: const Key('processing-status-cancellation-requested'),
              ),
            ],
            if (onCancelRequested != null) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                key: const Key('processing-status-cancel'),
                onPressed: state.cancellationRequested
                    ? null
                    : () => onCancelRequested!(state.jobId),
                icon: const Icon(Icons.cancel_outlined),
                label: Text(localizations.cancelProcessing),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _stageLabel(BuildContext context, String stageId) {
    final label = stageLabelBuilder(context, stageId);
    if (label.trim().isEmpty) {
      throw ArgumentError.value(
        label,
        'stageLabelBuilder',
        'must return a non-empty localized stage label',
      );
    }
    return label;
  }
}

class _PreparingProgress extends StatelessWidget {
  const _PreparingProgress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: AppSpacing.sm),
      Text(label),
    ],
  );
}

class _ProgressPresentation extends StatelessWidget {
  const _ProgressPresentation({required this.progress});

  final ProcessingProgress progress;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return switch (progress) {
      ProcessingDeterminateProgress(:final completedUnits, :final totalUnits) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              key: const Key('processing-progress-determinate'),
              value: completedUnits / totalUnits,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              localizations.processingProgressUnits(completedUnits, totalUnits),
              key: const Key('processing-progress-units'),
            ),
          ],
        ),
      ProcessingIndeterminateProgress() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(
            key: Key('processing-progress-indeterminate'),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(localizations.processingWorking),
        ],
      ),
    };
  }
}

class _TerminalProcessingStatus extends StatelessWidget {
  const _TerminalProcessingStatus({required this.state});

  final ProcessingTerminal state;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final presentation = switch (state.lifecycle) {
      ProcessingJobLifecycle.completed => (
        key: const Key('processing-status-completed'),
        icon: Icons.check_circle_outline,
        message: localizations.processingCompleted,
        color: colorScheme.primaryContainer,
        foreground: colorScheme.onPrimaryContainer,
      ),
      ProcessingJobLifecycle.failed => (
        key: const Key('processing-status-failed'),
        icon: Icons.error_outline,
        message: localizations.processingFailed,
        color: colorScheme.errorContainer,
        foreground: colorScheme.onErrorContainer,
      ),
      ProcessingJobLifecycle.cancelled => (
        key: const Key('processing-status-cancelled'),
        icon: Icons.cancel_outlined,
        message: localizations.processingCancelled,
        color: colorScheme.surfaceContainerHighest,
        foreground: colorScheme.onSurfaceVariant,
      ),
      ProcessingJobLifecycle.created || ProcessingJobLifecycle.running =>
        throw StateError('ProcessingTerminal must have a terminal lifecycle'),
    };

    return _FeedbackCard(
      cardKey: presentation.key,
      icon: presentation.icon,
      message: presentation.message,
      backgroundColor: presentation.color,
      foregroundColor: presentation.foreground,
    );
  }
}

class _RecoveryProcessingStatus extends StatelessWidget {
  const _RecoveryProcessingStatus({required this.state});

  final ProcessingRecovery state;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final presentation = switch (state.disposition) {
      ProcessingRecoveryDisposition.recoverable => (
        key: const Key('processing-status-recoverable'),
        icon: Icons.restore_outlined,
        message: localizations.processingRecoveryAvailable,
        color: colorScheme.secondaryContainer,
        foreground: colorScheme.onSecondaryContainer,
      ),
      ProcessingRecoveryDisposition.failed => (
        key: const Key('processing-status-recovery-failed'),
        icon: Icons.error_outline,
        message: localizations.processingRecoveryFailed,
        color: colorScheme.errorContainer,
        foreground: colorScheme.onErrorContainer,
      ),
    };

    return _FeedbackCard(
      cardKey: presentation.key,
      icon: presentation.icon,
      message: presentation.message,
      backgroundColor: presentation.color,
      foregroundColor: presentation.foreground,
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.cardKey,
    required this.icon,
    required this.message,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final Key cardKey;
  final IconData icon;
  final String message;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) => Card(
    key: cardKey,
    color: backgroundColor,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Icon(icon, color: foregroundColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: foregroundColor),
            ),
          ),
        ],
      ),
    ),
  );
}
