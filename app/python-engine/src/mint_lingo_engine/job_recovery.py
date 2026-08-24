"""Recovery reconciliation for interrupted jobs and retained checkpoints."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from enum import Enum

from mint_lingo_engine.checkpoint import CheckpointFormatError, CheckpointStore
from mint_lingo_engine.job import Job, JobLifecycle


class RecoveryDisposition(str, Enum):
    """The shared result of examining an interrupted lifecycle envelope."""

    NOT_REQUIRED = "notRequired"
    RECOVERABLE = "recoverable"
    FAILED = "failed"


@dataclass(frozen=True)
class JobRecoveryResult:
    """A reconciled lifecycle plus references whose checkpoint records verify.

    ``RECOVERABLE`` states only that retained checkpoints survived verification.
    The concrete workflow still decides whether and how it can resume from
    those checkpoints; this shared result contains no stage or artifact meaning.
    """

    job: Job
    disposition: RecoveryDisposition
    verified_checkpoint_references: tuple[str, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.job, Job):
            raise TypeError("job must be a Job")
        if not isinstance(self.disposition, RecoveryDisposition):
            raise TypeError("disposition must be a RecoveryDisposition")
        if not all(isinstance(reference, str) for reference in self.verified_checkpoint_references):
            raise TypeError("verified_checkpoint_references must contain strings")


class JobRecoveryReconciler:
    """Reconcile a possibly orphaned running job without workflow orchestration.

    The reconciler does not read or write Flutter's project manifest, start a
    worker, remove any checkpoint/artifact, or pick a workflow stage. It simply
    converts a persisted running job into its shared terminal ``failed``
    lifecycle and reports whether every supplied checkpoint record verified.
    """

    def __init__(self, checkpoint_store: CheckpointStore) -> None:
        if not isinstance(checkpoint_store, CheckpointStore):
            raise TypeError("checkpoint_store must be a CheckpointStore")
        self._checkpoint_store = checkpoint_store

    def reconcile(
        self,
        job: Job,
        checkpoint_references: Iterable[str],
    ) -> JobRecoveryResult:
        """Reconcile a persisted lifecycle after the previous process ended.

        A non-running job is already deterministic and needs no work. For a
        running job, every supplied record must load through CHECK-01 before
        the result is recoverable. Missing, damaged, or invalid records make
        the result failed, while any earlier verified records remain preserved.
        """

        if not isinstance(job, Job):
            raise TypeError("job must be a Job")
        references = _checkpoint_references(checkpoint_references)
        if job.lifecycle is not JobLifecycle.RUNNING:
            return JobRecoveryResult(
                job=job,
                disposition=RecoveryDisposition.NOT_REQUIRED,
                verified_checkpoint_references=(),
            )

        reconciled_job = job.transition_to(JobLifecycle.FAILED)
        verified_references: list[str] = []
        for reference in references:
            try:
                self._checkpoint_store.load(reference)
            except (FileNotFoundError, CheckpointFormatError):
                return JobRecoveryResult(
                    job=reconciled_job,
                    disposition=RecoveryDisposition.FAILED,
                    verified_checkpoint_references=tuple(verified_references),
                )
            verified_references.append(reference)

        disposition = (
            RecoveryDisposition.RECOVERABLE
            if verified_references
            else RecoveryDisposition.FAILED
        )
        return JobRecoveryResult(
            job=reconciled_job,
            disposition=disposition,
            verified_checkpoint_references=tuple(verified_references),
        )


def _checkpoint_references(value: Iterable[str]) -> tuple[str, ...]:
    if isinstance(value, str):
        raise TypeError("checkpoint_references must be an iterable of strings")
    try:
        references = tuple(value)
    except TypeError as error:
        raise TypeError("checkpoint_references must be an iterable of strings") from error
    if not all(isinstance(reference, str) for reference in references):
        raise TypeError("checkpoint_references must contain strings")
    return references
