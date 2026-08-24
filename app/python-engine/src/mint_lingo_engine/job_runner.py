"""Single-active-job execution and in-memory registration boundary."""

from __future__ import annotations

from collections.abc import Callable
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass
from threading import Lock

from mint_lingo_engine.job import Job, JobId, JobLifecycle


@dataclass(frozen=True)
class JobStartConflict:
    """A structured refusal to start while another job is active."""

    code: str
    active_job_id: JobId
    message: str


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
        if lifecycle not in {JobLifecycle.COMPLETED, JobLifecycle.FAILED}:
            raise ValueError("lifecycle must be completed or failed")

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
    transitions. The invocation itself owns its workflow-specific source,
    stage ordering, artifacts, and any future progress/checkpoint behavior.
    """

    def __init__(self) -> None:
        self._registry = JobRegistry()
        self._executor = ThreadPoolExecutor(
            max_workers=1,
            thread_name_prefix="mint-lingo-job",
        )
        self._futures: dict[JobId, Future[None]] = {}
        self._lock = Lock()
        self._closed = False

    @property
    def active_job(self) -> Job | None:
        """Return the single active job, if an invocation is executing."""

        return self._registry.active_job

    def get_job(self, job_id: JobId) -> Job | None:
        """Return the current lifecycle record for a started job."""

        return self._registry.get(job_id)

    def start(self, invocation: Callable[[], None]) -> Job | JobStartConflict:
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

            self._futures[job.id] = self._executor.submit(
                self._run_invocation,
                job.id,
                invocation,
            )
            return job

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
        """Stop accepting work and wait for the currently running invocation."""

        with self._lock:
            if self._closed:
                return
            self._closed = True
        self._executor.shutdown(wait=True)

    def _run_invocation(self, job_id: JobId, invocation: Callable[[], None]) -> None:
        try:
            invocation()
        except Exception:
            self._registry.complete_active(job_id, JobLifecycle.FAILED)
        else:
            self._registry.complete_active(job_id, JobLifecycle.COMPLETED)
