import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/features/project/project_manifest_store.dart';

void main() {
  test('returns no saved manifest when project.json is absent', () async {
    final projectDirectory = await _temporaryProjectDirectory();
    addTearDown(() => projectDirectory.delete(recursive: true));

    expect(await ProjectManifestStore().load(projectDirectory), isNull);
  });

  test('round-trips an opaque concrete Document workflow section', () async {
    final projectDirectory = await _temporaryProjectDirectory();
    addTearDown(() => projectDirectory.delete(recursive: true));
    final store = ProjectManifestStore();
    final manifest = _documentManifest();

    await store.save(projectDirectory, manifest);

    expect(await store.load(projectDirectory), manifest);
    expect(
      await projectDirectory
          .list()
          .where((entity) => entity.path.endsWith('.tmp'))
          .isEmpty,
      isTrue,
    );
  });

  test(
    'keeps the previous manifest when temporary writing is interrupted',
    () async {
      final projectDirectory = await _temporaryProjectDirectory();
      addTearDown(() => projectDirectory.delete(recursive: true));
      final initialManifest = _documentManifest();
      final stableStore = ProjectManifestStore();
      await stableStore.save(projectDirectory, initialManifest);
      final interruptedStore = ProjectManifestStore(
        writeTemporaryFile: (file, _) async {
          await file.writeAsString('{"partial":', flush: true);
          throw const FileSystemException('Simulated interrupted write.');
        },
      );

      await expectLater(
        () => interruptedStore.save(projectDirectory, _videoManifest()),
        throwsA(isA<FileSystemException>()),
      );

      expect(await stableStore.load(projectDirectory), initialManifest);
      expect(
        await projectDirectory
            .list()
            .where((entity) => entity.path.endsWith('.tmp'))
            .isEmpty,
        isTrue,
      );
    },
  );

  test(
    'replaces a complete manifest only after a complete temporary write',
    () async {
      final projectDirectory = await _temporaryProjectDirectory();
      addTearDown(() => projectDirectory.delete(recursive: true));
      final store = ProjectManifestStore();

      await store.save(projectDirectory, _documentManifest());
      await store.save(projectDirectory, _videoManifest());

      expect(await store.load(projectDirectory), _videoManifest());
    },
  );

  test('rejects a non-object JSON manifest', () async {
    final projectDirectory = await _temporaryProjectDirectory();
    addTearDown(() => projectDirectory.delete(recursive: true));
    final manifestFile = File(
      '${projectDirectory.path}${Platform.pathSeparator}'
      '${ProjectManifestStore.fileName}',
    );
    await manifestFile.writeAsString('[]');

    await expectLater(
      () => ProjectManifestStore().load(projectDirectory),
      throwsA(isA<ProjectManifestFormatException>()),
    );
  });
}

Future<Directory> _temporaryProjectDirectory() =>
    Directory.systemTemp.createTemp('project-manifest-store-test-');

Map<String, Object?> _documentManifest() => {
  'manifestVersion': 1,
  'workflow': 'documentTranslation',
  'source': {
    'reference': {'kind': 'localFile', 'path': r'C:\source\book.epub'},
    'configuration': {},
  },
  'configuration': {
    'languages': {
      'source': {'mode': 'autoDetect'},
      'target': {'tag': 'vi'},
    },
  },
  'processingReferences': {
    'retainedArtifacts': [
      {'reference': 'artifacts/document/opaque-package.json'},
    ],
  },
  'workflowState': {
    'documentTranslation': {
      'format': 'epub',
      'state': {'futureFormatOwnedValue': 'preserved without interpretation'},
      'artifactReferences': [
        {'reference': 'artifacts/document/epub-content.bin'},
      ],
    },
  },
};

Map<String, Object?> _videoManifest() => {
  'manifestVersion': 1,
  'workflow': 'videoTranslation',
  'source': {
    'reference': {'kind': 'localFile', 'path': r'C:\source\clip.mp4'},
    'configuration': {},
  },
  'configuration': {
    'languages': {
      'source': {'mode': 'explicit', 'tag': 'en'},
      'target': {'tag': 'vi'},
    },
  },
  'processingReferences': {'retainedArtifacts': []},
  'workflowState': {
    'videoTranslation': {
      'state': {'futureVideoOwnedValue': 'preserved without interpretation'},
      'artifactReferences': [],
    },
  },
};
