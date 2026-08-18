import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/app.dart';
import 'package:video_translator/app/theme/app_colors.dart';
import 'package:video_translator/features/project/project_draft.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';
import 'package:video_translator/features/project/source_video_picker.dart';

void main() {
  testWidgets('shows the empty project workspace', (WidgetTester tester) async {
    await tester.pumpWidget(
      const VideoTranslatorApp(startEngineOnLaunch: false),
    );

    expect(find.text('Video Translator'), findsOneWidget);
    expect(find.text('No video is open'), findsOneWidget);
    expect(
      find.text('Open a video to begin a translation project.'),
      findsOneWidget,
    );

    final context = tester.element(find.text('No video is open'));
    expect(Theme.of(context).colorScheme.primary, AppColors.primary);
    expect(Theme.of(context).brightness, Brightness.light);
    expect(find.text('Engine: stopped'), findsOneWidget);
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

    await tester.tap(find.text('Open video'));
    await tester.pumpAndSettle();
    expect(find.text('first.mp4'), findsOneWidget);
    expect(find.text('Replace video'), findsOneWidget);

    await tester.tap(find.text('Replace video'));
    await tester.pumpAndSettle();
    expect(find.text('second.mp4'), findsOneWidget);
    expect(find.text('first.mp4'), findsNothing);
  });

  testWidgets('shows actionable setup messages before processing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const VideoTranslatorApp(startEngineOnLaunch: false),
    );

    await tester.tap(find.text('Check setup'));
    await tester.pump();

    expect(find.textContaining('Select a source video'), findsOneWidget);
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
    expect(find.text('Open video'), findsOneWidget);
    await tester.ensureVisible(find.text('Select target language'));
    expect(find.text('Source language'), findsOneWidget);
    expect(find.text('Target language'), findsOneWidget);
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

    await tester.tap(find.text('Open video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto-detect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    await _enterLanguage(tester, code: 'en', displayName: 'English');

    await tester.ensureVisible(find.text('Select target language'));
    await tester.tap(find.text('Select target language'));
    await tester.pumpAndSettle();
    await _enterLanguage(tester, code: 'vi', displayName: 'Vietnamese');

    await tester.ensureVisible(find.text('Check setup'));
    await tester.tap(find.text('Check setup'));
    await tester.pump();

    expect(find.text('Project setup is complete.'), findsOneWidget);
    expect(
      (cubit.state as ProjectSetupConfigured).draft.source?.fileName,
      'source.mp4',
    );
  });
}

final class _FakeSourceVideoPicker implements SourceVideoPicker {
  _FakeSourceVideoPicker(this._sources);

  final List<ProjectSourceReference> _sources;

  @override
  Future<ProjectSourceReference?> pickSourceVideo() async =>
      _sources.removeAt(0);
}

Future<void> _enterLanguage(
  WidgetTester tester, {
  required String code,
  required String displayName,
}) async {
  await tester.enterText(find.byKey(const Key('language-code-field')), code);
  await tester.enterText(
    find.byKey(const Key('language-display-name-field')),
    displayName,
  );
  await tester.tap(find.text('Use language'));
  await tester.pumpAndSettle();
}
