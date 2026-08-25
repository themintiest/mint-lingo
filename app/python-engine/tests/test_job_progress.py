from dataclasses import FrozenInstanceError
import unittest

from mint_lingo_engine.processing.job import JobId
from mint_lingo_engine.processing.progress import (
    DeterminateProgress,
    IndeterminateProgress,
    JobProgressNotification,
)


class JobProgressNotificationTest(unittest.TestCase):
    def test_keeps_workflow_stage_identifiers_opaque(self) -> None:
        job_id = JobId.new()
        video_stage = JobProgressNotification(
            job_id=job_id,
            stage_id="extracting_audio",
            progress=DeterminateProgress(completed_units=42, total_units=61),
        )
        epub_stage = JobProgressNotification(
            job_id=job_id,
            stage_id="restoring_xhtml",
            progress=IndeterminateProgress(),
        )

        self.assertEqual(video_stage.stage_id, "extracting_audio")
        self.assertEqual(epub_stage.stage_id, "restoring_xhtml")
        self.assertIsInstance(video_stage.progress, DeterminateProgress)
        self.assertIsInstance(epub_stage.progress, IndeterminateProgress)

    def test_derives_determinate_completion_from_exact_work_units(self) -> None:
        progress = DeterminateProgress(completed_units=42, total_units=61)

        self.assertEqual(progress.completed_units, 42)
        self.assertEqual(progress.total_units, 61)
        self.assertEqual(progress.fraction_complete, 42 / 61)
        with self.assertRaises(FrozenInstanceError):
            progress.completed_units = 43  # type: ignore[misc]

    def test_rejects_unknown_or_invented_determinate_totals(self) -> None:
        with self.assertRaisesRegex(ValueError, "greater than zero"):
            DeterminateProgress(completed_units=0, total_units=0)
        with self.assertRaisesRegex(ValueError, "between zero and total_units"):
            DeterminateProgress(completed_units=62, total_units=61)
        with self.assertRaisesRegex(TypeError, "must be an integer"):
            DeterminateProgress(completed_units=0.68, total_units=1)  # type: ignore[arg-type]

    def test_rejects_non_job_or_non_progress_notification_values(self) -> None:
        with self.assertRaisesRegex(TypeError, "job_id must be a JobId"):
            JobProgressNotification(
                job_id="job-1",  # type: ignore[arg-type]
                stage_id="translating",
                progress=IndeterminateProgress(),
            )
        with self.assertRaisesRegex(ValueError, "non-empty trimmed"):
            JobProgressNotification(
                job_id=JobId.new(),
                stage_id=" translating ",
                progress=IndeterminateProgress(),
            )
        with self.assertRaisesRegex(TypeError, "DeterminateProgress or IndeterminateProgress"):
            JobProgressNotification(
                job_id=JobId.new(),
                stage_id="translating",
                progress={"percent": 68},  # type: ignore[arg-type]
            )
