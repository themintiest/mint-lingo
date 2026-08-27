"""Artifact-local safe recovery state for one EPUB translation invocation."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import Enum
import hashlib
import json
import os
from pathlib import Path
import sys
from uuid import UUID, uuid4

from mint_lingo_engine.providers.translation.base import LlmProviderFailure


class EpubRecoveryLifecycle(str, Enum):
    """The resumability state stored beside EPUB translation artifacts."""

    RUNNING = "running"
    RESUMABLE = "resumable"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    FAILED = "failed"


class EpubRecoveryRecordError(ValueError):
    """Raised when the local recovery record cannot be safely retained or read."""


@dataclass(frozen=True)
class EpubRecoveryCandidate:
    """Safe recovery metadata suitable for an EPUB-specific discovery result."""

    recovery_id: str
    source_language: str
    target_language: str
    provider_id: str
    model_id: str
    failure_category: str

    def __post_init__(self) -> None:
        _require_uuid4(self.recovery_id, "recovery_id")
        for name in (
            "source_language",
            "target_language",
            "provider_id",
            "model_id",
            "failure_category",
        ):
            _require_non_blank_string(getattr(self, name), name)

    def to_json(self) -> dict[str, str]:
        """Return the safe discovery representation without paths or text."""

        return {
            "failureCategory": self.failure_category,
            "modelId": self.model_id,
            "providerId": self.provider_id,
            "recoveryId": self.recovery_id,
            "sourceLanguage": self.source_language,
            "targetLanguage": self.target_language,
        }


@dataclass(frozen=True)
class _IndexedRecovery:
    """Private local-index entry that references, but does not copy, artifacts."""

    candidate: EpubRecoveryCandidate
    source_sha256: str
    artifact_root: Path

    def __post_init__(self) -> None:
        if not isinstance(self.candidate, EpubRecoveryCandidate):
            raise TypeError("candidate must be an EpubRecoveryCandidate")
        _require_sha256(self.source_sha256, "source_sha256")
        if not isinstance(self.artifact_root, Path):
            raise TypeError("artifact_root must be a Path")
        object.__setattr__(self, "artifact_root", self.artifact_root.resolve())

    @property
    def record_path(self) -> Path:
        return self.artifact_root / "epub-recovery" / f"{self.candidate.recovery_id}.json"

    def to_json(self) -> dict[str, str]:
        return {
            "artifactRoot": str(self.artifact_root),
            "failureCategory": self.candidate.failure_category,
            "modelId": self.candidate.model_id,
            "providerId": self.candidate.provider_id,
            "recoveryId": self.candidate.recovery_id,
            "sourceLanguage": self.candidate.source_language,
            "sourceSha256": self.source_sha256,
            "targetLanguage": self.candidate.target_language,
        }


class EpubRecoveryIndex:
    """Metadata-only local index for valid artifact-local EPUB recovery records.

    It never stores source/translated text, provider data, prompts, exceptions,
    or checkpoint content. The artifact-local record and checkpoint files stay
    authoritative; this index can only discover and validate a candidate.
    """

    def __init__(self, application_data_root: Path) -> None:
        if not isinstance(application_data_root, Path):
            raise TypeError("application_data_root must be a Path")
        self._application_data_root = application_data_root.resolve()

    @classmethod
    def for_local_application_data(cls) -> "EpubRecoveryIndex":
        """Create the index below the platform's local application-data root."""

        return cls(_local_application_data_root() / "mint-lingo")

    @property
    def path(self) -> Path:
        return self._application_data_root / "epub-recovery-index.json"

    def sync(self, record_path: Path, record: "EpubRecoveryRecord") -> None:
        """Add a resumable record or remove it when its lifecycle is terminal."""

        if not isinstance(record_path, Path):
            raise TypeError("record_path must be a Path")
        if not isinstance(record, EpubRecoveryRecord):
            raise TypeError("record must be an EpubRecoveryRecord")
        entries = self._read_entries()
        entries.pop(record.recovery_id, None)
        if record.is_resumable:
            if record.failure_category is None:
                raise ValueError("resumable recovery record requires a failure category")
            entry = _IndexedRecovery(
                candidate=EpubRecoveryCandidate(
                    recovery_id=record.recovery_id,
                    source_language=record.source_language,
                    target_language=record.target_language,
                    provider_id=record.provider_id,
                    model_id=record.model_id,
                    failure_category=record.failure_category,
                ),
                source_sha256=record.source_sha256,
                artifact_root=Path(record.artifact_root),
            )
            if record_path.resolve() != entry.record_path:
                raise ValueError("record_path must be artifact-local")
            entries[record.recovery_id] = entry
        self._write_entries(entries)

    def list_resumable(self) -> tuple[EpubRecoveryCandidate, ...]:
        """Return only records that still verify against their local artifact."""

        return tuple(entry.candidate for entry in self._validated_entries().values())

    def find_for_source(self, source_path: Path) -> tuple[EpubRecoveryCandidate, ...]:
        """Find candidates for an exact selected-source fingerprint only.

        A selected moved EPUB is therefore relinked only after its bytes match
        the retained record's original SHA-256 fingerprint.
        """

        if not isinstance(source_path, Path):
            raise TypeError("source_path must be a Path")
        try:
            source_sha256 = _source_sha256(source_path)
        except OSError:
            return ()
        return tuple(
            entry.candidate
            for entry in self._validated_entries().values()
            if entry.source_sha256 == source_sha256
        )

    def _validated_entries(self) -> dict[str, _IndexedRecovery]:
        entries = self._read_entries()
        valid_entries: dict[str, _IndexedRecovery] = {}
        for recovery_id, entry in entries.items():
            if _entry_matches_artifact(entry):
                valid_entries[recovery_id] = entry
        if valid_entries != entries:
            self._write_entries(valid_entries)
        return valid_entries

    def _read_entries(self) -> dict[str, _IndexedRecovery]:
        if not self.path.exists():
            return {}
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
            return _index_entries_from_json(payload)
        except (OSError, TypeError, ValueError, json.JSONDecodeError):
            self._write_entries({})
            return {}

    def _write_entries(self, entries: dict[str, _IndexedRecovery]) -> None:
        payload = {
            "recoveries": [
                entries[recovery_id].to_json()
                for recovery_id in sorted(entries)
            ]
        }
        encoded = json.dumps(payload, separators=(",", ":"), sort_keys=True)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary_path = self.path.with_name(f".{self.path.name}.{uuid4().hex}.tmp")
        try:
            with temporary_path.open("x", encoding="utf-8") as file:
                file.write(encoded)
                file.flush()
                os.fsync(file.fileno())
            os.replace(temporary_path, self.path)
        finally:
            if temporary_path.exists():
                temporary_path.unlink()


