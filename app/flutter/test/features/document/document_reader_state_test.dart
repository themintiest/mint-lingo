import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/features/document/document_presentation.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/project/project_draft.dart';

void main() {
  const epubSource = DocumentSourceReference(
    path: '/documents/book.epub',
    fileName: 'book.epub',
    format: DocumentReaderFormat.epub,
  );

  test('recognizes only the document reader formats', () {
    expect(DocumentReaderFormat.values, [
      DocumentReaderFormat.epub,
      DocumentReaderFormat.plainText,
      DocumentReaderFormat.pdf,
    ]);
  });

  test('preserves document-local path name and recognized format identity', () {
    expect(
      epubSource,
      const DocumentSourceReference(
        path: '/documents/book.epub',
        fileName: 'book.epub',
        format: DocumentReaderFormat.epub,
      ),
    );
    expect(
      epubSource,
      isNot(
        const DocumentSourceReference(
          path: '/documents/book.epub',
          fileName: 'book.epub',
          format: DocumentReaderFormat.pdf,
        ),
      ),
    );
  });

  test('distinguishes each document reader load state', () {
    const failure = FormatException('Cannot open local source');
    const unsupportedSource = DocumentSourceReference(
      path: '/documents/legacy.doc',
      fileName: 'legacy.doc',
    );
    final states = <DocumentReaderLoadState>[
      const DocumentReaderNoSource(),
      const DocumentReaderLoading(null),
      const DocumentReaderReady(
        source: epubSource,
        presentation: DocumentReaderUnavailablePresentation(),
      ),
      const DocumentReaderUnsupported(unsupportedSource),
      const DocumentReaderFailure(source: epubSource, error: failure),
    ];

    expect(states[0].source, isNull);
    expect(states[1].source, isNull);
    expect(states[2].source, epubSource);
    expect(states[3].source, unsupportedSource);
    expect(states[4].source, epubSource);
    expect(states.toSet(), hasLength(5));
  });

  test('keeps document source identity out of the Video project draft', () {
    const documentSource = DocumentSourceReference(
      path: '/documents/notes.txt',
      fileName: 'notes.txt',
      format: DocumentReaderFormat.plainText,
    );
    const videoDraft = ProjectDraft(
      source: ProjectSourceReference(
        path: '/videos/source.mp4',
        fileName: 'source.mp4',
      ),
    );

    expect(documentSource, isNot(isA<ProjectSourceReference>()));
    expect(videoDraft.source, isA<ProjectSourceReference>());
    expect(videoDraft.source?.path, '/videos/source.mp4');
  });
}
