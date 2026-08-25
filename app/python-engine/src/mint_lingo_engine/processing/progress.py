"""Workflow-owned stage and truthful progress notification domain values."""

from __future__ import annotations

from dataclasses import dataclass

from mint_lingo_engine.processing.job import JobId


@dataclass(frozen=True)
class DeterminateProgress:
    """Exact completed and total work units reported by one workflow stage."""

    completed_units: int
    total_units: int

    def __post_init__(self) -> None:
        if (
            not isinstance(self.completed_units, int)
            or isinstance(self.completed_units, bool)
        ):
            raise TypeError("completed_units must be an integer")
        if not isinstance(self.total_units, int) or isinstance(self.total_units, bool):
            raise TypeError("total_units must be an integer")
        if self.total_units <= 0:
            raise ValueError("total_units must be greater than zero")
        if not 0 <= self.completed_units <= self.total_units:
            raise ValueError("completed_units must be between zero and total_units")

    @property
    def fraction_complete(self) -> float:
        """Return the exact completion fraction derived from known work units."""

        return self.completed_units / self.total_units


@dataclass(frozen=True)
class IndeterminateProgress:
    """A stage where the workflow cannot truthfully provide a total."""


JobProgress = DeterminateProgress | IndeterminateProgress


@dataclass(frozen=True)
class JobProgressNotification:
    """One workflow-owned stage/progress update for a stable job identity.

    `stage_id` is intentionally an opaque workflow-defined string. This model
    does not create a shared stage enum, prescribe stage ordering, or define
    JSON-RPC event transport.
    """

    job_id: JobId
    stage_id: str
    progress: JobProgress

    def __post_init__(self) -> None:
        if not isinstance(self.job_id, JobId):
            raise TypeError("job_id must be a JobId")
        if (
            not isinstance(self.stage_id, str)
            or not self.stage_id
            or self.stage_id.strip() != self.stage_id
        ):
            raise ValueError("stage_id must be a non-empty trimmed string")
        if not isinstance(self.progress, (DeterminateProgress, IndeterminateProgress)):
            raise TypeError(
                "progress must be DeterminateProgress or IndeterminateProgress"
            )
