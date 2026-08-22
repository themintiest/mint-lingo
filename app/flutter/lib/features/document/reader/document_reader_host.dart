import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/features/document/document_reader_cubit.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/document/document_presentation.dart';
import 'package:video_translator/features/document/reader/epub/epub_reader_region.dart';
import 'package:video_translator/features/document/reader/plain_text/plain_text_reader_region.dart';
import 'package:video_translator/features/document/reader/pdf/pdf_reader_region.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

/// The single boundary that maps prepared document data to reader UI.
class DocumentReaderHost extends StatelessWidget {
  const DocumentReaderHost({
    super.key,
    required this.source,
    required this.presentation,
  });

  final DocumentSourceReference source;
  final DocumentPresentation presentation;

  @override
  Widget build(BuildContext context) => switch (presentation) {
    EpubDocumentPresentation(:final content) => EpubReaderRegion(
      content: content,
    ),
    PlainTextDocumentPresentation(:final content) => PlainTextReaderRegion(
      content: content,
    ),
    PdfDocumentPresentation() => PdfReaderRegion(
      key: ValueKey(source.path),
      localPath: source.path,
      onLoadFailure: (error) => context
          .read<DocumentReaderCubit>()
          .reportPdfReaderFailure(source, error),
      onPageLimitExceeded: () => context
          .read<DocumentReaderCubit>()
          .reportPdfPageLimitExceeded(source),
    ),
    DocumentReaderUnavailablePresentation() => const _UnavailableReaderRegion(
      regionKey: Key('document-reader-region-pdf'),
    ),
  };
}

class _UnavailableReaderRegion extends StatelessWidget {
  const _UnavailableReaderRegion({this.regionKey});

  final Key? regionKey;

  @override
  Widget build(BuildContext context) => Card(
    key: regionKey,
    child: const SizedBox.expand(child: _ReaderUnavailableContent()),
  );
}

class _ReaderUnavailableContent extends StatelessWidget {
  const _ReaderUnavailableContent();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chrome_reader_mode_outlined, size: 40),
            const SizedBox(height: AppSpacing.md),
            Text(
              localizations.documentReaderUnavailableTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              localizations.documentReaderUnavailableDescription,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
