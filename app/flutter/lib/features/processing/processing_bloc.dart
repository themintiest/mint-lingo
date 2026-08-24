import 'package:flutter_bloc/flutter_bloc.dart';

/// Shared Flutter state for one engine job, separate from workflow stages.
///
/// Concrete workflows own the meanings/order of their stage IDs. This BLoC
/// accepts already-normalized lifecycle and progress events; it does not start
/// a worker, issue RPC calls, interpret workflow payloads, or render UI.
final class ProcessingBloc extends Bloc<ProcessingEvent, ProcessingState> {
  ProcessingBloc() : super(const ProcessingIdle()) {
    on<ProcessingJobStarted>(_onJobStarted);
    on<ProcessingJobLifecycleChanged>(_onLifecycleChanged);
    on<ProcessingJobProgressReported>(_onProgressReported);
    on<ProcessingCancellationRequested>(_onCancellationRequested);
    on<ProcessingJobRecoveryReconciled>(_onRecoveryReconciled);
    on<ProcessingCleared>((_, emit) => emit(const ProcessingIdle()));
  }

  void _onJobStarted(
    ProcessingJobStarted event,
    Emitter<ProcessingState> emit,
  ) {
    if (state is ProcessingActive) {
      return;
    }
    emit(ProcessingActive.created(event.jobId));
  }

  void _onLifecycleChanged(
    ProcessingJobLifecycleChanged event,
    Emitter<ProcessingState> emit,
  ) {
    final current = state;
    if (current is! ProcessingActive || current.jobId != event.jobId) {
      return;
    }
    if (!_isLegalLifecycleTransition(current.lifecycle, event.lifecycle)) {
      return;
    }

    switch (event.lifecycle) {
      case ProcessingJobLifecycle.created:
      case ProcessingJobLifecycle.running:
        emit(
          ProcessingActive(
            jobId: current.jobId,
            lifecycle: event.lifecycle,
            stageId: current.stageId,
            progress: current.progress,
            cancellationRequested: current.cancellationRequested,
          ),
        );
      case ProcessingJobLifecycle.completed:
      case ProcessingJobLifecycle.failed:
      case ProcessingJobLifecycle.cancelled:
        emit(ProcessingTerminal(event.jobId, event.lifecycle));
    }
  }

  void _onProgressReported(
    ProcessingJobProgressReported event,
    Emitter<ProcessingState> emit,
  ) {
    final current = state;
    if (current is! ProcessingActive ||
        current.jobId != event.jobId ||
        current.lifecycle != ProcessingJobLifecycle.running) {
      return;
    }

    emit(
      ProcessingActive(
        jobId: current.jobId,
        lifecycle: current.lifecycle,
        stageId: event.stageId,
        progress: event.progress,
        cancellationRequested: current.cancellationRequested,
      ),
    );
  }

  void _onCancellationRequested(
    ProcessingCancellationRequested event,
    Emitter<ProcessingState> emit,
  ) {
    final current = state;
    if (current is! ProcessingActive || current.jobId != event.jobId) {
      return;
    }
    if (current.cancellationRequested) {
      return;
    }

    emit(
      ProcessingActive(
        jobId: current.jobId,
        lifecycle: current.lifecycle,
        stageId: current.stageId,
        progress: current.progress,
        cancellationRequested: true,
      ),
    );
  }

  void _onRecoveryReconciled(
    ProcessingJobRecoveryReconciled event,
    Emitter<ProcessingState> emit,
  ) {
    final current = state;
    if (current is ProcessingActive && current.jobId != event.jobId) {
      return;
    }
    emit(
      ProcessingRecovery(jobId: event.jobId, disposition: event.disposition),
    );
  }
}

sealed class ProcessingEvent {
  const ProcessingEvent();
}

final class ProcessingJobStarted extends ProcessingEvent {
  ProcessingJobStarted(this.jobId) {
    _requireJobId(jobId);
  }

  final String jobId;
}

final class ProcessingJobLifecycleChanged extends ProcessingEvent {
  ProcessingJobLifecycleChanged({
    required this.jobId,
    required this.lifecycle,
  }) {
    _requireJobId(jobId);
  }

  final String jobId;
  final ProcessingJobLifecycle lifecycle;
}

final class ProcessingJobProgressReported extends ProcessingEvent {
  ProcessingJobProgressReported({
    required this.jobId,
    required this.stageId,
    required this.progress,
  }) {
    _requireJobId(jobId);
    _requireStageId(stageId);
  }

  final String jobId;

  /// Opaque, workflow-owned stage identifier with no shared ordering.
  final String stageId;
  final ProcessingProgress progress;
}

final class ProcessingCancellationRequested extends ProcessingEvent {
  ProcessingCancellationRequested(this.jobId) {
    _requireJobId(jobId);
  }

  final String jobId;
}

final class ProcessingJobRecoveryReconciled extends ProcessingEvent {
  ProcessingJobRecoveryReconciled({
    required this.jobId,
    required this.disposition,
  }) {
    _requireJobId(jobId);
  }

  final String jobId;
  final ProcessingJobLifecycle lifecycle = ProcessingJobLifecycle.failed;
  final ProcessingRecoveryDisposition disposition;
}

final class ProcessingCleared extends ProcessingEvent {
  const ProcessingCleared();
}

sealed class ProcessingState {
  const ProcessingState();
}

