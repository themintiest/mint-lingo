import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/features/project/project_draft.dart';
import 'package:video_translator/features/video/video_player_cubit.dart';

void main() {
  const firstSource = ProjectSourceReference(
    path: '/videos/first.mp4',
    fileName: 'first.mp4',
  );
  const secondSource = ProjectSourceReference(
    path: '/videos/second.mp4',
    fileName: 'second.mp4',
  );

  test('opens one selected source paused and reports readiness', () async {
    final controller = _FakeVideoPlaybackController();
    final cubit = VideoPlayerCubit(
      controllerFactory: _FakeVideoPlaybackControllerFactory([controller]),
    );
    addTearDown(cubit.close);

    await cubit.open(firstSource);

    expect(controller.openedPaths, [firstSource.path]);
    expect(cubit.state, const VideoPlayerReady(firstSource));
  });

  test(
    'forwards play, pause, and seek commands to the opened controller',
    () async {
      final controller = _FakeVideoPlaybackController();
      final cubit = VideoPlayerCubit(
        controllerFactory: _FakeVideoPlaybackControllerFactory([controller]),
      );
      addTearDown(cubit.close);

      await cubit.open(firstSource);
      await cubit.play();
      await cubit.pause();
      await cubit.seek(const Duration(seconds: 42));

      expect(controller.playCount, 1);
      expect(controller.pauseCount, 1);
      expect(controller.seekPositions, [const Duration(seconds: 42)]);
    },
  );

  test('skips within the known playback range', () async {
    final controller = _FakeVideoPlaybackController();
    final cubit = VideoPlayerCubit(
      controllerFactory: _FakeVideoPlaybackControllerFactory([controller]),
    );
    addTearDown(cubit.close);

    await cubit.open(firstSource);
    controller.durationEvents.add(const Duration(minutes: 1));
    controller.positionEvents.add(const Duration(seconds: 5));

    await cubit.skipBackward();
    await cubit.skipForward();

    expect(controller.seekPositions, [
      Duration.zero,
      const Duration(seconds: 15),
    ]);
  });

  test('toggles mute through the opened controller volume', () async {
    final controller = _FakeVideoPlaybackController();
    final cubit = VideoPlayerCubit(
      controllerFactory: _FakeVideoPlaybackControllerFactory([controller]),
    );
    addTearDown(cubit.close);

    await cubit.open(firstSource);
    await cubit.toggleMuted();

    expect(controller.volumeValues, [0]);
    expect(
      cubit.state,
      const VideoPlayerReady(
        firstSource,
        playback: VideoPlayerPlaybackState(isMuted: true),
      ),
    );

    await cubit.toggleMuted();

    expect(controller.volumeValues, [0, 100]);
    expect(cubit.state, const VideoPlayerReady(firstSource));
  });

  test('toggles fullscreen through the registered viewport', () async {
    final controller = _FakeVideoPlaybackController();
    final cubit = VideoPlayerCubit(
      controllerFactory: _FakeVideoPlaybackControllerFactory([controller]),
      initialFullscreenToggler: () async => true,
    );
    addTearDown(cubit.close);

    await cubit.open(firstSource);
    await cubit.toggleFullscreen();

    expect(
      cubit.state,
      const VideoPlayerReady(
        firstSource,
        playback: VideoPlayerPlaybackState(isFullscreen: true),
      ),
    );
  });

  test(
    'keeps fullscreen state unchanged when the viewport declines the change',
    () async {
      final controller = _FakeVideoPlaybackController();
      final cubit = VideoPlayerCubit(
        controllerFactory: _FakeVideoPlaybackControllerFactory([controller]),
        initialFullscreenToggler: () async => false,
      );
      addTearDown(cubit.close);

      await cubit.open(firstSource);
      await cubit.toggleFullscreen();

      expect(cubit.state, const VideoPlayerReady(firstSource));
    },
  );

  test(
    'updates only the playback portion of ready state from controller streams',
    () async {
      final controller = _FakeVideoPlaybackController();
      final cubit = VideoPlayerCubit(
        controllerFactory: _FakeVideoPlaybackControllerFactory([controller]),
      );
      addTearDown(cubit.close);

      await cubit.open(firstSource);
      controller.durationEvents.add(const Duration(minutes: 2));
      controller.positionEvents.add(const Duration(seconds: 7));
      controller.playingEvents.add(true);

      expect(
        cubit.state,
        const VideoPlayerReady(
          firstSource,
          playback: VideoPlayerPlaybackState(
            isPlaying: true,
            position: Duration(seconds: 7),
            duration: Duration(minutes: 2),
          ),
        ),
      );
    },
  );

  test('disposes the old controller before replacing a source', () async {
    final firstController = _FakeVideoPlaybackController();
    final secondController = _FakeVideoPlaybackController();
    final cubit = VideoPlayerCubit(
      controllerFactory: _FakeVideoPlaybackControllerFactory([
        firstController,
        secondController,
      ]),
    );
    addTearDown(cubit.close);

    await cubit.open(firstSource);
    await cubit.open(secondSource);

    expect(firstController.disposeCount, 1);
    expect(secondController.openedPaths, [secondSource.path]);
    expect(cubit.state, const VideoPlayerReady(secondSource));
  });

  test(
    'disposes a controller and reports failure when opening fails',
    () async {
      final controller = _FakeVideoPlaybackController(
        openError: StateError('Unable to open source.'),
      );
      final cubit = VideoPlayerCubit(
        controllerFactory: _FakeVideoPlaybackControllerFactory([controller]),
      );
      addTearDown(cubit.close);

      await cubit.open(firstSource);

      expect(controller.disposeCount, 1);
      expect(cubit.state, const VideoPlayerFailure(firstSource));
    },
  );

  test('releases the active controller when closed', () async {
    final controller = _FakeVideoPlaybackController();
    final cubit = VideoPlayerCubit(
      controllerFactory: _FakeVideoPlaybackControllerFactory([controller]),
    );

    await cubit.open(firstSource);
    await cubit.close();

    expect(controller.disposeCount, 1);
  });

  test('clears the active controller and returns to the idle state', () async {
    final controller = _FakeVideoPlaybackController();
    final cubit = VideoPlayerCubit(
      controllerFactory: _FakeVideoPlaybackControllerFactory([controller]),
    );
    addTearDown(cubit.close);

    await cubit.open(firstSource);
    await cubit.clear();

    expect(controller.disposeCount, 1);
    expect(controller.cancelledSubscriptionCount, 4);
    expect(cubit.state, const VideoPlayerIdle());
  });

  test(
    'cancels old playback streams so they cannot update a replacement',
    () async {
      final firstController = _FakeVideoPlaybackController();
      final secondController = _FakeVideoPlaybackController();
      final cubit = VideoPlayerCubit(
        controllerFactory: _FakeVideoPlaybackControllerFactory([
          firstController,
          secondController,
        ]),
      );
      addTearDown(cubit.close);

      await cubit.open(firstSource);
      firstController.positionEvents.add(const Duration(seconds: 5));
      await cubit.open(secondSource);
      firstController.positionEvents.add(const Duration(seconds: 30));

      expect(firstController.cancelledSubscriptionCount, 4);
      expect(cubit.state, const VideoPlayerReady(secondSource));
    },
  );

  test(
    'ignores a delayed open completion after its source is replaced',
    () async {
      final firstOpenCompleter = Completer<void>();
      final firstController = _FakeVideoPlaybackController(
        openFuture: firstOpenCompleter.future,
      );
      final secondController = _FakeVideoPlaybackController();
      final cubit = VideoPlayerCubit(
        controllerFactory: _FakeVideoPlaybackControllerFactory([
          firstController,
          secondController,
        ]),
      );
      addTearDown(cubit.close);

      final firstOpen = cubit.open(firstSource);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, const VideoPlayerOpening(firstSource));

      await cubit.open(secondSource);
      firstOpenCompleter.complete();
      await firstOpen;

      expect(firstController.startedSubscriptionCount, 0);
      expect(cubit.state, const VideoPlayerReady(secondSource));
    },
  );
}

