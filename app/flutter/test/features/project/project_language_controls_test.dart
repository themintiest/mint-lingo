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

  testWidgets('renders inline source and target language pickers', (
    tester,
  ) async {
    await _pumpApp(tester, cubit);

    expect(find.text('Source language'), findsOneWidget);
    expect(find.byKey(const Key('source-language-picker')), findsOneWidget);
    expect(find.text('Auto-detect'), findsNWidgets(2));
    expect(find.text('Automatic detection'), findsOneWidget);
    expect(find.text('Target language'), findsOneWidget);
    expect(find.byKey(const Key('target-language-picker')), findsOneWidget);
    expect(find.text('No target language selected'), findsOneWidget);
    expect(find.text('Select target language'), findsOneWidget);
  });

  testWidgets('shows Auto-detect first and searches catalog entries inline', (
    tester,
  ) async {
    await _pumpApp(tester, cubit);

    await _openPicker(tester, const Key('source-language-picker'));
    final autoDetect = find.text('Auto-detect').last;
    final english = find.text('English (en)').last;
    expect(
      tester.getTopLeft(autoDetect).dy,
      lessThan(tester.getTopLeft(english).dy),
    );

    await _dismissMenu(tester);
    await _openPicker(tester, const Key('target-language-picker'));
    await _enterSearch(
      tester,
      const Key('target-language-picker'),
      'portuguese',
    );
    expect(find.text('Portuguese (Brazil) (pt-BR)'), findsAtLeastNWidgets(1));
    expect(find.text('Portuguese (Portugal) (pt-PT)'), findsAtLeastNWidgets(1));

    await _enterSearch(tester, const Key('target-language-picker'), 'zh-hans');
    expect(
      find.text('Chinese (Simplified) (zh-Hans)'),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('selects canonical catalog values into project state', (
    tester,
  ) async {
    await _pumpApp(tester, cubit);

    await _selectLanguage(
      tester,
      pickerKey: const Key('source-language-picker'),
      search: 'English',
      label: 'English (en)',
    );

    expect(
      (cubit.state as ProjectSetupConfigured).draft.sourceLanguage,
      ExplicitSourceLanguage(Language(tag: 'en')),
    );

    await _selectLanguage(
      tester,
      pickerKey: const Key('target-language-picker'),
      search: 'zh-hans',
      label: 'Chinese (Simplified) (zh-Hans)',
    );

    final draft = (cubit.state as ProjectSetupConfigured).draft;
    expect(draft.sourceLanguage, ExplicitSourceLanguage(Language(tag: 'en')));
    expect(draft.targetLanguage, Language(tag: 'zh-Hans'));
  });

  testWidgets('keeps Auto-detect source-only and owned by project state', (
    tester,
  ) async {
    cubit.selectManualSourceLanguage(Language(tag: 'ko'));
    await _pumpApp(tester, cubit);

    cubit.selectAutomaticSourceLanguage();
    await tester.pump();

    expect(find.text('Automatic detection'), findsOneWidget);
    expect(
      (cubit.state as ProjectSetupConfigured).draft.sourceLanguage,
      const SourceLanguageSelection.autoDetect(),
    );

    final targetPicker = tester.widget<DropdownMenu<Language>>(
      find.byKey(const Key('target-language-picker')),
    );
    expect(
      targetPicker.dropdownMenuEntries.map((entry) => entry.label),
      isNot(contains('Auto-detect')),
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

Future<void> _openPicker(WidgetTester tester, Key pickerKey) async {
  await _dismissMenu(tester);
  await tester.ensureVisible(find.byKey(pickerKey));
  await tester.tap(find.byKey(pickerKey));
  await tester.pumpAndSettle();
}

Future<void> _dismissMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(1, 1));
  await tester.pumpAndSettle();
}

Future<void> _enterSearch(
  WidgetTester tester,
  Key pickerKey,
  String search,
) async {
  final field = find.descendant(
    of: find.byKey(pickerKey),
    matching: find.byType(TextField),
  );
  await tester.enterText(field, search);
  await tester.pump();
}

Future<void> _selectLanguage(
  WidgetTester tester, {
  required Key pickerKey,
  required String search,
  required String label,
}) async {
  await _openPicker(tester, pickerKey);
  await _enterSearch(tester, pickerKey, search);
  await tester.tap(find.text(label).hitTestable());
  await tester.pumpAndSettle();
}
