from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from mint_lingo_engine.checkpoint import Checkpoint, CheckpointStore
from mint_lingo_engine.job import Job, JobLifecycle
from mint_lingo_engine.job_recovery import (
    JobRecoveryReconciler,
    RecoveryDisposition,
)


class PersistenceFlowTest(unittest.TestCase):
    """Cross-boundary persistence coverage without workflow-format semantics."""

    def test_damaged_checkpoint_keeps_prior_records_and_fails_recovery(self) -> None:
        temporary_directory = self.enterContext(TemporaryDirectory())
        project_root = Path(temporary_directory) / "project"
        project_root.mkdir()
        manifest_path = project_root / "project.json"
        manifest_contents = '{"manifestVersion":1,"workflow":"substituteWorkflow"}'
        manifest_path.write_text(manifest_contents)
        artifact_root = project_root / "artifacts"
        store = CheckpointStore(artifact_root)
        first_reference = self._record_checkpoint(
            store,
            artifact_root,
            checkpoint_id="opaque-first",
            artifact_name="first-value",
        )
        second_reference = self._record_checkpoint(
            store,
            artifact_root,
            checkpoint_id="opaque-second",
            artifact_name="second-value",
        )
        damaged_record = artifact_root / "checkpoints" / "opaque-second.json"
        damaged_record.write_text('{"checkpointId":')

        result = JobRecoveryReconciler(store).reconcile(
            Job.create().transition_to(JobLifecycle.RUNNING),
            [first_reference, second_reference],
        )

        self.assertEqual(result.job.lifecycle, JobLifecycle.FAILED)
        self.assertEqual(result.disposition, RecoveryDisposition.FAILED)
        self.assertEqual(result.verified_checkpoint_references, (first_reference,))
        self.assertEqual(manifest_path.read_text(), manifest_contents)
        self.assertTrue((artifact_root / "checkpoints" / "opaque-first.json").exists())
        self.assertTrue(damaged_record.exists())
        self.assertEqual(list((artifact_root / "checkpoints").glob(".*.tmp")), [])

    def _record_checkpoint(
        self,
        store: CheckpointStore,
        artifact_root: Path,
        *,
        checkpoint_id: str,
        artifact_name: str,
    ) -> str:
        artifact_path = artifact_root / "substitute" / artifact_name
        artifact_path.parent.mkdir(parents=True, exist_ok=True)
        artifact_path.write_text("workflow-owned")
        return store.record(
            Checkpoint(
                checkpoint_id=checkpoint_id,
                artifact_reference=f"artifacts/substitute/{artifact_name}",
            )
        ).reference


if __name__ == "__main__":
    unittest.main()
