import 'package:video_translator/features/document/document_reader_state.dart';

/// The path-only handoff from the selected EPUB source to Python acquisition.
///
/// This is deliberately independent of reader readiness: the Python EPUB
/// branch must inspect and validate the selected package for itself. It is a
/// concrete EPUB payload, not a shared workflow or document-source model.
final class EpubSourceAcquisitionRequest {
  EpubSourceAcquisitionRequest.fromDocumentSource(
    DocumentSourceReference source,
  ) : sourcePath = _sourcePathFor(source);

  /// The selected local path. No EPUB bytes are represented in this request.
  final String sourcePath;

  /// The concrete payload for the Python EPUB acquisition boundary.
  Map<String, String> toProcessingPayload() => {'sourcePath': sourcePath};

  static String _sourcePathFor(DocumentSourceReference source) {
    if (source.format != DocumentReaderFormat.epub) {
      throw ArgumentError.value(
        source.format,
        'source.format',
        'must identify an EPUB source',
      );
    }
    if (source.path.isEmpty || source.path.trim() != source.path) {
      throw ArgumentError.value(
        source.path,
        'source.path',
        'must be a non-empty local path',
      );
    }
    return source.path;
  }
}
