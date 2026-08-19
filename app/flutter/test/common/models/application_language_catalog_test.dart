import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/common/models/application_language_catalog.dart';
import 'package:video_translator/common/models/language.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

void main() {
  test('has unique canonical tags and expected practical entries', () {
    final tags = ApplicationLanguageCatalog.entries
        .map((entry) => entry.language.tag)
        .toList();

    expect(tags.toSet(), hasLength(tags.length));
    expect(tags, containsAll(['en', 'vi', 'ja', 'ko', 'zh-Hans', 'zh-Hant']));
    expect(tags, containsAll(['pt-BR', 'pt-PT']));
  });

  test('resolves catalog labels through the application UI locale', () async {
    final english = await AppLocalizations.delegate.load(const Locale('en'));
    final vietnamese = await AppLocalizations.delegate.load(const Locale('vi'));

    expect(
      ApplicationLanguageCatalog.labelFor(Language(tag: 'vi'), english),
      'Vietnamese',
    );
    expect(
      ApplicationLanguageCatalog.labelFor(Language(tag: 'vi'), vietnamese),
      'Tiếng Việt',
    );
    expect(
      ApplicationLanguageCatalog.labelFor(Language(tag: 'abc'), english),
      'abc',
    );
  });
}
