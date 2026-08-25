import io
import unittest
from unittest.mock import patch
from urllib.error import URLError

from mint_lingo_engine.providers.translation.ollama_availability import (
    DEFAULT_OLLAMA_SERVICE_URL,
    OllamaAvailability,
    OllamaAvailabilityDetector,
    OllamaAvailabilityStatus,
)


class OllamaAvailabilityDetectorTest(unittest.TestCase):
    def test_reports_uninstalled_without_attempting_service_health(self) -> None:
        health_calls: list[tuple[str, float]] = []
        detector = OllamaAvailabilityDetector(
            executable_lookup=lambda name: None,
            health_check=lambda url, timeout: health_calls.append((url, timeout)) or True,
        )

        result = detector.detect()

        self.assertEqual(
            result,
            OllamaAvailability(OllamaAvailabilityStatus.UNINSTALLED),
        )
        self.assertFalse(result.ready)
        self.assertEqual(health_calls, [])

    def test_reports_unreachable_when_installed_runtime_fails_health_check(self) -> None:
        health_calls: list[tuple[str, float]] = []
        detector = OllamaAvailabilityDetector(
            executable_lookup=lambda name: r"C:\Program Files\Ollama\ollama.exe",
            health_check=lambda url, timeout: health_calls.append((url, timeout)) or False,
        )

        result = detector.detect()

        self.assertEqual(
            result,
            OllamaAvailability(OllamaAvailabilityStatus.UNREACHABLE),
        )
        self.assertFalse(result.ready)
        self.assertEqual(health_calls, [(DEFAULT_OLLAMA_SERVICE_URL, 2.0)])

    def test_reports_ready_when_installed_runtime_passes_health_check(self) -> None:
        detector = OllamaAvailabilityDetector(
            executable_lookup=lambda name: "/usr/local/bin/ollama",
            health_check=lambda url, timeout: True,
        )

        result = detector.detect()

        self.assertEqual(result, OllamaAvailability(OllamaAvailabilityStatus.READY))
        self.assertTrue(result.ready)

    def test_uses_the_version_endpoint_as_the_concrete_health_check(self) -> None:
        response = _Response(b'{"version":"0.12.6"}')
        with patch(
            "mint_lingo_engine.providers.translation.ollama_availability.urlopen",
            return_value=response,
        ) as open_url:
            result = OllamaAvailabilityDetector(
                executable_lookup=lambda name: "/usr/local/bin/ollama",
            ).detect()

        self.assertEqual(result.status, OllamaAvailabilityStatus.READY)
        open_url.assert_called_once_with(
            "http://localhost:11434/api/version",
            timeout=2.0,
        )

    def test_treats_invalid_health_responses_as_unreachable(self) -> None:
        with patch(
            "mint_lingo_engine.providers.translation.ollama_availability.urlopen",
            return_value=_Response(b'{"version":" "}'),
        ):
            result = OllamaAvailabilityDetector(
                executable_lookup=lambda name: "/usr/local/bin/ollama",
            ).detect()

        self.assertEqual(result.status, OllamaAvailabilityStatus.UNREACHABLE)

    def test_treats_a_refused_version_endpoint_as_unreachable(self) -> None:
        with patch(
            "mint_lingo_engine.providers.translation.ollama_availability.urlopen",
            side_effect=URLError("connection refused"),
        ):
            result = OllamaAvailabilityDetector(
                executable_lookup=lambda name: "/usr/local/bin/ollama",
            ).detect()

        self.assertEqual(result.status, OllamaAvailabilityStatus.UNREACHABLE)

    def test_rejects_invalid_availability_status(self) -> None:
        with self.assertRaisesRegex(TypeError, "OllamaAvailabilityStatus"):
            OllamaAvailability("ready")  # type: ignore[arg-type]


class _Response:
    def __init__(self, payload: bytes, *, status: int = 200) -> None:
        self.status = status
        self._payload = io.BytesIO(payload)

    def __enter__(self) -> io.BytesIO:
        return self

    def __exit__(self, *args: object) -> None:
        self._payload.close()

    def read(self, size: int = -1) -> bytes:
        return self._payload.read(size)
