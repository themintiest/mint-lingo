"""EPUB-owned retention of validated translation units for later resume."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
from uuid import uuid4

from mint_lingo_engine.processing.checkpoint import Checkpoint, CheckpointStore
from mint_lingo_engine.translation.models import (
    StructuredTextArtifact,
    TranslatedTextUnit,
    TranslationArtifact,
    TranslationRequest,
)
from mint_lingo_engine.translation.validation import validate_translation_artifact


class EpubTranslationCheckpointError(ValueError):
    """Raised when retained EPUB translation data is incompatible or malformed."""


_NAMESPACE_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


@dataclass(frozen=True)
class EpubTranslationCheckpointStore:
    """Retain EPUB translation results while leaving generic checkpoints opaque.

    ``checkpoint_namespace`` is supplied by the caller and must remain stable
    when resuming the same EPUB translation. The stored record binds each
    result to its stable unit ID, exact source text, source language, and
    target language before it can be reused.
    """

    artifact_root: Path
    checkpoint_namespace: str

    def __post_init__(self) -> None:
        if not isinstance(self.artifact_root, Path):
            raise TypeError("artifact_root must be a Path")
        if not isinstance(self.checkpoint_namespace, str):
            raise TypeError("checkpoint_namespace must be a string")
        if not _NAMESPACE_PATTERN.fullmatch(self.checkpoint_namespace):
            raise ValueError("checkpoint_namespace must be a portable identifier")
        object.__setattr__(self, "artifact_root", self.artifact_root.resolve())
        object.__setattr__(self, "_checkpoint_store", CheckpointStore(self.artifact_root))

    def load_completed(
        self,
        artifact: StructuredTextArtifact,
        target_language: str,
    ) -> TranslationArtifact:
        """Return only valid retained results for the exact current projection."""

        if not isinstance(artifact, StructuredTextArtifact):
            raise TypeError("artifact must be a StructuredTextArtifact")
        completed_units: list[TranslatedTextUnit] = []
        for unit in artifact.units:
            checkpoint_path = self.artifact_root / "checkpoints" / (
                f"{self._checkpoint_id_for(unit.unit_id)}.json"
            )
            if not checkpoint_path.exists():
                continue
            stored = self._checkpoint_store.load(self._checkpoint_reference_for(unit.unit_id))
            expected_artifact_reference = self._artifact_reference_for(unit.unit_id)
            if stored.checkpoint.artifact_reference != expected_artifact_reference:
                raise EpubTranslationCheckpointError(
                    "EPUB translation checkpoint has an unexpected artifact reference"
                )
            completed_units.append(
                self._load_unit(
                    unit_id=unit.unit_id,
                    source_text=unit.text,
                    source_language=artifact.source_language,
                    target_language=target_language,
                )
            )
        return TranslationArtifact(
            target_language=target_language,
            units=tuple(completed_units),
        )

    def record(
        self,
        request: TranslationRequest,
        translation: TranslationArtifact,
    ) -> None:
        """Atomically retain every fully validated unit in one completed request."""

        validation = validate_translation_artifact(request, translation)
        if not isinstance(validation, TranslationArtifact):
            raise EpubTranslationCheckpointError(
                "EPUB translation checkpoints require a valid translation artifact"
            )

        translated_by_id = {unit.unit_id: unit for unit in validation.units}
        for source_unit in request.artifact.units:
            translated_unit = translated_by_id[source_unit.unit_id]
            artifact_path = self._artifact_path_for(source_unit.unit_id)
            payload = {
                "sourceLanguage": request.artifact.source_language,
                "sourceTextDigest": _source_text_digest(source_unit.text),
                "targetLanguage": request.target_language,
                "translatedText": translated_unit.translated_text,
                "unitId": source_unit.unit_id,
            }
            self._write_unit_artifact(artifact_path, payload)
            self._checkpoint_store.record(
                Checkpoint(
                    checkpoint_id=self._checkpoint_id_for(source_unit.unit_id),
                    artifact_reference=self._artifact_reference_for(source_unit.unit_id),
                )
            )

    def _load_unit(
        self,
        *,
        unit_id: str,
        source_text: str,
        source_language: str,
        target_language: str,
    ) -> TranslatedTextUnit:
        artifact_path = self._artifact_path_for(unit_id)
        try:
            payload = json.loads(artifact_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise EpubTranslationCheckpointError(
                "EPUB translation checkpoint artifact is not valid JSON"
            ) from error
        expected = {
            "sourceLanguage": source_language,
            "sourceTextDigest": _source_text_digest(source_text),
            "targetLanguage": target_language,
            "unitId": unit_id,
        }
        if not isinstance(payload, dict) or set(payload) != {
            *expected,
            "translatedText",
        }:
            raise EpubTranslationCheckpointError(
                "EPUB translation checkpoint artifact has unsupported fields"
            )
        if any(payload[name] != value for name, value in expected.items()):
            raise EpubTranslationCheckpointError(
                "EPUB translation checkpoint does not match the current source or target"
            )
        translated_text = payload["translatedText"]
        if not isinstance(translated_text, str) or not translated_text.strip():
            raise EpubTranslationCheckpointError(
                "EPUB translation checkpoint has invalid translated text"
            )
        try:
            return TranslatedTextUnit(
                unit_id=payload["unitId"],
                translated_text=translated_text,
            )
        except TypeError as error:
            raise EpubTranslationCheckpointError(
                "EPUB translation checkpoint has invalid translated text"
            ) from error

    def _write_unit_artifact(self, path: Path, payload: dict[str, str]) -> None:
        encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        if path.exists():
            try:
                existing = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as error:
                raise EpubTranslationCheckpointError(
                    "EPUB translation checkpoint artifact is not valid JSON"
                ) from error
            if existing != payload:
                raise EpubTranslationCheckpointError(
                    "EPUB translation checkpoint conflicts with completed unit data"
                )
            return

        path.parent.mkdir(parents=True, exist_ok=True)
        temporary_path = path.with_name(f".{path.name}.{uuid4().hex}.tmp")
        try:
            with temporary_path.open("x", encoding="utf-8") as file:
                file.write(encoded)
                file.flush()
                os.fsync(file.fileno())
            os.replace(temporary_path, path)
        finally:
            if temporary_path.exists():
                temporary_path.unlink()

    def _checkpoint_id_for(self, unit_id: str) -> str:
        return f"epub.{_unit_digest(self.checkpoint_namespace, unit_id)}"

    def _checkpoint_reference_for(self, unit_id: str) -> str:
        return f"artifacts/checkpoints/{self._checkpoint_id_for(unit_id)}.json"

    def _artifact_reference_for(self, unit_id: str) -> str:
        return (
            "artifacts/epub-translation/"
            f"{self.checkpoint_namespace}/{_unit_digest(self.checkpoint_namespace, unit_id)}.json"
        )

    def _artifact_path_for(self, unit_id: str) -> Path:
        return self.artifact_root / "epub-translation" / self.checkpoint_namespace / (
            f"{_unit_digest(self.checkpoint_namespace, unit_id)}.json"
        )


def _unit_digest(namespace: str, unit_id: str) -> str:
    return hashlib.sha256(f"{namespace}\0{unit_id}".encode("utf-8")).hexdigest()


def _source_text_digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()
