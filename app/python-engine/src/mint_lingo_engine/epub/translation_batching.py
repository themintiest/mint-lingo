"""EPUB-owned conservative request batching from neutral provider metadata."""

from __future__ import annotations

from dataclasses import dataclass

from mint_lingo_engine.providers.translation.base import LlmProviderCapabilities


_SMALL_CONTEXT_LIMIT = 8_192
_LARGE_CONTEXT_LIMIT = 32_768


@dataclass(frozen=True)
class EpubTranslationBatchingPolicy:
    """Structural EPUB request bounds selected without estimating token usage.

    The selected values deliberately remain small. A context limit is provider
    metadata, not a claim that a particular EPUB unit consumes a fixed number
    of tokens, so an unknown or small limit retains the one-unit safe default.
    """

    max_units_per_window: int
    overlap_units: int

    def __post_init__(self) -> None:
        for name in ("max_units_per_window", "overlap_units"):
            value = getattr(self, name)
            if isinstance(value, bool) or not isinstance(value, int):
                raise TypeError(f"{name} must be an integer")
        if self.max_units_per_window < 1:
            raise ValueError("max_units_per_window must be at least 1")
        if self.overlap_units < 0:
            raise ValueError("overlap_units must not be negative")
        if self.overlap_units >= self.max_units_per_window:
            raise ValueError("overlap_units must be smaller than max_units_per_window")

    @classmethod
    def from_capabilities(
        cls,
        capabilities: LlmProviderCapabilities,
    ) -> "EpubTranslationBatchingPolicy":
        if not isinstance(capabilities, LlmProviderCapabilities):
            raise TypeError("capabilities must be LlmProviderCapabilities")

        context_limit = capabilities.context_window_tokens
        if context_limit is None or context_limit < _SMALL_CONTEXT_LIMIT:
            return cls(max_units_per_window=1, overlap_units=0)
        if context_limit < _LARGE_CONTEXT_LIMIT:
            return cls(max_units_per_window=2, overlap_units=1)
        return cls(max_units_per_window=4, overlap_units=1)

    @property
    def reference_context_unit_limit(self) -> int:
        """Bound EPUB reference context to the existing overlap policy.

        One configured overlap unit permits at most one preceding and one
        following chapter-local reference unit. A safe no-overlap policy sends
        no reference context.
        """

        return self.overlap_units * 2
