import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/app_locale_selector.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/features/document/document_reader_cubit.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/document/epub_presentation_loader.dart';
import 'package:video_translator/features/document/plain_text_presentation_loader.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

/// Read-only presentation chrome for one document selected in this workflow.
///
/// Plain-text and PDF content surfaces are intentionally deferred to their
/// format-specific tasks. EPUB content is a local, read-only presentation and
/// never validates the source for processing.
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
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth < DocumentWorkspacePage._compactWidth
                  ? AppSpacing.lg
                  : AppSpacing.xl,
              AppSpacing.xl,
              constraints.maxWidth < DocumentWorkspacePage._compactWidth
                  ? AppSpacing.lg
                  : AppSpacing.xl,
              AppSpacing.xxl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DocumentWorkspacePage._maxContentWidth,
                ),
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
    EpubDocumentReaderReady(:final source) => localizations.documentSelected(
      source.fileName,
    ),
    PlainTextDocumentReaderReady(:final source) =>
      localizations.documentSelected(source.fileName),
    DocumentReaderReady(:final source) => localizations.documentSelected(
      source.fileName,
    ),
    DocumentReaderUnsupported(
      reason: DocumentReaderUnsupportedReason.epubFileTooLarge,
    ) =>
      localizations.epubReaderFileTooLarge,
    DocumentReaderUnsupported(
      reason: DocumentReaderUnsupportedReason.plainTextFileTooLarge,
    ) =>
      localizations.plainTextReaderFileTooLarge,
    DocumentReaderUnsupported(
      reason: DocumentReaderUnsupportedReason.plainTextUnsupportedContent,
    ) =>
      localizations.plainTextReaderUnsupportedContent,
    DocumentReaderUnsupported() => localizations.documentSourceUnsupported,
    DocumentReaderFailure() => localizations.documentSelectionFailed,
  };
}

class _PrimaryWorkspaceRegion extends StatelessWidget {
  const _PrimaryWorkspaceRegion({required this.state});

  final DocumentReaderLoadState state;

  @override
  Widget build(BuildContext context) => switch (state) {
    EpubDocumentReaderReady(:final content) => _EpubReaderRegion(
      content: content,
    ),
    PlainTextDocumentReaderReady(:final content) => _PlainTextReaderRegion(
      content: content,
    ),
    DocumentReaderReady(:final source) => switch (source.format) {
      DocumentReaderFormat.epub => const _UnavailableReaderRegion(
        regionKey: Key('document-reader-region-epub'),
      ),
      DocumentReaderFormat.plainText => const _UnavailableReaderRegion(
        regionKey: Key('document-reader-region-plain-text'),
      ),
      DocumentReaderFormat.pdf => const _PdfReaderRegion(),
      null => const _UnavailableReaderRegion(),
    },
    DocumentReaderLoading() => const _WorkspaceFeedbackRegion(
      regionKey: Key('document-workspace-loading'),
      icon: Icons.hourglass_top_outlined,
    ),
    DocumentReaderUnsupported(
      reason: DocumentReaderUnsupportedReason.epubFileTooLarge,
    ) =>
      _WorkspaceFeedbackRegion(
        regionKey: const Key('document-workspace-epub-too-large'),
        icon: Icons.report_outlined,
        description: AppLocalizations.of(context).epubReaderFileTooLarge,
      ),
    DocumentReaderUnsupported(
      reason: DocumentReaderUnsupportedReason.plainTextFileTooLarge,
    ) =>
      _WorkspaceFeedbackRegion(
        regionKey: const Key('document-workspace-plain-text-too-large'),
        icon: Icons.report_outlined,
        description: AppLocalizations.of(context).plainTextReaderFileTooLarge,
      ),
    DocumentReaderUnsupported(
      reason: DocumentReaderUnsupportedReason.plainTextUnsupportedContent,
    ) =>
      _WorkspaceFeedbackRegion(
        regionKey: const Key('document-workspace-plain-text-unsupported'),
        icon: Icons.report_outlined,
        description: AppLocalizations.of(context)
            .plainTextReaderUnsupportedContent,
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

class _EpubReaderRegion extends StatefulWidget {
  const _EpubReaderRegion({required this.content});

  final EpubPresentationContent content;

  @override
  State<_EpubReaderRegion> createState() => _EpubReaderRegionState();
}

class _EpubReaderRegionState extends State<_EpubReaderRegion> {
  var _chapterIndex = 0;

  void _showTableOfContents() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView.builder(
          key: const Key('epub-reader-table-of-contents'),
          itemCount: widget.content.chapters.length,
          itemBuilder: (context, index) {
            final chapter = widget.content.chapters[index];
            return ListTile(
              selected: index == _chapterIndex,
              title: Text(chapter.title),
              onTap: () {
                setState(() => _chapterIndex = index);
                Navigator.of(context).pop();
              },
            );
          },
        ),
      ),
    );
  }

