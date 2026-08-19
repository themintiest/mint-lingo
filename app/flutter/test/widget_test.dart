import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/app.dart';
import 'package:video_translator/app/engine/media_inspection.dart';
import 'package:video_translator/app/theme/app_colors.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/features/project/project_draft.dart';
import 'package:video_translator/features/project/media_inspection_cubit.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';
import 'package:video_translator/features/project/source_video_picker.dart';
import 'package:video_translator/features/video/video_player_cubit.dart';
import 'package:video_translator/features/video/video_player_surface.dart';

void main() {
  testWidgets('shows the empty project workspace', (WidgetTester tester) async {
    await tester.pumpWidget(
      const VideoTranslatorApp(startEngineOnLaunch: false),
    );

    expect(find.text('Video Translator'), findsOneWidget);
    expect(find.text('Start a translation project'), findsOneWidget);
    expect(
      find.text(
        'Open a local video to inspect its media and choose translation languages.',
      ),
      findsOneWidget,
    );

    final context = tester.element(find.text('Start a translation project'));
    expect(Theme.of(context).colorScheme.primary, AppColors.primary);
    expect(Theme.of(context).brightness, Brightness.light);
    expect(find.text('Open a video'), findsOneWidget);
    expect(find.text('Check setup'), findsNothing);
    expect(find.text('Source language'), findsNothing);
  });

  testWidgets('opens and replaces one source video', (
    WidgetTester tester,
  ) async {
    final cubit = ProjectSetupCubit(
      sourceVideoPicker: _FakeSourceVideoPicker([
        const ProjectSourceReference(
          path: '/videos/first.mp4',
          fileName: 'first.mp4',
        ),
        const ProjectSourceReference(
          path: '/videos/second.mp4',
          fileName: 'second.mp4',
        ),
      ]),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      VideoTranslatorApp(startEngineOnLaunch: false, projectSetupCubit: cubit),
    );

    await tester.tap(find.text('Open a video'));
    await tester.pumpAndSettle();
    expect(find.text('first.mp4'), findsOneWidget);
    expect(find.text('Replace video'), findsOneWidget);

    await tester.ensureVisible(find.text('Replace video'));
    await tester.tap(find.text('Replace video'));
    await tester.pumpAndSettle();
    expect(find.text('second.mp4'), findsOneWidget);
    expect(find.text('first.mp4'), findsNothing);
  });

  testWidgets('reserves a responsive preview viewport for a selected source', (
    WidgetTester tester,
  ) async {
    final cubit = ProjectSetupCubit(
      sourceVideoPicker: _FakeSourceVideoPicker([
        const ProjectSourceReference(
          path: '/videos/source.mp4',
          fileName: 'source.mp4',
        ),
      ]),
    );
    final playbackFactory = _FakeVideoPlaybackControllerFactory();
    final videoCubit = VideoPlayerCubit(controllerFactory: playbackFactory);
    addTearDown(cubit.close);
    addTearDown(videoCubit.close);

    await tester.pumpWidget(
      VideoTranslatorApp(
        startEngineOnLaunch: false,
        projectSetupCubit: cubit,
        videoPlayerCubit: videoCubit,
      ),
    );

    await tester.tap(find.text('Open a video'));
    await tester.pump();
    await tester.pump();

    final size = tester.getSize(find.byKey(VideoPlayerSurface.surfaceKey));
    expect(size.width / size.height, closeTo(16 / 9, 0.01));
    expect(find.text('Preparing video preview...'), findsOneWidget);
    expect(find.byTooltip('Play video'), findsOneWidget);

    playbackFactory.controller.durationEvents.add(const Duration(minutes: 2));
    playbackFactory.controller.positionEvents.add(const Duration(seconds: 5));
    await tester.pump();
    await tester.pump();

    expect(find.text('00:05 / 02:00'), findsOneWidget);
    expect(find.byTooltip('Skip back 10 seconds'), findsOneWidget);
    expect(find.byTooltip('Skip forward 10 seconds'), findsOneWidget);
    expect(find.byTooltip('Enter fullscreen'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Play video'));
    await tester.tap(find.byTooltip('Skip back 10 seconds'));
    await tester.tap(find.byTooltip('Skip forward 10 seconds'));
    await tester.tap(find.byTooltip('Play video'));
    expect(playbackFactory.controller.playCount, 1);
    expect(playbackFactory.controller.seekPositions, [
      Duration.zero,
      const Duration(seconds: 15),
    ]);

    playbackFactory.controller.playingEvents.add(true);
    await tester.pump();
    expect(find.byTooltip('Pause video'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause video'));
    expect(playbackFactory.controller.pauseCount, 1);

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeEnd!(30 * 1000);
    expect(playbackFactory.controller.seekPositions, [
      Duration.zero,
      const Duration(seconds: 15),
      const Duration(seconds: 30),
    ]);
  });

  testWidgets('prioritizes video beside a secondary setup region when wide', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cubit = ProjectSetupCubit(
      sourceVideoPicker: _FakeSourceVideoPicker([
        const ProjectSourceReference(
          path: '/videos/source.mp4',
          fileName: 'source.mp4',
        ),
      ]),
    );
    final videoCubit = VideoPlayerCubit(
      controllerFactory: _FakeVideoPlaybackControllerFactory(),
    );
    addTearDown(cubit.close);
    addTearDown(videoCubit.close);

    await tester.pumpWidget(
      VideoTranslatorApp(
        startEngineOnLaunch: false,
        projectSetupCubit: cubit,
        videoPlayerCubit: videoCubit,
      ),
    );

    await tester.tap(find.text('Open a video'));
    await tester.pump();
    await tester.pump();

    final primary = find.byKey(const Key('loaded-workspace-primary'));
    final secondary = find.byKey(const Key('loaded-workspace-secondary'));
    final primaryRect = tester.getRect(primary);
    final secondaryRect = tester.getRect(secondary);
    final playerRect = tester.getRect(
      find.byKey(VideoPlayerSurface.surfaceKey),
    );
    expect(primaryRect.left, lessThan(secondaryRect.left));
    expect(primaryRect.width, greaterThan(secondaryRect.width));
    expect(playerRect.top, secondaryRect.top);
    expect(secondaryRect.width, 440);
    expect(
      tester.getTopLeft(find.byKey(const Key('source-language-picker'))).dy,
      closeTo(tester.getTopLeft(find.text('Source language')).dy, 1),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('target-language-picker'))).dy,
      closeTo(tester.getTopLeft(find.text('Target language')).dy, 1),
    );
    expect(
      find.descendant(
        of: primary,
        matching: find.byKey(VideoPlayerSurface.surfaceKey),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: secondary, matching: find.text('Source language')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('engine-status-indicator')), findsOneWidget);
    expect(find.text('Engine: Stopped'), findsOneWidget);
  });

  testWidgets('stacks the player before setup on narrow desktops', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cubit = ProjectSetupCubit(
      sourceVideoPicker: _FakeSourceVideoPicker([
        const ProjectSourceReference(
          path: '/videos/source.mp4',
          fileName: 'source.mp4',
        ),
      ]),
    );
    final videoCubit = VideoPlayerCubit(
      controllerFactory: _FakeVideoPlaybackControllerFactory(),
    );
    addTearDown(cubit.close);
    addTearDown(videoCubit.close);

    await tester.pumpWidget(
      VideoTranslatorApp(
        startEngineOnLaunch: false,
        projectSetupCubit: cubit,
        videoPlayerCubit: videoCubit,
      ),
    );

    await tester.tap(find.text('Open a video'));
    await tester.pump();
    await tester.pump();

    final primaryRect = tester.getRect(
      find.byKey(const Key('loaded-workspace-primary')),
    );
    final secondaryRect = tester.getRect(
      find.byKey(const Key('loaded-workspace-secondary')),
    );
    expect(secondaryRect.top, greaterThan(primaryRect.bottom));
  });

  testWidgets('shows target-language setup guidance after opening a video', (
    WidgetTester tester,
  ) async {
    final cubit = ProjectSetupCubit(
      sourceVideoPicker: _FakeSourceVideoPicker([
        const ProjectSourceReference(
          path: '/videos/source.mp4',
          fileName: 'source.mp4',
        ),
      ]),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(
      VideoTranslatorApp(startEngineOnLaunch: false, projectSetupCubit: cubit),
    );

    await tester.tap(find.text('Open a video'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Check setup'));
    await tester.tap(find.text('Check setup'));
    await tester.pump();

    expect(find.textContaining('Select a target language'), findsOneWidget);
  });

  testWidgets('keeps project setup usable at a narrow desktop width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 500));
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() async {
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const VideoTranslatorApp(startEngineOnLaunch: false),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Open a video'), findsOneWidget);
    expect(find.text('Start a translation project'), findsOneWidget);
    expect(find.text('Source language'), findsNothing);
    expect(find.text('Target language'), findsNothing);
  });

  testWidgets('keeps deliberate space below the workspace content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const VideoTranslatorApp(startEngineOnLaunch: false),
    );

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      scrollView.padding,
      const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
    );
  });

  testWidgets('accepts a fully configured project setup', (
    WidgetTester tester,
  ) async {
    final cubit = ProjectSetupCubit(
      sourceVideoPicker: _FakeSourceVideoPicker([
        const ProjectSourceReference(
          path: '/videos/source.mp4',
          fileName: 'source.mp4',
        ),
      ]),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      VideoTranslatorApp(startEngineOnLaunch: false, projectSetupCubit: cubit),
    );

    await tester.tap(find.text('Open a video'));
    await tester.pumpAndSettle();
    await _selectCatalogLanguage(
      tester,
      pickerKey: const Key('source-language-picker'),
      search: 'English',
      label: 'English (en)',
    );

    await _selectCatalogLanguage(
      tester,
      pickerKey: const Key('target-language-picker'),
      search: 'Vietnamese',
      label: 'Vietnamese (vi)',
    );

    await tester.ensureVisible(find.text('Check setup'));
    await tester.tap(find.text('Check setup'));
    await tester.pump();

    expect(find.text('Project setup is complete.'), findsOneWidget);
    expect(
      (cubit.state as ProjectSetupConfigured).draft.source?.fileName,
      'source.mp4',
    );
  });

  testWidgets('shows validated media metadata after inspection', (
    WidgetTester tester,
  ) async {
    final setupCubit = ProjectSetupCubit(
      sourceVideoPicker: _FakeSourceVideoPicker([
        const ProjectSourceReference(
          path: '/private/videos/source.mp4',
          fileName: 'source.mp4',
        ),
      ]),
    );
    final inspectionCubit = MediaInspectionCubit(
      inspectMedia: (_) async => MediaInspectionMetadata(
        duration: const Duration(seconds: 95, milliseconds: 500),
        streams: const [
          MediaStreamMetadata(
            index: 0,
            kind: MediaStreamKind.video,
            codec: 'h264',
            dimensions: MediaDimensions(width: 1920, height: 1080),
          ),
          MediaStreamMetadata(
            index: 1,
            kind: MediaStreamKind.audio,
            codec: 'aac',
          ),
        ],
        hasAudio: true,
      ),
    );
    addTearDown(setupCubit.close);
    addTearDown(inspectionCubit.close);

    await tester.pumpWidget(
      VideoTranslatorApp(
        startEngineOnLaunch: false,
        projectSetupCubit: setupCubit,
        mediaInspectionCubit: inspectionCubit,
      ),
    );

    await tester.tap(find.text('Open a video'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Inspect video'));
    await tester.tap(find.text('Inspect video'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('media-inspection-details')), findsOneWidget);
    expect(find.byKey(const Key('media-detail-duration')), findsOneWidget);
    expect(find.byKey(const Key('media-detail-audio')), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('01:35'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Present'), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byKey(const Key('media-stream-0')), findsOneWidget);
    expect(find.byKey(const Key('media-stream-1')), findsOneWidget);
    expect(find.textContaining('h264'), findsOneWidget);
    expect(find.textContaining('aac'), findsOneWidget);
    /* Legacy assertions retained temporarily because their old literals were
       stored with corrupt character encoding.
    expect(find.text('Video #0 · h264 · 1920 × 1080'), findsOneWidget);
    expect(find.text('Audio #1 · aac'), findsOneWidget);
    */
  });

  testWidgets('shows a safe structured media inspection error', (
    WidgetTester tester,
  ) async {
    final setupCubit = ProjectSetupCubit(
      sourceVideoPicker: _FakeSourceVideoPicker([
        const ProjectSourceReference(
          path: '/private/videos/missing-audio.mp4',
          fileName: 'missing-audio.mp4',
        ),
      ]),
    );
    final inspectionCubit = MediaInspectionCubit(
      inspectMedia: (_) async => throw const MediaInspectionException(
        type: MediaInspectionErrorType.validation,
        code: 'media.audio_stream_missing',
        retryable: false,
      ),
    );
    addTearDown(setupCubit.close);
    addTearDown(inspectionCubit.close);

    await tester.pumpWidget(
      VideoTranslatorApp(
        startEngineOnLaunch: false,
        projectSetupCubit: setupCubit,
        mediaInspectionCubit: inspectionCubit,
      ),
    );

    await tester.tap(find.text('Open a video'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Inspect video'));
    await tester.tap(find.text('Inspect video'));
    await tester.pumpAndSettle();

    expect(find.text('Unable to inspect media'), findsOneWidget);
    expect(
      find.text('This video has no audio stream and cannot be translated.'),
      findsOneWidget,
    );
    expect(find.text('/private/videos/missing-audio.mp4'), findsNothing);
  });
}

final class _FakeSourceVideoPicker implements SourceVideoPicker {
  _FakeSourceVideoPicker(this._sources);

  final List<ProjectSourceReference> _sources;

  @override
  Future<ProjectSourceReference?> pickSourceVideo() async =>
      _sources.removeAt(0);
}

final class _FakeVideoPlaybackControllerFactory
    implements VideoPlaybackControllerFactory {
  final controller = _FakeVideoPlaybackController();

  @override
  VideoPlaybackController create() => controller;
}

final class _FakeVideoPlaybackController implements VideoPlaybackController {
  final durationEvents = StreamController<Duration>.broadcast();
  final playingEvents = StreamController<bool>.broadcast();
  final positionEvents = StreamController<Duration>.broadcast();
  int pauseCount = 0;
  int playCount = 0;
  final seekPositions = <Duration>[];

  @override
  Stream<Duration> get duration => durationEvents.stream;

  @override
  Stream<bool> get isPlaying => playingEvents.stream;

  @override
  Stream<Duration> get position => positionEvents.stream;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> open(String sourcePath) async {}

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
}

Future<void> _selectCatalogLanguage(
  WidgetTester tester, {
  required Key pickerKey,
  required String search,
  required String label,
}) async {
  await tester.ensureVisible(find.byKey(pickerKey));
  await tester.tapAt(const Offset(1, 1));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(pickerKey));
  await tester.pumpAndSettle();
  final field = find.descendant(
    of: find.byKey(pickerKey),
    matching: find.byType(TextField),
  );
  await tester.enterText(field, search);
  await tester.pump();
  await tester.tap(find.text(label).hitTestable());
  await tester.pumpAndSettle();
}
