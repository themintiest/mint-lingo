import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/engine/engine_connection_cubit.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';

class ProjectWorkspacePage extends StatelessWidget {
  const ProjectWorkspacePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Translator')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: BlocBuilder<ProjectSetupCubit, ProjectSetupState>(
            builder: (context, state) {
              final source = state.draft?.source;
              final isSelecting = state is ProjectSetupSelecting;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.video_file_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    source == null ? 'No video is open' : source.fileName,
                    style: Theme.of(context).textTheme.headlineSmall,
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
                  FilledButton.icon(
                    onPressed: isSelecting
                        ? null
                        : () => context
                              .read<ProjectSetupCubit>()
                              .selectSourceVideo(),
                    icon: isSelecting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
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
                  const SizedBox(height: AppSpacing.lg),
                  BlocBuilder<EngineConnectionCubit, EngineConnectionState>(
                    builder: (context, state) {
                      return Text('Engine: ${_engineStatusText(state.status)}');
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
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
