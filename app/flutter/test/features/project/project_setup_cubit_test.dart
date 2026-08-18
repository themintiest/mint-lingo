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
        targetLanguage: Language(code: 'vi', displayName: 'Vietnamese'),
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
    final draft = ProjectDraft(
      targetLanguage: Language(code: 'ja', displayName: 'Japanese'),
    );
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
    cubit.configure(
      ProjectDraft(
        targetLanguage: Language(code: 'ko', displayName: 'Korean'),
      ),
    );

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
      final target = Language(code: 'vi', displayName: 'Vietnamese');
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
