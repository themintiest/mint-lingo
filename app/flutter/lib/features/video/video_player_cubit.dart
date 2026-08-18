import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_translator/features/project/project_draft.dart';

abstract interface class VideoPlaybackController {
  Future<void> open(String sourcePath);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Stream<bool> get isPlaying;

  Stream<Duration> get position;

  Stream<Duration> get duration;

  Future<void> dispose();
}

abstract interface class VideoPlaybackControllerFactory {
  VideoPlaybackController create();
}

/// The direct media-kit controller for one selected local source.
final class MediaKitVideoPlaybackController implements VideoPlaybackController {
  MediaKitVideoPlaybackController() : _player = Player() {
    videoController = VideoController(_player);
  }

  final Player _player;
  late final VideoController videoController;

  @override
  Future<void> open(String sourcePath) =>
      _player.open(Media(sourcePath), play: false);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Stream<bool> get isPlaying => _player.stream.playing;

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<Duration> get duration => _player.stream.duration;

  @override
  Future<void> dispose() => _player.dispose();
}

final class MediaKitVideoPlaybackControllerFactory
    implements VideoPlaybackControllerFactory {
  const MediaKitVideoPlaybackControllerFactory();

  @override
  MediaKitVideoPlaybackController create() => MediaKitVideoPlaybackController();
}

sealed class VideoPlayerState {
  const VideoPlayerState();

  ProjectSourceReference? get source;
}

final class VideoPlayerIdle extends VideoPlayerState {
  const VideoPlayerIdle();

  @override
  ProjectSourceReference? get source => null;

