from dataclasses import FrozenInstanceError
import unittest
from uuid import UUID

from mint_lingo_engine.job import Job, JobId, JobLifecycle, JobTransitionError


class JobIdTest(unittest.TestCase):
    def test_creates_distinct_canonical_uuidv4_values(self) -> None:
        first = JobId.new()
        second = JobId.new()

        self.assertNotEqual(first, second)
        self.assertEqual(str(UUID(first.value)), first.value)
        self.assertEqual(UUID(first.value).version, 4)

    def test_rejects_noncanonical_or_non_v4_values(self) -> None:
        with self.assertRaisesRegex(ValueError, "canonical UUIDv4"):
            JobId("5B0B2879-BB42-4E1F-9A2B-D3CFD7C858A6")
        with self.assertRaisesRegex(ValueError, "canonical UUIDv4"):
            JobId("00000000-0000-0000-0000-000000000000")
        with self.assertRaisesRegex(TypeError, "must be a string"):
            JobId(42)  # type: ignore[arg-type]


class JobLifecycleTest(unittest.TestCase):
    def test_preserves_identity_through_each_legal_lifecycle_path(self) -> None:
        job = Job.create()
        self.assertEqual(job.lifecycle, JobLifecycle.CREATED)
        self.assertFalse(job.is_terminal)

        running = job.transition_to(JobLifecycle.RUNNING)
        completed = running.transition_to(JobLifecycle.COMPLETED)

        self.assertEqual(running.id, job.id)
        self.assertEqual(completed.id, job.id)
        self.assertEqual(completed.lifecycle, JobLifecycle.COMPLETED)
        self.assertTrue(completed.is_terminal)
        with self.assertRaises(FrozenInstanceError):
            completed.lifecycle = JobLifecycle.FAILED  # type: ignore[misc]

    def test_allows_cancellation_before_or_during_execution(self) -> None:
        created_cancelled = Job.create().transition_to(JobLifecycle.CANCELLED)
        running_cancelled = (
            Job.create()
            .transition_to(JobLifecycle.RUNNING)
            .transition_to(JobLifecycle.CANCELLED)
        )

        self.assertTrue(created_cancelled.is_terminal)
        self.assertTrue(running_cancelled.is_terminal)

    def test_rejects_illegal_and_terminal_transitions_without_stage_values(self) -> None:
        created = Job.create()
        running = created.transition_to(JobLifecycle.RUNNING)
        failed = running.transition_to(JobLifecycle.FAILED)

        with self.assertRaisesRegex(JobTransitionError, "created to completed"):
            created.transition_to(JobLifecycle.COMPLETED)
        with self.assertRaisesRegex(JobTransitionError, "running to created"):
            running.transition_to(JobLifecycle.CREATED)
        with self.assertRaisesRegex(JobTransitionError, "failed to running"):
            failed.transition_to(JobLifecycle.RUNNING)
        with self.assertRaisesRegex(TypeError, "must be a JobLifecycle"):
            running.transition_to("translating")  # type: ignore[arg-type]

    def test_rejects_unstructured_job_values(self) -> None:
        with self.assertRaisesRegex(TypeError, "id must be a JobId"):
            Job(id="job-1")  # type: ignore[arg-type]
        with self.assertRaisesRegex(TypeError, "lifecycle must be a JobLifecycle"):
            Job(id=JobId.new(), lifecycle="running")  # type: ignore[arg-type]
