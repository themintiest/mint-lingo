import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/app.dart';
import 'package:video_translator/features/document/document_presentation.dart';
import 'package:video_translator/features/document/document_reader_cubit.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/document/document_source_picker.dart';
import 'package:video_translator/features/document/epub_presentation_loader.dart';
import 'package:video_translator/features/project/project_draft.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

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

  testWidgets('opens the Document launcher with document selection only', (
    tester,
  ) async {
    await tester.pumpWidget(
      const VideoTranslatorApp(startEngineOnLaunch: false),
    );

    await tester.tap(find.byKey(const Key('workflow-document-translation')));
    await tester.pumpAndSettle();

    final launcher = find.byKey(const Key('document-translation-launcher'));
    final localizations = AppLocalizations.of(tester.element(launcher));
    expect(launcher, findsOneWidget);
    expect(
      find.text(localizations.documentLauncherDescription),
      findsOneWidget,
    );
    expect(find.byKey(const Key('select-document-source')), findsOneWidget);
    expect(find.text(localizations.selectDocument), findsOneWidget);
    expect(find.byType(SelectionArea), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workflow-selection-page')), findsOneWidget);
  });

  testWidgets(
    'returns a selected EPUB reader to workflow selection without retaining presentation state',
    (tester) async {
      DocumentReaderCubit? createdCubit;
      await tester.pumpWidget(
        VideoTranslatorApp(
          startEngineOnLaunch: false,
          documentReaderCubitFactory: () => createdCubit = DocumentReaderCubit(
            sourcePicker: _FakeDocumentSourcePicker(),
            epubPresentationLoader: const _FakeEpubPresentationLoader(),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('workflow-document-translation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select-document-source')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('document-reader-region-epub')),
        findsOneWidget,
      );
      expect(find.text('Chapter one'), findsOneWidget);
      await tester.tap(find.byKey(const Key('epub-reader-next-chapter')));
      await tester.pump();
      expect(find.text('Chapter two'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('document-translation-launcher')),
        findsOneWidget,
      );
      expect(
        createdCubit!.state,
        const DocumentReaderReady(
          source: DocumentSourceReference(
            path: '/documents/book.epub',
            fileName: 'book.epub',
            format: DocumentReaderFormat.epub,
          ),
          presentation: DocumentReaderUnavailablePresentation(),
        ),
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workflow-selection-page')), findsOneWidget);
    },
  );
}

final class _FakeDocumentSourcePicker implements DocumentSourcePicker {
  var _didSelect = false;

  @override
  Future<DocumentSourceReference?> pickDocumentSource() async {
    if (_didSelect) {
      return null;
    }
    _didSelect = true;
    return const DocumentSourceReference(
      path: '/documents/book.epub',
      fileName: 'book.epub',
      format: DocumentReaderFormat.epub,
    );
  }
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
