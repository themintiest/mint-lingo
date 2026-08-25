import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from mint_lingo_engine.checkpoint import (
    Checkpoint,
    CheckpointConflictError,
    CheckpointFormatError,
    CheckpointStore,
)


class CheckpointStoreTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary_directory = self.enterContext(TemporaryDirectory())
        self.project_root = Path(temporary_directory) / "project"
        self.project_root.mkdir()
        self.manifest = self.project_root / "project.json"
        self.manifest.write_text('{"manifestVersion":1}')
        self.artifact_root = self.project_root / "artifacts"
        self.store = CheckpointStore(self.artifact_root)

    def _write_artifact(self, reference: str) -> None:
        relative_path = Path(*reference.split("/")[1:])
        artifact_path = self.artifact_root / relative_path
        artifact_path.parent.mkdir(parents=True, exist_ok=True)
        artifact_path.write_text("workflow-owned")

    def test_atomically_records_and_loads_an_opaque_completed_checkpoint(self) -> None:
        checkpoint = Checkpoint(
            checkpoint_id="review-unit.17",
            artifact_reference="artifacts/opaque-work/retained-data",
        )
        self._write_artifact(checkpoint.artifact_reference)

        stored = self.store.record(checkpoint)

        self.assertEqual(stored.reference, "artifacts/checkpoints/review-unit.17.json")
        self.assertEqual(self.store.load(stored.reference), stored)
        record_path = self.artifact_root / "checkpoints" / "review-unit.17.json"
        self.assertEqual(
            json.loads(record_path.read_text()),
            {
                "artifactReference": "artifacts/opaque-work/retained-data",
                "checkpointId": "review-unit.17",
            },
        )
        self.assertEqual(self.manifest.read_text(), '{"manifestVersion":1}')
        self.assertEqual(list((self.artifact_root / "checkpoints").glob("*.tmp")), [])

    def test_rejects_replacing_a_checkpoint_with_different_workflow_metadata(self) -> None:
        first = Checkpoint(
            checkpoint_id="completed-work",
            artifact_reference="artifacts/opaque/first",
        )
        replacement = Checkpoint(
            checkpoint_id="completed-work",
            artifact_reference="artifacts/opaque/second",
        )
        self._write_artifact(first.artifact_reference)
        self._write_artifact(replacement.artifact_reference)
        self.store.record(first)

        self.assertEqual(self.store.record(first).checkpoint, first)
        with self.assertRaisesRegex(CheckpointConflictError, "completed-work"):
            self.store.record(replacement)

        self.assertEqual(
            self.store.load("artifacts/checkpoints/completed-work.json").checkpoint,
            first,
        )

    def test_rejects_nonportable_or_nonartifact_references_without_format_rules(self) -> None:
        with self.assertRaisesRegex(CheckpointFormatError, "beneath"):
            self.store.record(
                Checkpoint(
                    checkpoint_id="bad-root",
                    artifact_reference="temporary/opaque-data",
                )
            )
        with self.assertRaisesRegex(CheckpointFormatError, "retained artifact"):
            self.store.record(
                Checkpoint(
                    checkpoint_id="missing-artifact",
                    artifact_reference="artifacts/opaque-data",
                )
            )
        with self.assertRaisesRegex(CheckpointFormatError, "portable relative"):
            Checkpoint(
                checkpoint_id="bad-path",
                artifact_reference=r"artifacts\opaque-data",
            )
        with self.assertRaisesRegex(CheckpointFormatError, "portable identifier"):
            Checkpoint(
                checkpoint_id="chapter/17",
                artifact_reference="artifacts/opaque-data",
            )

    def test_failed_temporary_write_does_not_publish_a_partial_checkpoint(self) -> None:
        def interrupted_write(path: Path, _contents: str) -> None:
            path.write_text('{"partial":')
            raise OSError("simulated interrupted write")

        store = CheckpointStore(
            self.artifact_root,
            write_temporary_file=interrupted_write,
        )
        checkpoint = Checkpoint(
            checkpoint_id="interrupted-work",
            artifact_reference="artifacts/opaque-data",
        )
        self._write_artifact(checkpoint.artifact_reference)

        with self.assertRaisesRegex(OSError, "simulated interrupted write"):
            store.record(checkpoint)

        checkpoint_directory = self.artifact_root / "checkpoints"
        self.assertFalse((checkpoint_directory / "interrupted-work.json").exists())
        self.assertEqual(list(checkpoint_directory.glob(".*.tmp")), [])

    def test_load_rejects_a_damaged_record_without_interpreting_artifact_contents(self) -> None:
        self._write_artifact("artifacts/opaque-data")
        checkpoint_directory = self.artifact_root / "checkpoints"
        checkpoint_directory.mkdir(parents=True)
        (checkpoint_directory / "damaged-work.json").write_text(
            '{"checkpointId":"damaged-work","artifactReference":"artifacts/opaque-data","stage":"ignored"}'
        )

        with self.assertRaisesRegex(CheckpointFormatError, "unsupported fields"):
            self.store.load("artifacts/checkpoints/damaged-work.json")
