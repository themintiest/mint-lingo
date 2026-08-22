import 'package:flutter/material.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

/// Returns the existing localized feedback for a semantic reader limitation.
///
/// The source format is used only where the current UX has distinct wording;
/// the unsupported reason itself remains independent of document format.
String documentReaderUnsupportedDescription(
  AppLocalizations localizations,
  DocumentSourceReference source,
  DocumentReaderUnsupportedReason reason,
) => switch ((source.format, reason)) {
  (DocumentReaderFormat.epub, DocumentReaderUnsupportedReason.fileTooLarge) =>
    localizations.epubReaderFileTooLarge,
  (
    DocumentReaderFormat.plainText,
    DocumentReaderUnsupportedReason.fileTooLarge,
  ) =>
    localizations.plainTextReaderFileTooLarge,
  (
    DocumentReaderFormat.plainText,
    DocumentReaderUnsupportedReason.unsupportedContent,
  ) =>
    localizations.plainTextReaderUnsupportedContent,
  _ => localizations.documentSourceUnsupported,
};

/// Preserves stable widget keys for the current localized feedback variants.
Key documentReaderUnsupportedRegionKey(
  DocumentSourceReference source,
  DocumentReaderUnsupportedReason reason,
) => switch ((source.format, reason)) {
  (DocumentReaderFormat.epub, DocumentReaderUnsupportedReason.fileTooLarge) =>
    const Key('document-workspace-epub-too-large'),
  (
    DocumentReaderFormat.plainText,
    DocumentReaderUnsupportedReason.fileTooLarge,
  ) =>
    const Key('document-workspace-plain-text-too-large'),
  (
    DocumentReaderFormat.plainText,
    DocumentReaderUnsupportedReason.unsupportedContent,
  ) =>
    const Key('document-workspace-plain-text-unsupported'),
  _ => const Key('document-workspace-unsupported'),
};