@dataclass(frozen=True)
class EpubRecoveryRecord:
    """Metadata needed for later EPUB recovery, never translation/provider content."""

    recovery_id: str
    source_sha256: str
    source_language: str
    target_language: str
    provider_id: str
    model_id: str
    artifact_root: str
    checkpoint_namespace: str
    lifecycle: EpubRecoveryLifecycle
    failure_category: str | None = None

    def __post_init__(self) -> None:
        _require_uuid4(self.recovery_id, "recovery_id")
        _require_sha256(self.source_sha256, "source_sha256")
        for name in (
            "source_language",
            "target_language",
            "provider_id",
            "model_id",
            "artifact_root",
            "checkpoint_namespace",
        ):
            _require_non_blank_string(getattr(self, name), name)
        if not isinstance(self.lifecycle, EpubRecoveryLifecycle):
            raise TypeError("lifecycle must be an EpubRecoveryLifecycle")
        if self.failure_category is not None:
            _require_non_blank_string(self.failure_category, "failure_category")
        if self.lifecycle is EpubRecoveryLifecycle.RESUMABLE:
            if self.failure_category is None:
                raise ValueError("resumable recovery records require a failure category")
        elif self.failure_category is not None and self.lifecycle is not EpubRecoveryLifecycle.FAILED:
            raise ValueError("only failed or resumable records may retain a failure category")

    @property
    def is_resumable(self) -> bool:
        """Return whether a later EPUB-specific recovery action may consider it."""

        return self.lifecycle is EpubRecoveryLifecycle.RESUMABLE

    def to_json(self) -> dict[str, object]:
        """Return the fixed metadata-only artifact representation."""

        return {
            "artifactRoot": self.artifact_root,
            "checkpointNamespace": self.checkpoint_namespace,
            "failureCategory": self.failure_category,
            "lifecycle": self.lifecycle.value,
            "modelId": self.model_id,
            "providerId": self.provider_id,
            "recoveryId": self.recovery_id,
            "sourceLanguage": self.source_language,
            "sourceSha256": self.source_sha256,
            "targetLanguage": self.target_language,
        }


