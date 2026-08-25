"""Workload-agnostic temporary workspace ownership for one job execution."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from shutil import rmtree

from mint_lingo_engine.job import JobId


@dataclass(frozen=True)
class JobWorkspace:
    """The temporary directory assigned exclusively to one stable job ID.

    A concrete workflow owns the meanings and names of files it creates inside
    this directory. Shared infrastructure only assigns the directory and
    cleans it when the invocation reaches a terminal lifecycle state.
    """

    job_id: JobId
    path: Path

    def __post_init__(self) -> None:
        if not isinstance(self.job_id, JobId):
            raise TypeError("job_id must be a JobId")
        if not isinstance(self.path, Path):
            raise TypeError("path must be a Path")


class JobWorkspaceManager:
    """Allocate and clean job-scoped directories below one temporary root.

    The supplied root is the engine's temporary area (for example,
    ``<project>/temporary``), not the project root or an artifact directory.
    This boundary never reads or writes persistent project files.
    """

    def __init__(self, temporary_root: Path | str) -> None:
        if not isinstance(temporary_root, (Path, str)):
            raise TypeError("temporary_root must be a path")

        self._temporary_root = Path(temporary_root).resolve()
        if self._temporary_root.exists() and not self._temporary_root.is_dir():
            raise ValueError("temporary_root must be a directory")

    @property
    def temporary_root(self) -> Path:
        """Return the engine-owned root that contains per-job workspaces."""

        return self._temporary_root

    def allocate(self, job_id: JobId) -> JobWorkspace:
        """Create an empty workspace for one job without reusing old work."""

        if not isinstance(job_id, JobId):
            raise TypeError("job_id must be a JobId")

        self._temporary_root.mkdir(parents=True, exist_ok=True)
        workspace_path = self._workspace_path_for(job_id)
        try:
            workspace_path.mkdir()
        except FileExistsError as error:
            raise FileExistsError(
                f"temporary workspace already exists for job {job_id.value}"
            ) from error
        return JobWorkspace(job_id=job_id, path=workspace_path)

    def cleanup(self, workspace: JobWorkspace) -> None:
        """Remove only the supplied workspace after its job invocation exits.

        Cleanup is intentionally agnostic to file names and artifact types. It
        is idempotent for an already-removed workspace, but never permits this
        manager to remove a sibling, parent, or external directory.
        """

        if not isinstance(workspace, JobWorkspace):
            raise TypeError("workspace must be a JobWorkspace")

        expected_path = self._workspace_path_for(workspace.job_id)
        workspace_path = workspace.path.resolve()
        if workspace_path != expected_path or not workspace_path.is_relative_to(
            self._temporary_root
        ):
            raise ValueError("workspace is not owned by this temporary root")
        if not workspace_path.exists():
            return
        if not workspace_path.is_dir():
            raise ValueError("workspace must be a directory")

        rmtree(workspace_path)

    def _workspace_path_for(self, job_id: JobId) -> Path:
        return self._temporary_root / f"job-{job_id.value}"
