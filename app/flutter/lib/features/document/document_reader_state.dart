import 'package:video_translator/features/document/epub_presentation_loader.dart';
import 'package:video_translator/features/document/plain_text_presentation_loader.dart';

/// Reader formats recognized by the Document Translation presentation flow.
///
/// This classification only selects a future reader surface. It does not
/// validate a source for processing or describe a document artifact.
enum DocumentReaderFormat { epub, plainText, pdf }

/// An immutable local source reference owned by Document Translation.
///
/// The reference deliberately retains only presentation identity. File access,
/// parsing, and processing validation belong to later, format-specific work.
final class DocumentSourceReference {
  const DocumentSourceReference({
    required this.path,
    required this.fileName,
    this.format,
  });

  final String path;
  final String fileName;

  /// The reader format recognized from local source metadata, if any.
  ///
  /// A null value is retained only to report that a selected local source is
  /// unsupported by the Document Translation reader boundary.
  final DocumentReaderFormat? format;

  @override
  bool operator ==(Object other) =>
      other is DocumentSourceReference &&
      other.path == path &&
      other.fileName == fileName &&
      other.format == format;

  @override
  int get hashCode => Object.hash(path, fileName, format);
}

/// Immutable reader load state owned solely by Document Translation.
///
/// A reader state reports only presentation readiness for a local source. It
/// makes no statement about processing support, extraction, translation, or
/// export validity.
sealed class DocumentReaderLoadState {
  const DocumentReaderLoadState();

  DocumentSourceReference? get source;
}

/// No local document has been selected for presentation.
final class DocumentReaderNoSource extends DocumentReaderLoadState {
  const DocumentReaderNoSource();

  @override
  DocumentSourceReference? get source => null;

  @override
  bool operator ==(Object other) => other is DocumentReaderNoSource;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// A recognized local document is loading into its future reader surface.
final class DocumentReaderLoading extends DocumentReaderLoadState {
  const DocumentReaderLoading(this.source);

  @override
  final DocumentSourceReference? source;

  @override
  bool operator ==(Object other) =>
      other is DocumentReaderLoading && other.source == source;

  @override
  int get hashCode => Object.hash(runtimeType, source);
}

/// A local document is ready for read-only presentation.
final class DocumentReaderReady extends DocumentReaderLoadState {
  const DocumentReaderReady(this.source);

  @override
  final DocumentSourceReference source;

  @override
  bool operator ==(Object other) =>
      other is DocumentReaderReady && other.source == source;

  @override
  int get hashCode => Object.hash(runtimeType, source);
}

/// A selected local EPUB has been decoded into reader-only presentation data.
///
/// The content is intentionally specific to the EPUB surface and is not a
/// normalized document artifact or a processing validation result.
final class EpubDocumentReaderReady extends DocumentReaderLoadState {
  const EpubDocumentReaderReady({required this.source, required this.content});

  @override
  final DocumentSourceReference source;
  final EpubPresentationContent content;
}

/// A selected local UTF-8 text source is ready for read-only presentation.
final class PlainTextDocumentReaderReady extends DocumentReaderLoadState {
  const PlainTextDocumentReaderReady({
    required this.source,
    required this.content,
  });

  @override
  final DocumentSourceReference source;
  final PlainTextPresentationContent content;
}

enum DocumentReaderUnsupportedReason {
  generic,
  epubFileTooLarge,
  plainTextFileTooLarge,
  plainTextUnsupportedContent,
}

/// The selected local document cannot be presented by its reader surface.
final class DocumentReaderUnsupported extends DocumentReaderLoadState {
  const DocumentReaderUnsupported(
    this.source, {
    this.reason = DocumentReaderUnsupportedReason.generic,
  });

  @override
  final DocumentSourceReference source;
  final DocumentReaderUnsupportedReason reason;

  @override
  bool operator ==(Object other) =>
      other is DocumentReaderUnsupported &&
      other.source == source &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(runtimeType, source, reason);
}

/// Loading a local document failed before read-only presentation was ready.
final class DocumentReaderFailure extends DocumentReaderLoadState {
  const DocumentReaderFailure({required this.source, required this.error});

  @override
  final DocumentSourceReference? source;
  final Object error;

  @override
  bool operator ==(Object other) =>
      other is DocumentReaderFailure &&
      other.source == source &&
      other.error == error;

  @override
  int get hashCode => Object.hash(runtimeType, source, error);
}
