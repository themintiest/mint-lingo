import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_translator/features/project/project_draft.dart';

abstract interface class VideoPlaybackController {
  Future<void> open(String sourcePath);

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

final class VideoPlayerReady extends VideoPlayerState {
  const VideoPlayerReady(this.source);

  @override
  final ProjectSourceReference source;

  @override
  bool operator ==(Object other) =>
      other is VideoPlayerReady && other.source == source;

  @override
  int get hashCode => Object.hash(runtimeType, source);
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
    if (controller != null) {
      await _disposeIgnoringErrors(controller);
    }
    if (_isCurrent(operation)) {
      emit(const VideoPlayerIdle());
    }
  }

  @override
  Future<void> close() async {
    ++_operation;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      await _disposeIgnoringErrors(controller);
    }
    return super.close();
  }

  bool _isCurrent(int operation) => !isClosed && _operation == operation;

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
