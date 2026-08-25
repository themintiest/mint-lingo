import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/document/epub_source_acquisition_request.dart';

void main() {
  test('maps a selected EPUB source to a path-only processing payload', () {
    const source = DocumentSourceReference(
      path: '/documents/novel.epub',
      fileName: 'novel.epub',
      format: DocumentReaderFormat.epub,
    );

    final request = EpubSourceAcquisitionRequest.fromDocumentSource(source);

    expect(request.sourcePath, source.path);
    expect(request.toProcessingPayload(), {'sourcePath': source.path});
  });

  test(
    'accepts an EPUB selection without claiming reader or package validity',
    () {
      const source = DocumentSourceReference(
        path: '/documents/unverified.epub',
        fileName: 'unverified.epub',
        format: DocumentReaderFormat.epub,
      );

      final request = EpubSourceAcquisitionRequest.fromDocumentSource(source);

      expect(request.toProcessingPayload().keys, ['sourcePath']);
    },
  );

  test('rejects a non-EPUB document source without changing reader state', () {
    const source = DocumentSourceReference(
      path: '/documents/notes.txt',
      fileName: 'notes.txt',
      format: DocumentReaderFormat.plainText,
    );

    expect(
      () => EpubSourceAcquisitionRequest.fromDocumentSource(source),
      throwsArgumentError,
    );
  });
}
