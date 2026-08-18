import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/common/models/language.dart';
import 'package:video_translator/features/project/project_draft.dart';
import 'package:video_translator/features/project/source_video_picker.dart';

sealed class ProjectSetupState {
  const ProjectSetupState();

  ProjectDraft? get draft;
}

enum ProjectSetupValidationIssue {
  sourceRequired('Select a source video before processing.'),
  targetLanguageRequired('Select a target language before processing.');

  const ProjectSetupValidationIssue(this.message);

  final String message;
}

/// Describes the missing project values that prevent processing from starting.
final class ProjectSetupValidationError implements Exception {
  ProjectSetupValidationError(Iterable<ProjectSetupValidationIssue> issues)
    : issues = List.unmodifiable(issues) {
    if (this.issues.isEmpty) {
      throw ArgumentError.value(issues, 'issues', 'must not be empty');
    }
  }

  final List<ProjectSetupValidationIssue> issues;

  String get message => issues.map((issue) => issue.message).join('\n');
}

final class ProjectSetupEmpty extends ProjectSetupState {
  const ProjectSetupEmpty();

  @override
  ProjectDraft? get draft => null;

  @override
  bool operator ==(Object other) => other is ProjectSetupEmpty;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class ProjectSetupSelecting extends ProjectSetupState {
  const ProjectSetupSelecting({this.draft});

  @override
  final ProjectDraft? draft;

  @override
  bool operator ==(Object other) =>
      other is ProjectSetupSelecting && other.draft == draft;

  @override
  int get hashCode => Object.hash(runtimeType, draft);
}

final class ProjectSetupConfigured extends ProjectSetupState {
  const ProjectSetupConfigured(this.draft);

  @override
  final ProjectDraft draft;

  @override
  bool operator ==(Object other) =>
      other is ProjectSetupConfigured && other.draft == draft;

  @override
  int get hashCode => Object.hash(runtimeType, draft);
}

final class ProjectSetupError extends ProjectSetupState {
  const ProjectSetupError({required this.error, this.draft});

  final Object error;

  @override
  final ProjectDraft? draft;

  @override
  bool operator ==(Object other) =>
      other is ProjectSetupError &&
      other.error == error &&
      other.draft == draft;

  @override
  int get hashCode => Object.hash(runtimeType, error, draft);
}

/// Coordinates the in-memory project setup flow without performing file I/O.
///
/// A draft is considered configured when one is supplied. It may still be
/// incomplete until [validateForProcessing] confirms required setup values.
final class ProjectSetupCubit extends Cubit<ProjectSetupState> {
  ProjectSetupCubit({SourceVideoPicker? sourceVideoPicker})
    : _sourceVideoPicker =
          sourceVideoPicker ?? const FileSelectorSourceVideoPicker(),
      super(const ProjectSetupEmpty());

  final SourceVideoPicker _sourceVideoPicker;

  void beginSourceSelection() {
    emit(ProjectSetupSelecting(draft: state.draft));
  }

  Future<void> selectSourceVideo() async {
    if (state is ProjectSetupSelecting) {
      return;
    }

    final existingDraft = state.draft;
    beginSourceSelection();
    try {
      final source = await _sourceVideoPicker.pickSourceVideo();
      if (isClosed) {
        return;
      }
      if (source == null) {
        _restoreDraft(existingDraft);
        return;
      }
      configure((existingDraft ?? const ProjectDraft()).withSource(source));
    } on Object catch (error) {
      if (!isClosed) {
        reportError(error);
      }
    }
  }

  void configure(ProjectDraft draft) {
    emit(ProjectSetupConfigured(draft));
  }

  void selectAutomaticSourceLanguage() {
    configure(
      _draftForConfiguration.withSourceLanguage(
        const SourceLanguageSelection.autoDetect(),
      ),
    );
  }

  void selectManualSourceLanguage(Language language) {
    configure(
      _draftForConfiguration.withSourceLanguage(
        SourceLanguageSelection.manual(language),
      ),
    );
  }

  void selectTargetLanguage(Language language) {
    configure(_draftForConfiguration.withTargetLanguage(language));
  }

  /// Verifies the required setup values before processing can begin.
  ///
  /// Media validation remains a later Python-owned responsibility.
  bool validateForProcessing() {
    final draft = state.draft;
    final issues = <ProjectSetupValidationIssue>[
      if (draft?.source == null) ProjectSetupValidationIssue.sourceRequired,
      if (draft?.targetLanguage == null)
        ProjectSetupValidationIssue.targetLanguageRequired,
    ];
    if (issues.isEmpty) {
      return true;
    }

    emit(
      ProjectSetupError(
        error: ProjectSetupValidationError(issues),
        draft: draft,
      ),
    );
    return false;
  }

  void reportError(Object error) {
    emit(ProjectSetupError(error: error, draft: state.draft));
  }

  void clear() {
    emit(const ProjectSetupEmpty());
  }

  void _restoreDraft(ProjectDraft? draft) {
    if (draft == null) {
      clear();
      return;
    }
    configure(draft);
  }

  ProjectDraft get _draftForConfiguration =>
      state.draft ?? const ProjectDraft();
}
