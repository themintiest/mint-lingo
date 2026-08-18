import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/common/models/language.dart';
import 'package:video_translator/features/project/project_draft.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';

/// Renders project language choices without assuming a provider language catalog.
///
/// Provider capability-driven lists will replace free-form entry in a later task.
class ProjectLanguageControls extends StatelessWidget {
  const ProjectLanguageControls({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProjectSetupCubit, ProjectSetupState>(
      builder: (context, state) {
        final draft = state.draft ?? const ProjectDraft();
        final sourceLanguage = draft.sourceLanguage;
        final manualSourceLanguage = switch (sourceLanguage) {
          ExplicitSourceLanguage(:final language) => language,
          AutomaticSourceLanguageDetection() => null,
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.record_voice_over_outlined),
              title: const Text('Source language'),
              subtitle: Text(
                manualSourceLanguage == null
                    ? 'Automatic detection'
                    : _languageLabel(manualSourceLanguage),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<_SourceLanguageMode>(
                    value: manualSourceLanguage == null
                        ? _SourceLanguageMode.automatic
                        : _SourceLanguageMode.manual,
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
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.translate_outlined),
              title: const Text('Target language'),
              subtitle: Text(
                draft.targetLanguage == null
                    ? 'No target language selected'
                    : _languageLabel(draft.targetLanguage!),
              ),
              trailing: OutlinedButton(
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

  static String _languageLabel(Language language) =>
      '${language.displayName} (${language.code})';
}

enum _SourceLanguageMode { automatic, manual }

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
  late final TextEditingController _codeController;
  late final TextEditingController _displayNameController;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.initialLanguage?.code);
    _displayNameController = TextEditingController(
      text: widget.initialLanguage?.displayName,
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final language = Language(
        code: _codeController.text,
        displayName: _displayNameController.text,
      );
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
            key: const Key('language-code-field'),
            controller: _codeController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Language code',
              hintText: 'For example: en or pt-BR',
              errorText: _validationMessage,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('language-display-name-field'),
            controller: _displayNameController,
            decoration: const InputDecoration(labelText: 'Display name'),
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
