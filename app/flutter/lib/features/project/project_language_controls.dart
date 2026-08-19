import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/common/models/application_language_catalog.dart';
import 'package:video_translator/common/models/language.dart';
import 'package:video_translator/features/project/project_draft.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

/// Renders project language choices while preserving the temporary free-form
/// entry flow until LANG-R03 introduces catalog-backed selectors.
///
/// Display labels are resolved from the application catalog rather than stored
/// with project language values.
class ProjectLanguageControls extends StatelessWidget {
  const ProjectLanguageControls({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProjectSetupCubit, ProjectSetupState>(
      builder: (context, state) {
        final localizations = AppLocalizations.of(context);
        final draft = state.draft ?? const ProjectDraft();
        final sourceLanguage = draft.sourceLanguage;
        final manualSourceLanguage = switch (sourceLanguage) {
          ExplicitSourceLanguage(:final language) => language,
          AutomaticSourceLanguageDetection() => null,
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LanguageControlRow(
              icon: Icons.record_voice_over_outlined,
              title: 'Source language',
              description: manualSourceLanguage == null
                  ? 'Automatic detection'
                  : _languageLabel(manualSourceLanguage, localizations),
              control: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<_SourceLanguageMode>(
                      key: const Key('source-language-mode-field'),
                      initialValue: manualSourceLanguage == null
                          ? _SourceLanguageMode.automatic
                          : _SourceLanguageMode.manual,
                      isDense: true,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 10,
                        ),
                      ),
                      onChanged: (mode) {
                        if (mode == _SourceLanguageMode.automatic) {
                          context
                              .read<ProjectSetupCubit>()
                              .selectAutomaticSourceLanguage();
                          return;
                        }
                        if (mode == _SourceLanguageMode.manual) {
                          _selectManualSourceLanguage(
                            context,
                            initialLanguage: manualSourceLanguage,
                          );
                        }
                      },
                      items: const [
                        DropdownMenuItem(
                          value: _SourceLanguageMode.automatic,
                          child: Text('Auto-detect'),
                        ),
                        DropdownMenuItem(
                          value: _SourceLanguageMode.manual,
                          child: Text('Manual'),
                        ),
                      ],
                    ),
                  ),
                  if (manualSourceLanguage != null)
                    IconButton(
                      tooltip: 'Choose source language',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _selectManualSourceLanguage(
                        context,
                        initialLanguage: manualSourceLanguage,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _LanguageControlRow(
              icon: Icons.translate_outlined,
              title: 'Target language',
              description: draft.targetLanguage == null
                  ? 'No target language selected'
                  : _languageLabel(draft.targetLanguage!, localizations),
              control: OutlinedButton(
                onPressed: () => _selectTargetLanguage(
                  context,
                  initialLanguage: draft.targetLanguage,
                ),
                child: const Text('Select target language'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectManualSourceLanguage(
    BuildContext context, {
    Language? initialLanguage,
  }) async {
    final language = await _showLanguageEntryDialog(
      context,
      title: 'Select source language',
      initialLanguage: initialLanguage,
    );
    if (language != null && context.mounted) {
      context.read<ProjectSetupCubit>().selectManualSourceLanguage(language);
    }
  }

  Future<void> _selectTargetLanguage(
    BuildContext context, {
    Language? initialLanguage,
  }) async {
    final language = await _showLanguageEntryDialog(
      context,
      title: 'Select target language',
      initialLanguage: initialLanguage,
    );
    if (language != null && context.mounted) {
      context.read<ProjectSetupCubit>().selectTargetLanguage(language);
    }
  }

  static String _languageLabel(
    Language language,
    AppLocalizations localizations,
  ) =>
      '${ApplicationLanguageCatalog.labelFor(language, localizations)} '
      '(${language.tag})';
}

enum _SourceLanguageMode { automatic, manual }

class _LanguageControlRow extends StatelessWidget {
  const _LanguageControlRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.control,
  });

  static const _compactWidth = 400.0;

  final IconData icon;
  final String title;
  final String description;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final details = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(description),
                ],
              ),
            ),
          ],
        );

        if (constraints.maxWidth < _compactWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              details,
              const SizedBox(height: AppSpacing.sm),
              Align(alignment: Alignment.centerRight, child: control),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: details),
            const SizedBox(width: AppSpacing.md),
            control,
          ],
        );
      },
    );
  }
}

Future<Language?> _showLanguageEntryDialog(
  BuildContext context, {
  required String title,
  Language? initialLanguage,
}) {
  return showDialog<Language>(
    context: context,
    builder: (context) =>
        _LanguageEntryDialog(title: title, initialLanguage: initialLanguage),
  );
}

class _LanguageEntryDialog extends StatefulWidget {
  const _LanguageEntryDialog({required this.title, this.initialLanguage});

  final String title;
  final Language? initialLanguage;

  @override
  State<_LanguageEntryDialog> createState() => _LanguageEntryDialogState();
}

class _LanguageEntryDialogState extends State<_LanguageEntryDialog> {
  late final TextEditingController _tagController;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _tagController = TextEditingController(text: widget.initialLanguage?.tag);
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final language = Language(tag: _tagController.text);
      Navigator.of(context).pop(language);
    } on ArgumentError catch (error) {
      setState(() {
        _validationMessage = error.message?.toString() ?? 'Enter a language.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('language-tag-field'),
            controller: _tagController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Language tag',
              hintText: 'For example: en or pt-BR',
              errorText: _validationMessage,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Use language')),
      ],
    );
  }
}
