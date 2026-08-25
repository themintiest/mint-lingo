import subprocess
import sys
import threading
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from mint_lingo_engine.job import Job, JobLifecycle
from mint_lingo_engine.job_runner import (
    JobCancellationAccepted,
    JobCancellationNotFound,
    JobExecutionContext,
    JobRunner,
    JobStartConflict,
)


class JobRunnerTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary_directory = self.enterContext(TemporaryDirectory())
        self.temporary_root = Path(temporary_directory) / "temporary"
        self.runner = JobRunner(self.temporary_root)
        self.addCleanup(self.runner.close)

    def test_runs_one_already_selected_invocation_and_rejects_conflicts(self) -> None:
        started = threading.Event()
        release = threading.Event()
        invocations: list[str] = []

        def first_workflow(context: JobExecutionContext) -> None:
            invocations.append("first")
            (context.workspace.path / "opaque-work").write_text("temporary")
            started.set()
            self.assertTrue(release.wait(timeout=1))

        def second_workflow(_context: JobExecutionContext) -> None:
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
        self.assertFalse(
            (self.temporary_root / f"job-{started_job.id.value}").exists()
        )

    def test_records_failure_without_an_error_payload_and_releases_the_runner(self) -> None:
        workspace_path: Path | None = None

        def failing_workflow(context: JobExecutionContext) -> None:
            nonlocal workspace_path
            workspace_path = context.workspace.path
            (workspace_path / "nested").mkdir()
            (workspace_path / "nested" / "opaque-work").write_text("temporary")
            raise RuntimeError("workflow failure")

        failed_job = self.runner.start(failing_workflow)

        self.assertIsInstance(failed_job, Job)
        assert isinstance(failed_job, Job)
        completed = self.runner.wait_for_completion(failed_job.id, timeout=1)

        self.assertEqual(completed.lifecycle, JobLifecycle.FAILED)
        self.assertIsNone(self.runner.active_job)
        self.assertIsNotNone(workspace_path)
        assert workspace_path is not None
        self.assertFalse(workspace_path.exists())

        next_job = self.runner.start(lambda _context: None)
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

    def test_cancellation_reaches_the_active_workflow_and_marks_it_cancelled(self) -> None:
        started = threading.Event()

        workspace_path: Path | None = None

        def cancellable_workflow(context: JobExecutionContext) -> None:
            nonlocal workspace_path
            workspace_path = context.workspace.path
            (workspace_path / "opaque-work").write_text("temporary")
            started.set()
            self.assertTrue(context.cancellation.wait(timeout=1))
            context.cancellation.raise_if_cancelled()

        started_job = self.runner.start(cancellable_workflow)

        self.assertIsInstance(started_job, Job)
        assert isinstance(started_job, Job)
        self.assertTrue(started.wait(timeout=1))

        cancellation = self.runner.cancel(started_job.id)

        self.assertEqual(cancellation, JobCancellationAccepted(started_job.id))
        completed = self.runner.wait_for_completion(started_job.id, timeout=1)
        self.assertEqual(completed.lifecycle, JobLifecycle.CANCELLED)
        self.assertIsNone(self.runner.active_job)
        self.assertIsNotNone(workspace_path)
        assert workspace_path is not None
        self.assertFalse(workspace_path.exists())

        missing = self.runner.cancel(started_job.id)
        self.assertEqual(
            missing,
            JobCancellationNotFound(
                code="job.not_found",
                job_id=started_job.id,
                message="Job not found.",
            ),
        )

    def test_cancellation_terminates_a_registered_child_process(self) -> None:
        started = threading.Event()
        child_process: subprocess.Popen[str] | None = None

        def stop_child_if_needed() -> None:
            if child_process is not None and child_process.poll() is None:
                child_process.kill()
                child_process.wait(timeout=1)

        self.addCleanup(stop_child_if_needed)

        def child_process_workflow(context: JobExecutionContext) -> None:
            nonlocal child_process
            child_process = subprocess.Popen(
                [sys.executable, "-c", "import time; time.sleep(30)"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            context.register_child_process(child_process)
            started.set()
            context.cancellation.wait(timeout=5)
            context.cancellation.raise_if_cancelled()

        started_job = self.runner.start(child_process_workflow)

        self.assertIsInstance(started_job, Job)
        assert isinstance(started_job, Job)
        self.assertTrue(started.wait(timeout=1))
        self.assertEqual(self.runner.cancel(started_job.id), JobCancellationAccepted(started_job.id))
        completed = self.runner.wait_for_completion(started_job.id, timeout=2)

        self.assertEqual(completed.lifecycle, JobLifecycle.CANCELLED)
        self.assertIsNotNone(child_process)
        assert child_process is not None
        self.assertIsNotNone(child_process.poll())

    def test_cancellation_escalates_to_kill_when_a_child_does_not_exit(self) -> None:
        child_process = _StubbornChildProcess()

        def child_process_workflow(context: JobExecutionContext) -> None:
            context.register_child_process(child_process)
            context.cancellation.wait(timeout=1)
            context.cancellation.raise_if_cancelled()

        started_job = self.runner.start(child_process_workflow)

        self.assertIsInstance(started_job, Job)
        assert isinstance(started_job, Job)
        self.assertEqual(self.runner.cancel(started_job.id), JobCancellationAccepted(started_job.id))
        self.assertEqual(
            self.runner.wait_for_completion(started_job.id, timeout=1).lifecycle,
            JobLifecycle.CANCELLED,
        )
        self.assertEqual(child_process.terminate_calls, 1)
        self.assertEqual(child_process.kill_calls, 1)


class _StubbornChildProcess:
    def __init__(self) -> None:
        self.terminate_calls = 0
        self.kill_calls = 0
        self._exited = False

    def poll(self) -> int | None:
        return 0 if self._exited else None

    def terminate(self) -> None:
        self.terminate_calls += 1

    def kill(self) -> None:
        self.kill_calls += 1
        self._exited = True

    def wait(self, timeout: float | None = None) -> int:
        if not self._exited:
            raise subprocess.TimeoutExpired("stubborn-child", timeout)
        return 0
