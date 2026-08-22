import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/app_locale_selector.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/features/document/document_reader_cubit.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

/// Read-only presentation chrome for one document selected in this workflow.
///
/// Concrete EPUB, plain-text, and PDF content surfaces are intentionally
/// deferred to their format-specific tasks. This page does not read, parse, or
/// validate the source.
class DocumentWorkspacePage extends StatelessWidget {
  const DocumentWorkspacePage({
    super.key,
    required this.localeOverride,
    required this.onLocaleSelected,
  });

  static const _maxContentWidth = 1040.0;
  static const _compactWidth = 680.0;

  final Locale? localeOverride;
  final ValueChanged<Locale> onLocaleSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.documentWorkspaceTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: AppLocaleSelector(
              localeOverride: localeOverride,
              onLocaleSelected: onLocaleSelected,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth < _compactWidth
                  ? AppSpacing.lg
                  : AppSpacing.xl,
              AppSpacing.xl,
              constraints.maxWidth < _compactWidth
                  ? AppSpacing.lg
                  : AppSpacing.xl,
              AppSpacing.xxl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child:
                    BlocBuilder<DocumentReaderCubit, DocumentReaderLoadState>(
                      builder: (context, state) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DocumentSourceChrome(state: state),
                          const SizedBox(height: AppSpacing.lg),
                          _PrimaryWorkspaceRegion(state: state),
                        ],
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentSourceChrome extends StatelessWidget {
  const _DocumentSourceChrome({required this.state});

  final DocumentReaderLoadState state;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final source = state.source;

    return Card(
      key: const Key('document-workspace-source'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            const Icon(Icons.description_outlined),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source?.fileName ?? localizations.documentWorkspaceTitle,
                    key: const Key('document-workspace-source-name'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(_statusText(localizations, state)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            if (state is DocumentReaderLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              OutlinedButton.icon(
                key: const Key('replace-document-source'),
                onPressed: () =>
                    context.read<DocumentReaderCubit>().selectOrReplaceSource(),
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(localizations.replaceDocument),
              ),
          ],
        ),
      ),
    );
  }

  String _statusText(
    AppLocalizations localizations,
    DocumentReaderLoadState state,
  ) => switch (state) {
    DocumentReaderNoSource() => localizations.documentSourceMissing,
    DocumentReaderLoading() => localizations.replacingDocument,
    DocumentReaderReady(:final source) => localizations.documentSelected(
      source.fileName,
    ),
    DocumentReaderUnsupported() => localizations.documentSourceUnsupported,
    DocumentReaderFailure() => localizations.documentSelectionFailed,
  };
}

class _PrimaryWorkspaceRegion extends StatelessWidget {
  const _PrimaryWorkspaceRegion({required this.state});

  final DocumentReaderLoadState state;

  @override
  Widget build(BuildContext context) => switch (state) {
    DocumentReaderReady(:final source) => switch (source.format) {
      DocumentReaderFormat.epub => const _EpubReaderRegion(),
      DocumentReaderFormat.plainText => const _PlainTextReaderRegion(),
      DocumentReaderFormat.pdf => const _PdfReaderRegion(),
      null => const _UnavailableReaderRegion(),
    },
    DocumentReaderLoading() => const _WorkspaceFeedbackRegion(
      regionKey: Key('document-workspace-loading'),
      icon: Icons.hourglass_top_outlined,
    ),
    DocumentReaderUnsupported() => const _WorkspaceFeedbackRegion(
      regionKey: Key('document-workspace-unsupported'),
      icon: Icons.report_outlined,
    ),
    DocumentReaderFailure() => const _WorkspaceFeedbackRegion(
      regionKey: Key('document-workspace-failure'),
      icon: Icons.error_outline,
    ),
    DocumentReaderNoSource() => const _WorkspaceFeedbackRegion(
      regionKey: Key('document-workspace-no-source'),
      icon: Icons.description_outlined,
    ),
  };
}

class _EpubReaderRegion extends StatelessWidget {
  const _EpubReaderRegion();

  @override
  Widget build(BuildContext context) => const _UnavailableReaderRegion(
    regionKey: Key('document-reader-region-epub'),
  );
}

class _PlainTextReaderRegion extends StatelessWidget {
  const _PlainTextReaderRegion();

  @override
  Widget build(BuildContext context) => const _UnavailableReaderRegion(
    regionKey: Key('document-reader-region-plain-text'),
  );
}

class _PdfReaderRegion extends StatelessWidget {
  const _PdfReaderRegion();

  @override
  Widget build(BuildContext context) => const _UnavailableReaderRegion(
    regionKey: Key('document-reader-region-pdf'),
  );
}

class _UnavailableReaderRegion extends StatelessWidget {
  const _UnavailableReaderRegion({this.regionKey});

  final Key? regionKey;

  @override
  Widget build(BuildContext context) => _WorkspaceFeedbackRegion(
    regionKey: regionKey,
    icon: Icons.chrome_reader_mode_outlined,
  );
}

class _WorkspaceFeedbackRegion extends StatelessWidget {
  const _WorkspaceFeedbackRegion({required this.regionKey, required this.icon});

  final Key? regionKey;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Card(
      key: regionKey,
      child: SizedBox(
        height: 360,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 40),
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
        ),
      ),
    );
  }
}
