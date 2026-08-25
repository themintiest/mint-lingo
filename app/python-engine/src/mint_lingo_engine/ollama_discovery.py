"""Ollama-owned model inventory and capability discovery.

The boundary reads the local service's current model inventory rather than
hard-coding model names. It deliberately does not create an ``LlmProvider`` or
translate structured text.
"""

from __future__ import annotations

import json
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from mint_lingo_engine.ollama_availability import DEFAULT_OLLAMA_SERVICE_URL


_DISCOVERY_TIMEOUT_SECONDS = 2.0


class OllamaDiscoveryError(RuntimeError):
    """Raised when a healthy Ollama service returns unusable discovery data."""


@dataclass(frozen=True)
class OllamaModelCapabilities:
    """One installed model's service-advertised capabilities and context limit."""

    model_id: str
    capabilities: tuple[str, ...]
    context_window_tokens: int | None

    def __post_init__(self) -> None:
        _require_identifier(self.model_id, "model_id")
        capabilities = _normalize_capabilities(self.capabilities)
        if self.context_window_tokens is not None:
            if isinstance(self.context_window_tokens, bool) or not isinstance(
                self.context_window_tokens, int
            ):
                raise TypeError("context_window_tokens must be an integer or None")
            if self.context_window_tokens < 1:
                raise ValueError("context_window_tokens must be at least 1")
        object.__setattr__(self, "capabilities", capabilities)


@dataclass(frozen=True)
class OllamaModelInventory:
    """The current locally installed models, in service-reported order."""

    models: tuple[OllamaModelCapabilities, ...]

    def __post_init__(self) -> None:
        models = tuple(self.models)
        if any(not isinstance(model, OllamaModelCapabilities) for model in models):
            raise TypeError("models must contain only OllamaModelCapabilities values")
        model_ids = tuple(model.model_id for model in models)
        if len(set(model_ids)) != len(model_ids):
            raise ValueError("models must have unique model_id values")
        object.__setattr__(self, "models", models)


class OllamaModelDiscovery:
    """Discover models and their advertised capabilities from a ready service."""

    def __init__(
        self,
        *,
        request_json: (
            Callable[[str, str, Mapping[str, object] | None], object] | None
        ) = None,
    ) -> None:
        self._request_json = request_json or _request_ollama_json

    def discover(self) -> OllamaModelInventory:
        """Return the live model inventory without selecting or running a model."""

        tags_response = self._request_json("GET", "/api/tags", None)
        model_ids = _parse_model_ids(tags_response)
        return OllamaModelInventory(
            models=tuple(
                _parse_model_capabilities(
                    model_id,
                    self._request_json("POST", "/api/show", {"model": model_id}),
                )
                for model_id in model_ids
            )
        )


def _request_ollama_json(
    method: str,
    path: str,
    payload: Mapping[str, object] | None,
) -> object:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = Request(
        f"{DEFAULT_OLLAMA_SERVICE_URL}{path}",
        data=data,
        headers={"Content-Type": "application/json"} if data is not None else {},
        method=method,
    )
    try:
        with urlopen(request, timeout=_DISCOVERY_TIMEOUT_SECONDS) as response:
            if response.status != 200:
                raise OllamaDiscoveryError("Ollama model discovery request failed")
            return json.load(response)
    except (HTTPError, URLError, OSError, TimeoutError, json.JSONDecodeError) as error:
        raise OllamaDiscoveryError("Ollama model discovery request failed") from error


def _parse_model_ids(response: object) -> tuple[str, ...]:
    if not isinstance(response, dict) or not isinstance(response.get("models"), list):
        raise OllamaDiscoveryError("Ollama model inventory has an invalid shape")
    model_ids: list[str] = []
    for model in response["models"]:
        if not isinstance(model, dict):
            raise OllamaDiscoveryError("Ollama model inventory contains an invalid model")
        model_id = model.get("name")
        try:
            _require_identifier(model_id, "model name")
        except (TypeError, ValueError) as error:
            raise OllamaDiscoveryError(
                "Ollama model inventory contains an invalid model name"
            ) from error
        model_ids.append(model_id)
    if len(set(model_ids)) != len(model_ids):
        raise OllamaDiscoveryError("Ollama model inventory contains duplicate model names")
    return tuple(model_ids)


def _parse_model_capabilities(
    model_id: str,
    response: object,
) -> OllamaModelCapabilities:
    if not isinstance(response, dict):
        raise OllamaDiscoveryError("Ollama model details have an invalid shape")
    try:
        capabilities = _normalize_capabilities(response.get("capabilities"))
    except (TypeError, ValueError) as error:
        raise OllamaDiscoveryError(
            "Ollama model details contain invalid capabilities"
        ) from error
    return OllamaModelCapabilities(
        model_id=model_id,
        capabilities=capabilities,
        context_window_tokens=_context_window_tokens(response.get("model_info")),
    )


def _context_window_tokens(model_info: object) -> int | None:
    if not isinstance(model_info, dict):
        return None
    context_lengths = [
        value
        for key, value in model_info.items()
        if isinstance(key, str)
        and key.endswith(".context_length")
        and isinstance(value, int)
        and not isinstance(value, bool)
        and value > 0
    ]
    return context_lengths[0] if len(context_lengths) == 1 else None


def _normalize_capabilities(value: object) -> tuple[str, ...]:
    if isinstance(value, (str, bytes)) or value is None:
        raise TypeError("capabilities must be an iterable of strings")
    try:
        capabilities = tuple(value)
    except TypeError as error:
        raise TypeError("capabilities must be an iterable of strings") from error
    for capability in capabilities:
        _require_identifier(capability, "capabilities")
    if len(set(capabilities)) != len(capabilities):
        raise ValueError("capabilities must be unique")
    return capabilities


def _require_identifier(value: object, name: str) -> None:
    if not isinstance(value, str):
        raise TypeError(f"{name} must be a string")
    if not value or value.strip() != value:
        raise ValueError(f"{name} must not be blank or padded")
