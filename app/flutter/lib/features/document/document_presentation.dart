import 'package:video_translator/features/document/epub_presentation_loader.dart';
import 'package:video_translator/features/document/plain_text_presentation_loader.dart';

/// Reader-only data prepared for one local document format.
///
/// Presentation data remains format-specific. It is not a normalized document
/// artifact and does not describe processing, translation, or export support.
sealed class DocumentPresentation {
  const DocumentPresentation();
}

/// EPUB presentation data adapted from the EPUB parser for the Flutter reader.
final class EpubDocumentPresentation extends DocumentPresentation {
  const EpubDocumentPresentation({required this.content});

  final EpubPresentationContent content;
}

/// UTF-8 plain-text presentation data prepared for the Flutter reader.
final class PlainTextDocumentPresentation extends DocumentPresentation {
  const PlainTextDocumentPresentation({required this.content});

  final PlainTextPresentationContent content;
}

/// A recognized source whose reader surface has not been implemented yet.
///
/// This is deliberately format-neutral: it preserves the current PDF
/// placeholder without introducing a PDF data model before there is PDF data
/// to present.
final class DocumentReaderUnavailablePresentation extends DocumentPresentation {
  const DocumentReaderUnavailablePresentation();

  @override
  bool operator ==(Object other) =>
      other is DocumentReaderUnavailablePresentation;

  @override
  int get hashCode => runtimeType.hashCode;
}
