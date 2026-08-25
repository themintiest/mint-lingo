import subprocess
import sys
import threading
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from mint_lingo_engine.processing.checkpoint import Checkpoint, CheckpointStore
from mint_lingo_engine.processing.job import Job, JobLifecycle, JobTransitionError
from mint_lingo_engine.processing.progress import (
    DeterminateProgress,
    IndeterminateProgress,
    JobProgressNotification,
)
from mint_lingo_engine.processing.recovery import (
    JobRecoveryReconciler,
    RecoveryDisposition,
)
from mint_lingo_engine.processing.runner import (
    JobCancellationAccepted,
    JobExecutionContext,
    JobRunner,
    JobStartConflict,
)


class JobFlowTest(unittest.TestCase):
    """Integration-oriented coverage for shared job infrastructure only."""

    def setUp(self) -> None:
        temporary_directory = self.enterContext(TemporaryDirectory())
        self.root = Path(temporary_directory)
        self.runner = JobRunner(self.root / "temporary")
        self.addCleanup(self.runner.close)

    def test_illegal_lifecycle_transitions_leave_shared_jobs_unchanged(self) -> None:
        created = Job.create()

        with self.assertRaises(JobTransitionError):
            created.transition_to(JobLifecycle.COMPLETED)

        self.assertEqual(created.lifecycle, JobLifecycle.CREATED)
        running = created.transition_to(JobLifecycle.RUNNING)
        with self.assertRaises(JobTransitionError):
            running.transition_to(JobLifecycle.CREATED)
        self.assertEqual(running.lifecycle, JobLifecycle.RUNNING)

    def test_runs_substitutes_with_unlike_opaque_stage_sequences(self) -> None:
        notifications: list[JobProgressNotification] = []

        def first_substitute(context: JobExecutionContext) -> None:
            notifications.extend(
                [
                    JobProgressNotification(
                        job_id=context.job_id,
                        stage_id="assembling_fragments",
                        progress=IndeterminateProgress(),
                    ),
                    JobProgressNotification(
                        job_id=context.job_id,
                        stage_id="counting_markers",
                        progress=DeterminateProgress(
                            completed_units=4,
                            total_units=7,
                        ),
                    ),
                ]
            )

        def second_substitute(context: JobExecutionContext) -> None:
            notifications.extend(
                [
                    JobProgressNotification(
                        job_id=context.job_id,
                        stage_id="sealing_result",
                        progress=DeterminateProgress(
                            completed_units=1,
                            total_units=1,
                        ),
                    ),
                    JobProgressNotification(
                        job_id=context.job_id,
                        stage_id="surveying_input",
                        progress=IndeterminateProgress(),
                    ),
                ]
            )

        first = self.runner.start(first_substitute)
        self.assertIsInstance(first, Job)
        assert isinstance(first, Job)
        self.assertEqual(
            self.runner.wait_for_completion(first.id, timeout=1).lifecycle,
            JobLifecycle.COMPLETED,
        )

        second = self.runner.start(second_substitute)
        self.assertIsInstance(second, Job)
        assert isinstance(second, Job)
        self.assertEqual(
            self.runner.wait_for_completion(second.id, timeout=1).lifecycle,
            JobLifecycle.COMPLETED,
        )

        self.assertEqual(
            [(notification.job_id, notification.stage_id) for notification in notifications],
            [
                (first.id, "assembling_fragments"),
                (first.id, "counting_markers"),
                (second.id, "sealing_result"),
                (second.id, "surveying_input"),
            ],
        )
        self.assertIsInstance(notifications[0].progress, IndeterminateProgress)
        self.assertEqual(
            notifications[1].progress,
            DeterminateProgress(completed_units=4, total_units=7),
        )

    def test_cancellation_keeps_the_job_active_until_the_substitute_exits(self) -> None:
        child_started = threading.Event()
        cancellation_observed = threading.Event()
        allow_substitute_exit = threading.Event()
        child_process: subprocess.Popen[str] | None = None

        def stop_child_if_needed() -> None:
            if child_process is not None and child_process.poll() is None:
                child_process.kill()
                child_process.wait(timeout=1)

        self.addCleanup(stop_child_if_needed)

        def cancellable_substitute(context: JobExecutionContext) -> None:
            nonlocal child_process
            child_process = subprocess.Popen(
                [sys.executable, "-c", "import time; time.sleep(30)"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            context.register_child_process(child_process)
            child_started.set()
            self.assertTrue(context.cancellation.wait(timeout=1))
            cancellation_observed.set()
            self.assertTrue(allow_substitute_exit.wait(timeout=1))
            context.cancellation.raise_if_cancelled()

        started = self.runner.start(cancellable_substitute)
        self.assertIsInstance(started, Job)
        assert isinstance(started, Job)
        self.assertTrue(child_started.wait(timeout=1))

        self.assertEqual(
            self.runner.cancel(started.id),
            JobCancellationAccepted(job_id=started.id),
        )
        self.assertTrue(cancellation_observed.wait(timeout=1))
        self.assertIsNotNone(child_process)
        assert child_process is not None
        child_process.wait(timeout=1)

        conflict = self.runner.start(lambda _context: None)
        self.assertIsInstance(conflict, JobStartConflict)
        assert isinstance(conflict, JobStartConflict)
        self.assertEqual(conflict.active_job_id, started.id)

        allow_substitute_exit.set()
        self.assertEqual(
            self.runner.wait_for_completion(started.id, timeout=1).lifecycle,
            JobLifecycle.CANCELLED,
        )
        self.assertIsNone(self.runner.active_job)

    def test_reconciles_lost_running_work_to_deterministic_recovery_states(self) -> None:
        artifact_root = self.root / "project" / "artifacts"
        artifact_path = artifact_root / "opaque" / "retained-unit"
        artifact_path.parent.mkdir(parents=True)
        artifact_path.write_text("workflow-owned")
        checkpoint_store = CheckpointStore(artifact_root)
        reference = checkpoint_store.record(
            Checkpoint(
                checkpoint_id="retained-unit",
                artifact_reference="artifacts/opaque/retained-unit",
            )
        ).reference
        reconciler = JobRecoveryReconciler(checkpoint_store)
        lost_job = Job.create().transition_to(JobLifecycle.RUNNING)

        recoverable = reconciler.reconcile(lost_job, [reference])
        failed = reconciler.reconcile(
            lost_job,
            [reference, "artifacts/checkpoints/missing-unit.json"],
        )

        self.assertEqual(recoverable.job.id, lost_job.id)
        self.assertEqual(recoverable.job.lifecycle, JobLifecycle.FAILED)
        self.assertEqual(recoverable.disposition, RecoveryDisposition.RECOVERABLE)
        self.assertEqual(recoverable.verified_checkpoint_references, (reference,))
        self.assertEqual(failed.job.id, lost_job.id)
        self.assertEqual(failed.job.lifecycle, JobLifecycle.FAILED)
        self.assertEqual(failed.disposition, RecoveryDisposition.FAILED)
        self.assertEqual(failed.verified_checkpoint_references, (reference,))
        self.assertTrue(artifact_path.exists())


if __name__ == "__main__":
    unittest.main()
