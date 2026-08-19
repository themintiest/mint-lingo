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
    final targetLanguage = Language(tag: 'vi');
    final draft = ProjectDraft(
      source: const ProjectSourceReference(
        path: 'C:\\Videos\\source.mp4',
        fileName: 'source.mp4',
      ),
      sourceLanguage: SourceLanguageSelection.manual(Language(tag: 'en')),
      targetLanguage: targetLanguage,
    );

    expect(draft.source?.path, 'C:\\Videos\\source.mp4');
    expect(draft.sourceLanguage, isA<ExplicitSourceLanguage>());
    expect((draft.sourceLanguage as ExplicitSourceLanguage).language.tag, 'en');
    expect(draft.targetLanguage, targetLanguage);
  });

  test('compares drafts and source references by their immutable values', () {
    final first = ProjectDraft(
      source: const ProjectSourceReference(
        path: '/videos/source.mp4',
        fileName: 'source.mp4',
      ),
      targetLanguage: Language(tag: 'ja'),
    );
    final second = ProjectDraft(
      source: const ProjectSourceReference(
        path: '/videos/source.mp4',
        fileName: 'source.mp4',
      ),
      targetLanguage: Language(tag: 'ja'),
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('copies language selections without changing the source reference', () {
    const source = ProjectSourceReference(
      path: '/videos/source.mp4',
      fileName: 'source.mp4',
    );
    final sourceLanguage = Language(tag: 'en');
    final targetLanguage = Language(tag: 'vi');

    final draft = const ProjectDraft(source: source)
        .withSourceLanguage(SourceLanguageSelection.manual(sourceLanguage))
        .withTargetLanguage(targetLanguage);

    expect(draft.source, source);
    expect(draft.sourceLanguage, ExplicitSourceLanguage(sourceLanguage));
    expect(draft.targetLanguage, targetLanguage);
  });
}
