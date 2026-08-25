"""Source-neutral construction of bounded translation request windows.

Each window is a normal ``TranslationRequest`` over a contiguous subset of an
ordered ``StructuredTextArtifact``. The boundary owns no source-format data,
provider capability, token estimation, prompt, overlap, or provider call.
"""

from __future__ import annotations

from mint_lingo_engine.translation import (
    StructuredTextArtifact,
    TranslationRequest,
)


def build_translation_context_windows(
    artifact: StructuredTextArtifact,
    target_language: str,
    *,
    max_units_per_window: int,
) -> tuple[TranslationRequest, ...]:
    """Split ordered source units into bounded, non-overlapping requests.

    ``max_units_per_window`` is an application-supplied structural bound, not
    a provider context-window or token claim. A later capability-aware task
    can select that bound, and a later overlap task can add context without
    changing the authoritative ownership of these requested unit IDs.
    """

    if not isinstance(artifact, StructuredTextArtifact):
        raise TypeError("artifact must be a StructuredTextArtifact")
    if isinstance(max_units_per_window, bool) or not isinstance(
        max_units_per_window, int
    ):
        raise TypeError("max_units_per_window must be an integer")
    if max_units_per_window < 1:
        raise ValueError("max_units_per_window must be at least 1")

    return tuple(
        TranslationRequest(
            artifact=StructuredTextArtifact(
                source_language=artifact.source_language,
                units=artifact.units[start : start + max_units_per_window],
            ),
            target_language=target_language,
        )
        for start in range(0, len(artifact.units), max_units_per_window)
    )
