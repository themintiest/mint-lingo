import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/app.dart';
import 'package:video_translator/common/models/language.dart';
import 'package:video_translator/features/project/project_draft.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

void main() {
  test(
    'resolves English and Vietnamese system locales, then defaults to English',
    () {
      expect(
        resolveAppLocale(const [
          Locale('en', 'US'),
        ], AppLocalizations.supportedLocales),
        const Locale('en'),
      );
      expect(
        resolveAppLocale(const [
          Locale('vi', 'VN'),
        ], AppLocalizations.supportedLocales),
        const Locale('vi'),
      );
      expect(
        resolveAppLocale(const [
          Locale('ja', 'JP'),
        ], AppLocalizations.supportedLocales),
        const Locale('en'),
      );
    },
  );

  testWidgets(
    'uses the Vietnamese system locale without mutating project languages',
    (tester) async {
      final cubit = ProjectSetupCubit();
      addTearDown(cubit.close);
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      cubit.configure(
        ProjectDraft(
          sourceLanguage: SourceLanguageSelection.manual(Language(tag: 'en')),
          targetLanguage: Language(tag: 'ja'),
        ),
      );
      tester.binding.platformDispatcher.localesTestValue = const [
        Locale('vi', 'VN'),
      ];

      await tester.pumpWidget(
        VideoTranslatorApp(
          startEngineOnLaunch: false,
          projectSetupCubit: cubit,
        ),
      );

      final context = tester.element(find.byType(Scaffold));
      expect(Localizations.localeOf(context), const Locale('vi'));
      expect(AppLocalizations.of(context).languageVietnamese, 'Tiếng Việt');
      expect(find.text('Bắt đầu dự án dịch'), findsOneWidget);
      final draft = (cubit.state as ProjectSetupConfigured).draft;
      expect(
        draft.sourceLanguage,
        SourceLanguageSelection.manual(Language(tag: 'en')),
      );
      expect(draft.targetLanguage, Language(tag: 'ja'));
    },
  );

  testWidgets('uses English when the system locale is unsupported', (
    tester,
  ) async {
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.binding.platformDispatcher.localesTestValue = const [
      Locale('ja', 'JP'),
    ];

    await tester.pumpWidget(
      const VideoTranslatorApp(startEngineOnLaunch: false),
    );

    final context = tester.element(find.byType(Scaffold));
    expect(Localizations.localeOf(context), const Locale('en'));
    expect(AppLocalizations.of(context).languageVietnamese, 'Vietnamese');
  });

  testWidgets('uses English for an English system locale', (tester) async {
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.binding.platformDispatcher.localesTestValue = const [
      Locale('en', 'GB'),
    ];

    await tester.pumpWidget(
      const VideoTranslatorApp(startEngineOnLaunch: false),
    );

    final context = tester.element(find.byType(Scaffold));
    expect(Localizations.localeOf(context), const Locale('en'));
    expect(AppLocalizations.of(context).languageVietnamese, 'Vietnamese');
  });
}