class EpubRecoveryRecordStore:
    """Atomically retain one artifact-local recovery record for one invocation.

    This class does not search for records, create an index, match a new source,
    or start a retry job. Those later recovery responsibilities intentionally
    remain outside this task.
    """

    def __init__(self, artifact_root: Path, recovery_id: str | None = None) -> None:
        if not isinstance(artifact_root, Path):
            raise TypeError("artifact_root must be a Path")
        if recovery_id is None:
            recovery_id = str(uuid4())
        _require_uuid4(recovery_id, "recovery_id")
        self._artifact_root = artifact_root.resolve()
        self._recovery_id = recovery_id
        self._last_record: EpubRecoveryRecord | None = None

    @property
    def path(self) -> Path:
        """Return this record's artifact-local path without discovering others."""

        return self._artifact_root / "epub-recovery" / f"{self._recovery_id}.json"

    def create(
        self,
        *,
        source_path: Path,
        source_language: str,
        target_language: str,
        provider_id: str,
        model_id: str,
        checkpoint_namespace: str,
    ) -> EpubRecoveryRecord:
        """Atomically start an invocation record using only its file fingerprint."""

        if not isinstance(source_path, Path):
            raise TypeError("source_path must be a Path")
        record = EpubRecoveryRecord(
            recovery_id=self._recovery_id,
            source_sha256=_source_sha256(source_path),
            source_language=source_language,
            target_language=target_language,
            provider_id=provider_id,
            model_id=model_id,
            artifact_root=str(self._artifact_root),
            checkpoint_namespace=checkpoint_namespace,
            lifecycle=EpubRecoveryLifecycle.RUNNING,
        )
        self._write(record)
        self._last_record = record
        return record

    def mark_completed(self) -> EpubRecoveryRecord:
        """Invalidate the record after a successful export."""

        return self._transition(EpubRecoveryLifecycle.COMPLETED)

    def mark_cancelled(self) -> EpubRecoveryRecord:
        """Invalidate the record when the invocation was cancelled."""

        return self._transition(EpubRecoveryLifecycle.CANCELLED)

    def mark_failed(self, failure: LlmProviderFailure | None = None) -> EpubRecoveryRecord:
        """Retain only a safe retryable provider category, if one is resumable."""

        if failure is not None and not isinstance(failure, LlmProviderFailure):
            raise TypeError("failure must be an LlmProviderFailure or None")
        if failure is not None and failure.retryable:
            return self._transition(
                EpubRecoveryLifecycle.RESUMABLE,
                failure_category=failure.category.value,
            )
        return self._transition(
            EpubRecoveryLifecycle.FAILED,
            failure_category=(None if failure is None else failure.category.value),
        )

    def load(self) -> EpubRecoveryRecord:
        """Read this fixed record only; callers must reject corrupt records."""

        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            self._invalidate_corrupt_if_known()
            raise EpubRecoveryRecordError("EPUB recovery record is not valid JSON") from None
        try:
            record = _record_from_json(payload)
        except (TypeError, ValueError) as error:
            self._invalidate_corrupt_if_known()
            raise EpubRecoveryRecordError("EPUB recovery record is invalid") from None
        self._last_record = record
        return record

    def _transition(
        self,
        lifecycle: EpubRecoveryLifecycle,
        *,
        failure_category: str | None = None,
    ) -> EpubRecoveryRecord:
        current = self.load()
        record = replace(
            current,
            lifecycle=lifecycle,
            failure_category=failure_category,
        )
        self._write(record)
        self._last_record = record
        return record

    def _invalidate_corrupt_if_known(self) -> None:
        """Overwrite a known damaged record with a non-resumable safe state."""

        if self._last_record is None:
            return
        invalidated = replace(
            self._last_record,
            lifecycle=EpubRecoveryLifecycle.FAILED,
            failure_category=None,
        )
        try:
            self._write(invalidated)
        except OSError:
            return
        self._last_record = invalidated

    def _write(self, record: EpubRecoveryRecord) -> None:
        encoded = json.dumps(record.to_json(), separators=(",", ":"), sort_keys=True)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary_path = self.path.with_name(f".{self.path.name}.{uuid4().hex}.tmp")
        try:
            with temporary_path.open("x", encoding="utf-8") as file:
                file.write(encoded)
                file.flush()
                os.fsync(file.fileno())
            os.replace(temporary_path, self.path)
        finally:
            if temporary_path.exists():
                temporary_path.unlink()