  @override
  bool operator ==(Object other) => other is VideoPlayerIdle;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class VideoPlayerOpening extends VideoPlayerState {
  const VideoPlayerOpening(this.source);

  @override
  final ProjectSourceReference source;

  @override
  bool operator ==(Object other) =>
      other is VideoPlayerOpening && other.source == source;

  @override
  int get hashCode => Object.hash(runtimeType, source);
}

/// The small, independently-updated portion of an opened player's state.
final class VideoPlayerPlaybackState {
  const VideoPlayerPlaybackState({
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  final bool isPlaying;
  final Duration position;
  final Duration duration;

  VideoPlayerPlaybackState copyWith({
    bool? isPlaying,
    Duration? position,
    Duration? duration,
  }) {
    return VideoPlayerPlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VideoPlayerPlaybackState &&
      other.isPlaying == isPlaying &&
      other.position == position &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(isPlaying, position, duration);
}

final class VideoPlayerReady extends VideoPlayerState {
  const VideoPlayerReady(
    this.source, {
    this.playback = const VideoPlayerPlaybackState(),
  });

  @override
  final ProjectSourceReference source;
  final VideoPlayerPlaybackState playback;

  VideoPlayerReady copyWith({VideoPlayerPlaybackState? playback}) {
    return VideoPlayerReady(source, playback: playback ?? this.playback);
  }

  @override
  bool operator ==(Object other) =>
      other is VideoPlayerReady &&
      other.source == source &&
      other.playback == playback;

  @override
  int get hashCode => Object.hash(runtimeType, source, playback);
}

final class VideoPlayerFailure extends VideoPlayerState {
  const VideoPlayerFailure(this.source);

  @override
  final ProjectSourceReference source;

  @override
  bool operator ==(Object other) =>
      other is VideoPlayerFailure && other.source == source;

  @override
  int get hashCode => Object.hash(runtimeType, source);
}

/// Owns one native player controller and releases it on replacement or close.
final class VideoPlayerCubit extends Cubit<VideoPlayerState> {
  VideoPlayerCubit({VideoPlaybackControllerFactory? controllerFactory})
    : _controllerFactory =
          controllerFactory ?? const MediaKitVideoPlaybackControllerFactory(),
      super(const VideoPlayerIdle());

  final VideoPlaybackControllerFactory _controllerFactory;
  VideoPlaybackController? _controller;
  final List<StreamSubscription<Object>> _playbackSubscriptions = [];
  int _operation = 0;

  /// Available to VIDEO-04 after the player surface is introduced.
  VideoController? get videoController => switch (_controller) {
    MediaKitVideoPlaybackController controller => controller.videoController,
    _ => null,
  };

  Future<void> open(ProjectSourceReference source) async {
    final operation = ++_operation;
    final previousController = _controller;
    _controller = null;
    await _cancelPlaybackSubscriptions();
    if (previousController != null) {
      try {
        await previousController.dispose();
      } on Object {
        if (_isCurrent(operation)) {
          emit(VideoPlayerFailure(source));
        }
        return;
      }
    }
    if (!_isCurrent(operation)) {
      return;
    }

    emit(VideoPlayerOpening(source));
    VideoPlaybackController? controller;
    try {
      controller = _controllerFactory.create();
      _controller = controller;
      await controller.open(source.path);
      if (_isCurrent(operation)) {
        emit(VideoPlayerReady(source));
        _listenToPlaybackState(controller, operation);
      }
    } on Object {
      if (_isCurrent(operation)) {
        if (identical(_controller, controller)) {
          _controller = null;
        }
        if (controller != null) {
          await _disposeIgnoringErrors(controller);
        }
        if (_isCurrent(operation)) {
          emit(VideoPlayerFailure(source));
        }
      }
    }
  }

  Future<void> clear() async {
    final operation = ++_operation;
    final controller = _controller;
    _controller = null;
    await _cancelPlaybackSubscriptions();
    if (controller != null) {
      await _disposeIgnoringErrors(controller);
    }
    if (_isCurrent(operation)) {
      emit(const VideoPlayerIdle());
    }
  }

  /// Starts playback when an opened controller is still current.
  Future<void> play() => _runPlaybackCommand((controller) => controller.play());

  /// Pauses playback when an opened controller is still current.
  Future<void> pause() =>
      _runPlaybackCommand((controller) => controller.pause());

  /// Seeks the opened controller. Position state updates from its stream.
  Future<void> seek(Duration position) =>
      _runPlaybackCommand((controller) => controller.seek(position));

  @override
  Future<void> close() async {
    ++_operation;
    final controller = _controller;
    _controller = null;
    await _cancelPlaybackSubscriptions();
    if (controller != null) {
      await _disposeIgnoringErrors(controller);
    }
    return super.close();
  }

  bool _isCurrent(int operation) => !isClosed && _operation == operation;

  void _listenToPlaybackState(
    VideoPlaybackController controller,
    int operation,
  ) {
    _playbackSubscriptions.addAll([
      controller.isPlaying.listen(
        (isPlaying) => _updatePlaybackState(
          controller,
          operation,
          (playback) => playback.copyWith(isPlaying: isPlaying),
        ),
        onError: _ignorePlaybackStreamError,
      ),
      controller.position.listen(
        (position) => _updatePlaybackState(
          controller,
          operation,
          (playback) => playback.copyWith(position: position),
        ),
        onError: _ignorePlaybackStreamError,
      ),
      controller.duration.listen(
        (duration) => _updatePlaybackState(
          controller,
          operation,
          (playback) => playback.copyWith(duration: duration),
        ),
        onError: _ignorePlaybackStreamError,
      ),
    ]);
  }

  Future<void> _runPlaybackCommand(
    Future<void> Function(VideoPlaybackController controller) command,
  ) async {
    final controller = _controller;
    if (controller == null || state is! VideoPlayerReady) {
      return;
    }

    final operation = _operation;
    try {
      await command(controller);
    } on Object {
      // Media-kit stream updates remain the source of truth for player state.
      // A stale or disposed controller must not affect a replacement source.
      if (!_isCurrent(operation) || !identical(_controller, controller)) {
        return;
      }
    }
  }

  void _updatePlaybackState(
    VideoPlaybackController controller,
    int operation,
    VideoPlayerPlaybackState Function(VideoPlayerPlaybackState playback) update,
  ) {
    if (!_isCurrent(operation) || !identical(_controller, controller)) {
      return;
    }
    final currentState = state;
    if (currentState is! VideoPlayerReady) {
      return;
    }
    final playback = update(currentState.playback);
    if (playback != currentState.playback) {
      emit(currentState.copyWith(playback: playback));
    }
  }

  Future<void> _cancelPlaybackSubscriptions() async {
    final subscriptions = List<StreamSubscription<Object>>.from(
      _playbackSubscriptions,
    );
    _playbackSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  void _ignorePlaybackStreamError(Object _) {
    // Player stream failures must not escape through the widget tree. Opening
    // failures are handled separately by the controller lifecycle state.
  }

  Future<void> _disposeIgnoringErrors(
    VideoPlaybackController controller,
  ) async {
    try {
      await controller.dispose();
    } on Object {
      // A disposal failure must not retain a controller or block replacement.
    }
  }
}
