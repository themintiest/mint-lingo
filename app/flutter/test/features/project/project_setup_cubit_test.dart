import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/common/models/language.dart';
import 'package:video_translator/features/project/project_draft.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';

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
}
