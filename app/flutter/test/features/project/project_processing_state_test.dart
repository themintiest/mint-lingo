import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/features/project/project_manifest_store.dart';
import 'package:video_translator/features/project/project_processing_state.dart';

void main() {
  final state = ProjectProcessingState(
    jobId: '2a0a14c6-670a-4f70-9d95-6847237b0c0c',
    lifecycle: ProjectProcessingLifecycle.running,
    workflowId: 'documentTranslation.epub',
    checkpointReferences: ['artifacts/checkpoints/epub-001.json'],
    recoveryStatus: ProjectRecoveryStatus.pendingReconciliation,
  );

  test('encodes only the durable workflow-neutral processing envelope', () {
    expect(state.toManifestJson(), {
      'job': {
        'id': '2a0a14c6-670a-4f70-9d95-6847237b0c0c',
        'lifecycle': 'running',
        'workflowId': 'documentTranslation.epub',
      },
      'checkpointReferences': ['artifacts/checkpoints/epub-001.json'],
      'recoveryStatus': 'pendingReconciliation',
    });
    expect(
      () => state.checkpointReferences.add('artifacts/checkpoints/other.json'),
      throwsUnsupportedError,
    );
  });

  test('round-trips through the atomic manifest store without altering workflow state', () async {
    final directory = await Directory.systemTemp.createTemp(
      'project-processing-state-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final manifest = state.withManifest({
      'manifestVersion': 1,
      'workflow': 'documentTranslation',
      'workflowState': {
        'documentTranslation': {
          'format': 'epub',
          'futureWorkflowField': {'mustRemainOpaque': true},
        },
      },
    });

    await ProjectManifestStore().save(directory, manifest);
    final loaded = await ProjectManifestStore().load(directory);

    expect(ProjectProcessingState.fromManifest(loaded!), _hasState(state));
    expect(
      (loaded['workflowState']! as Map)['documentTranslation'],
      (manifest['workflowState']! as Map)['documentTranslation'],
    );
  });

  test('rejects malformed or stage-specific durable state', () {
    expect(
      () => ProjectProcessingState.fromManifestJson({
        'job': {
          'id': '2a0a14c6-670a-4f70-9d95-6847237b0c0c',
          'lifecycle': 'running',
          'workflowId': 'videoTranslation',
          'stage': 'transcribing',
        },
        'checkpointReferences': [],
        'recoveryStatus': 'none',
      }),
      throwsA(isA<ProjectProcessingStateFormatException>()),
    );
    expect(
      () => ProjectProcessingState(
        jobId: 'not-a-job-id',
        lifecycle: ProjectProcessingLifecycle.created,
        workflowId: 'videoTranslation',
        checkpointReferences: const [],
        recoveryStatus: ProjectRecoveryStatus.none,
      ),
      throwsArgumentError,
    );
  });
}

Matcher _hasState(ProjectProcessingState expected) => predicate(
  (Object? value) =>
      value is ProjectProcessingState &&
      value.jobId == expected.jobId &&
      value.lifecycle == expected.lifecycle &&
      value.workflowId == expected.workflowId &&
      _sameStrings(value.checkpointReferences, expected.checkpointReferences) &&
      value.recoveryStatus == expected.recoveryStatus,
  'matches the expected processing state',
);

bool _sameStrings(List<String> left, List<String> right) =>
    left.length == right.length &&
    left.indexed.every((entry) => entry.$2 == right[entry.$1]);