  void _openInternalTarget(String target) {
    final chapterIndex = widget.content.chapters.indexWhere(
      (chapter) => chapter.packagePath == target,
    );
    if (chapterIndex >= 0) {
      setState(() => _chapterIndex = chapterIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.content.chapters[_chapterIndex];
    final isFirst = _chapterIndex == 0;
    final isLast = _chapterIndex == widget.content.chapters.length - 1;

    return Card(
      key: const Key('document-reader-region-epub'),
      child: SizedBox(
        height: 600,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('epub-reader-table-of-contents-button'),
                    tooltip: 'Table of contents',
                    onPressed: _showTableOfContents,
                    icon: const Icon(Icons.format_list_bulleted_outlined),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      chapter.title,
                      key: const Key('epub-reader-chapter-title'),
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    key: const Key('epub-reader-previous-chapter'),
                    tooltip: 'Previous chapter',
                    onPressed: isFirst
                        ? null
                        : () => setState(() => _chapterIndex--),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    key: const Key('epub-reader-next-chapter'),
                    tooltip: 'Next chapter',
                    onPressed: isLast
                        ? null
                        : () => setState(() => _chapterIndex++),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                key: const Key('epub-reader-content'),
                padding: const EdgeInsets.all(AppSpacing.xl),
                itemCount: chapter.blocks.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) => _EpubBlock(
                  block: chapter.blocks[index],
                  images: widget.content.images,
                  onInternalTarget: _openInternalTarget,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpubBlock extends StatelessWidget {
  const _EpubBlock({
    required this.block,
    required this.images,
    required this.onInternalTarget,
  });

  final EpubPresentationBlock block;
  final Map<String, Uint8List> images;
  final ValueChanged<String> onInternalTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = switch (block.kind) {
      EpubPresentationBlockKind.heading => theme.textTheme.headlineSmall,
      EpubPresentationBlockKind.quote => theme.textTheme.bodyLarge?.copyWith(
        fontStyle: FontStyle.italic,
      ),
      EpubPresentationBlockKind.listItem => theme.textTheme.bodyLarge,
      EpubPresentationBlockKind.paragraph => theme.textTheme.bodyLarge,
    };
    final text = <InlineSpan>[];
    for (final inline in block.inlines) {
      if (inline.imagePath case final path?) {
        final image = images[path];
        if (image != null) {
          text.add(
            WidgetSpan(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Image.memory(image, fit: BoxFit.contain),
              ),
            ),
          );
        }
        continue;
      }
      final style = textStyle?.copyWith(
        fontWeight: inline.bold ? FontWeight.bold : null,
        fontStyle: inline.italic ? FontStyle.italic : null,
        decoration: inline.underline ? TextDecoration.underline : null,
        color: inline.internalTarget == null ? null : theme.colorScheme.primary,
      );
      if (inline.internalTarget case final target?) {
        text.add(
          WidgetSpan(
            child: TextButton(
              onPressed: () => onInternalTarget(target),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(inline.text ?? '', style: style),
            ),
          ),
        );
      } else {
        text.add(TextSpan(text: inline.text, style: style));
      }
    }
    return Padding(
      padding: block.kind == EpubPresentationBlockKind.listItem
          ? const EdgeInsets.only(left: AppSpacing.lg)
          : EdgeInsets.zero,
      child: RichText(
        textAlign: block.alignment,
        text: TextSpan(children: text),
      ),
    );
  }
}

class _PlainTextReaderRegion extends StatelessWidget {
  const _PlainTextReaderRegion({required this.content});

  final PlainTextPresentationContent content;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('document-reader-region-plain-text'),
    child: SizedBox(
      height: 600,
      child: SelectionArea(
        child: SingleChildScrollView(
          key: const Key('plain-text-reader-content'),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            content.text,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(fontFamily: 'monospace', height: 1.45),
          ),
        ),
      ),
    ),
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
