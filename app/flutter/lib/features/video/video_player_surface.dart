import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_translator/app/theme/app_radius.dart';
import 'package:video_translator/features/video/video_player_cubit.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

/// Renders the one active media-kit video output and Cubit-owned controls.
class VideoPlayerSurface extends StatefulWidget {
  const VideoPlayerSurface({super.key});

  static const surfaceKey = Key('video-player-surface');
  static const _aspectRatio = 16 / 9;

  @override
  State<VideoPlayerSurface> createState() => _VideoPlayerSurfaceState();
}

class _VideoPlayerSurfaceState extends State<VideoPlayerSurface> {
  final _videoKey = GlobalKey<VideoState>();
  late final VideoPlayerCubit _videoPlayerCubit;

  @override
  void initState() {
    super.initState();
    _videoPlayerCubit = context.read<VideoPlayerCubit>();
    _videoPlayerCubit.setFullscreenToggler(_toggleFullscreen);
  }

  @override
  void dispose() {
    _videoPlayerCubit.setFullscreenToggler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: BlocBuilder<VideoPlayerCubit, VideoPlayerState>(
        buildWhen: (previous, current) =>
            previous is! VideoPlayerReady || current is! VideoPlayerReady,
        builder: (context, state) {
          return switch (state) {
            VideoPlayerIdle() => const SizedBox.shrink(),
            VideoPlayerOpening() => _PlayerViewport(
              child: _PlayerStatus(
                icon: Icons.hourglass_top_outlined,
                message: localizations.openingVideoPreview,
                showProgress: true,
              ),
            ),
            VideoPlayerFailure() => _PlayerViewport(
              child: _PlayerStatus(
                icon: Icons.error_outline,
                message: localizations.videoPreviewUnavailable,
              ),
            ),
            VideoPlayerReady() => _readySurface(context),
          };
        },
      ),
    );
  }

  Widget _readySurface(BuildContext context) {
    final controller = context.read<VideoPlayerCubit>().videoController;
    if (controller == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PlayerViewport(
            child: _PlayerStatus(
              icon: Icons.hourglass_top_outlined,
              message: AppLocalizations.of(context).preparingVideoPreview,
              showProgress: true,
            ),
          ),
          const SizedBox(height: 8),
          const _VideoPlaybackControls(),
        ],
      );
    }

    return _PlayerViewport(
      child: Video(
        key: _videoKey,
        controller: controller,
        controls: (_) => const _MouseActivatedVideoControls(),
        fit: BoxFit.contain,
      ),
    );
  }

  Future<bool> _toggleFullscreen() async {
    final videoState = _videoKey.currentState;
    if (videoState == null) {
      return false;
    }
    await videoState.toggleFullscreen();
    return true;
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final currentState = _videoPlayerCubit.state;
    final playback = switch (currentState) {
      VideoPlayerReady() => currentState.playback,
      _ => null,
    };
    final shouldToggle =
        event.logicalKey == LogicalKeyboardKey.f11 ||
        (event.logicalKey == LogicalKeyboardKey.escape &&
            playback?.isFullscreen == true);
    if (!shouldToggle) {
      return KeyEventResult.ignored;
    }

    unawaited(_videoPlayerCubit.toggleFullscreen());
    return KeyEventResult.handled;
  }
}

class _MouseActivatedVideoControls extends StatefulWidget {
  const _MouseActivatedVideoControls();

  @override
  State<_MouseActivatedVideoControls> createState() =>
      _MouseActivatedVideoControlsState();
}

class _MouseActivatedVideoControlsState
    extends State<_MouseActivatedVideoControls> {
  static const _hideDelay = Duration(seconds: 3);

  Timer? _hideTimer;
  bool _isVisible = false;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _show,
      onHover: _show,
      onExit: (_) => _scheduleHide(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: IgnorePointer(
                ignoring: !_isVisible,
                child: AnimatedOpacity(
                  opacity: _isVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: MouseRegion(
                    onEnter: _show,
                    onHover: _show,
                    onExit: (_) => _scheduleHide(),
                    child: const _VideoPlaybackControls(compact: true),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _show(PointerEvent _) {
    _hideTimer?.cancel();
    if (!_isVisible) {
      setState(() {
        _isVisible = true;
      });
    }
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) {
        setState(() {
          _isVisible = false;
        });
      }
    });
  }
}

class _VideoPlaybackControls extends StatelessWidget {
  const _VideoPlaybackControls({this.compact = false});

  final bool compact;

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
        return _ControlsContent(playback: playback, compact: compact);
      },
    );
  }
}

class _ControlsContent extends StatelessWidget {
  const _ControlsContent({required this.playback, required this.compact});

