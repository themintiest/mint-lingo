import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/app.dart';
import 'package:video_translator/features/project/project_draft.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';

void main() {
  testWidgets(
    'opens the preserved Video workspace without resetting its draft',
    (tester) async {
      final projectSetupCubit = ProjectSetupCubit();
      addTearDown(projectSetupCubit.close);
      projectSetupCubit.configure(
        const ProjectDraft(
          source: ProjectSourceReference(
            path: '/videos/source.mp4',
            fileName: 'source.mp4',
          ),
        ),
      );

      await tester.pumpWidget(
        VideoTranslatorApp(
          startEngineOnLaunch: false,
          projectSetupCubit: projectSetupCubit,
        ),
      );

      expect(find.byKey(const Key('workflow-selection-page')), findsOneWidget);
      await tester.tap(find.byKey(const Key('workflow-video-translation')));
      await tester.pumpAndSettle();

      expect(find.text('source.mp4'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workflow-selection-page')), findsOneWidget);

      await tester.tap(find.byKey(const Key('workflow-video-translation')));
      await tester.pumpAndSettle();
      expect(find.text('source.mp4'), findsOneWidget);
    },
  );
}
