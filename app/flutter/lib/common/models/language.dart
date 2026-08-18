/// A provider-neutral language value used for source and target selections.
///
/// The code follows the supported BCP 47 profile: a two- or three-letter
/// primary language subtag, optionally followed by a script subtag and a
/// region subtag. The model validates only this syntax; providers decide which
/// syntactically valid languages they support.
final class Language {
  Language({required String code, required String displayName})
    : code = _normalizeCode(code),
      displayName = _normalizeDisplayName(displayName);

  final String code;
  final String displayName;

  factory Language.fromJson(Map<String, Object?> json) {
    if (!_hasExactKeys(json, const {'code', 'displayName'})) {
      throw const FormatException(
        'A language must contain code and displayName.',
      );
    }

    final code = json['code'];
    final displayName = json['displayName'];
    if (code is! String || displayName is! String) {
      throw const FormatException(
        'Language code and displayName must be strings.',
      );
    }

    try {
      return Language(code: code, displayName: displayName);
    } on ArgumentError catch (error) {
      throw FormatException('Invalid language: $error');
    }
  }

  Map<String, String> toJson() => {'code': code, 'displayName': displayName};

  static String _normalizeCode(String value) {
    if (value.isEmpty || value.trim() != value) {
      throw ArgumentError.value(value, 'code', 'must not be empty or padded');
    }

    final subtags = value.split('-');
    if (subtags.any((subtag) => subtag.isEmpty) ||
        !_isPrimarySubtag(subtags.first)) {
      throw ArgumentError.value(
        value,
        'code',
        'has an unsupported language-tag format',
      );
    }

    var index = 1;
    String? script;
    String? region;
    if (index < subtags.length && _isScriptSubtag(subtags[index])) {
      script = subtags[index];
      index++;
    }
    if (index < subtags.length && _isRegionSubtag(subtags[index])) {
      region = subtags[index];
      index++;
    }
    if (index != subtags.length) {
      throw ArgumentError.value(
        value,
        'code',
        'has an unsupported language-tag format',
      );
    }

    return [
      subtags.first.toLowerCase(),
      if (script != null) _toTitleCase(script),
      if (region != null) _normalizeRegion(region),
    ].join('-');
  }

  static String _normalizeDisplayName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'displayName', 'must not be blank');
    }
    return normalized;
  }

  static bool _isPrimarySubtag(String value) =>
      RegExp(r'^[A-Za-z]{2,3}$').hasMatch(value);

  static bool _isScriptSubtag(String value) =>
      RegExp(r'^[A-Za-z]{4}$').hasMatch(value);

  static bool _isRegionSubtag(String value) =>
      RegExp(r'^(?:[A-Za-z]{2}|[0-9]{3})$').hasMatch(value);

  static String _toTitleCase(String value) =>
      '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';

  static String _normalizeRegion(String value) =>
      RegExp(r'^[0-9]{3}$').hasMatch(value) ? value : value.toUpperCase();

  @override
  bool operator ==(Object other) =>
      other is Language &&
      other.code == code &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(code, displayName);
}

/// A source-language choice that is either explicit or left to the provider.
sealed class SourceLanguageSelection {
  const SourceLanguageSelection();

  const factory SourceLanguageSelection.autoDetect() =
      AutomaticSourceLanguageDetection;

  const factory SourceLanguageSelection.manual(Language language) =
      ExplicitSourceLanguage;

  factory SourceLanguageSelection.fromJson(Map<String, Object?> json) {
    final mode = json['mode'];
    if (mode == 'auto' && _hasExactKeys(json, const {'mode'})) {
      return const SourceLanguageSelection.autoDetect();
    }
    if (mode == 'manual' && _hasExactKeys(json, const {'mode', 'language'})) {
      final language = json['language'];
      if (language is! Map) {
        throw const FormatException(
          'A manual source language requires a language.',
        );
      }
      return SourceLanguageSelection.manual(
        Language.fromJson(Map<String, Object?>.from(language)),
      );
    }
    throw const FormatException('Invalid source language selection.');
  }

  Map<String, Object?> toJson();
}

/// A source-language choice that leaves detection to the transcription provider.
final class AutomaticSourceLanguageDetection extends SourceLanguageSelection {
  const AutomaticSourceLanguageDetection();

  @override
  Map<String, Object?> toJson() => const {'mode': 'auto'};

  @override
  bool operator ==(Object other) => other is AutomaticSourceLanguageDetection;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// A source-language choice with a specific language selected by the user.
final class ExplicitSourceLanguage extends SourceLanguageSelection {
  const ExplicitSourceLanguage(this.language);

  final Language language;

  @override
  Map<String, Object?> toJson() => {
    'mode': 'manual',
    'language': language.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is ExplicitSourceLanguage && other.language == language;

  @override
  int get hashCode => language.hashCode;
}

bool _hasExactKeys(Map<String, Object?> json, Set<String> expectedKeys) =>
    json.length == expectedKeys.length &&
    json.keys.toSet().containsAll(expectedKeys);
