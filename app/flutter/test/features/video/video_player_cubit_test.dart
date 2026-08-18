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
}

final class _FakeVideoPlaybackControllerFactory
    implements VideoPlaybackControllerFactory {
  _FakeVideoPlaybackControllerFactory(this._controllers);

  final List<VideoPlaybackController> _controllers;

  @override
  VideoPlaybackController create() => _controllers.removeAt(0);
}

final class _FakeVideoPlaybackController implements VideoPlaybackController {
  _FakeVideoPlaybackController({this.openError});

  final Object? openError;
  final List<String> openedPaths = [];
  int disposeCount = 0;

  @override
  Future<void> dispose() async {
    disposeCount++;
  }

  @override
  Future<void> open(String sourcePath) async {
    openedPaths.add(sourcePath);
    if (openError != null) {
      throw openError!;
    }
  }
}
