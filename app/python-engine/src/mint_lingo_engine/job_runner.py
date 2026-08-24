"""Single-active-job execution and in-memory registration boundary."""

from __future__ import annotations

from collections.abc import Callable
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass
from subprocess import TimeoutExpired
from threading import Event, Lock
from typing import Protocol

from mint_lingo_engine.job import Job, JobId, JobLifecycle


@dataclass(frozen=True)
class JobStartConflict:
    """A structured refusal to start while another job is active."""

    code: str
    active_job_id: JobId
    message: str


@dataclass(frozen=True)
class JobCancellationAccepted:
    """Confirmation that cancellation was delivered to one active job."""

    job_id: JobId


@dataclass(frozen=True)
class JobCancellationNotFound:
    """A structured refusal when a job is no longer active."""

    code: str
    job_id: JobId
    message: str


class JobCancelled(Exception):
    """Raised by a cooperative workflow after it observes cancellation."""


class ChildProcess(Protocol):
    """The subprocess operations required for a job-owned child process."""

    def poll(self) -> int | None: ...

    def terminate(self) -> None: ...

    def kill(self) -> None: ...

    def wait(self, timeout: float | None = None) -> int: ...


class CancellationToken:
    """A thread-safe cancellation signal owned by one runner invocation."""

    def __init__(self) -> None:
        self._event = Event()

    @property
    def is_cancelled(self) -> bool:
        """Whether cancellation has been requested."""

        return self._event.is_set()

    def wait(self, timeout: float | None = None) -> bool:
        """Wait until cancellation is requested or the timeout expires."""

        return self._event.wait(timeout)

    def raise_if_cancelled(self) -> None:
        """Raise the shared cooperative-cancellation signal when requested."""

        if self.is_cancelled:
            raise JobCancelled("job cancellation was requested")

    def _cancel(self) -> None:
        self._event.set()


class JobExecutionContext:
    """Cancellation and direct-child ownership for one concrete invocation."""

    def __init__(self, job_id: JobId, *, child_termination_timeout: float) -> None:
        self.job_id = job_id
        self.cancellation = CancellationToken()
        self._child_termination_timeout = child_termination_timeout
        self._lock = Lock()
        self._children: dict[int, ChildProcess] = {}

    def register_child_process(self, child_process: ChildProcess) -> None:
        """Register a direct child process for cancellation-time termination."""

        for method_name in ("poll", "terminate", "kill", "wait"):
            if not callable(getattr(child_process, method_name, None)):
                raise TypeError("child_process must support process termination")

        with self._lock:
            self._children[id(child_process)] = child_process
            cancellation_requested = self.cancellation.is_cancelled
        if cancellation_requested:
            self._terminate_child_process(child_process)

    def unregister_child_process(self, child_process: ChildProcess) -> None:
        """Stop tracking a child process that the workflow has already reaped."""

        with self._lock:
            self._children.pop(id(child_process), None)

    def request_cancellation(self) -> None:
        """Signal cooperative cancellation and terminate registered children."""

        self.cancellation._cancel()
        with self._lock:
            children = tuple(self._children.values())
        for child_process in children:
            self._terminate_child_process(child_process)

    def _terminate_child_process(self, child_process: ChildProcess) -> None:
        if child_process.poll() is not None:
            return

        try:
            child_process.terminate()
        except ProcessLookupError:
            return

        try:
            child_process.wait(timeout=self._child_termination_timeout)
        except TimeoutExpired:
            if child_process.poll() is not None:
                return
            try:
                child_process.kill()
            except ProcessLookupError:
                return
            try:
                child_process.wait(timeout=self._child_termination_timeout)
            except (ProcessLookupError, TimeoutExpired):
                return


class JobRegistry:
    """In-memory lifecycle records with at most one active job.

    The registry stores only shared job lifecycle values. It does not record a
    workflow, source, stage, progress, artifact, checkpoint, or error payload.
    """

    def __init__(self) -> None:
        self._lock = Lock()
        self._jobs: dict[JobId, Job] = {}
        self._active_job_id: JobId | None = None

    def reserve(self, job: Job) -> JobStartConflict | None:
        """Record a running job, or return the active-job conflict."""

        if not isinstance(job, Job):
            raise TypeError("job must be a Job")
        if job.lifecycle is not JobLifecycle.RUNNING:
            raise ValueError("only a running job can be reserved")

        with self._lock:
            if self._active_job_id is not None:
                return JobStartConflict(
                    code="job.active_job_conflict",
                    active_job_id=self._active_job_id,
                    message="Another job is already active.",
                )

            self._jobs[job.id] = job
            self._active_job_id = job.id
            return None

    def complete_active(self, job_id: JobId, lifecycle: JobLifecycle) -> Job:
        """Finish the matching active job with a terminal lifecycle value."""

        if not isinstance(job_id, JobId):
            raise TypeError("job_id must be a JobId")
        if lifecycle not in {
            JobLifecycle.COMPLETED,
            JobLifecycle.FAILED,
            JobLifecycle.CANCELLED,
        }:
            raise ValueError("lifecycle must be completed, failed, or cancelled")

        with self._lock:
            if self._active_job_id != job_id:
                raise ValueError("job is not the active job")

            completed = self._jobs[job_id].transition_to(lifecycle)
            self._jobs[job_id] = completed
            self._active_job_id = None
            return completed

    def get(self, job_id: JobId) -> Job | None:
        """Return the current immutable record for one known job."""

        if not isinstance(job_id, JobId):
            raise TypeError("job_id must be a JobId")
        with self._lock:
            return self._jobs.get(job_id)

    @property
    def active_job(self) -> Job | None:
        """Return the current active job, if any."""

        with self._lock:
            if self._active_job_id is None:
                return None
            return self._jobs[self._active_job_id]


