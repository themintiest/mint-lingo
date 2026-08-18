import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_translator/app/theme/app_radius.dart';
import 'package:video_translator/features/video/video_player_cubit.dart';

/// Renders the one active media-kit video output without adding controls.
///
/// Playback interaction remains at the Cubit boundary until a dedicated
/// controls task consumes its play, pause, and seek commands.
class VideoPlayerSurface extends StatelessWidget {
  const VideoPlayerSurface({super.key});

  static const surfaceKey = Key('video-player-surface');
  static const _aspectRatio = 16 / 9;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VideoPlayerCubit, VideoPlayerState>(
      buildWhen: (previous, current) =>
          previous is! VideoPlayerReady || current is! VideoPlayerReady,
      builder: (context, state) {
        return switch (state) {
          VideoPlayerIdle() => const SizedBox.shrink(),
          VideoPlayerOpening() => _PlayerViewport(
            child: const _PlayerStatus(
              icon: Icons.hourglass_top_outlined,
              message: 'Opening video preview...',
              showProgress: true,
            ),
          ),
          VideoPlayerFailure() => _PlayerViewport(
            child: const _PlayerStatus(
              icon: Icons.error_outline,
              message: 'Video preview is unavailable.',
            ),
          ),
          VideoPlayerReady() => _readySurface(context),
        };
      },
    );
  }

  Widget _readySurface(BuildContext context) {
    final controller = context.read<VideoPlayerCubit>().videoController;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller == null)
          _PlayerViewport(
            child: const _PlayerStatus(
              icon: Icons.hourglass_top_outlined,
              message: 'Preparing video preview...',
              showProgress: true,
            ),
          )
        else
          _PlayerViewport(
            child: Video(
              controller: controller,
              controls: NoVideoControls,
              fit: BoxFit.contain,
            ),
          ),
        const SizedBox(height: 8),
        const _VideoPlaybackControls(),
      ],
    );
  }
}

class _VideoPlaybackControls extends StatelessWidget {
  const _VideoPlaybackControls();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      VideoPlayerCubit,
      VideoPlayerState,
      VideoPlayerPlaybackState?
    >(
      selector: (state) => switch (state) {
        VideoPlayerReady() => state.playback,
        _ => null,
      },
      builder: (context, playback) {
        if (playback == null) {
          return const SizedBox.shrink();
        }
        return _ControlsContent(playback: playback);
      },
    );
  }
}

class _ControlsContent extends StatelessWidget {
  const _ControlsContent({required this.playback});

  final VideoPlayerPlaybackState playback;

  @override
  Widget build(BuildContext context) {
    final durationMilliseconds = playback.duration.inMilliseconds;
    final canSeek = durationMilliseconds > 0;
    final positionMilliseconds = playback.position.inMilliseconds
        .clamp(0, durationMilliseconds)
        .toDouble();
    final durationText = _formatDuration(playback.duration);
    final positionText = _formatDuration(playback.position);
    final cubit = context.read<VideoPlayerCubit>();

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: playback.isPlaying ? 'Pause video' : 'Play video',
              onPressed: () {
                if (playback.isPlaying) {
                  unawaited(cubit.pause());
                } else {
                  unawaited(cubit.play());
                }
              },
              icon: Icon(playback.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            Expanded(
              child: Slider(
                value: positionMilliseconds,
                max: canSeek ? durationMilliseconds.toDouble() : 1,
                onChanged: canSeek ? (_) {} : null,
                onChangeEnd: canSeek
                    ? (value) => unawaited(
                        cubit.seek(Duration(milliseconds: value.round())),
                      )
                    : null,
              ),
            ),
            Text('$positionText / $durationText'),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    final minutesText = minutes.toString().padLeft(2, '0');
    final secondsText = seconds.toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:$minutesText:$secondsText'
        : '$minutesText:$secondsText';
  }
}

class _PlayerViewport extends StatelessWidget {
  const _PlayerViewport({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      key: VideoPlayerSurface.surfaceKey,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AspectRatio(
        aspectRatio: VideoPlayerSurface._aspectRatio,
        child: ColoredBox(color: Colors.black, child: child),
      ),
    );
  }
}

class _PlayerStatus extends StatelessWidget {
  const _PlayerStatus({
    required this.icon,
    required this.message,
    this.showProgress = false,
  });

  final IconData icon;
  final String message;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Colors.white),
          ),
          if (showProgress) ...[
            const SizedBox(height: 12),
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
