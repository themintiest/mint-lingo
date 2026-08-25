"""Local Ollama runtime availability and service-health detection.

This boundary distinguishes a missing local runtime from an installed runtime
whose local API cannot be reached. It intentionally performs no model
discovery, provider capability mapping, or translation.
"""

from __future__ import annotations

import json
import shutil
from collections.abc import Callable
from dataclasses import dataclass
from enum import Enum
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


DEFAULT_OLLAMA_SERVICE_URL = "http://localhost:11434"
_HEALTH_TIMEOUT_SECONDS = 2.0


class OllamaAvailabilityStatus(str, Enum):
    """The distinct local-runtime states needed before model discovery."""

    UNINSTALLED = "uninstalled"
    UNREACHABLE = "unreachable"
    READY = "ready"


@dataclass(frozen=True)
class OllamaAvailability:
    """A normalized Ollama runtime and local service-health result."""

    status: OllamaAvailabilityStatus

    def __post_init__(self) -> None:
        if not isinstance(self.status, OllamaAvailabilityStatus):
            raise TypeError("status must be an OllamaAvailabilityStatus")

    @property
    def ready(self) -> bool:
        """Whether the local runtime is installed and its API is healthy."""

        return self.status is OllamaAvailabilityStatus.READY


class OllamaAvailabilityDetector:
    """Detect the local runtime first, then its documented version endpoint."""

    def __init__(
        self,
        *,
        executable_lookup: Callable[[str], str | None] = shutil.which,
        health_check: Callable[[str, float], bool] | None = None,
    ) -> None:
        self._executable_lookup = executable_lookup
        self._health_check = health_check or _is_ollama_service_healthy

    def detect(self) -> OllamaAvailability:
        """Return uninstalled, unreachable, or ready without model discovery."""

        if self._executable_lookup("ollama") is None:
            return OllamaAvailability(OllamaAvailabilityStatus.UNINSTALLED)
        if not self._health_check(
            DEFAULT_OLLAMA_SERVICE_URL,
            _HEALTH_TIMEOUT_SECONDS,
        ):
            return OllamaAvailability(OllamaAvailabilityStatus.UNREACHABLE)
        return OllamaAvailability(OllamaAvailabilityStatus.READY)


def _is_ollama_service_healthy(service_url: str, timeout_seconds: float) -> bool:
    """Verify the documented version endpoint without discovering models."""

    try:
        with urlopen(
            f"{service_url}/api/version",
            timeout=timeout_seconds,
        ) as response:
            if response.status != 200:
                return False
            payload = json.load(response)
    except (HTTPError, URLError, OSError, TimeoutError, json.JSONDecodeError):
        return False

    version = payload.get("version") if isinstance(payload, dict) else None
    return isinstance(version, str) and bool(version.strip())
