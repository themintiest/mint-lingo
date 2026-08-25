"""Provider-neutral contract for structured-text translation.

Concrete adapters normalize their vendor request and response types at this
boundary. Translation orchestration can therefore depend on ``LlmProvider``
and the shared translation models without importing an Ollama- or other
vendor-specific dependency.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Iterable
from dataclasses import dataclass

from mint_lingo_engine.translation import TranslationArtifact, TranslationRequest


@dataclass(frozen=True)
class LlmProviderCapabilities:
    """Provider-neutral metadata describing one LLM provider snapshot.

    ``context_window_tokens`` is ``None`` when the provider does not report a
    usable context limit. Model discovery and selecting limits for request
    construction remain separate later concerns.
    """

    model_ids: tuple[str, ...]
    context_window_tokens: int | None
    supports_structured_output: bool
    supports_streaming: bool

    def __post_init__(self) -> None:
        object.__setattr__(self, "model_ids", _normalize_model_ids(self.model_ids))
        if self.context_window_tokens is not None:
            if isinstance(self.context_window_tokens, bool) or not isinstance(
                self.context_window_tokens, int
            ):
                raise TypeError("context_window_tokens must be an integer or None")
            if self.context_window_tokens < 1:
                raise ValueError("context_window_tokens must be at least 1")
        _require_boolean(self.supports_structured_output, "supports_structured_output")
        _require_boolean(self.supports_streaming, "supports_streaming")


class LlmProvider(ABC):
    """Translates one provider-neutral structured-text request.

    Prompt construction, validation, retries, and workflow composition are
    intentionally defined by later tasks.
    """

    @property
    @abstractmethod
    def capabilities(self) -> LlmProviderCapabilities:
        """Return the provider's normalized capability metadata."""

    @abstractmethod
    def translate(
        self,
        request: TranslationRequest,
        instructions: str,
    ) -> TranslationArtifact:
        """Return normalized translated units for one request and instructions.

        ``instructions`` is provider-neutral text prepared by the shared
        translation capability. Concrete adapters decide how to place it and
        the structured source/context content in their vendor request.
        """


def _normalize_model_ids(value: object) -> tuple[str, ...]:
    if isinstance(value, (str, bytes)) or not isinstance(value, Iterable):
        raise TypeError("model_ids must be an iterable of strings")
    model_ids = tuple(value)
    for model_id in model_ids:
        if not isinstance(model_id, str):
            raise TypeError("model_ids must contain only strings")
        if not model_id or model_id.strip() != model_id:
            raise ValueError("model_ids must not contain blank or padded values")
    if len(set(model_ids)) != len(model_ids):
        raise ValueError("model_ids must be unique")
    return model_ids


def _require_boolean(value: object, name: str) -> None:
    if not isinstance(value, bool):
        raise TypeError(f"{name} must be a boolean")
