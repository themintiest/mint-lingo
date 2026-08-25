import io
import unittest
from unittest.mock import patch

from mint_lingo_engine.providers.translation.ollama_discovery import (
    OllamaDiscoveryError,
    OllamaModelCapabilities,
    OllamaModelDiscovery,
    OllamaModelInventory,
)


class OllamaModelDiscoveryTest(unittest.TestCase):
    def test_discovers_live_model_ids_and_per_model_capabilities(self) -> None:
        requests: list[tuple[str, str, dict[str, object] | None]] = []

        def request_json(
            method: str,
            path: str,
            payload: dict[str, object] | None,
        ) -> object:
            requests.append((method, path, payload))
            if path == "/api/tags":
                return {"models": [{"name": "qwen3:8b"}, {"name": "gemma3:4b"}]}
            if payload == {"model": "qwen3:8b"}:
                return {
                    "capabilities": ["completion", "tools"],
                    "model_info": {"qwen3.context_length": 40_960},
                }
            return {
                "capabilities": ["completion", "vision"],
                "model_info": {"gemma3.context_length": 131_072},
            }

        inventory = OllamaModelDiscovery(request_json=request_json).discover()

        self.assertEqual(
            inventory,
            OllamaModelInventory(
                models=(
                    OllamaModelCapabilities(
                        model_id="qwen3:8b",
                        capabilities=("completion", "tools"),
                        context_window_tokens=40_960,
                    ),
                    OllamaModelCapabilities(
                        model_id="gemma3:4b",
                        capabilities=("completion", "vision"),
                        context_window_tokens=131_072,
                    ),
                )
            ),
        )
        self.assertEqual(
            requests,
            [
                ("GET", "/api/tags", None),
                ("POST", "/api/show", {"model": "qwen3:8b"}),
                ("POST", "/api/show", {"model": "gemma3:4b"}),
            ],
        )

    def test_allows_an_empty_live_model_inventory_without_a_hard_coded_default(self) -> None:
        requests: list[tuple[str, str, dict[str, object] | None]] = []

        def request_json(
            method: str,
            path: str,
            payload: dict[str, object] | None,
        ) -> object:
            requests.append((method, path, payload))
            return {"models": []}

        inventory = OllamaModelDiscovery(request_json=request_json).discover()

        self.assertEqual(inventory, OllamaModelInventory(models=()))
        self.assertEqual(requests, [("GET", "/api/tags", None)])

    def test_allows_missing_or_ambiguous_context_length(self) -> None:
        responses = iter(
            (
                {"models": [{"name": "model:latest"}]},
                {
                    "capabilities": ["completion"],
                    "model_info": {
                        "first.context_length": 4_096,
                        "second.context_length": 8_192,
                    },
                },
            )
        )

        inventory = OllamaModelDiscovery(
            request_json=lambda method, path, payload: next(responses)
        ).discover()

        self.assertIsNone(inventory.models[0].context_window_tokens)

    def test_uses_documented_inventory_and_model_detail_http_requests(self) -> None:
        with patch(
            "mint_lingo_engine.providers.translation.ollama_discovery.urlopen",
            side_effect=(
                _Response(b'{"models":[{"name":"model:latest"}]}'),
                _Response(
                    b'{"capabilities":["completion"],'
                    b'"model_info":{"model.context_length":4096}}'
                ),
            ),
        ) as open_url:
            inventory = OllamaModelDiscovery().discover()

        self.assertEqual(inventory.models[0].model_id, "model:latest")
        self.assertEqual(inventory.models[0].context_window_tokens, 4_096)
        self.assertEqual(len(open_url.call_args_list), 2)
        tags_request = open_url.call_args_list[0].args[0]
        tags_timeout = open_url.call_args_list[0].kwargs["timeout"]
        show_request = open_url.call_args_list[1].args[0]
        show_timeout = open_url.call_args_list[1].kwargs["timeout"]
        self.assertEqual(tags_request.full_url, "http://localhost:11434/api/tags")
        self.assertEqual(tags_request.get_method(), "GET")
        self.assertIsNone(tags_request.data)
        self.assertEqual(tags_timeout, 2.0)
        self.assertEqual(show_request.full_url, "http://localhost:11434/api/show")
        self.assertEqual(show_request.get_method(), "POST")
        self.assertEqual(show_request.data, b'{"model": "model:latest"}')
        self.assertEqual(show_timeout, 2.0)

    def test_rejects_malformed_inventory_and_model_details(self) -> None:
        malformed_cases = (
            (
                "missing model list",
                ({},),
                "inventory has an invalid shape",
            ),
            (
                "blank model name",
                ({"models": [{"name": " "}]},),
                "inventory contains an invalid model name",
            ),
            (
                "duplicate model name",
                ({"models": [{"name": "same"}, {"name": "same"}]},),
                "inventory contains duplicate model names",
            ),
            (
                "invalid capabilities",
                ({"models": [{"name": "model"}]}, {"capabilities": "completion"}),
                "details contain invalid capabilities",
            ),
        )
        for name, responses, message in malformed_cases:
            with self.subTest(name=name):
                response_iterator = iter(responses)
                discovery = OllamaModelDiscovery(
                    request_json=lambda method, path, payload: next(response_iterator)
                )

                with self.assertRaisesRegex(OllamaDiscoveryError, message):
                    discovery.discover()

    def test_model_values_reject_invalid_normalized_data(self) -> None:
        with self.assertRaisesRegex(ValueError, "model_id"):
            OllamaModelCapabilities(" ", (), None)
        with self.assertRaisesRegex(ValueError, "capabilities must be unique"):
            OllamaModelCapabilities("model", ("completion", "completion"), None)
        with self.assertRaisesRegex(ValueError, "at least 1"):
            OllamaModelCapabilities("model", (), 0)
        with self.assertRaisesRegex(ValueError, "unique model_id"):
            OllamaModelInventory(
                (
                    OllamaModelCapabilities("same", (), None),
                    OllamaModelCapabilities("same", (), None),
                )
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
