import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/engine/engine_connection_cubit.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/features/project/media_inspection_cubit.dart';
import 'package:video_translator/features/project/media_inspection_panel.dart';
import 'package:video_translator/features/project/project_language_controls.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';
import 'package:video_translator/features/video/video_player_cubit.dart';
import 'package:video_translator/features/video/video_player_surface.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

class ProjectWorkspacePage extends StatelessWidget {
  const ProjectWorkspacePage({super.key});

  static const _maxContentWidth = 720.0;
  static const _compactWidth = 600.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Translator')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < _compactWidth
              ? AppSpacing.lg
              : AppSpacing.xl;
          return BlocListener<ProjectSetupCubit, ProjectSetupState>(
            listenWhen: (previous, current) =>
                previous.draft?.source != current.draft?.source ||
                current is ProjectSetupError,
            listener: (context, state) {
              final inspectionCubit = context.read<MediaInspectionCubit>();
              if (inspectionCubit.state.source != state.draft?.source) {
                inspectionCubit.clear();
              }
              final videoPlayerCubit = context.read<VideoPlayerCubit>();
              final source = state.draft?.source;
              if (videoPlayerCubit.state.source != source) {
                if (source == null) {
                  unawaited(videoPlayerCubit.clear());
                } else {
                  unawaited(videoPlayerCubit.open(source));
                }
              }
              if (state is ProjectSetupError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_setupErrorMessage(state.error))),
                );
              }
            },
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: AppSpacing.xl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                  child: SizedBox(
                    width: double.infinity,
                    child: BlocBuilder<ProjectSetupCubit, ProjectSetupState>(
                      builder: (context, state) {
                        final source = state.draft?.source;
                        final isSelecting = state is ProjectSetupSelecting;
                        if (source == null) {
                          return _EmptyProjectWorkspace(
                            isSelecting: isSelecting,
                            onOpenVideo: isSelecting
                                ? null
                                : () => context
                                      .read<ProjectSetupCubit>()
                                      .selectSourceVideo(),
                          );
                        }

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              source.fileName,
                              style: Theme.of(context).textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'This video is ready for project setup.',
                              style: Theme.of(context).textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            const VideoPlayerSurface(),
                            const SizedBox(height: AppSpacing.lg),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: [
                                FilledButton.icon(
                                  onPressed: isSelecting
                                      ? null
                                      : () => context
                                            .read<ProjectSetupCubit>()
                                            .selectSourceVideo(),
                                  icon: isSelecting
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.folder_open_outlined),
                                  label: Text(
                                    isSelecting
                                        ? 'Selecting video...'
                                        : 'Replace video',
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: isSelecting
                                      ? null
                                      : () => _checkSetup(context),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Check setup'),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            MediaInspectionPanel(source: source),
                            const SizedBox(height: AppSpacing.lg),
                            const ProjectLanguageControls(),
                            const SizedBox(height: AppSpacing.lg),
                            Center(
                              child:
                                  BlocBuilder<
                                    EngineConnectionCubit,
                                    EngineConnectionState
                                  >(
                                    builder: (context, state) {
                                      return Text(
                                        'Engine: ${_engineStatusText(state.status)}',
                                      );
                                    },
                                  ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _checkSetup(BuildContext context) {
    if (context.read<ProjectSetupCubit>().validateForProcessing()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project setup is complete.')),
      );
    }
  }

  String _setupErrorMessage(Object error) {
    return switch (error) {
      ProjectSetupValidationError() => error.message,
      _ => 'Unable to update project setup. Please try again.',
    };
  }

  String _engineStatusText(EngineConnectionStatus status) {
    return switch (status) {
      EngineConnectionStatus.stopped => 'stopped',
      EngineConnectionStatus.starting => 'starting',
      EngineConnectionStatus.ready => 'ready',
      EngineConnectionStatus.unavailable => 'unavailable',
      EngineConnectionStatus.crashed => 'crashed',
    };
  }
}

class _EmptyProjectWorkspace extends StatelessWidget {
  const _EmptyProjectWorkspace({
    required this.isSelecting,
    required this.onOpenVideo,
  });

  final bool isSelecting;
  final VoidCallback? onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Icon(
                      Icons.video_file_outlined,
                      size: 40,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  localizations.emptyWorkspaceTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  localizations.emptyWorkspaceDescription,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: onOpenVideo,
                  icon: isSelecting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_outlined),
                  label: Text(
                    isSelecting
                        ? localizations.selectingVideoEmptyState
                        : localizations.openVideoEmptyState,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
