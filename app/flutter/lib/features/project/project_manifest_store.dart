import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Persists the Flutter-owned project manifest without interpreting its
/// workflow-specific contents.
///
/// The store deliberately accepts and returns a JSON object rather than a
/// Video or Document model. STORE-02's `workflow` discriminator chooses the
/// concrete section; this store preserves that section unchanged. It does not
/// validate manifest versions, workflow fields, artifact meaning, jobs, or
/// checkpoints.
final class ProjectManifestStore {
  ProjectManifestStore({
    Future<void> Function(File file, String contents)? writeTemporaryFile,
    Future<void> Function(File temporaryFile, File destination)?
    promoteTemporaryFile,
  }) : _writeTemporaryFile = writeTemporaryFile ?? _writeTemporaryFileToDisk,
       _promoteTemporaryFile =
           promoteTemporaryFile ?? _promoteTemporaryFileOnDisk;

  static const fileName = 'project.json';

  final Future<void> Function(File file, String contents) _writeTemporaryFile;
  final Future<void> Function(File temporaryFile, File destination)
  _promoteTemporaryFile;

  /// Loads the manifest from [projectDirectory], or returns `null` when it has
  /// not been saved yet.
  ///
  /// A malformed JSON document or a JSON value other than an object is not a
  /// project manifest and throws [ProjectManifestFormatException].
  Future<Map<String, Object?>?> load(Directory projectDirectory) async {
    final manifestFile = _manifestFile(projectDirectory);
    if (!await manifestFile.exists()) {
      return null;
    }

    try {
      final decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is! Map) {
        throw const ProjectManifestFormatException(
          'Project manifest root must be a JSON object.',
        );
      }

      return Map<String, Object?>.from(decoded);
    } on FormatException catch (error) {
      throw ProjectManifestFormatException(
        'Project manifest is not valid JSON: ${error.message}',
      );
    }
  }

  /// Saves [manifest] atomically within [projectDirectory].
  ///
  /// The JSON is encoded before any filesystem mutation. It is then flushed to
  /// a uniquely named sibling temporary file and promoted with a same-directory
  /// rename. A failure before promotion leaves an existing `project.json`
  /// untouched; the temporary file is cleaned up best-effort.
  Future<void> save(
    Directory projectDirectory,
    Map<String, Object?> manifest,
  ) async {
    final encoded = jsonEncode(manifest);
    final destination = _manifestFile(projectDirectory);
    final temporaryFile = await _createTemporaryFile(projectDirectory);

    try {
      await _writeTemporaryFile(temporaryFile, encoded);
      await _promoteTemporaryFile(temporaryFile, destination);
    } finally {
      try {
        if (await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      } on FileSystemException {
        // A failed cleanup cannot make an unpromoted temporary file appear as
        // the project's manifest. A later save can use a different name.
      }
    }
  }

  File _manifestFile(Directory projectDirectory) =>
      File('${projectDirectory.path}${Platform.pathSeparator}$fileName');

  Future<File> _createTemporaryFile(Directory projectDirectory) async {
    final random = Random.secure();
    for (var attempt = 0; attempt != 3; attempt++) {
      final temporaryFile = File(
        '${projectDirectory.path}${Platform.pathSeparator}'
        '.$fileName.${DateTime.now().microsecondsSinceEpoch}.${random.nextInt(1 << 32)}.tmp',
      );
      try {
        return await temporaryFile.create(exclusive: true);
      } on PathExistsException {
        // A collision is harmless; select a new sibling name and retry.
      }
    }

    throw FileSystemException(
      'Could not reserve a temporary project manifest file.',
      projectDirectory.path,
    );
  }

  static Future<void> _writeTemporaryFileToDisk(File file, String contents) =>
      file.writeAsString(contents, flush: true);

  static Future<void> _promoteTemporaryFileOnDisk(
    File temporaryFile,
    File destination,
  ) => temporaryFile.rename(destination.path);
}

final class ProjectManifestFormatException implements Exception {
  const ProjectManifestFormatException(this.message);

  final String message;

  @override
  String toString() => 'ProjectManifestFormatException: $message';
}
