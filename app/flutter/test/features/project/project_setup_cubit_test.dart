import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/common/models/language.dart';
import 'package:video_translator/features/project/project_draft.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';
import 'package:video_translator/features/project/source_video_picker.dart';

void main() {
  late ProjectSetupCubit cubit;

  setUp(() {
    cubit = ProjectSetupCubit();
  });

  tearDown(() => cubit.close());

  test('starts empty', () {
    expect(cubit.state, const ProjectSetupEmpty());
  });

  test(
    'transitions from selecting to configured with the supplied draft',
    () async {
      final draft = ProjectDraft(
        source: const ProjectSourceReference(
          path: '/videos/source.mp4',
          fileName: 'source.mp4',
        ),
        targetLanguage: Language(tag: 'vi'),
      );

      final states = expectLater(
        cubit.stream,
        emitsInOrder([
          const ProjectSetupSelecting(),
          ProjectSetupConfigured(draft),
        ]),
      );

      cubit.beginSourceSelection();
      cubit.configure(draft);

      await states;
      expect(cubit.state, ProjectSetupConfigured(draft));
    },
  );

  test('retains the current draft when selection reports an error', () async {
    final draft = ProjectDraft(targetLanguage: Language(tag: 'ja'));
    final error = StateError('Source selection failed.');
    cubit.configure(draft);

    final states = expectLater(
      cubit.stream,
      emitsInOrder([
        ProjectSetupSelecting(draft: draft),
        ProjectSetupError(error: error, draft: draft),
      ]),
    );

    cubit.beginSourceSelection();
    cubit.reportError(error);

    await states;
    expect(cubit.state, ProjectSetupError(error: error, draft: draft));
  });

  test('returns to empty when cleared', () async {
    cubit.configure(ProjectDraft(targetLanguage: Language(tag: 'ko')));

    final states = expectLater(cubit.stream, emits(const ProjectSetupEmpty()));

    cubit.clear();

    await states;
    expect(cubit.state, const ProjectSetupEmpty());
  });

  test(
    'selects and replaces one source without changing language choices',
    () async {
      final sourcePicker = _FakeSourceVideoPicker([
        const ProjectSourceReference(
          path: '/videos/first.mp4',
          fileName: 'first.mp4',
        ),
        const ProjectSourceReference(
          path: '/videos/second.mp4',
          fileName: 'second.mp4',
        ),
      ]);
      await cubit.close();
      cubit = ProjectSetupCubit(sourceVideoPicker: sourcePicker);
      final target = Language(tag: 'vi');
      cubit.configure(ProjectDraft(targetLanguage: target));

      await cubit.selectSourceVideo();
      await cubit.selectSourceVideo();

      final configured = cubit.state as ProjectSetupConfigured;
      expect(configured.draft.source?.path, '/videos/second.mp4');
      expect(configured.draft.targetLanguage, target);
    },
  );

  test('treats a canceled source selection as a no-op', () async {
    await cubit.close();
    cubit = ProjectSetupCubit(
      sourceVideoPicker: _FakeSourceVideoPicker([null]),
    );
    final draft = ProjectDraft(
      source: const ProjectSourceReference(
        path: '/videos/source.mp4',
        fileName: 'source.mp4',
      ),
    );
    cubit.configure(draft);

    await cubit.selectSourceVideo();

    expect(cubit.state, ProjectSetupConfigured(draft));
  });

  test('maps a source-picker failure to the error state', () async {
    final error = StateError('Native picker failed.');
    await cubit.close();
    cubit = ProjectSetupCubit(
      sourceVideoPicker: _FakeSourceVideoPicker([], error: error),
    );

    await cubit.selectSourceVideo();

    expect(cubit.state, ProjectSetupError(error: error));
  });

  test(
    'sets a manual source language without changing the source or target',
    () {
      const source = ProjectSourceReference(
        path: '/videos/source.mp4',
        fileName: 'source.mp4',
      );
      final targetLanguage = Language(tag: 'vi');
      final sourceLanguage = Language(tag: 'en');
      cubit.configure(
        ProjectDraft(source: source, targetLanguage: targetLanguage),
      );

      cubit.selectManualSourceLanguage(sourceLanguage);

      final draft = (cubit.state as ProjectSetupConfigured).draft;
      expect(draft.source, source);
      expect(draft.sourceLanguage, ExplicitSourceLanguage(sourceLanguage));
      expect(draft.targetLanguage, targetLanguage);
    },
  );

  test(
    'returns source language to automatic detection without target changes',
    () {
      final sourceLanguage = Language(tag: 'en');
      final targetLanguage = Language(tag: 'vi');
      cubit.configure(
        ProjectDraft(
          sourceLanguage: SourceLanguageSelection.manual(sourceLanguage),
          targetLanguage: targetLanguage,
        ),
      );

      cubit.selectAutomaticSourceLanguage();

      final draft = (cubit.state as ProjectSetupConfigured).draft;
      expect(draft.sourceLanguage, const SourceLanguageSelection.autoDetect());
      expect(draft.targetLanguage, targetLanguage);
    },
  );

  test('sets an explicit target language from an incomplete draft', () {
    final targetLanguage = Language(tag: 'ja');

    cubit.selectTargetLanguage(targetLanguage);

    final draft = (cubit.state as ProjectSetupConfigured).draft;
    expect(draft.sourceLanguage, const SourceLanguageSelection.autoDetect());
    expect(draft.targetLanguage, targetLanguage);
  });

  test('blocks processing with actionable missing-value messages', () {
    expect(cubit.validateForProcessing(), isFalse);

    final error = (cubit.state as ProjectSetupError).error;
    expect(error, isA<ProjectSetupValidationError>());
    expect((error as ProjectSetupValidationError).issues, [
      ProjectSetupValidationIssue.sourceRequired,
      ProjectSetupValidationIssue.targetLanguageRequired,
    ]);
    expect(error.message, contains('Select a source video'));
    expect(error.message, contains('Select a target language'));
  });

  test('reports only a missing source video', () {
    cubit.configure(ProjectDraft(targetLanguage: Language(tag: 'vi')));

    expect(cubit.validateForProcessing(), isFalse);

    final error =
        (cubit.state as ProjectSetupError).error as ProjectSetupValidationError;
    expect(error.issues, [ProjectSetupValidationIssue.sourceRequired]);
  });

  test('reports only a missing target language', () {
    cubit.configure(
      const ProjectDraft(
        source: ProjectSourceReference(
          path: '/videos/source.mp4',
          fileName: 'source.mp4',
        ),
      ),
    );

    expect(cubit.validateForProcessing(), isFalse);

    final error =
        (cubit.state as ProjectSetupError).error as ProjectSetupValidationError;
    expect(error.issues, [ProjectSetupValidationIssue.targetLanguageRequired]);
  });

  test('allows processing only after the source and target are selected', () {
    cubit.configure(
      ProjectDraft(
        source: const ProjectSourceReference(
          path: '/videos/source.mp4',
          fileName: 'source.mp4',
        ),
        targetLanguage: Language(tag: 'vi'),
      ),
    );

    expect(cubit.validateForProcessing(), isTrue);
    expect(cubit.state, isA<ProjectSetupConfigured>());
  });
}

final class _FakeSourceVideoPicker implements SourceVideoPicker {
  _FakeSourceVideoPicker(this._sources, {this.error});

  final List<ProjectSourceReference?> _sources;
  final Object? error;

  @override
  Future<ProjectSourceReference?> pickSourceVideo() async {
    if (error != null) {
      throw error!;
    }
    return _sources.removeAt(0);
  }
}
