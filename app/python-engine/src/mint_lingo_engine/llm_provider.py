"""Provider-neutral contract for structured-text translation.

Concrete adapters normalize their vendor request and response types at this
boundary. Translation orchestration can therefore depend on ``LlmProvider``
and the shared translation models without importing an Ollama- or other
vendor-specific dependency.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from mint_lingo_engine.translation import TranslationArtifact, TranslationRequest


class LlmProvider(ABC):
    """Translates one provider-neutral structured-text request.

    Provider capabilities, prompt construction, validation, retries, and
    workflow composition are intentionally defined by later tasks.
    """

    @abstractmethod
    def translate(self, request: TranslationRequest) -> TranslationArtifact:
        """Return normalized translated units for ``request``."""
