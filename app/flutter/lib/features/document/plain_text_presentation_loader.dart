import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Read-only plain-text data for the Document Workspace.
///
/// This is a presentation model, not a `PlainTextDocumentArtifact` and does
/// not define processing encoding, newline, or text-unit behavior.
final class PlainTextPresentationContent {
  const PlainTextPresentationContent({required this.text});

  final String text;
}

final class PlainTextReaderFileTooLargeException implements Exception {
  const PlainTextReaderFileTooLargeException(this.sizeInBytes);

  final int sizeInBytes;
}

final class PlainTextReaderUnsupportedContentException implements Exception {
  const PlainTextReaderUnsupportedContentException();
}

/// Opens a selected local UTF-8 text source for read-only presentation.
abstract interface class PlainTextPresentationLoader {
  Future<PlainTextPresentationContent> load(String localPath);
}

/// Bounded, isolate-backed loader for the first plain-text reader slice.
final class IsolatePlainTextPresentationLoader
    implements PlainTextPresentationLoader {
  const IsolatePlainTextPresentationLoader();

  static const maxFileBytes = 10 * 1024 * 1024;

  @override
  Future<PlainTextPresentationContent> load(String localPath) async {
    final text = await Isolate.run(() => _loadInIsolate(localPath));
    return PlainTextPresentationContent(text: text);
  }
}

Future<String> _loadInIsolate(String localPath) async {
  final file = File(localPath);
  final length = await file.length();
  if (length > IsolatePlainTextPresentationLoader.maxFileBytes) {
    throw PlainTextReaderFileTooLargeException(length);
  }

  final bytes = await file.readAsBytes();
  if (_containsBinaryControlByte(bytes)) {
    throw const PlainTextReaderUnsupportedContentException();
  }
  try {
    final text = utf8.decode(bytes, allowMalformed: false);
    return text.startsWith('\uFEFF') ? text.substring(1) : text;
  } on FormatException {
    throw const PlainTextReaderUnsupportedContentException();
  }
}

bool _containsBinaryControlByte(List<int> bytes) => bytes.any(
  (byte) =>
      byte == 0 ||
      (byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D),
);
