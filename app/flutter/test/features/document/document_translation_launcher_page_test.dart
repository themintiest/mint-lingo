import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/theme/app_theme.dart';
import 'package:video_translator/features/document/document_reader_cubit.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/document/document_source_picker.dart';
import 'package:video_translator/features/document/document_translation_launcher_page.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('selects then replaces a document without rendering a reader', (
    tester,
  ) async {
    final cubit = DocumentReaderCubit(
      sourcePicker: _FakeDocumentSourcePicker([
        const DocumentSourceReference(
          path: '/documents/first.txt',
          fileName: 'first.txt',
          format: DocumentReaderFormat.plainText,
        ),
        const DocumentSourceReference(
          path: '/documents/second.epub',
          fileName: 'second.epub',
          format: DocumentReaderFormat.epub,
        ),
      ]),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: DocumentTranslationLauncherPage(
            localeOverride: null,
            onLocaleSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Select document'), findsOneWidget);
    await tester.tap(find.byKey(const Key('select-document-source')));
    await tester.pumpAndSettle();

    expect(find.text('Selected document: first.txt'), findsOneWidget);
    expect(find.text('Replace document'), findsOneWidget);
    expect(find.byType(SelectionArea), findsNothing);

    await tester.tap(find.byKey(const Key('select-document-source')));
    await tester.pumpAndSettle();
    expect(find.text('Selected document: second.epub'), findsOneWidget);
    expect(find.text('first.txt'), findsNothing);
  });
}

final class _FakeDocumentSourcePicker implements DocumentSourcePicker {
  _FakeDocumentSourcePicker(this._sources);

  final List<DocumentSourceReference?> _sources;

  @override
  Future<DocumentSourceReference?> pickDocumentSource() async =>
      _sources.removeAt(0);
}
