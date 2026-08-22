import 'dart:io';

/// Performs the bounded local-file preflight required before PDF presentation.
///
/// This does not parse, extract, validate, or create a processing artifact for
/// the PDF. Native PDF rendering remains owned by the reader widget.
abstract interface class PdfPresentationLoader {
  Future<PdfPresentationContent> load(String localPath);
}

final class LocalPdfPresentationLoader implements PdfPresentationLoader {
  const LocalPdfPresentationLoader();

  static const maxFileBytes = 50 * 1024 * 1024;

  @override
  Future<PdfPresentationContent> load(String localPath) async {
    final byteLength = await File(localPath).length();
    if (byteLength > maxFileBytes) {
      throw PdfReaderFileTooLargeException(byteLength);
    }
    return const PdfPresentationContent();
  }
}

/// Deliberately empty PDF reader data.
///
/// Keeping this marker separate from the source reference lets the Document
/// feature distinguish PDF reader readiness without retaining document bytes.
final class PdfPresentationContent {
  const PdfPresentationContent();
}

final class PdfReaderFileTooLargeException implements Exception {
  const PdfReaderFileTooLargeException(this.byteLength);

  final int byteLength;
}
