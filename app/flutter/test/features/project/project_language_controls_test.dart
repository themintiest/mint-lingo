import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/theme/app_theme.dart';
import 'package:video_translator/common/models/language.dart';
import 'package:video_translator/features/project/project_language_controls.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

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
    await _enterLanguage(tester, tag: 'en');

    expect(find.text('English (en)'), findsOneWidget);
    expect(
      (cubit.state as ProjectSetupConfigured).draft.sourceLanguage,
      ExplicitSourceLanguage(Language(tag: 'en')),
    );

    await tester.tap(find.text('Select target language'));
    await tester.pumpAndSettle();
    await _enterLanguage(tester, tag: 'vi');

    expect(find.text('Vietnamese (vi)'), findsOneWidget);
    expect(
      (cubit.state as ProjectSetupConfigured).draft.targetLanguage,
      Language(tag: 'vi'),
    );
  });

  testWidgets('returns a manual source language to automatic detection', (
    tester,
  ) async {
    cubit.selectManualSourceLanguage(Language(tag: 'ko'));
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
    BlocProvider.value(
      value: cubit,
      child: MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ProjectLanguageControls()),
      ),
    ),
  );
}

Future<void> _enterLanguage(WidgetTester tester, {required String tag}) async {
  await tester.enterText(find.byKey(const Key('language-tag-field')), tag);
  await tester.tap(find.text('Use language'));
  await tester.pumpAndSettle();
}
