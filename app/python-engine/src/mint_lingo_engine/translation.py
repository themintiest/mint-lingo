"""Source-agnostic values at the shared structured-text translation seam.

Concrete workflows project their translatable content into
``StructuredTextArtifact`` and later merge ``TranslationArtifact`` units back
into their own artifacts. This module intentionally owns neither projection,
merging, batching, provider invocation, validation, nor workflow behavior.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass


@dataclass(frozen=True)
class StructuredTextUnit:
    """One source-text value with workflow-owned stable identity."""

    unit_id: str
    text: str

    def __post_init__(self) -> None:
        _require_identifier(self.unit_id, "unit_id")
        _require_text(self.text, "text")


@dataclass(frozen=True)
class StructuredTextArtifact:
    """Ordered source text projected from one concrete workflow artifact."""

    source_language: str
    units: tuple[StructuredTextUnit, ...]

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "source_language",
            _require_language(self.source_language, "source_language"),
        )
        units = _to_tuple(self.units, "units")
        if not units:
            raise ValueError("units must not be empty")
        if any(not isinstance(unit, StructuredTextUnit) for unit in units):
            raise TypeError("units must contain only StructuredTextUnit values")
        _require_unique_unit_ids(units)
        object.__setattr__(self, "units", units)


@dataclass(frozen=True)
class TranslationRequest:
    """A provider-neutral request to translate structured source text.

    ``context`` is optional workflow-neutral text supplied with this request.
    Context construction, batch ownership, and provider prompting remain later
    shared translation capabilities.
    """

    artifact: StructuredTextArtifact
    target_language: str
    context: str | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.artifact, StructuredTextArtifact):
            raise TypeError("artifact must be a StructuredTextArtifact")
        object.__setattr__(
            self,
            "target_language",
            _require_language(self.target_language, "target_language"),
        )
        if self.context is not None:
            if not isinstance(self.context, str):
                raise TypeError("context must be a string or None")


@dataclass(frozen=True)
class TranslatedTextUnit:
    """One translated result retaining the requested stable unit identity."""

    unit_id: str
    translated_text: str

    def __post_init__(self) -> None:
        if not isinstance(self.unit_id, str):
            raise TypeError("unit_id must be a string")
        if not isinstance(self.translated_text, str):
            raise TypeError("translated_text must be a string")


@dataclass(frozen=True)
class TranslationArtifact:
    """Ordered translated units returned by the shared translation capability.

    The artifact intentionally does not validate correspondence with a request,
    result IDs, or translated values; result validation is a later shared
    translation responsibility.
    """

    target_language: str
    units: tuple[TranslatedTextUnit, ...]

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "target_language",
            _require_language(self.target_language, "target_language"),
        )
        units = _to_tuple(self.units, "units")
        if any(not isinstance(unit, TranslatedTextUnit) for unit in units):
            raise TypeError("units must contain only TranslatedTextUnit values")
        object.__setattr__(self, "units", units)


def _to_tuple(value: object, name: str) -> tuple[object, ...]:
    if isinstance(value, (str, bytes)) or not isinstance(value, Iterable):
        raise TypeError(f"{name} must be an iterable")
    return tuple(value)


def _require_identifier(value: object, name: str) -> None:
    if not isinstance(value, str):
        raise TypeError(f"{name} must be a string")
    if not value or value.strip() != value:
        raise ValueError(f"{name} must not be blank or padded")


def _require_text(value: object, name: str) -> None:
    if not isinstance(value, str):
        raise TypeError(f"{name} must be a string")
    if not value or not value.strip():
        raise ValueError(f"{name} must not be blank")


def _require_unique_unit_ids(units: tuple[object, ...]) -> None:
    unit_ids = [unit.unit_id for unit in units]  # type: ignore[union-attr]
    if len(set(unit_ids)) != len(unit_ids):
        raise ValueError("units must have unique unit_id values")


def _require_language(value: object, name: str) -> str:
    if not isinstance(value, str):
        raise TypeError(f"{name} must be a string")
    if not value or value.strip() != value:
        raise ValueError(f"{name} must not be blank or padded")
    return value
