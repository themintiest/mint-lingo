import 'package:video_translator/common/models/language.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

/// The maintained set of application language choices.
///
/// This is deliberately a practical product catalog, not a claim about every
/// provider's capabilities. Provider adapters remain responsible for mapping
/// these application-owned tags to their provider-specific values.
final class ApplicationLanguageCatalog {
  ApplicationLanguageCatalog._();

  static const entries = <ApplicationLanguageCatalogEntry>[
    ApplicationLanguageCatalogEntry(
      tag: 'en',
      label: ApplicationLanguageCatalogLabel.english,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'vi',
      label: ApplicationLanguageCatalogLabel.vietnamese,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'ja',
      label: ApplicationLanguageCatalogLabel.japanese,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'ko',
      label: ApplicationLanguageCatalogLabel.korean,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'zh-Hans',
      label: ApplicationLanguageCatalogLabel.chineseSimplified,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'zh-Hant',
      label: ApplicationLanguageCatalogLabel.chineseTraditional,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'pt-BR',
      label: ApplicationLanguageCatalogLabel.portugueseBrazil,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'pt-PT',
      label: ApplicationLanguageCatalogLabel.portuguesePortugal,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'fr',
      label: ApplicationLanguageCatalogLabel.french,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'de',
      label: ApplicationLanguageCatalogLabel.german,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'es',
      label: ApplicationLanguageCatalogLabel.spanish,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'it',
      label: ApplicationLanguageCatalogLabel.italian,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'ru',
      label: ApplicationLanguageCatalogLabel.russian,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'hi',
      label: ApplicationLanguageCatalogLabel.hindi,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'ar',
      label: ApplicationLanguageCatalogLabel.arabic,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'th',
      label: ApplicationLanguageCatalogLabel.thai,
    ),
    ApplicationLanguageCatalogEntry(
      tag: 'id',
      label: ApplicationLanguageCatalogLabel.indonesian,
    ),
  ];

  static ApplicationLanguageCatalogEntry? findByTag(String tag) {
    for (final entry in entries) {
      if (entry.language.tag == tag) {
        return entry;
      }
    }
    return null;
  }

  /// Resolves a catalog label for the current application UI locale.
  ///
  /// A tag entered through the temporary M2 free-form compatibility control is
  /// shown as its canonical tag until LANG-R03 removes that control.
  static String labelFor(Language language, AppLocalizations localizations) =>
      findByTag(language.tag)?.label.resolve(localizations) ?? language.tag;
}

final class ApplicationLanguageCatalogEntry {
  const ApplicationLanguageCatalogEntry({
    required this.tag,
    required this.label,
  });

  final String tag;
  final ApplicationLanguageCatalogLabel label;

  Language get language => Language(tag: tag);
}

enum ApplicationLanguageCatalogLabel {
  english,
  vietnamese,
  japanese,
  korean,
  chineseSimplified,
  chineseTraditional,
  portugueseBrazil,
  portuguesePortugal,
  french,
  german,
  spanish,
  italian,
  russian,
  hindi,
  arabic,
  thai,
  indonesian;

  String resolve(AppLocalizations localizations) => switch (this) {
    ApplicationLanguageCatalogLabel.english => localizations.languageEnglish,
    ApplicationLanguageCatalogLabel.vietnamese =>
      localizations.languageVietnamese,
    ApplicationLanguageCatalogLabel.japanese => localizations.languageJapanese,
    ApplicationLanguageCatalogLabel.korean => localizations.languageKorean,
    ApplicationLanguageCatalogLabel.chineseSimplified =>
      localizations.languageChineseSimplified,
    ApplicationLanguageCatalogLabel.chineseTraditional =>
      localizations.languageChineseTraditional,
    ApplicationLanguageCatalogLabel.portugueseBrazil =>
      localizations.languagePortugueseBrazil,
    ApplicationLanguageCatalogLabel.portuguesePortugal =>
      localizations.languagePortuguesePortugal,
    ApplicationLanguageCatalogLabel.french => localizations.languageFrench,
    ApplicationLanguageCatalogLabel.german => localizations.languageGerman,
    ApplicationLanguageCatalogLabel.spanish => localizations.languageSpanish,
    ApplicationLanguageCatalogLabel.italian => localizations.languageItalian,
    ApplicationLanguageCatalogLabel.russian => localizations.languageRussian,
    ApplicationLanguageCatalogLabel.hindi => localizations.languageHindi,
    ApplicationLanguageCatalogLabel.arabic => localizations.languageArabic,
    ApplicationLanguageCatalogLabel.thai => localizations.languageThai,
    ApplicationLanguageCatalogLabel.indonesian =>
      localizations.languageIndonesian,
  };
}
