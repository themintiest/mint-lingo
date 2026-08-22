import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/theme/app_theme.dart';
import 'package:video_translator/features/document/document_reader_cubit.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/document/document_source_picker.dart';
import 'package:video_translator/features/document/document_translation_launcher_page.dart';
import 'package:video_translator/features/document/epub_presentation_loader.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('opens the workspace and replaces a document reader region', (
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
      epubPresentationLoader: const _FakeEpubPresentationLoader(),
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

    expect(find.byKey(const Key('document-workspace-source')), findsOneWidget);
    expect(find.text('first.txt'), findsOneWidget);
    expect(find.text('Replace document'), findsOneWidget);
    expect(find.byType(SelectionArea), findsNothing);
    expect(
      find.byKey(const Key('document-reader-region-plain-text')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('replace-document-source')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('document-reader-region-epub')),
      findsOneWidget,
    );
    expect(find.text('second.epub'), findsOneWidget);
    expect(find.text('first.txt'), findsNothing);
    expect(find.text('Chapter one'), findsOneWidget);

    await tester.tap(find.byKey(const Key('epub-reader-next-chapter')));
    await tester.pump();
    expect(find.text('Chapter two'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('epub-reader-table-of-contents-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('epub-reader-table-of-contents')),
      findsOneWidget,
    );
    await tester.tap(find.text('Chapter one'));
    await tester.pumpAndSettle();
    expect(find.text('Chapter one'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('document-translation-launcher')),
      findsOneWidget,
    );
    expect(find.text('Replace document'), findsOneWidget);
  });

  testWidgets('presents unsupported replacement feedback in the workspace', (
    tester,
  ) async {
    final cubit = DocumentReaderCubit(
      sourcePicker: _FakeDocumentSourcePicker([
        const DocumentSourceReference(
          path: '/documents/guide.pdf',
          fileName: 'guide.pdf',
          format: DocumentReaderFormat.pdf,
        ),
        const DocumentSourceReference(
          path: '/documents/legacy.doc',
          fileName: 'legacy.doc',
        ),
      ]),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_launcherApp(cubit));
    await tester.tap(find.byKey(const Key('select-document-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replace-document-source')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('document-workspace-unsupported')),
      findsOneWidget,
    );
    expect(
      find.text(
        'This file is not supported for document viewing. Choose an EPUB, TXT, or PDF.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps workspace chrome within a narrow desktop viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cubit = DocumentReaderCubit(
      sourcePicker: _FakeDocumentSourcePicker([
        const DocumentSourceReference(
          path: '/documents/notes.txt',
          fileName: 'notes.txt',
          format: DocumentReaderFormat.plainText,
        ),
      ]),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_launcherApp(cubit));
    await tester.tap(find.byKey(const Key('select-document-source')));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('document-workspace-source'))).width,
      lessThan(480),
    );
    expect(tester.takeException(), isNull);
  });
}

final class _FakeEpubPresentationLoader implements EpubPresentationLoader {
  const _FakeEpubPresentationLoader();

  @override
  Future<EpubPresentationContent> load(String localPath) async =>
      const EpubPresentationContent(
        chapters: [
          EpubPresentationChapter(
            title: 'Chapter one',
            packagePath: 'Text/chapter-one.xhtml',
            blocks: [],
          ),
          EpubPresentationChapter(
            title: 'Chapter two',
            packagePath: 'Text/chapter-two.xhtml',
            blocks: [],
          ),
        ],
        images: {},
      );
}

Widget _launcherApp(DocumentReaderCubit cubit) => BlocProvider.value(
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
);

final class _FakeDocumentSourcePicker implements DocumentSourcePicker {
  _FakeDocumentSourcePicker(this._sources);

  final List<DocumentSourceReference?> _sources;

  @override
  Future<DocumentSourceReference?> pickDocumentSource() async =>
      _sources.removeAt(0);
}
