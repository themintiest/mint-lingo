import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/common/models/application_language_catalog.dart';
import 'package:video_translator/common/models/language.dart';
import 'package:video_translator/common/widgets/model_picker.dart';
import 'package:video_translator/features/document/document_presentation.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/document/epub_translation_cubit.dart';
import 'package:video_translator/features/document/reader/epub/epub_reader_region.dart';
import 'package:video_translator/features/processing/processing_bloc.dart';
import 'package:video_translator/features/processing/processing_status_panel.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

/// EPUB-specific controls and original/rebuilt reader selection.
///
/// This is deliberately not a general Document processing surface: TXT and
/// PDF remain reader-only until their own workflows exist. It uses the shared
/// language catalog and processing panel without adopting Video draft state.
class EpubTranslationWorkspace extends StatefulWidget {
  const EpubTranslationWorkspace({
    super.key,
    required this.source,
    required this.presentation,
  });

  final DocumentSourceReference source;
  final EpubDocumentPresentation presentation;

  @override
  State<EpubTranslationWorkspace> createState() =>
      _EpubTranslationWorkspaceState();
}

class _EpubTranslationWorkspaceState extends State<EpubTranslationWorkspace> {
  @override
  void initState() {
    super.initState();
    unawaited(context.read<EpubTranslationCubit>().refreshModelInventory());
  }

