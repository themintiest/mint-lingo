import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/features/document/document_reader_cubit.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/document/document_source_picker.dart';
import 'package:video_translator/features/document/epub_presentation_loader.dart';

void main() {
  test('recognizes only EPUB TXT and PDF filename extensions', () {
    expect(
      documentReaderFormatForFileName('BOOK.EPUB'),
      DocumentReaderFormat.epub,
    );
    expect(
      documentReaderFormatForFileName('notes.txt'),
      DocumentReaderFormat.plainText,
    );
    expect(
      documentReaderFormatForFileName('guide.pdf'),
      DocumentReaderFormat.pdf,
    );
    expect(documentReaderFormatForFileName('archive.docx'), isNull);
  });

  test('selects and replaces a recognized local document source', () async {
    final cubit = DocumentReaderCubit(
      sourcePicker: _FakeDocumentSourcePicker([
        const DocumentSourceReference(
          path: '/documents/first.txt',
          fileName: 'first.txt',
          format: DocumentReaderFormat.plainText,
        ),
        const DocumentSourceReference(
          path: '/documents/second.pdf',
          fileName: 'second.pdf',
          format: DocumentReaderFormat.pdf,
        ),
      ]),
    );
    addTearDown(cubit.close);

    await cubit.selectOrReplaceSource();
    await cubit.selectOrReplaceSource();

    expect(
      cubit.state,
      const DocumentReaderReady(
        DocumentSourceReference(
          path: '/documents/second.pdf',
          fileName: 'second.pdf',
          format: DocumentReaderFormat.pdf,
        ),
      ),
    );
  });

  test(
    'restores the prior source when document selection is canceled',
    () async {
      const source = DocumentSourceReference(
        path: '/documents/book.epub',
        fileName: 'book.epub',
        format: DocumentReaderFormat.epub,
      );
      final cubit = DocumentReaderCubit(
        sourcePicker: _FakeDocumentSourcePicker([source, null]),
        epubPresentationLoader: const _FakeEpubPresentationLoader(),
      );
      addTearDown(cubit.close);
      await cubit.selectOrReplaceSource();

      await cubit.selectOrReplaceSource();

      expect(cubit.state, isA<EpubDocumentReaderReady>());
      expect((cubit.state as EpubDocumentReaderReady).source, source);
    },
  );

  test(
    'stores only EPUB presentation content after local reader loading',
    () async {
      const source = DocumentSourceReference(
        path: '/documents/book.epub',
        fileName: 'book.epub',
        format: DocumentReaderFormat.epub,
      );
      final cubit = DocumentReaderCubit(
        sourcePicker: _FakeDocumentSourcePicker([source]),
        epubPresentationLoader: const _FakeEpubPresentationLoader(),
      );
      addTearDown(cubit.close);

      await cubit.selectOrReplaceSource();

      expect(cubit.state, isA<EpubDocumentReaderReady>());
      final ready = cubit.state as EpubDocumentReaderReady;
      expect(ready.source, source);
      expect(ready.content.chapters.single.title, 'Chapter');
    },
  );

  test('releases EPUB presentation content on reader disposal', () async {
    const source = DocumentSourceReference(
      path: '/documents/book.epub',
      fileName: 'book.epub',
      format: DocumentReaderFormat.epub,
    );
    final cubit = DocumentReaderCubit(
      sourcePicker: _FakeDocumentSourcePicker([source]),
      epubPresentationLoader: const _FakeEpubPresentationLoader(),
    );
    addTearDown(cubit.close);

    await cubit.selectOrReplaceSource();
    await cubit.close();

    expect(cubit.state, const DocumentReaderReady(source));
  });

  test(
    'reports the EPUB size envelope as document-owned unsupported state',
    () async {
      const source = DocumentSourceReference(
        path: '/documents/book.epub',
        fileName: 'book.epub',
        format: DocumentReaderFormat.epub,
      );
      final cubit = DocumentReaderCubit(
        sourcePicker: _FakeDocumentSourcePicker([source]),
        epubPresentationLoader: const _TooLargeEpubPresentationLoader(),
      );
      addTearDown(cubit.close);

      await cubit.selectOrReplaceSource();

      expect(
        cubit.state,
        const DocumentReaderUnsupported(
          source,
          reason: DocumentReaderUnsupportedReason.epubFileTooLarge,
        ),
      );
    },
  );

  test(
    'reports an unsupported document without claiming a reader format',
    () async {
      const source = DocumentSourceReference(
        path: '/documents/legacy.doc',
        fileName: 'legacy.doc',
      );
      final cubit = DocumentReaderCubit(
        sourcePicker: _FakeDocumentSourcePicker([source]),
      );
      addTearDown(cubit.close);

      await cubit.selectOrReplaceSource();

      expect(cubit.state, const DocumentReaderUnsupported(source));
      expect(cubit.state.source?.format, isNull);
    },
  );

  test('reports picker failures without mutating the prior source', () async {
    const source = DocumentSourceReference(
      path: '/documents/guide.pdf',
      fileName: 'guide.pdf',
      format: DocumentReaderFormat.pdf,
    );
    final error = StateError('Native picker failed.');
    final cubit = DocumentReaderCubit(
      sourcePicker: _FakeDocumentSourcePicker(
        [source],
        error: error,
        errorOnCall: 2,
      ),
    );
    addTearDown(cubit.close);
    await cubit.selectOrReplaceSource();

    await cubit.selectOrReplaceSource();

    expect(cubit.state, DocumentReaderFailure(source: source, error: error));
  });
}

final class _FakeEpubPresentationLoader implements EpubPresentationLoader {
  const _FakeEpubPresentationLoader();

  @override
  Future<EpubPresentationContent> load(String localPath) async =>
      const EpubPresentationContent(
        chapters: [
          EpubPresentationChapter(
            title: 'Chapter',
            packagePath: 'Text/chapter.xhtml',
            blocks: [],
          ),
        ],
        images: {},
      );
}

final class _TooLargeEpubPresentationLoader implements EpubPresentationLoader {
  const _TooLargeEpubPresentationLoader();

  @override
  Future<EpubPresentationContent> load(String localPath) =>
      Future<EpubPresentationContent>.error(
        const EpubReaderFileTooLargeException(50 * 1024 * 1024 + 1),
      );
}

final class _FakeDocumentSourcePicker implements DocumentSourcePicker {
  _FakeDocumentSourcePicker(this._sources, {this.error, this.errorOnCall});

  final List<DocumentSourceReference?> _sources;
  final Object? error;
  final int? errorOnCall;
  var _callCount = 0;

  @override
  Future<DocumentSourceReference?> pickDocumentSource() async {
    _callCount++;
    if (error != null && _callCount == errorOnCall) {
      throw error!;
    }
    return _sources.removeAt(0);
  }
}