class JobRunner:
    """Run one already-selected concrete workflow invocation at a time.

    This boundary owns only execution scheduling and shared job lifecycle
    transitions and cooperative cancellation. The invocation itself owns its
    workflow-specific source, stage ordering, artifacts, and progress/checkpoint
    behavior.
    """

    def __init__(self, *, child_termination_timeout: float = 1.0) -> None:
        if child_termination_timeout <= 0:
            raise ValueError("child_termination_timeout must be greater than zero")
        self._registry = JobRegistry()
        self._executor = ThreadPoolExecutor(
            max_workers=1,
            thread_name_prefix="mint-lingo-job",
        )
        self._futures: dict[JobId, Future[None]] = {}
        self._contexts: dict[JobId, JobExecutionContext] = {}
        self._lock = Lock()
        self._closed = False
        self._child_termination_timeout = child_termination_timeout

    @property
    def active_job(self) -> Job | None:
        """Return the single active job, if an invocation is executing."""

        return self._registry.active_job

    def get_job(self, job_id: JobId) -> Job | None:
        """Return the current lifecycle record for a started job."""

        return self._registry.get(job_id)

    def start(
        self,
        invocation: Callable[[JobExecutionContext], None],
    ) -> Job | JobStartConflict:
        """Start one already-selected invocation or return an active-job conflict."""

        if not callable(invocation):
            raise TypeError("invocation must be callable")

        with self._lock:
            if self._closed:
                raise RuntimeError("job runner is closed")

            job = Job.create().transition_to(JobLifecycle.RUNNING)
            conflict = self._registry.reserve(job)
            if conflict is not None:
                return conflict

            context = JobExecutionContext(
                job.id,
                child_termination_timeout=self._child_termination_timeout,
            )
            self._contexts[job.id] = context

            self._futures[job.id] = self._executor.submit(
                self._run_invocation,
                job.id,
                invocation,
                context,
            )
            return job

    def cancel(
        self,
        job_id: JobId,
    ) -> JobCancellationAccepted | JobCancellationNotFound:
        """Request cooperative cancellation for the matching active job."""

        if not isinstance(job_id, JobId):
            raise TypeError("job_id must be a JobId")

        with self._lock:
            context = self._contexts.get(job_id)
            if context is None:
                return JobCancellationNotFound(
                    code="job.not_found",
                    job_id=job_id,
                    message="Job not found.",
                )
            context.request_cancellation()
            return JobCancellationAccepted(job_id=job_id)

    def wait_for_completion(self, job_id: JobId, timeout: float | None = None) -> Job:
        """Wait for a started invocation and return its terminal lifecycle record."""

        if not isinstance(job_id, JobId):
            raise TypeError("job_id must be a JobId")

        with self._lock:
            future = self._futures.get(job_id)
        if future is None:
            raise KeyError(f"unknown job: {job_id.value}")

        future.result(timeout=timeout)
        job = self._registry.get(job_id)
        if job is None:
            raise RuntimeError("completed job is missing from the registry")
        return job

    def close(self) -> None:
        """Cancel active work, stop accepting jobs, and wait for it to exit."""

        with self._lock:
            if self._closed:
                return
            self._closed = True
            contexts = tuple(self._contexts.values())
            for context in contexts:
                context.request_cancellation()
        self._executor.shutdown(wait=True)

    def _run_invocation(
        self,
        job_id: JobId,
        invocation: Callable[[JobExecutionContext], None],
        context: JobExecutionContext,
    ) -> None:
        lifecycle = JobLifecycle.FAILED
        try:
            invocation(context)
        except JobCancelled:
            lifecycle = JobLifecycle.CANCELLED
        except Exception:
            lifecycle = (
                JobLifecycle.CANCELLED
                if context.cancellation.is_cancelled
                else JobLifecycle.FAILED
            )
        else:
            lifecycle = (
                JobLifecycle.CANCELLED
                if context.cancellation.is_cancelled
                else JobLifecycle.COMPLETED
            )
        finally:
            with self._lock:
                self._registry.complete_active(job_id, lifecycle)
                self._contexts.pop(job_id, None)
