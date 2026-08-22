import 'package:video_translator/features/document/epub_presentation_loader.dart';
import 'package:video_translator/features/document/plain_text_presentation_loader.dart';
import 'package:video_translator/features/document/pdf_presentation_loader.dart';

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

/// PDF presentation readiness for the local original-source reader.
///
/// The content intentionally contains no extracted text, pages, or processing
/// metadata. PDFium opens the selected local path only inside the reader widget.
final class PdfDocumentPresentation extends DocumentPresentation {
  const PdfDocumentPresentation({required this.content});

  final PdfPresentationContent content;
}

/// A selected source whose presentation data has been released.
final class DocumentReaderUnavailablePresentation extends DocumentPresentation {
  const DocumentReaderUnavailablePresentation();

  @override
  bool operator ==(Object other) =>
      other is DocumentReaderUnavailablePresentation;

  @override
  int get hashCode => runtimeType.hashCode;
}
