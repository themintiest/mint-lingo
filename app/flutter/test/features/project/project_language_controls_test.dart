import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/app.dart';
import 'package:video_translator/common/models/language.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';

void main() {
  late ProjectSetupCubit cubit;

  setUp(() {
    cubit = ProjectSetupCubit();
  });

  tearDown(() => cubit.close());

  testWidgets(
    'renders automatic source detection and an unset target language',
    (tester) async {
      await _pumpApp(tester, cubit);

      expect(find.text('Source language'), findsOneWidget);
      expect(find.text('Auto-detect'), findsOneWidget);
      expect(find.text('Automatic detection'), findsOneWidget);
      expect(find.text('Target language'), findsOneWidget);
      expect(find.text('No target language selected'), findsOneWidget);
      expect(find.text('Select target language'), findsOneWidget);
    },
  );

  testWidgets('selects manual source and explicit target languages', (
    tester,
  ) async {
    await _pumpApp(tester, cubit);

    await tester.tap(find.text('Auto-detect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    await _enterLanguage(tester, code: 'en', displayName: 'English');

    expect(find.text('English (en)'), findsOneWidget);
    expect(
      (cubit.state as ProjectSetupConfigured).draft.sourceLanguage,
      ExplicitSourceLanguage(Language(code: 'en', displayName: 'English')),
    );

    await tester.tap(find.text('Select target language'));
    await tester.pumpAndSettle();
    await _enterLanguage(tester, code: 'vi', displayName: 'Vietnamese');

    expect(find.text('Vietnamese (vi)'), findsOneWidget);
    expect(
      (cubit.state as ProjectSetupConfigured).draft.targetLanguage,
      Language(code: 'vi', displayName: 'Vietnamese'),
    );
  });

  testWidgets('returns a manual source language to automatic detection', (
    tester,
  ) async {
    cubit.selectManualSourceLanguage(
      Language(code: 'ko', displayName: 'Korean'),
    );
    await _pumpApp(tester, cubit);

    expect(find.text('Korean (ko)'), findsOneWidget);

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto-detect'));
    await tester.pumpAndSettle();

    expect(find.text('Automatic detection'), findsOneWidget);
    expect(
      (cubit.state as ProjectSetupConfigured).draft.sourceLanguage,
      const SourceLanguageSelection.autoDetect(),
    );
  });
}

Future<void> _pumpApp(WidgetTester tester, ProjectSetupCubit cubit) {
  return tester.pumpWidget(
    VideoTranslatorApp(startEngineOnLaunch: false, projectSetupCubit: cubit),
  );
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