  Future<void> _startTranslation(EpubTranslationState state) async {
    final sourceName = widget.source.fileName;
    final baseName = sourceName.toLowerCase().endsWith('.epub')
        ? sourceName.substring(0, sourceName.length - 5)
        : sourceName;
    final location = await getSaveLocation(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'EPUB', extensions: ['epub']),
      ],
      initialDirectory: File(widget.source.path).parent.path,
      suggestedName: '$baseName-translated.epub',
    );
    if (!mounted || location == null) {
      return;
    }
    await context.read<EpubTranslationCubit>().start(
      source: widget.source,
      destinationPath: location.path,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EpubTranslationCubit, EpubTranslationState>(
      builder: (context, state) {
        final translated = state.sourcePath == widget.source.path
            ? state.translatedContent
            : null;
        final visibleContent =
            state.readerVersion == EpubReaderVersion.translated
            ? translated ?? widget.presentation.content
            : widget.presentation.content;
        final active = state.processing is ProcessingActive;

        return LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.55,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        key: const Key('epub-translation-configuration'),
                        child: ExpansionTile(
                          title: Text(
                            AppLocalizations.of(context).epubTranslationTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            0,
                            AppSpacing.lg,
                            AppSpacing.lg,
                          ),
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: AppSpacing.md),
                                _LanguagePicker(
                                  key: const Key('epub-source-language-picker'),
                                  label: AppLocalizations.of(context)
                                      .sourceLanguage,
                                  value: state.sourceLanguage,
                                  onSelected: active
                                      ? null
                                      : context
                                            .read<EpubTranslationCubit>()
                                            .selectSourceLanguage,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                _LanguagePicker(
                                  key: const Key('epub-target-language-picker'),
                                  label: AppLocalizations.of(context)
                                      .targetLanguage,
                                  value: state.targetLanguage,
                                  onSelected: active
                                      ? null
                                      : context
                                            .read<EpubTranslationCubit>()
                                            .selectTargetLanguage,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                ModelPicker(
                                  status: state.modelInventoryStatus,
                                  modelIds: state.modelIds,
                                  selectedModelId: state.modelId,
                                  enabled: !active,
                                  onSelected: context
                                      .read<EpubTranslationCubit>()
                                      .selectModelId,
                                  onRefresh: context
                                      .read<EpubTranslationCubit>()
                                      .refreshModelInventory,
                                  text: ModelPickerText(
                                    label: AppLocalizations.of(context)
                                        .epubModelLabel,
                                    hint: AppLocalizations.of(context)
                                        .epubModelHint,
                                    loading: AppLocalizations.of(context)
                                        .epubModelLoading,
                                    empty: AppLocalizations.of(context)
                                        .epubModelEmpty,
                                    unavailable: AppLocalizations.of(context)
                                        .epubModelUnavailable,
                                    refresh: AppLocalizations.of(context)
                                        .epubModelRefresh,
                                  ),
                                  keyPrefix: 'epub-model',
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton.icon(
                                    key: const Key('start-epub-translation'),
                                    onPressed: state.isConfigured && !active
                                        ? () => _startTranslation(state)
                                        : null,
                                    icon: const Icon(Icons.translate_outlined),
                                    label: Text(
                                      AppLocalizations.of(context)
                                          .translateEpub,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ProcessingStatusPanel(
                        state: state.processing,
                        stageLabelBuilder: _stageLabel,
                        onCancelRequested: (_) =>
                            context.read<EpubTranslationCubit>().cancel(),
                      ),
                      if (state.failureDiagnostic != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _FailureDiagnosticCard(
                          diagnostic: state.failureDiagnostic!,
                        ),
                      ] else if (state.message != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _MessageCard(message: state.message!),
                      ],
                      if (translated != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        SegmentedButton<EpubReaderVersion>(
                          key: const Key('epub-reader-version-picker'),
                          segments: [
                            ButtonSegment(
                              value: EpubReaderVersion.original,
                              label: Text(
                                AppLocalizations.of(context).epubOriginal,
                              ),
                              icon: const Icon(Icons.menu_book_outlined),
                            ),
                            ButtonSegment(
                              value: EpubReaderVersion.translated,
                              label: Text(
                                AppLocalizations.of(context).epubTranslated,
                              ),
                              icon: const Icon(Icons.auto_stories_outlined),
                            ),
                          ],
                          selected: {state.readerVersion},
                          onSelectionChanged: (selection) => context
                              .read<EpubTranslationCubit>()
                              .selectReader(selection.single),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: EpubReaderRegion(
                  key: ValueKey(state.readerVersion),
                  content: visibleContent,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _stageLabel(BuildContext context, String stageId) => switch (stageId) {
    'translating_epub' => AppLocalizations.of(context).epubStageTranslating,
    'exporting_epub' => AppLocalizations.of(context).epubStageExporting,
    _ => AppLocalizations.of(context).epubStageWorking,
  };
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({
    super.key,
    required this.label,
    required this.value,
    required this.onSelected,
  });

  final String label;
  final Language? value;
  final ValueChanged<Language>? onSelected;

  @override
  Widget build(BuildContext context) => DropdownMenu<Language>(
    width: double.infinity,
    initialSelection: value,
    label: Text(label),
    enableFilter: true,
    enabled: onSelected != null,
    onSelected: (language) {
      if (language != null) {
        onSelected?.call(language);
      }
    },
    dropdownMenuEntries: ApplicationLanguageCatalog.entries
        .map(
          (entry) => DropdownMenuEntry(
            value: entry.language,
            label:
                '${ApplicationLanguageCatalog.labelFor(entry.language, AppLocalizations.of(context))} (${entry.language.tag})',
          ),
        )
        .toList(),
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final EpubTranslationMessage message;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final text = switch (message) {
      EpubTranslationMessage.startFailed => localizations.epubStartFailed,
      EpubTranslationMessage.cancelFailed => localizations.epubCancelFailed,
      EpubTranslationMessage.loadingOutput => localizations.epubLoadingOutput,
      EpubTranslationMessage.outputLoadFailed =>
        localizations.epubOutputLoadFailed,
    };
    return Card(
      key: const Key('epub-translation-message'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(text),
      ),
    );
  }
}

class _FailureDiagnosticCard extends StatelessWidget {
  const _FailureDiagnosticCard({required this.diagnostic});

  final EpubFailureDiagnostic diagnostic;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('epub-translation-failure-diagnostic'),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(diagnostic.message),
          const SizedBox(height: AppSpacing.xs),
          Text(diagnostic.code),
          const SizedBox(height: AppSpacing.xs),
          Text(
            diagnostic.retryable
                ? 'You can try again.'
                : 'Update the EPUB or configuration before trying again.',
          ),
        ],
      ),
    ),
  );
}
