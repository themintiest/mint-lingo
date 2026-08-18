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
}

final class _FakeSourceVideoPicker implements SourceVideoPicker {
  _FakeSourceVideoPicker(this._sources);

  final List<ProjectSourceReference> _sources;

  @override
  Future<ProjectSourceReference?> pickSourceVideo() async =>
      _sources.removeAt(0);
}
