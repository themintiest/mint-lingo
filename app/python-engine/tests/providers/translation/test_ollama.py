import io
import json
import errno
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

from mint_lingo_engine.providers.translation.ollama_discovery import (
    OllamaModelCapabilities,
    OllamaModelInventory,
)
from mint_lingo_engine.providers.translation.ollama import OllamaProvider
from mint_lingo_engine.providers.translation.base import (
    LlmProviderFailureCategory,
    LlmProviderFailureError,
    LlmProviderFailureRetryScope,
)
from mint_lingo_engine.translation.models import (
    StructuredTextArtifact,
    StructuredTextUnit,
    TranslationContext,
    TranslationRequest,
)


class OllamaProviderTest(unittest.TestCase):
    def test_normalizes_a_structured_chat_response_behind_llm_provider(self) -> None:
        payloads: list[dict[str, object]] = []
        provider = OllamaProvider(
            _inventory(),
            "qwen3:8b",
            post_chat=lambda payload: payloads.append(dict(payload))
            or {
                "message": {
                    "content": json.dumps(
                        {
                            "translations": [
                                {"unitId": "unit.2", "translatedText": "Hai"},
                                {"unitId": "unit.1", "translatedText": "Mot"},
                            ]
                        }
                    )
                }
            },
        )
        request = TranslationRequest(
            artifact=StructuredTextArtifact(
                source_language="en",
                units=(
                    StructuredTextUnit("unit.1", "First"),
                    StructuredTextUnit("unit.2", "Second"),
                ),
            ),
            target_language="vi",
            context=TranslationContext(
                units=(StructuredTextUnit("unit.0", "Reference"),)
            ),
        )

        result = provider.translate(request, "Translate the requested source units.")

        self.assertEqual(
            [(unit.unit_id, unit.translated_text) for unit in result.units],
            [("unit.2", "Hai"), ("unit.1", "Mot")],
        )
        self.assertEqual(provider.capabilities.model_ids, ("qwen3:8b", "embed"))
        self.assertEqual(provider.capabilities.context_window_tokens, 40_960)
        self.assertTrue(provider.capabilities.supports_structured_output)
        self.assertTrue(provider.capabilities.supports_streaming)
        self.assertEqual(payloads[0]["model"], "qwen3:8b")
        self.assertFalse(payloads[0]["stream"])
        messages = payloads[0]["messages"]
        self.assertEqual(messages[0]["content"], "Translate the requested source units.")
        self.assertEqual(
            json.loads(messages[1]["content"]),
            {
                "sourceLanguage": "en",
                "targetLanguage": "vi",
                "units": [
                    {"unitId": "unit.1", "text": "First"},
                    {"unitId": "unit.2", "text": "Second"},
                ],
                "referenceContext": [{"unitId": "unit.0", "text": "Reference"}],
            },
        )
        self.assertEqual(payloads[0]["format"]["required"], ["translations"])

    def test_rejects_unknown_or_non_completion_models(self) -> None:
        with self.assertRaisesRegex(ValueError, "in the inventory"):
            OllamaProvider(_inventory(), "missing")
        with self.assertRaisesRegex(ValueError, "completion-capable"):
            OllamaProvider(_inventory(), "embed")

    def test_returns_unvalidated_translation_units_for_shared_validation(self) -> None:
        provider = OllamaProvider(
            _inventory(),
            "qwen3:8b",
            post_chat=lambda payload: {
                "message": {
                    "content": json.dumps(
                        {
                            "translations": [
                                {"unitId": "unexpected", "translatedText": ""}
                            ]
                        }
                    )
                }
            },
        )

        result = provider.translate(_request(), "Instructions")

        self.assertEqual(result.units[0].unit_id, "unexpected")
        self.assertEqual(result.units[0].translated_text, "")

    def test_rejects_malformed_provider_responses_and_input(self) -> None:
        provider = OllamaProvider(
            _inventory(),
            "qwen3:8b",
            post_chat=lambda payload: {"message": {"content": "not JSON"}},
        )

        with self.assertRaises(LlmProviderFailureError) as raised:
            provider.translate(_request(), "Instructions")
        self.assertEqual(
            raised.exception.failure.category,
            LlmProviderFailureCategory.MALFORMED_RESPONSE,
        )
        self.assertTrue(raised.exception.failure.retryable)
        self.assertEqual(
            raised.exception.failure.retry_scope,
            LlmProviderFailureRetryScope.IMMEDIATE_REQUEST,
        )
        self.assertIsNone(raised.exception.__cause__)
        self.assertIsNone(raised.exception.__context__)
        self.assertNotIn("not JSON", str(raised.exception))
        with self.assertRaisesRegex(TypeError, "TranslationRequest"):
            provider.translate("request", "Instructions")  # type: ignore[arg-type]
        with self.assertRaisesRegex(ValueError, "instructions"):
            provider.translate(_request(), " ")

    def test_classifies_offline_transport_and_response_failures(self) -> None:
        cases: tuple[tuple[object, LlmProviderFailureCategory, LlmProviderFailureRetryScope], ...] = (
            (
                URLError(OSError(errno.ECONNREFUSED, "private connection detail")),
                LlmProviderFailureCategory.SERVICE_UNAVAILABLE,
                LlmProviderFailureRetryScope.USER_DIRECTED_RESUME,
            ),
            (
                TimeoutError("private timeout detail"),
                LlmProviderFailureCategory.TIMEOUT,
                LlmProviderFailureRetryScope.USER_DIRECTED_RESUME,
            ),
            (
                HTTPError(
                    "http://localhost:11434/api/chat",
                    503,
                    "private status detail",
                    {"Authorization": "secret"},
                    None,
                ),
                LlmProviderFailureCategory.REQUEST_REJECTED,
                LlmProviderFailureRetryScope.USER_DIRECTED_RESUME,
            ),
            (
                _Response(b"not JSON"),
                LlmProviderFailureCategory.MALFORMED_RESPONSE,
                LlmProviderFailureRetryScope.IMMEDIATE_REQUEST,
            ),
        )
        for response_or_error, expected_category, expected_scope in cases:
            with self.subTest(expected_category=expected_category):
                provider = OllamaProvider(_inventory(), "qwen3:8b")
                with patch(
                    "mint_lingo_engine.providers.translation.ollama.urlopen",
                    side_effect=(
                        response_or_error
                        if isinstance(response_or_error, BaseException)
                        else None
                    ),
                    return_value=(
                        response_or_error
                        if isinstance(response_or_error, _Response)
                        else None
                    ),
                ):
                    with self.assertRaises(LlmProviderFailureError) as raised:
                        provider.translate(_request(), "Instructions")
                self.assertEqual(raised.exception.failure.category, expected_category)
                self.assertEqual(raised.exception.failure.retry_scope, expected_scope)
                self.assertIsNone(raised.exception.__cause__)
                self.assertIsNone(raised.exception.__context__)
                self.assertNotIn("private", str(raised.exception))
                self.assertNotIn("secret", str(raised.exception))

    def test_posts_a_non_streaming_structured_chat_request(self) -> None:
        response_content = json.dumps(
            {"translations": [{"unitId": "unit.1", "translatedText": "Mot"}]}
        ).encode("utf-8")
        with patch(
            "mint_lingo_engine.providers.translation.ollama.urlopen",
            return_value=_Response(
                b'{"message":{"content":' + json.dumps(response_content.decode()).encode() + b"}}"
            ),
        ) as open_url:
            result = OllamaProvider(_inventory(), "qwen3:8b").translate(
                _request(),
                "Instructions",
            )

        self.assertEqual(result.units[0].translated_text, "Mot")
        request = open_url.call_args.args[0]
        self.assertEqual(request.full_url, "http://localhost:11434/api/chat")
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(open_url.call_args.kwargs["timeout"], 300.0)
        payload = json.loads(request.data)
        self.assertEqual(payload["model"], "qwen3:8b")
        self.assertFalse(payload["stream"])


def _inventory() -> OllamaModelInventory:
    return OllamaModelInventory(
        models=(
            OllamaModelCapabilities("qwen3:8b", ("completion",), 40_960),
            OllamaModelCapabilities("embed", ("embedding",), None),
        )
    )


def _request() -> TranslationRequest:
    return TranslationRequest(
        artifact=StructuredTextArtifact(
            source_language="en",
            units=(StructuredTextUnit("unit.1", "First"),),
        ),
        target_language="vi",
    )


class _Response:
    def __init__(self, payload: bytes) -> None:
        self.status = 200
        self._payload = io.BytesIO(payload)

    def __enter__(self) -> "_Response":
        return self

    def __exit__(self, *args: object) -> None:
        self._payload.close()

    def read(self, size: int = -1) -> bytes:
        return self._payload.read(size)
