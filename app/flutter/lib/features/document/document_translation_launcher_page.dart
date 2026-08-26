import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/app_locale_selector.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/features/document/document_reader_cubit.dart';
import 'package:video_translator/features/document/document_reader_feedback.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/document/document_presentation.dart';
import 'package:video_translator/features/document/document_workspace_page.dart';
import 'package:video_translator/features/document/epub_translation_cubit.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

/// Whether a prepared reader presentation should open the workspace.
///
/// A released presentation retains its source only for launcher context; it
/// must never reopen a workspace after the user has navigated back from it.
bool shouldOpenDocumentWorkspace(DocumentReaderLoadState state) =>
    state is DocumentReaderReady &&
    state.presentation is! DocumentReaderUnavailablePresentation;

/// The Document Translation entry for selecting one local reader source.
class DocumentTranslationLauncherPage extends StatelessWidget {
  const DocumentTranslationLauncherPage({
    super.key,
    required this.localeOverride,
    required this.onLocaleSelected,
    this.epubTranslationCubit,
  });

  static const _maxContentWidth = 520.0;
  static const _compactWidth = 600.0;

  final Locale? localeOverride;
  final ValueChanged<Locale> onLocaleSelected;
  final EpubTranslationCubit? epubTranslationCubit;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return BlocListener<DocumentReaderCubit, DocumentReaderLoadState>(
      listenWhen: (_, state) => shouldOpenDocumentWorkspace(state),
      listener: (context, state) {
        if (ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) {
              final workspace = SelectionArea(
                key: const Key('document-workspace-selection-area'),
                child: DocumentWorkspacePage(
                  localeOverride: localeOverride,
                  onLocaleSelected: onLocaleSelected,
                  epubTranslationCubit: epubTranslationCubit,
                ),
              );
              if (epubTranslationCubit == null) {
                return BlocProvider.value(
                  value: context.read<DocumentReaderCubit>(),
                  child: workspace,
                );
              }
              return MultiBlocProvider(
                providers: [
                  BlocProvider.value(
                    value: context.read<DocumentReaderCubit>(),
                  ),
                  BlocProvider.value(value: epubTranslationCubit!),
                ],
                child: workspace,
              );
            },
          ),
        );
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(localizations.documentTranslationWorkflow),
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
            builder: (context, constraints) {
              final horizontalPadding = constraints.maxWidth < _compactWidth
                  ? AppSpacing.lg
                  : AppSpacing.xl;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  AppSpacing.xxl,
                  horizontalPadding,
                  AppSpacing.xxl,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _maxContentWidth,
                    ),
                    child: Card(
                      key: const Key('document-translation-launcher'),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLow,
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                child: Icon(
                                  Icons.description_outlined,
                                  size: 40,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              localizations.documentTranslationWorkflow,
                              style: Theme.of(context).textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            BlocBuilder<
                              DocumentReaderCubit,
                              DocumentReaderLoadState
                            >(
                              builder: (context, state) => Column(
                                children: [
                                  Text(
                                    _descriptionForState(localizations, state),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  if (state is DocumentReaderLoading)
                                    const CircularProgressIndicator()
                                  else
                                    FilledButton.icon(
                                      key: const Key('select-document-source'),
                                      onPressed: () => context
                                          .read<DocumentReaderCubit>()
                                          .selectOrReplaceSource(),
                                      icon: const Icon(
                                        Icons.folder_open_outlined,
                                      ),
                                      label: Text(
                                        state.source == null
                                            ? localizations.selectDocument
                                            : localizations.replaceDocument,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _descriptionForState(
    AppLocalizations localizations,
    DocumentReaderLoadState state,
  ) => switch (state) {
    DocumentReaderNoSource() => localizations.documentLauncherDescription,
    DocumentReaderLoading() => localizations.selectingDocument,
    DocumentReaderReady(:final source) => localizations.documentSelected(
      source.fileName,
    ),
    DocumentReaderUnsupported(:final source, :final reason) =>
      documentReaderUnsupportedDescription(localizations, source, reason),
    DocumentReaderFailure() => localizations.documentSelectionFailed,
  };
}
