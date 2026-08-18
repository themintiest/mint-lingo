import 'package:file_selector/file_selector.dart';
import 'package:video_translator/features/project/project_draft.dart';

abstract interface class SourceVideoPicker {
  Future<ProjectSourceReference?> pickSourceVideo();
}

/// Uses the operating system's native file dialog to select a single video.
///
/// This boundary returns path metadata only. It never loads the selected file's
/// contents, leaving media access and validation to later processing tasks.
final class FileSelectorSourceVideoPicker implements SourceVideoPicker {
  const FileSelectorSourceVideoPicker();

  static const _videoTypeGroup = XTypeGroup(
    label: 'Video files',
    extensions: ['avi', 'm4v', 'mkv', 'mov', 'mp4', 'mpeg', 'mpg', 'webm'],
  );

  @override
  Future<ProjectSourceReference?> pickSourceVideo() async {
    final selectedFile = await openFile(
      acceptedTypeGroups: const [_videoTypeGroup],
    );
    if (selectedFile == null) {
      return null;
    }
    if (selectedFile.path.isEmpty) {
      throw StateError('The selected video does not provide a local path.');
    }
    return ProjectSourceReference(
      path: selectedFile.path,
      fileName: selectedFile.name,
    );
  }
}
