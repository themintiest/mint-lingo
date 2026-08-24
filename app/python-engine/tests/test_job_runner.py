import threading
import unittest

from mint_lingo_engine.job import Job, JobLifecycle
from mint_lingo_engine.job_runner import JobRunner, JobStartConflict


class JobRunnerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.runner = JobRunner()
        self.addCleanup(self.runner.close)

    def test_runs_one_already_selected_invocation_and_rejects_conflicts(self) -> None:
        started = threading.Event()
        release = threading.Event()
        invocations: list[str] = []

        def first_workflow() -> None:
            invocations.append("first")
            started.set()
            self.assertTrue(release.wait(timeout=1))

        def second_workflow() -> None:
            invocations.append("second")

        started_job = self.runner.start(first_workflow)

        self.assertIsInstance(started_job, Job)
        assert isinstance(started_job, Job)
        self.assertTrue(started.wait(timeout=1))
        self.assertEqual(started_job.lifecycle, JobLifecycle.RUNNING)
        self.assertEqual(self.runner.active_job, started_job)

        conflict = self.runner.start(second_workflow)

        self.assertIsInstance(conflict, JobStartConflict)
        assert isinstance(conflict, JobStartConflict)
        self.assertEqual(conflict.code, "job.active_job_conflict")
        self.assertEqual(conflict.active_job_id, started_job.id)
        self.assertEqual(invocations, ["first"])

        release.set()
        completed = self.runner.wait_for_completion(started_job.id, timeout=1)

        self.assertEqual(completed.id, started_job.id)
        self.assertEqual(completed.lifecycle, JobLifecycle.COMPLETED)
        self.assertIsNone(self.runner.active_job)
        self.assertEqual(self.runner.get_job(started_job.id), completed)

    def test_records_failure_without_an_error_payload_and_releases_the_runner(self) -> None:
        def failing_workflow() -> None:
            raise RuntimeError("workflow failure")

        failed_job = self.runner.start(failing_workflow)

        self.assertIsInstance(failed_job, Job)
        assert isinstance(failed_job, Job)
        completed = self.runner.wait_for_completion(failed_job.id, timeout=1)

        self.assertEqual(completed.lifecycle, JobLifecycle.FAILED)
        self.assertIsNone(self.runner.active_job)

        next_job = self.runner.start(lambda: None)
        self.assertIsInstance(next_job, Job)
        assert isinstance(next_job, Job)
        self.assertEqual(
            self.runner.wait_for_completion(next_job.id, timeout=1).lifecycle,
            JobLifecycle.COMPLETED,
        )

    def test_rejects_non_callable_invocations_and_unknown_job_queries(self) -> None:
        with self.assertRaisesRegex(TypeError, "invocation must be callable"):
            self.runner.start(None)  # type: ignore[arg-type]

        unknown_job = Job.create()
        with self.assertRaisesRegex(KeyError, unknown_job.id.value):
            self.runner.wait_for_completion(unknown_job.id)
