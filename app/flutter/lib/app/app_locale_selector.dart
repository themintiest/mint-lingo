import 'package:flutter/material.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

/// Selects the application UI locale for the current run.
class AppLocaleSelector extends StatelessWidget {
  const AppLocaleSelector({
    super.key,
    required this.localeOverride,
    required this.onLocaleSelected,
  });

  final Locale? localeOverride;
  final ValueChanged<Locale> onLocaleSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final activeLanguageCode =
        localeOverride?.languageCode ??
        Localizations.localeOf(context).languageCode;

    return PopupMenuButton<Locale>(
      key: const Key('ui-language-selector'),
      tooltip: localizations.changeAppLanguage,
      icon: const Icon(Icons.language_outlined),
      onSelected: onLocaleSelected,
      itemBuilder: (context) => [
        _languageMenuItem(
          key: const Key('ui-language-option-en'),
          locale: const Locale('en'),
          label: localizations.languageEnglish,
          isActive: activeLanguageCode == 'en',
        ),
        _languageMenuItem(
          key: const Key('ui-language-option-vi'),
          locale: const Locale('vi'),
          label: localizations.languageVietnamese,
          isActive: activeLanguageCode == 'vi',
        ),
      ],
    );
  }

  PopupMenuItem<Locale> _languageMenuItem({
    required Key key,
    required Locale locale,
    required String label,
    required bool isActive,
  }) {
    return PopupMenuItem(
      key: key,
      value: locale,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: isActive ? const Icon(Icons.check, size: 18) : null,
          ),
          Text(label),
        ],
      ),
    );
  }
}
