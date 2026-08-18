import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/features/project/project_draft.dart';

sealed class ProjectSetupState {
  const ProjectSetupState();

  ProjectDraft? get draft;
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
/// A draft is considered configured when one is supplied. Required-value and
/// media validation are intentionally deferred to their dedicated tasks.
final class ProjectSetupCubit extends Cubit<ProjectSetupState> {
  ProjectSetupCubit() : super(const ProjectSetupEmpty());

  void beginSourceSelection() {
    emit(ProjectSetupSelecting(draft: state.draft));
  }

  void configure(ProjectDraft draft) {
    emit(ProjectSetupConfigured(draft));
  }

  void reportError(Object error) {
    emit(ProjectSetupError(error: error, draft: state.draft));
  }

  void clear() {
    emit(const ProjectSetupEmpty());
  }
}
