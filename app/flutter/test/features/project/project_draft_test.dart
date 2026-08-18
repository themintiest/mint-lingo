import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/common/models/language.dart';
import 'package:video_translator/features/project/project_draft.dart';

void main() {
  test('starts as an incomplete draft with automatic source detection', () {
    const draft = ProjectDraft();

    expect(draft.source, isNull);
    expect(draft.sourceLanguage, isA<AutomaticSourceLanguageDetection>());
    expect(draft.targetLanguage, isNull);
  });

  test('keeps source, source selection, and target language independent', () {
    final targetLanguage = Language(code: 'vi', displayName: 'Vietnamese');
    final draft = ProjectDraft(
      source: const ProjectSourceReference(
        path: 'C:\\Videos\\source.mp4',
        fileName: 'source.mp4',
      ),
      sourceLanguage: SourceLanguageSelection.manual(
        Language(code: 'en', displayName: 'English'),
      ),
      targetLanguage: targetLanguage,
    );

    expect(draft.source?.path, 'C:\\Videos\\source.mp4');
    expect(draft.sourceLanguage, isA<ExplicitSourceLanguage>());
    expect(
      (draft.sourceLanguage as ExplicitSourceLanguage).language.code,
      'en',
    );
    expect(draft.targetLanguage, targetLanguage);
  });

  test('compares drafts and source references by their immutable values', () {
    final first = ProjectDraft(
      source: const ProjectSourceReference(
        path: '/videos/source.mp4',
        fileName: 'source.mp4',
      ),
      targetLanguage: Language(code: 'ja', displayName: 'Japanese'),
    );
    final second = ProjectDraft(
      source: const ProjectSourceReference(
        path: '/videos/source.mp4',
        fileName: 'source.mp4',
      ),
      targetLanguage: Language(code: 'ja', displayName: 'Japanese'),
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });
}
