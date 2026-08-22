import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/app_workflow.dart';
import 'package:video_translator/app/theme/app_theme.dart';
import 'package:video_translator/app/workflow_selection_page.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('shows exactly the English product workflow choices', (
    tester,
  ) async {
    await tester.pumpWidget(_selectionApp());

    expect(find.text('What would you like to translate?'), findsOneWidget);
    expect(find.text('Video Translation'), findsOneWidget);
    expect(find.text('Document Translation'), findsOneWidget);
    expect(find.byKey(const Key('workflow-video-translation')), findsOneWidget);
    expect(
      find.byKey(const Key('workflow-document-translation')),
      findsOneWidget,
    );

    for (final formatSpecificChoice in const [
      'EPUB',
      'TXT',
      'PDF',
      'Audio Translation',
      'Comic',
      'Game Localization',
    ]) {
      expect(find.text(formatSpecificChoice), findsNothing);
    }
  });

  testWidgets('localizes the workflow screen in Vietnamese', (tester) async {
    await tester.pumpWidget(_selectionApp(locale: const Locale('vi')));

    expect(find.text('Bạn muốn dịch nội dung gì?'), findsOneWidget);
    expect(find.text('Dịch video'), findsOneWidget);
    expect(find.text('Dịch tài liệu'), findsOneWidget);
  });

  testWidgets('reports the selected application workflow identity', (
    tester,
  ) async {
    AppWorkflow? selected;
    await tester.pumpWidget(
      _selectionApp(onWorkflowSelected: (workflow) => selected = workflow),
    );

    await tester.tap(find.byKey(const Key('workflow-video-translation')));
    expect(selected, AppWorkflow.videoTranslation);

    await tester.tap(find.byKey(const Key('workflow-document-translation')));
    expect(selected, AppWorkflow.documentTranslation);
  });

  testWidgets('supports keyboard activation and exposes button semantics', (
    tester,
  ) async {
    AppWorkflow? selected;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _selectionApp(onWorkflowSelected: (workflow) => selected = workflow),
    );

    final videoButton = find.descendant(
      of: find.byKey(const Key('workflow-video-translation')),
      matching: find.byType(FilledButton),
    );
    expect(
      tester.getSemantics(videoButton),
      matchesSemantics(
        label: 'Video Translation',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, AppWorkflow.videoTranslation);
    semantics.dispose();
  });

  testWidgets('stacks the workflow choices in a scrollable narrow layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 500));
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() async {
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_selectionApp());

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final videoChoice = tester.getRect(
      find.byKey(const Key('workflow-video-translation')),
    );
    final documentChoice = tester.getRect(
      find.byKey(const Key('workflow-document-translation')),
    );
    expect(documentChoice.top, greaterThan(videoChoice.bottom));
    expect(tester.takeException(), isNull);
  });
}

Widget _selectionApp({
  Locale locale = const Locale('en'),
  ValueChanged<AppWorkflow>? onWorkflowSelected,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: WorkflowSelectionPage(
      onWorkflowSelected: onWorkflowSelected ?? (_) {},
    ),
  );
}