  final VideoPlayerPlaybackState playback;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final durationText = _formatDuration(playback.duration);
    final positionText = _formatDuration(playback.position);
    final cubit = context.read<VideoPlayerCubit>();
    final localizations = AppLocalizations.of(context);

    if (compact) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Material(
          color: const Color(0xD9101114),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _VideoSeekBar(
                  playback: playback,
                  onSeek: cubit.seek,
                  dark: true,
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: localizations.skipBackTenSeconds,
                      color: Colors.white,
                      onPressed: () => unawaited(cubit.skipBackward()),
                      icon: const Icon(Icons.replay_10),
                    ),
                    IconButton(
                      tooltip: playback.isPlaying
                          ? localizations.pauseVideo
                          : localizations.playVideo,
                      color: Colors.white,
                      onPressed: () {
                        if (playback.isPlaying) {
                          unawaited(cubit.pause());
                        } else {
                          unawaited(cubit.play());
                        }
                      },
                      icon: Icon(
                        playback.isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                    IconButton(
                      tooltip: localizations.skipForwardTenSeconds,
                      color: Colors.white,
                      onPressed: () => unawaited(cubit.skipForward()),
                      icon: const Icon(Icons.forward_10),
                    ),
                    const Spacer(),
                    Text(
                      '$positionText / $durationText',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: Colors.white),
                    ),
                    IconButton(
                      tooltip: playback.isFullscreen
                          ? localizations.exitFullscreen
                          : localizations.enterFullscreen,
                      color: Colors.white,
                      onPressed: () => unawaited(cubit.toggleFullscreen()),
                      icon: Icon(
                        playback.isFullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: localizations.skipBackTenSeconds,
              onPressed: () => unawaited(cubit.skipBackward()),
              icon: const Icon(Icons.replay_10),
            ),
            IconButton(
              tooltip: playback.isPlaying
                  ? localizations.pauseVideo
                  : localizations.playVideo,
              onPressed: () {
                if (playback.isPlaying) {
                  unawaited(cubit.pause());
                } else {
                  unawaited(cubit.play());
                }
              },
              icon: Icon(playback.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
              tooltip: localizations.skipForwardTenSeconds,
              onPressed: () => unawaited(cubit.skipForward()),
              icon: const Icon(Icons.forward_10),
            ),
            Expanded(
              child: _VideoSeekBar(playback: playback, onSeek: cubit.seek),
            ),
            Text('$positionText / $durationText'),
            IconButton(
              tooltip: playback.isFullscreen
                  ? localizations.exitFullscreen
                  : localizations.enterFullscreen,
              onPressed: () => unawaited(cubit.toggleFullscreen()),
              icon: Icon(
                playback.isFullscreen
                    ? Icons.fullscreen_exit
                    : Icons.fullscreen,
              ),
            ),
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

/// Provides immediate visual feedback while dragging and seeks on release.
class _VideoSeekBar extends StatefulWidget {
  const _VideoSeekBar({
    required this.playback,
    required this.onSeek,
    this.dark = false,
  });

  final VideoPlayerPlaybackState playback;
  final Future<void> Function(Duration position) onSeek;
  final bool dark;

  @override
  State<_VideoSeekBar> createState() => _VideoSeekBarState();
}

class _VideoSeekBarState extends State<_VideoSeekBar> {
  Duration? _scrubbedPosition;
  bool _isScrubbing = false;

  @override
  void didUpdateWidget(covariant _VideoSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isScrubbing &&
        oldWidget.playback.position != widget.playback.position) {
      _scrubbedPosition = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.playback.duration;
    final canSeek = duration > Duration.zero;
    final position = _scrubbedPosition ?? widget.playback.position;
    final value = position.inMilliseconds
        .clamp(0, duration.inMilliseconds)
        .toDouble();

    final slider = Slider(
      value: value,
      max: canSeek ? duration.inMilliseconds.toDouble() : 1,
      onChangeStart: canSeek
          ? (value) => setState(() {
              _isScrubbing = true;
              _scrubbedPosition = Duration(milliseconds: value.round());
            })
          : null,
      onChanged: canSeek
          ? (value) => setState(() {
              _scrubbedPosition = Duration(milliseconds: value.round());
            })
          : null,
      onChangeEnd: canSeek
          ? (value) {
              final position = Duration(milliseconds: value.round());
              setState(() {
                _isScrubbing = false;
                _scrubbedPosition = position;
              });
              unawaited(widget.onSeek(position));
            }
          : null,
    );

    if (!widget.dark) {
      return slider;
    }
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: Colors.white,
        inactiveTrackColor: Colors.white38,
        thumbColor: Colors.white,
        overlayColor: Colors.white24,
        trackHeight: 3,
      ),
      child: slider,
    );
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
