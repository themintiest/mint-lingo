import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/engine/engine_connection_cubit.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/features/project/media_inspection_cubit.dart';
import 'package:video_translator/features/project/media_inspection_panel.dart';
import 'package:video_translator/features/project/project_draft.dart';
import 'package:video_translator/features/project/project_language_controls.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';
import 'package:video_translator/features/video/video_player_cubit.dart';
import 'package:video_translator/features/video/video_player_surface.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

class ProjectWorkspacePage extends StatelessWidget {
  const ProjectWorkspacePage({super.key});

  static const _maxContentWidth = 1280.0;
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
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                AppSpacing.xl,
                horizontalPadding,
                AppSpacing.xxl,
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

                        return _LoadedProjectWorkspace(
                          source: source,
                          isSelecting: isSelecting,
                          onReplaceVideo: isSelecting
                              ? null
                              : () => context
                                    .read<ProjectSetupCubit>()
                                    .selectSourceVideo(),
                          onCheckSetup: isSelecting
                              ? null
                              : () => _checkSetup(context),
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
}

class _LoadedProjectWorkspace extends StatelessWidget {
  const _LoadedProjectWorkspace({
    required this.source,
    required this.isSelecting,
    required this.onReplaceVideo,
    required this.onCheckSetup,
  });

  static const _wideBreakpoint = 960.0;
  static const _secondaryRegionWidth = 440.0;

  final ProjectSourceReference source;
  final bool isSelecting;
  final VoidCallback? onReplaceVideo;
  final VoidCallback? onCheckSetup;

  @override
  Widget build(BuildContext context) {
    final primary = const _LoadedVideoRegion();
    final secondary = _LoadedSetupRegion(
      source: source,
      isSelecting: isSelecting,
      onReplaceVideo: onReplaceVideo,
      onCheckSetup: onCheckSetup,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LoadedVideoHeader(source: source),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= _wideBreakpoint) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: primary),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(width: _secondaryRegionWidth, child: secondary),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                primary,
                const SizedBox(height: AppSpacing.lg),
                secondary,
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LoadedVideoHeader extends StatelessWidget {
  const _LoadedVideoHeader({required this.source});

  final ProjectSourceReference source;

  @override
  Widget build(BuildContext context) {
    return Column(
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
      ],
    );
  }
}

class _LoadedVideoRegion extends StatelessWidget {
  const _LoadedVideoRegion();

  @override
  Widget build(BuildContext context) => const Column(
    key: Key('loaded-workspace-primary'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [VideoPlayerSurface()],
  );
}

class _LoadedSetupRegion extends StatelessWidget {
  const _LoadedSetupRegion({
    required this.source,
    required this.isSelecting,
    required this.onReplaceVideo,
    required this.onCheckSetup,
  });

  final ProjectSourceReference source;
  final bool isSelecting;
  final VoidCallback? onReplaceVideo;
  final VoidCallback? onCheckSetup;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('loaded-workspace-secondary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    FilledButton.icon(
                      onPressed: onReplaceVideo,
                      icon: isSelecting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.folder_open_outlined),
                      label: Text(
                        isSelecting ? 'Selecting video...' : 'Replace video',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onCheckSetup,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Check setup'),
                    ),
                  ],
                ),
                const Divider(),
                const ProjectLanguageControls(),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        MediaInspectionPanel(source: source),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: BlocBuilder<EngineConnectionCubit, EngineConnectionState>(
            builder: (context, state) {
              return Text('Engine: ${_engineStatusText(state.status)}');
            },
          ),
        ),
      ],
    );
  }
}

String _engineStatusText(EngineConnectionStatus status) => switch (status) {
  EngineConnectionStatus.stopped => 'stopped',
  EngineConnectionStatus.starting => 'starting',
  EngineConnectionStatus.ready => 'ready',
  EngineConnectionStatus.unavailable => 'unavailable',
  EngineConnectionStatus.crashed => 'crashed',
};

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
