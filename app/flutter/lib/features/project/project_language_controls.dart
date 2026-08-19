import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/common/models/application_language_catalog.dart';
import 'package:video_translator/common/models/language.dart';
import 'package:video_translator/features/project/project_draft.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

/// Renders project language choices from the application-owned language catalog.
///
/// Display labels are resolved from the catalog rather than stored with project
/// language values.
class ProjectLanguageControls extends StatelessWidget {
  const ProjectLanguageControls({super.key});

  static const _pickerWidth = 220.0;
  static const _menuHeight = 360.0;

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
              control: _SourceLanguagePicker(
                selection: sourceLanguage,
                localizations: localizations,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _LanguageControlRow(
              icon: Icons.translate_outlined,
              title: 'Target language',
              description: draft.targetLanguage == null
                  ? 'No target language selected'
                  : _languageLabel(draft.targetLanguage!, localizations),
              control: _TargetLanguagePicker(
                language: draft.targetLanguage,
                localizations: localizations,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SourceLanguagePicker extends StatelessWidget {
  const _SourceLanguagePicker({
    required this.selection,
    required this.localizations,
  });

  final SourceLanguageSelection selection;
  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<SourceLanguageSelection>(
      key: const Key('source-language-picker'),
      width: ProjectLanguageControls._pickerWidth,
      menuHeight: ProjectLanguageControls._menuHeight,
      initialSelection: selection,
      hintText: 'Select source language',
      enableFilter: true,
      filterCallback: _filterEntries,
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
      ),
      onSelected: (selection) {
        if (selection case AutomaticSourceLanguageDetection()) {
          context.read<ProjectSetupCubit>().selectAutomaticSourceLanguage();
        } else if (selection case ExplicitSourceLanguage(:final language)) {
          context.read<ProjectSetupCubit>().selectManualSourceLanguage(
            language,
          );
        }
      },
      dropdownMenuEntries: [
        const DropdownMenuEntry(
          value: SourceLanguageSelection.autoDetect(),
          label: 'Auto-detect',
        ),
        ...ApplicationLanguageCatalog.entries.map(
          (entry) => DropdownMenuEntry(
            value: SourceLanguageSelection.manual(entry.language),
            label: _languageLabel(entry.language, localizations),
          ),
        ),
      ],
    );
  }
}

class _TargetLanguagePicker extends StatelessWidget {
  const _TargetLanguagePicker({
    required this.language,
    required this.localizations,
  });

  final Language? language;
  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<Language>(
      key: const Key('target-language-picker'),
      width: ProjectLanguageControls._pickerWidth,
      menuHeight: ProjectLanguageControls._menuHeight,
      initialSelection: language,
      hintText: 'Select target language',
      enableFilter: true,
      filterCallback: _filterEntries,
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
      ),
      onSelected: (language) {
        if (language != null) {
          context.read<ProjectSetupCubit>().selectTargetLanguage(language);
        }
      },
      dropdownMenuEntries: ApplicationLanguageCatalog.entries
          .map(
            (entry) => DropdownMenuEntry(
              value: entry.language,
              label: _languageLabel(entry.language, localizations),
            ),
          )
          .toList(),
    );
  }
}

List<DropdownMenuEntry<T>> _filterEntries<T>(
  List<DropdownMenuEntry<T>> entries,
  String filter,
) {
  final query = filter.trim().toLowerCase();
  if (query.isEmpty) {
    return entries;
  }
  return entries
      .where((entry) => entry.label.toLowerCase().contains(query))
      .toList();
}

String _languageLabel(Language language, AppLocalizations localizations) =>
    '${ApplicationLanguageCatalog.labelFor(language, localizations)} '
    '(${language.tag})';

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
