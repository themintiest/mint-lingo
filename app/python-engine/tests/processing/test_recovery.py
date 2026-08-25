from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from mint_lingo_engine.processing.checkpoint import Checkpoint, CheckpointStore
from mint_lingo_engine.processing.job import Job, JobLifecycle
from mint_lingo_engine.processing.recovery import (
    JobRecoveryReconciler,
    RecoveryDisposition,
)


class JobRecoveryReconcilerTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary_directory = self.enterContext(TemporaryDirectory())
        self.artifact_root = Path(temporary_directory) / "project" / "artifacts"
        self.store = CheckpointStore(self.artifact_root)
        self.reconciler = JobRecoveryReconciler(self.store)

    def test_marks_orphaned_running_work_recoverable_when_every_checkpoint_verifies(self) -> None:
        reference = self._record_checkpoint("opaque-review", "retained-review")
        running_job = Job.create().transition_to(JobLifecycle.RUNNING)

        result = self.reconciler.reconcile(running_job, [reference])

        self.assertEqual(result.job.id, running_job.id)
        self.assertEqual(result.job.lifecycle, JobLifecycle.FAILED)
        self.assertEqual(result.disposition, RecoveryDisposition.RECOVERABLE)
        self.assertEqual(result.verified_checkpoint_references, (reference,))

    def test_marks_orphaned_running_work_failed_when_any_checkpoint_is_not_verified(self) -> None:
        verified_reference = self._record_checkpoint("opaque-first", "retained-first")
        artifact_path = self.artifact_root / "opaque" / "retained-first"
        record_path = self.artifact_root / "checkpoints" / "opaque-first.json"
        running_job = Job.create().transition_to(JobLifecycle.RUNNING)

        result = self.reconciler.reconcile(
            running_job,
            [verified_reference, "artifacts/checkpoints/missing-work.json"],
        )

        self.assertEqual(result.job.lifecycle, JobLifecycle.FAILED)
        self.assertEqual(result.disposition, RecoveryDisposition.FAILED)
        self.assertEqual(result.verified_checkpoint_references, (verified_reference,))
        self.assertTrue(artifact_path.exists())
        self.assertTrue(record_path.exists())

    def test_marks_an_orphaned_job_without_checkpoints_failed(self) -> None:
        running_job = Job.create().transition_to(JobLifecycle.RUNNING)

        result = self.reconciler.reconcile(running_job, [])

        self.assertEqual(result.job.lifecycle, JobLifecycle.FAILED)
        self.assertEqual(result.disposition, RecoveryDisposition.FAILED)
        self.assertEqual(result.verified_checkpoint_references, ())

    def test_leaves_terminal_lifecycle_unchanged_without_verifying_checkpoints(self) -> None:
        completed_job = (
            Job.create()
            .transition_to(JobLifecycle.RUNNING)
            .transition_to(JobLifecycle.COMPLETED)
        )

        result = self.reconciler.reconcile(
            completed_job,
            ["artifacts/checkpoints/missing-work.json"],
        )

        self.assertEqual(result.job, completed_job)
        self.assertEqual(result.disposition, RecoveryDisposition.NOT_REQUIRED)
        self.assertEqual(result.verified_checkpoint_references, ())

    def test_rejects_non_string_checkpoint_references(self) -> None:
        running_job = Job.create().transition_to(JobLifecycle.RUNNING)

        with self.assertRaisesRegex(TypeError, "iterable of strings"):
            self.reconciler.reconcile(running_job, "artifacts/checkpoints/work.json")
        with self.assertRaisesRegex(TypeError, "contain strings"):
            self.reconciler.reconcile(running_job, [42])  # type: ignore[list-item]

    def _record_checkpoint(self, checkpoint_id: str, artifact_name: str) -> str:
        artifact_path = self.artifact_root / "opaque" / artifact_name
        artifact_path.parent.mkdir(parents=True, exist_ok=True)
        artifact_path.write_text("workflow-owned")
        return self.store.record(
            Checkpoint(
                checkpoint_id=checkpoint_id,
                artifact_reference=f"artifacts/opaque/{artifact_name}",
            )
        ).reference
