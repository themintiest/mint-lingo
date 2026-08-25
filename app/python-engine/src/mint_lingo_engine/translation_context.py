"""Source-neutral construction of bounded translation request windows.

Each window is a normal ``TranslationRequest`` over a contiguous subset of an
ordered ``StructuredTextArtifact``. Adjacent source units can repeat only in
structured reference context; requested units retain sole result ownership.
The boundary owns no source-format data, provider capability, token estimation,
prompt, or provider call.
"""

from __future__ import annotations

from mint_lingo_engine.translation import (
    StructuredTextArtifact,
    TranslationContext,
    TranslationRequest,
)


def build_translation_context_windows(
    artifact: StructuredTextArtifact,
    target_language: str,
    *,
    max_units_per_window: int,
    overlap_units: int = 0,
) -> tuple[TranslationRequest, ...]:
    """Split ordered source units into bounded requests with optional overlap.

    ``max_units_per_window`` is an application-supplied structural bound, not
    a provider context-window or token claim. A later capability-aware task
    can select that bound. ``overlap_units`` supplies neighboring source units
    as reference context only; every source unit remains requested by exactly
    one window.
    """

    if not isinstance(artifact, StructuredTextArtifact):
        raise TypeError("artifact must be a StructuredTextArtifact")
    _require_non_negative_integer(max_units_per_window, "max_units_per_window")
    if max_units_per_window < 1:
        raise ValueError("max_units_per_window must be at least 1")
    _require_non_negative_integer(overlap_units, "overlap_units")

    return tuple(
        TranslationRequest(
            artifact=StructuredTextArtifact(
                source_language=artifact.source_language,
                units=artifact.units[start : start + max_units_per_window],
            ),
            target_language=target_language,
            context=_build_overlap_context(
                artifact,
                start=start,
                end=start + max_units_per_window,
                overlap_units=overlap_units,
            ),
        )
        for start in range(0, len(artifact.units), max_units_per_window)
    )


def _build_overlap_context(
    artifact: StructuredTextArtifact,
    *,
    start: int,
    end: int,
    overlap_units: int,
) -> TranslationContext | None:
    if overlap_units == 0:
        return None
    context_units = (
        artifact.units[max(0, start - overlap_units) : start]
        + artifact.units[end : end + overlap_units]
    )
    if not context_units:
        return None
    return TranslationContext(units=context_units)


def _require_non_negative_integer(value: object, name: str) -> None:
    if isinstance(value, bool) or not isinstance(value, int):
        raise TypeError(f"{name} must be an integer")
    if value < 0:
        raise ValueError(f"{name} must not be negative")
