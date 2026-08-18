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
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Icon(
                                Icons.video_file_outlined,
                                size: 64,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              source == null
                                  ? 'No video is open'
                                  : source.fileName,
                              style: Theme.of(context).textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              source == null
                                  ? 'Open a video to begin a translation project.'
                                  : 'This video is ready for project setup.',
                              style: Theme.of(context).textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
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
                                        : source == null
                                        ? 'Open video'
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
                            if (source != null)
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
