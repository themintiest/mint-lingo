import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/features/processing/processing_bloc.dart';

void main() {
  const firstJobId = '2a0a14c6-670a-4f70-9d95-6847237b0c0c';
  const secondJobId = 'd77fd6f7-a2ea-440d-97bc-5006d5695b81';

  test(
    'tracks opaque stages and truthful determinate or indeterminate progress',
    () async {
      final bloc = ProcessingBloc();
      addTearDown(bloc.close);
      final states = expectLater(
        bloc.stream,
        emitsInOrder([
          ProcessingActive.created(firstJobId),
          ProcessingActive(
            jobId: firstJobId,
            lifecycle: ProcessingJobLifecycle.running,
            cancellationRequested: false,
          ),
          ProcessingActive(
            jobId: firstJobId,
            lifecycle: ProcessingJobLifecycle.running,
            stageId: 'restoring_xhtml',
            progress: const ProcessingIndeterminateProgress(),
            cancellationRequested: false,
          ),
          ProcessingActive(
            jobId: firstJobId,
            lifecycle: ProcessingJobLifecycle.running,
            stageId: 'extracting_audio',
            progress: ProcessingDeterminateProgress(
              completedUnits: 42,
              totalUnits: 61,
            ),
            cancellationRequested: false,
          ),
        ]),
      );

      bloc
        ..add(ProcessingJobStarted(firstJobId))
        ..add(
          ProcessingJobLifecycleChanged(
            jobId: firstJobId,
            lifecycle: ProcessingJobLifecycle.running,
          ),
        )
        ..add(
          ProcessingJobProgressReported(
            jobId: firstJobId,
            stageId: 'restoring_xhtml',
            progress: const ProcessingIndeterminateProgress(),
          ),
        )
        ..add(
          ProcessingJobProgressReported(
            jobId: firstJobId,
            stageId: 'extracting_audio',
            progress: ProcessingDeterminateProgress(
              completedUnits: 42,
              totalUnits: 61,
            ),
          ),
        );

      await states;
    },
  );

  test(
    'retains cancellation acknowledgement until the terminal lifecycle arrives',
    () async {
      final bloc = ProcessingBloc();
      addTearDown(bloc.close);
      final states = expectLater(
        bloc.stream,
        emitsInOrder([
          ProcessingActive.created(firstJobId),
          ProcessingActive(
            jobId: firstJobId,
            lifecycle: ProcessingJobLifecycle.running,
            cancellationRequested: false,
          ),
          ProcessingActive(
            jobId: firstJobId,
            lifecycle: ProcessingJobLifecycle.running,
            cancellationRequested: true,
          ),
          ProcessingTerminal(firstJobId, ProcessingJobLifecycle.cancelled),
        ]),
      );

      bloc
        ..add(ProcessingJobStarted(firstJobId))
        ..add(
          ProcessingJobLifecycleChanged(
            jobId: firstJobId,
            lifecycle: ProcessingJobLifecycle.running,
          ),
        )
        ..add(ProcessingCancellationRequested(firstJobId))
        ..add(
          ProcessingJobLifecycleChanged(
            jobId: firstJobId,
            lifecycle: ProcessingJobLifecycle.cancelled,
          ),
        );

      await states;
    },
  );

  test(
    'ignores stale job notifications and admits a new job after failure',
    () async {
      final bloc = ProcessingBloc();
      addTearDown(bloc.close);
      final states = expectLater(
        bloc.stream,
        emitsInOrder([
          ProcessingActive.created(firstJobId),
          ProcessingActive(
            jobId: firstJobId,
            lifecycle: ProcessingJobLifecycle.running,
            cancellationRequested: false,
          ),
          ProcessingTerminal(firstJobId, ProcessingJobLifecycle.failed),
          ProcessingActive.created(secondJobId),
        ]),
      );

      bloc
        ..add(ProcessingJobStarted(firstJobId))
        ..add(
          ProcessingJobLifecycleChanged(
            jobId: firstJobId,
            lifecycle: ProcessingJobLifecycle.running,
          ),
        )
        ..add(
          ProcessingJobProgressReported(
            jobId: secondJobId,
            stageId: 'unrelated_work',
            progress: const ProcessingIndeterminateProgress(),
          ),
        )
        ..add(
          ProcessingJobLifecycleChanged(
            jobId: firstJobId,
            lifecycle: ProcessingJobLifecycle.failed,
          ),
        )
        ..add(ProcessingJobStarted(secondJobId));

      await states;
    },
  );

  test(
    'ignores lifecycle events that violate the shared lifecycle contract',
    () async {
      final bloc = ProcessingBloc();
      addTearDown(bloc.close);
      final states = expectLater(
        bloc.stream,
        emitsInOrder([
          ProcessingActive.created(firstJobId),
          ProcessingActive(
            jobId: firstJobId,
            lifecycle: ProcessingJobLifecycle.running,
            cancellationRequested: false,
          ),
        ]),
      );

      bloc
        ..add(ProcessingJobStarted(firstJobId))
        ..add(
          ProcessingJobLifecycleChanged(
            jobId: firstJobId,
            lifecycle: ProcessingJobLifecycle.running,
          ),
        )
        ..add(
          ProcessingJobLifecycleChanged(
            jobId: firstJobId,
            lifecycle: ProcessingJobLifecycle.created,
          ),
        );

      await states;
      expect(
        bloc.state,
        ProcessingActive(
          jobId: firstJobId,
          lifecycle: ProcessingJobLifecycle.running,
          cancellationRequested: false,
        ),
      );
    },
  );

  test('emits recovery states without selecting a workflow stage', () async {
    final bloc = ProcessingBloc();
    addTearDown(bloc.close);
    final states = expectLater(
      bloc.stream,
      emitsInOrder([
        ProcessingRecovery(
          jobId: firstJobId,
          disposition: ProcessingRecoveryDisposition.recoverable,
        ),
        ProcessingRecovery(
          jobId: secondJobId,
          disposition: ProcessingRecoveryDisposition.failed,
        ),
      ]),
    );

    bloc
      ..add(
        ProcessingJobRecoveryReconciled(
          jobId: firstJobId,
          disposition: ProcessingRecoveryDisposition.recoverable,
        ),
      )
      ..add(
        ProcessingJobRecoveryReconciled(
          jobId: secondJobId,
          disposition: ProcessingRecoveryDisposition.failed,
        ),
      );

    await states;
  });

  test('rejects fabricated progress and malformed shared identifiers', () {
    expect(
      () => ProcessingDeterminateProgress(completedUnits: 2, totalUnits: 0),
      throwsArgumentError,
    );
    expect(() => ProcessingJobStarted('job-1'), throwsArgumentError);
    expect(
      () => ProcessingJobProgressReported(
        jobId: firstJobId,
        stageId: ' translating ',
        progress: const ProcessingIndeterminateProgress(),
      ),
      throwsArgumentError,
    );
  });
}