final class _FakeVideoPlaybackControllerFactory
    implements VideoPlaybackControllerFactory {
  _FakeVideoPlaybackControllerFactory(this._controllers);

  final List<VideoPlaybackController> _controllers;

  @override
  VideoPlaybackController create() => _controllers.removeAt(0);
}

final class _FakeVideoPlaybackController implements VideoPlaybackController {
  _FakeVideoPlaybackController({this.openError, this.openFuture}) {
    playingEvents = StreamController<bool>.broadcast(
      sync: true,
      onListen: _recordStartedSubscription,
      onCancel: _recordCancelledSubscription,
    );
    positionEvents = StreamController<Duration>.broadcast(
      sync: true,
      onListen: _recordStartedSubscription,
      onCancel: _recordCancelledSubscription,
    );
    durationEvents = StreamController<Duration>.broadcast(
      sync: true,
      onListen: _recordStartedSubscription,
      onCancel: _recordCancelledSubscription,
    );
    volumeEvents = StreamController<double>.broadcast(
      sync: true,
      onListen: _recordStartedSubscription,
      onCancel: _recordCancelledSubscription,
    );
  }

  final Object? openError;
  final Future<void>? openFuture;
  final List<String> openedPaths = [];
  final List<Duration> seekPositions = [];
  final List<double> volumeValues = [];
  int disposeCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  int cancelledSubscriptionCount = 0;
  int startedSubscriptionCount = 0;
  late final StreamController<bool> playingEvents;
  late final StreamController<Duration> positionEvents;
  late final StreamController<Duration> durationEvents;
  late final StreamController<double> volumeEvents;

  @override
  Stream<bool> get isPlaying => playingEvents.stream;

  @override
  Stream<double> get volume => volumeEvents.stream;

  @override
  Stream<Duration> get position => positionEvents.stream;

  @override
  Stream<Duration> get duration => durationEvents.stream;

  @override
  Future<void> dispose() async {
    disposeCount++;
  }

  @override
  Future<void> open(String sourcePath) async {
    openedPaths.add(sourcePath);
    await openFuture;
    if (openError != null) {
      throw openError!;
    }
  }

  @override
  Future<void> pause() async {
    pauseCount++;
  }

  @override
  Future<void> play() async {
    playCount++;
  }

  @override
  Future<void> seek(Duration position) async {
    seekPositions.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    volumeValues.add(volume);
    volumeEvents.add(volume);
  }

  void _recordCancelledSubscription() {
    cancelledSubscriptionCount++;
  }

  void _recordStartedSubscription() {
    startedSubscriptionCount++;
  }
}