def _record_from_json(payload: object) -> EpubRecoveryRecord:
    if not isinstance(payload, dict) or set(payload) != {
        "artifactRoot",
        "checkpointNamespace",
        "failureCategory",
        "lifecycle",
        "modelId",
        "providerId",
        "recoveryId",
        "sourceLanguage",
        "sourceSha256",
        "targetLanguage",
    }:
        raise ValueError("recovery record has unsupported fields")
    return EpubRecoveryRecord(
        recovery_id=payload["recoveryId"],
        source_sha256=payload["sourceSha256"],
        source_language=payload["sourceLanguage"],
        target_language=payload["targetLanguage"],
        provider_id=payload["providerId"],
        model_id=payload["modelId"],
        artifact_root=payload["artifactRoot"],
        checkpoint_namespace=payload["checkpointNamespace"],
        lifecycle=EpubRecoveryLifecycle(payload["lifecycle"]),
        failure_category=payload["failureCategory"],
    )


def _index_entries_from_json(payload: object) -> dict[str, _IndexedRecovery]:
    if not isinstance(payload, dict) or set(payload) != {"recoveries"}:
        raise ValueError("recovery index has unsupported fields")
    recoveries = payload["recoveries"]
    if not isinstance(recoveries, list):
        raise TypeError("recovery index recoveries must be a list")
    entries: dict[str, _IndexedRecovery] = {}
    for item in recoveries:
        if not isinstance(item, dict) or set(item) != {
            "artifactRoot",
            "failureCategory",
            "modelId",
            "providerId",
            "recoveryId",
            "sourceLanguage",
            "sourceSha256",
            "targetLanguage",
        }:
            raise ValueError("recovery index entry has unsupported fields")
        entry = _IndexedRecovery(
            candidate=EpubRecoveryCandidate(
                recovery_id=item["recoveryId"],
                source_language=item["sourceLanguage"],
                target_language=item["targetLanguage"],
                provider_id=item["providerId"],
                model_id=item["modelId"],
                failure_category=item["failureCategory"],
            ),
            source_sha256=item["sourceSha256"],
            artifact_root=Path(item["artifactRoot"]),
        )
        if entry.candidate.recovery_id in entries:
            raise ValueError("recovery index entry IDs must be unique")
        entries[entry.candidate.recovery_id] = entry
    return entries


def _entry_matches_artifact(entry: _IndexedRecovery) -> bool:
    """Verify the index entry against its authoritative artifact-local record."""

    store = EpubRecoveryRecordStore(
        entry.artifact_root,
        entry.candidate.recovery_id,
    )
    try:
        record = store.load()
    except EpubRecoveryRecordError:
        return False
    return (
        record.is_resumable
        and record.recovery_id == entry.candidate.recovery_id
        and record.source_sha256 == entry.source_sha256
        and Path(record.artifact_root).resolve() == entry.artifact_root
        and record.source_language == entry.candidate.source_language
        and record.target_language == entry.candidate.target_language
        and record.provider_id == entry.candidate.provider_id
        and record.model_id == entry.candidate.model_id
        and record.failure_category == entry.candidate.failure_category
    )


def _local_application_data_root() -> Path:
    """Return a cross-platform local application-data root without a dependency."""

    if os.name == "nt":
        configured = os.environ.get("LOCALAPPDATA")
        if configured:
            return Path(configured)
        return Path.home() / "AppData" / "Local"
    if sys_platform := os.environ.get("XDG_DATA_HOME"):
        return Path(sys_platform)
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support"
    return Path.home() / ".local" / "share"


def _source_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source_file:
        for chunk in iter(lambda: source_file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _require_uuid4(value: object, name: str) -> None:
    if not isinstance(value, str):
        raise TypeError(f"{name} must be a canonical UUIDv4")
    try:
        parsed = UUID(value)
    except (ValueError, AttributeError) as error:
        raise ValueError(f"{name} must be a canonical UUIDv4") from error
    if parsed.version != 4 or str(parsed) != value:
        raise ValueError(f"{name} must be a canonical UUIDv4")


def _require_sha256(value: object, name: str) -> None:
    if not isinstance(value, str):
        raise TypeError(f"{name} must be a SHA-256 string")
    if len(value) != 64 or any(character not in "0123456789abcdef" for character in value):
        raise ValueError(f"{name} must be a lowercase SHA-256 string")


def _require_non_blank_string(value: object, name: str) -> None:
    if not isinstance(value, str):
        raise TypeError(f"{name} must be a string")
    if not value or value.strip() != value:
        raise ValueError(f"{name} must not be blank or padded")