final class ProcessingIdle extends ProcessingState {
  const ProcessingIdle();

  @override
  bool operator ==(Object other) => other is ProcessingIdle;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class ProcessingActive extends ProcessingState {
  ProcessingActive({
    required this.jobId,
    required this.lifecycle,
    this.stageId,
    this.progress,
    required this.cancellationRequested,
  }) {
    _requireJobId(jobId);
    if (lifecycle != ProcessingJobLifecycle.created &&
        lifecycle != ProcessingJobLifecycle.running) {
      throw ArgumentError.value(lifecycle, 'lifecycle', 'must be active');
    }
    if ((stageId == null) != (progress == null)) {
      throw ArgumentError(
        'stageId and progress must either both be present or both be absent',
      );
    }
    if (stageId != null) {
      _requireStageId(stageId!);
    }
  }

  ProcessingActive.created(String jobId)
    : this(
        jobId: jobId,
        lifecycle: ProcessingJobLifecycle.created,
        cancellationRequested: false,
      );

  final String jobId;
  final ProcessingJobLifecycle lifecycle;
  final String? stageId;
  final ProcessingProgress? progress;
  final bool cancellationRequested;

  @override
  bool operator ==(Object other) =>
      other is ProcessingActive &&
      other.jobId == jobId &&
      other.lifecycle == lifecycle &&
      other.stageId == stageId &&
      other.progress == progress &&
      other.cancellationRequested == cancellationRequested;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    jobId,
    lifecycle,
    stageId,
    progress,
    cancellationRequested,
  );
}

final class ProcessingTerminal extends ProcessingState {
  ProcessingTerminal(this.jobId, this.lifecycle) {
    _requireJobId(jobId);
    if (lifecycle != ProcessingJobLifecycle.completed &&
        lifecycle != ProcessingJobLifecycle.failed &&
        lifecycle != ProcessingJobLifecycle.cancelled) {
      throw ArgumentError.value(lifecycle, 'lifecycle', 'must be terminal');
    }
  }

  final String jobId;
  final ProcessingJobLifecycle lifecycle;

  @override
  bool operator ==(Object other) =>
      other is ProcessingTerminal &&
      other.jobId == jobId &&
      other.lifecycle == lifecycle;

  @override
  int get hashCode => Object.hash(runtimeType, jobId, lifecycle);
}

final class ProcessingRecovery extends ProcessingState {
  ProcessingRecovery({required this.jobId, required this.disposition}) {
    _requireJobId(jobId);
  }

  final String jobId;
  final ProcessingJobLifecycle lifecycle = ProcessingJobLifecycle.failed;
  final ProcessingRecoveryDisposition disposition;

  @override
  bool operator ==(Object other) =>
      other is ProcessingRecovery &&
      other.jobId == jobId &&
      other.lifecycle == lifecycle &&
      other.disposition == disposition;

  @override
  int get hashCode => Object.hash(runtimeType, jobId, lifecycle, disposition);
}

enum ProcessingJobLifecycle { created, running, completed, failed, cancelled }

enum ProcessingRecoveryDisposition { recoverable, failed }

sealed class ProcessingProgress {
  const ProcessingProgress();
}

final class ProcessingDeterminateProgress extends ProcessingProgress {
  ProcessingDeterminateProgress({
    required this.completedUnits,
    required this.totalUnits,
  }) {
    if (totalUnits <= 0) {
      throw ArgumentError.value(totalUnits, 'totalUnits', 'must be positive');
    }
    if (completedUnits < 0 || completedUnits > totalUnits) {
      throw ArgumentError.value(
        completedUnits,
        'completedUnits',
        'must be between zero and totalUnits',
      );
    }
  }

  final int completedUnits;
  final int totalUnits;

  double get fractionComplete => completedUnits / totalUnits;

  @override
  bool operator ==(Object other) =>
      other is ProcessingDeterminateProgress &&
      other.completedUnits == completedUnits &&
      other.totalUnits == totalUnits;

  @override
  int get hashCode => Object.hash(runtimeType, completedUnits, totalUnits);
}

final class ProcessingIndeterminateProgress extends ProcessingProgress {
  const ProcessingIndeterminateProgress();

  @override
  bool operator ==(Object other) => other is ProcessingIndeterminateProgress;

  @override
  int get hashCode => runtimeType.hashCode;
}

final RegExp _jobIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void _requireJobId(String value) {
  if (!_jobIdPattern.hasMatch(value)) {
    throw ArgumentError.value(value, 'jobId', 'must be a canonical UUIDv4');
  }
}

void _requireStageId(String value) {
  if (value.isEmpty || value.trim() != value) {
    throw ArgumentError.value(
      value,
      'stageId',
      'must be non-empty and trimmed',
    );
  }
}

bool _isLegalLifecycleTransition(
  ProcessingJobLifecycle current,
  ProcessingJobLifecycle next,
) => switch (current) {
  ProcessingJobLifecycle.created =>
    next == ProcessingJobLifecycle.running ||
        next == ProcessingJobLifecycle.cancelled,
  ProcessingJobLifecycle.running =>
    next == ProcessingJobLifecycle.completed ||
        next == ProcessingJobLifecycle.failed ||
        next == ProcessingJobLifecycle.cancelled,
  ProcessingJobLifecycle.completed ||
  ProcessingJobLifecycle.failed ||
  ProcessingJobLifecycle.cancelled => false,
};
