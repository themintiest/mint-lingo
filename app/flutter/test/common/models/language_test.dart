import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/common/models/language.dart';

void main() {
  group('Language', () {
    test(
      'normalizes and round-trips a valid provider-neutral language tag',
      () {
        final language = Language(
          code: 'zh-hans-cn',
          displayName: '  Simplified Chinese (China)  ',
        );

        expect(language.code, 'zh-Hans-CN');
        expect(language.displayName, 'Simplified Chinese (China)');
        expect(language.toJson(), {
          'code': 'zh-Hans-CN',
          'displayName': 'Simplified Chinese (China)',
        });
        expect(Language.fromJson(language.toJson()), language);
      },
    );

    test(
      'accepts provider-defined language codes without a hard-coded list',
      () {
        final language = Language(
          code: 'abc',
          displayName: 'Provider-defined language',
        );

        expect(language.code, 'abc');
      },
    );

    test('rejects invalid language codes and malformed serialized values', () {
      for (final code in [
        '',
        'en_US',
        'english',
        'e',
        'en--US',
        'en-US-extra',
      ]) {
        expect(
          () => Language(code: code, displayName: 'English'),
          throwsArgumentError,
          reason: code,
        );
      }

      expect(
        () => Language.fromJson(const {
          'code': 'en_US',
          'displayName': 'English',
        }),
        throwsFormatException,
      );
      expect(
        () => Language.fromJson(const {'code': 'en'}),
        throwsFormatException,
      );
    });
  });

  group('SourceLanguageSelection', () {
    test('keeps automatic detection distinct from an explicit language', () {
      final automatic = const SourceLanguageSelection.autoDetect();
      final manual = SourceLanguageSelection.manual(
        Language(code: 'vi', displayName: 'Vietnamese'),
      );

      expect(automatic, isA<AutomaticSourceLanguageDetection>());
      expect(automatic, isNot(isA<Language>()));
      expect(manual, isA<ExplicitSourceLanguage>());
      expect((manual as ExplicitSourceLanguage).language.code, 'vi');
      expect(automatic.toJson(), {'mode': 'auto'});
      expect(manual.toJson(), {
        'mode': 'manual',
        'language': {'code': 'vi', 'displayName': 'Vietnamese'},
      });
    });

    test(
      'round-trips source language selections and rejects invalid shapes',
      () {
        final selections = [
          const SourceLanguageSelection.autoDetect(),
          SourceLanguageSelection.manual(
            Language(code: 'pt-BR', displayName: 'Brazilian Portuguese'),
          ),
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
            'language': {'code': 'en', 'displayName': 'English'},
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
