import 'package:file_selector/file_selector.dart';
import 'package:video_translator/features/document/document_reader_state.dart';

/// Selects one local source for Document Translation presentation.
abstract interface class DocumentSourcePicker {
  Future<DocumentSourceReference?> pickDocumentSource();
}

/// Recognizes the narrow set of reader formats supported by this milestone.
///
/// This maps a filename extension to a reader surface only. It does not open,
/// inspect, parse, or validate the selected document.
DocumentReaderFormat? documentReaderFormatForFileName(String fileName) {
  final separator = fileName.lastIndexOf('.');
  if (separator <= 0 || separator == fileName.length - 1) {
    return null;
  }

  return switch (fileName.substring(separator + 1).toLowerCase()) {
    'epub' => DocumentReaderFormat.epub,
    'pdf' => DocumentReaderFormat.pdf,
    'txt' => DocumentReaderFormat.plainText,
    _ => null,
  };
}

/// Uses the operating system's native dialog for one local document.
///
/// This boundary keeps only path metadata. It never reads document bytes or
/// sends anything to the processing engine.
final class FileSelectorDocumentSourcePicker implements DocumentSourcePicker {
  const FileSelectorDocumentSourcePicker();

  static const _documentTypeGroup = XTypeGroup(
    label: 'Document files',
    extensions: ['epub', 'pdf', 'txt'],
  );

  @override
  Future<DocumentSourceReference?> pickDocumentSource() async {
    final selectedFile = await openFile(
      acceptedTypeGroups: const [_documentTypeGroup],
    );
    if (selectedFile == null) {
      return null;
    }
    if (selectedFile.path.isEmpty) {
      throw StateError('The selected document does not provide a local path.');
    }

    return DocumentSourceReference(
      path: selectedFile.path,
      fileName: selectedFile.name,
      format: documentReaderFormatForFileName(selectedFile.name),
    );
  }
}
