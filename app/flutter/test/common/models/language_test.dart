import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/common/models/language.dart';

void main() {
  group('Language', () {
    test('normalizes and round-trips a canonical language tag', () {
      final language = Language(tag: 'zh-hans-cn');

      expect(language.tag, 'zh-Hans-CN');
      expect(language.toJson(), {'tag': 'zh-Hans-CN'});
      expect(Language.fromJson(language.toJson()), language);
    });

    test('uses the canonical tag as the complete value identity', () {
      expect(Language(tag: 'pt-br'), Language(tag: 'pt-BR'));
      expect(Language(tag: 'pt-BR').hashCode, Language(tag: 'pt-br').hashCode);
    });

    test('accepts BCP 47-compatible tags without a provider mapping', () {
      expect(Language(tag: 'abc').tag, 'abc');
    });

    test('reads legacy labels without making them application identity', () {
      final language = Language.fromJson(const {
        'code': 'vi',
        'displayName': 'An arbitrary label',
      });

      expect(language, Language(tag: 'vi'));
      expect(language.toJson(), {'tag': 'vi'});
    });

    test('rejects invalid language tags and malformed serialized values', () {
      for (final tag in [
        '',
        'en_US',
        'english',
        'e',
        'en--US',
        'en-US-extra',
      ]) {
        expect(() => Language(tag: tag), throwsArgumentError, reason: tag);
      }

      expect(
        () => Language.fromJson(const {'tag': 'en_US'}),
        throwsFormatException,
      );
      expect(
        () => Language.fromJson(const {'tag': 'en', 'displayName': 'English'}),
        throwsFormatException,
      );
    });
  });

  group('SourceLanguageSelection', () {
    test('keeps automatic detection distinct from an explicit language', () {
      final automatic = const SourceLanguageSelection.autoDetect();
      final manual = SourceLanguageSelection.manual(Language(tag: 'vi'));

      expect(automatic, isA<AutomaticSourceLanguageDetection>());
      expect(automatic, isNot(isA<Language>()));
      expect(manual, isA<ExplicitSourceLanguage>());
      expect((manual as ExplicitSourceLanguage).language.tag, 'vi');
      expect(automatic.toJson(), {'mode': 'auto'});
      expect(manual.toJson(), {
        'mode': 'manual',
        'language': {'tag': 'vi'},
      });
    });

    test(
      'round-trips source language selections and rejects invalid shapes',
      () {
        final selections = [
          const SourceLanguageSelection.autoDetect(),
          SourceLanguageSelection.manual(Language(tag: 'pt-BR')),
        ];

        for (final selection in selections) {
          expect(
            SourceLanguageSelection.fromJson(selection.toJson()),
            selection,
          );
        }

        expect(
          () => SourceLanguageSelection.fromJson(const {
            'mode': 'auto',
            'language': {'tag': 'en'},
          }),
          throwsFormatException,
        );
        expect(
          () => SourceLanguageSelection.fromJson(const {'mode': 'manual'}),
          throwsFormatException,
        );
      },
    );
  });
}
