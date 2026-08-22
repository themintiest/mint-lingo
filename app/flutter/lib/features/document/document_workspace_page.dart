import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/app_locale_selector.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/features/document/document_reader_cubit.dart';
import 'package:video_translator/features/document/document_reader_feedback.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/document/reader/document_reader_host.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

/// Read-only workspace chrome for a selected local document.
///
/// Reader-specific presentation and UI are owned by [DocumentReaderHost].
class DocumentWorkspacePage extends StatefulWidget {
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
  State<DocumentWorkspacePage> createState() => _DocumentWorkspacePageState();
}

class _DocumentWorkspacePageState extends State<DocumentWorkspacePage> {
  late final DocumentReaderCubit _readerCubit;

  @override
  void initState() {
    super.initState();
    _readerCubit = context.read<DocumentReaderCubit>();
  }

  @override
  void dispose() {
    _readerCubit.releaseReaderPresentation();
    super.dispose();
  }

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
              localeOverride: widget.localeOverride,
              onLocaleSelected: widget.onLocaleSelected,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding =
                constraints.maxWidth < DocumentWorkspacePage._compactWidth
                ? AppSpacing.lg
                : AppSpacing.xl;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DocumentWorkspacePage._maxContentWidth,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    AppSpacing.xl,
                    horizontalPadding,
                    AppSpacing.xl,
                  ),
                  child:
                      BlocBuilder<DocumentReaderCubit, DocumentReaderLoadState>(
                        builder: (context, state) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _DocumentSourceChrome(state: state),
                            const SizedBox(height: AppSpacing.lg),
                            Expanded(
                              child: _PrimaryWorkspaceRegion(state: state),
                            ),
                          ],
                        ),
                      ),
                ),
              ),
            );
          },
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
    DocumentReaderUnsupported(:final source, :final reason) =>
      documentReaderUnsupportedDescription(localizations, source, reason),
    DocumentReaderFailure() => localizations.documentSelectionFailed,
  };
}

class _PrimaryWorkspaceRegion extends StatelessWidget {
  const _PrimaryWorkspaceRegion({required this.state});

  final DocumentReaderLoadState state;

  @override
  Widget build(BuildContext context) => switch (state) {
    DocumentReaderReady(:final presentation) => DocumentReaderHost(
      presentation: presentation,
    ),
    DocumentReaderLoading() => const _WorkspaceFeedbackRegion(
      regionKey: Key('document-workspace-loading'),
      icon: Icons.hourglass_top_outlined,
    ),
    DocumentReaderUnsupported(:final source, :final reason) =>
      _unsupportedFeedback(context, source, reason),
    DocumentReaderFailure() => const _WorkspaceFeedbackRegion(
      regionKey: Key('document-workspace-failure'),
      icon: Icons.error_outline,
    ),
    DocumentReaderNoSource() => const _WorkspaceFeedbackRegion(
      regionKey: Key('document-workspace-no-source'),
      icon: Icons.description_outlined,
    ),
  };

  Widget _unsupportedFeedback(
    BuildContext context,
    DocumentSourceReference source,
    DocumentReaderUnsupportedReason reason,
  ) {
    final localizations = AppLocalizations.of(context);
    return _WorkspaceFeedbackRegion(
      regionKey: documentReaderUnsupportedRegionKey(source, reason),
      icon: Icons.report_outlined,
      description: documentReaderUnsupportedDescription(
        localizations,
        source,
        reason,
      ),
    );
  }
}

class _WorkspaceFeedbackRegion extends StatelessWidget {
  const _WorkspaceFeedbackRegion({
    required this.regionKey,
    required this.icon,
    this.description,
  });

  final Key? regionKey;
  final IconData icon;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Card(
      key: regionKey,
      child: SizedBox.expand(
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
                  description ??
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
