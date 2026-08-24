/// The durable, workflow-neutral processing state stored in a project manifest.
///
/// This is intentionally limited to the stable job envelope. Concrete workflow
/// state, artifacts, stages, progress, errors, and checkpoint meaning remain
/// outside this model.
final class ProjectProcessingState {
  factory ProjectProcessingState({
    required String jobId,
    required ProjectProcessingLifecycle lifecycle,
    required String workflowId,
    required Iterable<String> checkpointReferences,
    required ProjectRecoveryStatus recoveryStatus,
  }) {
    _requireUuidV4(jobId, 'jobId');
    _requireIdentifier(workflowId, 'workflowId');
    if (!ProjectProcessingLifecycle.values.contains(lifecycle)) {
      throw ArgumentError.value(lifecycle, 'lifecycle');
    }
    if (!ProjectRecoveryStatus.values.contains(recoveryStatus)) {
      throw ArgumentError.value(recoveryStatus, 'recoveryStatus');
    }

    final references = checkpointReferences
        .map((reference) {
          _requireIdentifier(reference, 'checkpoint reference');
          return reference;
        })
        .toList(growable: false);

    return ProjectProcessingState._(
      jobId: jobId,
      lifecycle: lifecycle,
      workflowId: workflowId,
      checkpointReferences: List.unmodifiable(references),
      recoveryStatus: recoveryStatus,
    );
  }

  const ProjectProcessingState._({
    required this.jobId,
    required this.lifecycle,
    required this.workflowId,
    required this.checkpointReferences,
    required this.recoveryStatus,
  });

  static const manifestKey = 'processingState';

  static final RegExp _uuidV4Pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  final String jobId;
  final ProjectProcessingLifecycle lifecycle;

  /// A concrete workflow-owned identifier, never inferred from a source.
  final String workflowId;

  /// Opaque engine-returned references; CHECK-01 owns their later validation.
  final List<String> checkpointReferences;
  final ProjectRecoveryStatus recoveryStatus;

  Map<String, Object?> toManifestJson() => {
    'job': {'id': jobId, 'lifecycle': lifecycle.name, 'workflowId': workflowId},
    'checkpointReferences': checkpointReferences,
    'recoveryStatus': recoveryStatus.name,
  };

  Map<String, Object?> withManifest(Map<String, Object?> manifest) => {
    ...manifest,
    manifestKey: toManifestJson(),
  };

  static ProjectProcessingState? fromManifest(Map<String, Object?> manifest) {
    final value = manifest[manifestKey];
    return value == null ? null : fromManifestJson(value);
  }

  static ProjectProcessingState fromManifestJson(Object? value) {
    if (value is! Map) {
      throw const ProjectProcessingStateFormatException(
        'Processing state must be a JSON object.',
      );
    }
    final state = Map<Object?, Object?>.from(value);
    if (!state.keys.every((key) => key is String) ||
        state.keys.toSet().difference({
          'job',
          'checkpointReferences',
          'recoveryStatus',
        }).isNotEmpty) {
      throw const ProjectProcessingStateFormatException(
        'Processing state has unsupported fields.',
      );
    }

    final jobValue = state['job'];
    if (jobValue is! Map) {
      throw const ProjectProcessingStateFormatException(
        'Processing state job must be a JSON object.',
      );
    }
    final job = Map<Object?, Object?>.from(jobValue);
    if (!job.keys.every((key) => key is String) ||
        job.keys.toSet().difference({
          'id',
          'lifecycle',
          'workflowId',
        }).isNotEmpty) {
      throw const ProjectProcessingStateFormatException(
        'Processing state job has unsupported fields.',
      );
    }

    final referencesValue = state['checkpointReferences'];
    if (referencesValue is! List ||
        !referencesValue.every((reference) => reference is String)) {
      throw const ProjectProcessingStateFormatException(
        'Checkpoint references must be a list of strings.',
      );
    }

    try {
      return ProjectProcessingState(
        jobId: _requiredString(job['id'], 'job ID'),
        lifecycle: _lifecycleFromName(
          _requiredString(job['lifecycle'], 'job lifecycle'),
        ),
        workflowId: _requiredString(job['workflowId'], 'workflow ID'),
        checkpointReferences: referencesValue.cast<String>(),
        recoveryStatus: _recoveryStatusFromName(
          _requiredString(state['recoveryStatus'], 'recovery status'),
        ),
      );
    } on ArgumentError catch (error) {
      throw ProjectProcessingStateFormatException(error.message.toString());
    }
  }

  static ProjectProcessingLifecycle _lifecycleFromName(String value) =>
      ProjectProcessingLifecycle.values.byName(value);

  static ProjectRecoveryStatus _recoveryStatusFromName(String value) =>
      ProjectRecoveryStatus.values.byName(value);
}

enum ProjectProcessingLifecycle {
  created,
  running,
  completed,
  failed,
  cancelled,
}

enum ProjectRecoveryStatus { none, pendingReconciliation }

final class ProjectProcessingStateFormatException implements Exception {
  const ProjectProcessingStateFormatException(this.message);

  final String message;

  @override
  String toString() => 'ProjectProcessingStateFormatException: $message';
}

String _requiredString(Object? value, String name) {
  if (value is! String) {
    throw ArgumentError.value(value, name, 'must be a string');
  }
  return value;
}

void _requireIdentifier(Object value, String name) {
  if (value is! String) {
    throw ArgumentError.value(value, name, 'must be a string');
  }
  if (value.isEmpty || value.trim() != value) {
    throw ArgumentError.value(value, name, 'must not be blank or padded');
  }
}

void _requireUuidV4(Object value, String name) {
  _requireIdentifier(value, name);
  if (!ProjectProcessingState._uuidV4Pattern.hasMatch(value as String)) {
    throw ArgumentError.value(value, name, 'must be a canonical UUIDv4');
  }
}
