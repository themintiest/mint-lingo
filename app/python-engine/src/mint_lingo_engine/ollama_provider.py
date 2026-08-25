"""Ollama implementation of the provider-neutral structured translation API."""

from __future__ import annotations

import json
from collections.abc import Callable, Mapping
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from mint_lingo_engine.llm_provider import LlmProvider, LlmProviderCapabilities
from mint_lingo_engine.ollama_availability import DEFAULT_OLLAMA_SERVICE_URL
from mint_lingo_engine.ollama_discovery import (
    OllamaModelCapabilities,
    OllamaModelInventory,
)
from mint_lingo_engine.translation import (
    TranslatedTextUnit,
    TranslationArtifact,
    TranslationRequest,
)


_CHAT_TIMEOUT_SECONDS = 60.0
_TRANSLATION_RESPONSE_SCHEMA: dict[str, object] = {
    "type": "object",
    "properties": {
        "translations": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "unitId": {"type": "string"},
                    "translatedText": {"type": "string"},
                },
                "required": ["unitId", "translatedText"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["translations"],
    "additionalProperties": False,
}


class OllamaProviderError(RuntimeError):
    """Raised when Ollama cannot supply a normalized provider response."""


class OllamaProvider(LlmProvider):
    """Translate one normalized request through a discovered local Ollama model."""

    def __init__(
        self,
        inventory: OllamaModelInventory,
        model_id: str,
        *,
        post_chat: Callable[[Mapping[str, object]], object] | None = None,
    ) -> None:
        if not isinstance(inventory, OllamaModelInventory):
            raise TypeError("inventory must be an OllamaModelInventory")
        selected_model = _selected_model(inventory, model_id)
        if "completion" not in selected_model.capabilities:
            raise ValueError("model_id must identify a completion-capable model")
        self._model_id = model_id
        self._post_chat = post_chat or _post_ollama_chat
        self._capabilities = LlmProviderCapabilities(
            model_ids=tuple(model.model_id for model in inventory.models),
            context_window_tokens=selected_model.context_window_tokens,
            supports_structured_output=True,
            supports_streaming=True,
        )

    @property
    def capabilities(self) -> LlmProviderCapabilities:
        """Return the discovered inventory and selected-model context limit."""

        return self._capabilities

    def translate(
        self,
        request: TranslationRequest,
        instructions: str,
    ) -> TranslationArtifact:
        """Invoke local Ollama and normalize its structured chat response."""

        if not isinstance(request, TranslationRequest):
            raise TypeError("request must be a TranslationRequest")
        _require_instructions(instructions)
        response = self._post_chat(_chat_payload(self._model_id, request, instructions))
        return _parse_translation_response(request, response)


def _selected_model(
    inventory: OllamaModelInventory,
    model_id: object,
) -> OllamaModelCapabilities:
    if not isinstance(model_id, str):
        raise TypeError("model_id must be a string")
    if not model_id or model_id.strip() != model_id:
        raise ValueError("model_id must not be blank or padded")
    for model in inventory.models:
        if model.model_id == model_id:
            return model
    raise ValueError("model_id must identify a model in the inventory")


def _chat_payload(
    model_id: str,
    request: TranslationRequest,
    instructions: str,
) -> dict[str, object]:
    source_payload: dict[str, object] = {
        "sourceLanguage": request.artifact.source_language,
        "targetLanguage": request.target_language,
        "units": [
            {"unitId": unit.unit_id, "text": unit.text}
            for unit in request.artifact.units
        ],
    }
    if request.context is not None:
        source_payload["referenceContext"] = [
            {"unitId": unit.unit_id, "text": unit.text}
            for unit in request.context.units
        ]
    return {
        "model": model_id,
        "messages": [
            {"role": "system", "content": instructions},
            {
                "role": "user",
                "content": json.dumps(source_payload, ensure_ascii=False),
            },
        ],
        "format": _TRANSLATION_RESPONSE_SCHEMA,
        "stream": False,
    }


def _post_ollama_chat(payload: Mapping[str, object]) -> object:
    request = Request(
        f"{DEFAULT_OLLAMA_SERVICE_URL}/api/chat",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=_CHAT_TIMEOUT_SECONDS) as response:
            if response.status != 200:
                raise OllamaProviderError("Ollama translation request failed")
            return json.load(response)
    except (HTTPError, URLError, OSError, TimeoutError, json.JSONDecodeError) as error:
        raise OllamaProviderError("Ollama translation request failed") from error


def _parse_translation_response(
    request: TranslationRequest,
    response: object,
) -> TranslationArtifact:
    if not isinstance(response, dict):
        raise OllamaProviderError("Ollama translation response has an invalid shape")
    message = response.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    if not isinstance(content, str):
        raise OllamaProviderError("Ollama translation response has no message content")
    try:
        document = json.loads(content)
    except json.JSONDecodeError as error:
        raise OllamaProviderError("Ollama translation response is not valid JSON") from error
    if not isinstance(document, dict) or not isinstance(
        document.get("translations"), list
    ):
        raise OllamaProviderError("Ollama translation response has an invalid payload")
    try:
        units = tuple(
            TranslatedTextUnit(
                unit_id=unit["unitId"],
                translated_text=unit["translatedText"],
            )
            for unit in document["translations"]
            if isinstance(unit, dict)
        )
    except (KeyError, TypeError) as error:
        raise OllamaProviderError("Ollama translation response has invalid units") from error
    if len(units) != len(document["translations"]):
        raise OllamaProviderError("Ollama translation response has invalid units")
    return TranslationArtifact(target_language=request.target_language, units=units)


def _require_instructions(instructions: object) -> None:
    if not isinstance(instructions, str):
        raise TypeError("instructions must be a string")
    if not instructions or not instructions.strip():
        raise ValueError("instructions must not be blank")
