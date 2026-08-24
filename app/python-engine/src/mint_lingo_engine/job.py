"""Workflow-neutral processing-job identity and lifecycle domain values."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import Enum
from uuid import UUID, uuid4


@dataclass(frozen=True)
class JobId:
    """A stable, canonical UUIDv4 identity for one job execution."""

    value: str

    def __post_init__(self) -> None:
        if not isinstance(self.value, str):
            raise TypeError("job ID value must be a string")

        try:
            parsed = UUID(self.value)
        except (AttributeError, ValueError) as error:
            raise ValueError("job ID value must be a canonical UUIDv4") from error

        if parsed.version != 4 or str(parsed) != self.value:
            raise ValueError("job ID value must be a canonical UUIDv4")

    @classmethod
    def new(cls) -> JobId:
        """Create a new stable identity for one execution."""

        return cls(str(uuid4()))


class JobLifecycle(str, Enum):
    """The shared lifecycle, separate from workflow-defined processing stages."""

    CREATED = "created"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


_LEGAL_TRANSITIONS: dict[JobLifecycle, frozenset[JobLifecycle]] = {
    JobLifecycle.CREATED: frozenset({JobLifecycle.RUNNING, JobLifecycle.CANCELLED}),
    JobLifecycle.RUNNING: frozenset(
        {JobLifecycle.COMPLETED, JobLifecycle.FAILED, JobLifecycle.CANCELLED}
    ),
    JobLifecycle.COMPLETED: frozenset(),
    JobLifecycle.FAILED: frozenset(),
    JobLifecycle.CANCELLED: frozenset(),
}


class JobTransitionError(ValueError):
    """Raised when a lifecycle transition is not legal for the current job."""


@dataclass(frozen=True)
class Job:
    """One execution of an already-selected concrete workflow.

    This model owns no workflow name, source, stage identifier, progress,
    checkpoint, or error payload. Those values are introduced by their
    respective later M4 boundaries.
    """

    id: JobId
    lifecycle: JobLifecycle = JobLifecycle.CREATED

    def __post_init__(self) -> None:
        if not isinstance(self.id, JobId):
            raise TypeError("id must be a JobId")
        if not isinstance(self.lifecycle, JobLifecycle):
            raise TypeError("lifecycle must be a JobLifecycle")

    @classmethod
    def create(cls) -> Job:
        """Create a job in the only initial lifecycle state."""

        return cls(id=JobId.new())

    @property
    def is_terminal(self) -> bool:
        """Whether this job can no longer make a lifecycle transition."""

        return not _LEGAL_TRANSITIONS[self.lifecycle]

    def transition_to(self, next_lifecycle: JobLifecycle) -> Job:
        """Return the job in [next_lifecycle] when that transition is legal."""

        if not isinstance(next_lifecycle, JobLifecycle):
            raise TypeError("next_lifecycle must be a JobLifecycle")
        if next_lifecycle not in _LEGAL_TRANSITIONS[self.lifecycle]:
            raise JobTransitionError(
                f"cannot transition job from {self.lifecycle.value} "
                f"to {next_lifecycle.value}"
            )
        return replace(self, lifecycle=next_lifecycle)
