"""Atomic, workflow-agnostic retention of completed checkpoint metadata."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
from uuid import uuid4


class CheckpointFormatError(ValueError):
    """Raised when checkpoint metadata or a checkpoint record is invalid."""


class CheckpointConflictError(ValueError):
    """Raised when an existing checkpoint ID describes different metadata."""


_CHECKPOINT_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


@dataclass(frozen=True)
class Checkpoint:
    """One workflow-confirmed checkpoint and its opaque retained artifact.

    The presence of this value means the concrete workflow has already decided
    that its checkpoint is complete and valid. Shared infrastructure records no
    stage, unit, source-format, or artifact-content semantics.
    """

    checkpoint_id: str
    artifact_reference: str

    def __post_init__(self) -> None:
        if not isinstance(self.checkpoint_id, str):
            raise TypeError("checkpoint_id must be a string")
        if not _CHECKPOINT_ID_PATTERN.fullmatch(self.checkpoint_id):
            raise CheckpointFormatError(
                "checkpoint_id must be a non-empty portable identifier"
            )
        _validate_relative_reference(self.artifact_reference, "artifact_reference")


@dataclass(frozen=True)
class StoredCheckpoint:
    """A retained checkpoint plus its stable project-relative record reference."""

    checkpoint: Checkpoint
    reference: str

    def __post_init__(self) -> None:
        if not isinstance(self.checkpoint, Checkpoint):
            raise TypeError("checkpoint must be a Checkpoint")
        _validate_relative_reference(self.reference, "reference")


class CheckpointStore:
    """Atomically retain workflow-confirmed checkpoints below an artifact root.

    ``artifact_root`` is the engine-owned persistent artifact directory. Its
    project-relative name is supplied explicitly so references remain portable
    and this store never needs to infer a project layout from workflow files.
    """

    def __init__(
        self,
        artifact_root: Path | str,
        *,
        artifact_root_reference: str = "artifacts",
        write_temporary_file: Callable[[Path, str], None] | None = None,
    ) -> None:
        if not isinstance(artifact_root, (Path, str)):
            raise TypeError("artifact_root must be a path")
        _validate_relative_reference(
            artifact_root_reference,
            "artifact_root_reference",
        )

        self._artifact_root = Path(artifact_root).resolve()
        if self._artifact_root.exists() and not self._artifact_root.is_dir():
            raise ValueError("artifact_root must be a directory")
        self._artifact_root_reference = artifact_root_reference
        self._artifact_root_parts = PurePosixPath(artifact_root_reference).parts
        self._checkpoint_root = self._artifact_root / "checkpoints"
        self._write_temporary_file = (
            write_temporary_file or self._write_temporary_file_to_disk
        )

    def record(self, checkpoint: Checkpoint) -> StoredCheckpoint:
        """Atomically retain one completed workflow checkpoint.

        Re-recording identical metadata is idempotent. The same checkpoint ID
        cannot replace a prior record with a different artifact reference.
        """

        if not isinstance(checkpoint, Checkpoint):
            raise TypeError("checkpoint must be a Checkpoint")
        self._validate_artifact_reference(checkpoint.artifact_reference)

        reference = self._reference_for(checkpoint.checkpoint_id)
        destination = self._path_for(checkpoint.checkpoint_id)
        if destination.exists():
            existing = self.load(reference)
            if existing.checkpoint != checkpoint:
                raise CheckpointConflictError(
                    f"checkpoint already exists: {checkpoint.checkpoint_id}"
                )
            return existing

        self._checkpoint_root.mkdir(parents=True, exist_ok=True)
        temporary_file = self._temporary_path_for(checkpoint.checkpoint_id)
        encoded = json.dumps(
            {
                "checkpointId": checkpoint.checkpoint_id,
                "artifactReference": checkpoint.artifact_reference,
            },
            separators=(",", ":"),
            sort_keys=True,
        )
        try:
            self._write_temporary_file(temporary_file, encoded)
            os.replace(temporary_file, destination)
        finally:
            if temporary_file.exists():
                temporary_file.unlink()

        return StoredCheckpoint(checkpoint=checkpoint, reference=reference)

    def load(self, reference: str) -> StoredCheckpoint:
        """Load and validate one retained checkpoint record without recovery."""

        checkpoint_id = self._checkpoint_id_from_reference(reference)
        record_path = self._path_for(checkpoint_id)
        try:
            decoded = json.loads(record_path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            raise
        except (OSError, json.JSONDecodeError) as error:
            raise CheckpointFormatError("checkpoint record is not valid JSON") from error

        if not isinstance(decoded, dict) or set(decoded) != {
            "checkpointId",
            "artifactReference",
        }:
            raise CheckpointFormatError("checkpoint record has unsupported fields")

        try:
            checkpoint = Checkpoint(
                checkpoint_id=decoded["checkpointId"],
                artifact_reference=decoded["artifactReference"],
            )
        except (TypeError, CheckpointFormatError) as error:
            raise CheckpointFormatError("checkpoint record has invalid metadata") from error

        if checkpoint.checkpoint_id != checkpoint_id:
            raise CheckpointFormatError("checkpoint record ID does not match its reference")
        self._validate_artifact_reference(checkpoint.artifact_reference)
        return StoredCheckpoint(checkpoint=checkpoint, reference=reference)

    def _validate_artifact_reference(self, artifact_reference: str) -> None:
        artifact_parts = PurePosixPath(artifact_reference).parts
        if artifact_parts[: len(self._artifact_root_parts)] != self._artifact_root_parts:
            raise CheckpointFormatError(
                "artifact_reference must stay beneath artifact_root_reference"
            )
        relative_parts = artifact_parts[len(self._artifact_root_parts) :]
        if not relative_parts:
            raise CheckpointFormatError("artifact_reference must identify an artifact")

        artifact_path = self._artifact_root.joinpath(*relative_parts)
        try:
            resolved_artifact_path = artifact_path.resolve(strict=True)
        except FileNotFoundError as error:
            raise CheckpointFormatError(
                "artifact_reference must identify a retained artifact"
            ) from error
        if not resolved_artifact_path.is_relative_to(self._artifact_root):
            raise CheckpointFormatError(
                "artifact_reference must stay beneath artifact_root_reference"
            )

    def _reference_for(self, checkpoint_id: str) -> str:
        return str(
            PurePosixPath(self._artifact_root_reference)
            / "checkpoints"
            / f"{checkpoint_id}.json"
        )

    def _path_for(self, checkpoint_id: str) -> Path:
        return self._checkpoint_root / f"{checkpoint_id}.json"

    def _temporary_path_for(self, checkpoint_id: str) -> Path:
        return self._checkpoint_root / f".{checkpoint_id}.{uuid4().hex}.tmp"

    def _checkpoint_id_from_reference(self, reference: str) -> str:
        _validate_relative_reference(reference, "reference")
        parts = PurePosixPath(reference).parts
        expected_prefix = (*self._artifact_root_parts, "checkpoints")
        if len(parts) != len(expected_prefix) + 1 or parts[: len(expected_prefix)] != (
            expected_prefix
        ):
            raise CheckpointFormatError("reference is not a checkpoint record")

        filename = parts[-1]
        if not filename.endswith(".json"):
            raise CheckpointFormatError("reference is not a checkpoint record")
        checkpoint_id = filename.removesuffix(".json")
        if not _CHECKPOINT_ID_PATTERN.fullmatch(checkpoint_id):
            raise CheckpointFormatError("reference has an invalid checkpoint ID")
        return checkpoint_id

    @staticmethod
    def _write_temporary_file_to_disk(path: Path, contents: str) -> None:
        with path.open("x", encoding="utf-8") as file:
            file.write(contents)
            file.flush()
            os.fsync(file.fileno())


def _validate_relative_reference(value: object, name: str) -> None:
    if not isinstance(value, str):
        raise TypeError(f"{name} must be a string")
    if not value or value.strip() != value:
        raise CheckpointFormatError(f"{name} must be a non-empty trimmed string")
    if "\\" in value or ":" in value or "//" in value:
        raise CheckpointFormatError(f"{name} must use a portable relative path")

    posix_path = PurePosixPath(value)
    windows_path = PureWindowsPath(value)
    if posix_path.is_absolute() or windows_path.is_absolute():
        raise CheckpointFormatError(f"{name} must be relative")
    if any(part in {"", ".", ".."} for part in posix_path.parts):
        raise CheckpointFormatError(f"{name} must not contain traversal components")
