import 'package:video_translator/common/models/language.dart';

/// An immutable reference to the video selected for a project.
///
/// This model only describes the selected source. File existence, readability,
/// and media validation belong to later project and media tasks.
final class ProjectSourceReference {
  const ProjectSourceReference({required this.path, required this.fileName});

  final String path;
  final String fileName;

  @override
  bool operator ==(Object other) =>
      other is ProjectSourceReference &&
      other.path == path &&
      other.fileName == fileName;

  @override
  int get hashCode => Object.hash(path, fileName);
}

/// The in-memory, potentially incomplete configuration for one video project.
///
/// A draft can exist before the user selects a video or target language. Source
/// language selection is independent so automatic detection cannot be treated
/// as a target language.
final class ProjectDraft {
  const ProjectDraft({
    this.source,
    this.sourceLanguage = const SourceLanguageSelection.autoDetect(),
    this.targetLanguage,
  });

  final ProjectSourceReference? source;
  final SourceLanguageSelection sourceLanguage;
  final Language? targetLanguage;

  ProjectDraft withSource(ProjectSourceReference source) => ProjectDraft(
    source: source,
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
  );

  ProjectDraft withSourceLanguage(SourceLanguageSelection sourceLanguage) =>
      ProjectDraft(
        source: source,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );

  ProjectDraft withTargetLanguage(Language targetLanguage) => ProjectDraft(
    source: source,
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
  );

  @override
  bool operator ==(Object other) =>
      other is ProjectDraft &&
      other.source == source &&
      other.sourceLanguage == sourceLanguage &&
      other.targetLanguage == targetLanguage;

  @override
  int get hashCode => Object.hash(source, sourceLanguage, targetLanguage);
}
