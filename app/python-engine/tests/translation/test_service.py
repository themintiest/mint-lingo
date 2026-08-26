import unittest

from mint_lingo_engine.providers.translation.base import LlmProvider, LlmProviderCapabilities
from mint_lingo_engine.translation.models import (
    StructuredTextArtifact,
    StructuredTextUnit,
    TranslatedTextUnit,
    TranslationArtifact,
    TranslationRequest,
)
from mint_lingo_engine.translation.service import (
    TranslationService,
    TranslationServiceValidationError,
)
from mint_lingo_engine.translation.validation import TranslationValidationErrorCode


class TranslationServiceTest(unittest.TestCase):
    def test_batches_context_builds_instructions_and_returns_source_order(self) -> None:
        provider = _FakeLlmProvider(
            responses=(
                _artifact("vi", ("unit.2", "Two"), ("unit.1", "One")),
                _artifact("vi", ("unit.3", "Three")),
            )
        )
        service = TranslationService(
            provider,
            max_units_per_window=2,
            overlap_units=1,
        )

        result = service.translate(_source_artifact(), "vi")

        self.assertEqual(
            [(unit.unit_id, unit.translated_text) for unit in result.units],
            [("unit.1", "One"), ("unit.2", "Two"), ("unit.3", "Three")],
        )
        self.assertEqual(
            [
                [unit.unit_id for unit in request.artifact.units]
                for request, _ in provider.calls
            ],
            [["unit.1", "unit.2"], ["unit.3"]],
        )
        self.assertEqual(
            [
                [unit.unit_id for unit in request.context.units]
                if request.context is not None
                else []
                for request, _ in provider.calls
            ],
            [["unit.3"], ["unit.2"]],
        )
        self.assertIn("Target language: vi", provider.calls[0][1])
        self.assertIn(
            "Reference context is supplied only for comprehension",
            provider.calls[0][1],
        )

    def test_retries_only_invalid_units_and_preserves_prior_valid_results(self) -> None:
        provider = _FakeLlmProvider(
            responses=(
                _artifact(
                    "vi",
                    ("unit.1", "First result"),
                    ("unit.3", "Third result"),
                ),
                _artifact("vi", ("unit.2", "Retried second result")),
            )
        )
        service = TranslationService(provider, max_units_per_window=3)

        result = service.translate(_source_artifact(), "vi")

        self.assertEqual(
            [(unit.unit_id, unit.translated_text) for unit in result.units],
            [
                ("unit.1", "First result"),
                ("unit.2", "Retried second result"),
                ("unit.3", "Third result"),
            ],
        )
        self.assertEqual(
            [
                [unit.unit_id for unit in request.artifact.units]
                for request, _ in provider.calls
            ],
            [["unit.1", "unit.2", "unit.3"], ["unit.2"]],
        )
        self.assertIn(
            'Required unit IDs, in order: ["unit.2"]',
            provider.calls[1][1],
        )

    def test_notifies_only_after_each_request_has_a_valid_translation(self) -> None:
        provider = _FakeLlmProvider(
            responses=(
                _artifact("vi", ("unit.2", "Two"), ("unit.1", "One")),
                _artifact("vi", ("unit.3", "Three")),
            )
        )
        service = TranslationService(provider, max_units_per_window=2)
        completed: list[tuple[tuple[str, ...], tuple[str, ...]]] = []

        service.translate(
            _source_artifact(),
            "vi",
            on_request_translated=lambda request, translation: completed.append(
                (
                    tuple(unit.unit_id for unit in request.artifact.units),
                    tuple(unit.unit_id for unit in translation.units),
                )
            ),
        )

        self.assertEqual(
            completed,
            [
                (("unit.1", "unit.2"), ("unit.1", "unit.2")),
                (("unit.3",), ("unit.3",)),
            ],
        )

    def test_retries_the_whole_batch_when_result_structure_is_unsafe(self) -> None:
        provider = _FakeLlmProvider(
            responses=(
                _artifact("vi", ("unexpected", "Unexpected")),
                _artifact(
                    "vi",
                    ("unit.1", "One"),
                    ("unit.2", "Two"),
                    ("unit.3", "Three"),
                ),
            )
        )
        service = TranslationService(provider, max_units_per_window=3)

        result = service.translate(_source_artifact(), "vi")

        self.assertEqual(result.units[0].translated_text, "One")
        self.assertEqual(
            [
                [unit.unit_id for unit in request.artifact.units]
                for request, _ in provider.calls
            ],
            [["unit.1", "unit.2", "unit.3"], ["unit.1", "unit.2", "unit.3"]],
        )

    def test_stops_without_retrying_a_non_retryable_validation_failure(self) -> None:
        provider = _FakeLlmProvider(
            responses=(
                _artifact(
                    "pt-BR",
                    ("unit.1", "One"),
                    ("unit.2", "Two"),
                    ("unit.3", "Three"),
                ),
            )
        )
        service = TranslationService(provider, max_units_per_window=3)

        with self.assertRaises(TranslationServiceValidationError) as raised:
            service.translate(_source_artifact(), "vi")

        self.assertEqual(
            raised.exception.failure.code,
            TranslationValidationErrorCode.TARGET_LANGUAGE_MISMATCH,
        )
        self.assertEqual(len(provider.calls), 1)

    def test_rejects_invalid_service_configuration(self) -> None:
        provider = _FakeLlmProvider(responses=())

        with self.assertRaisesRegex(TypeError, "LlmProvider"):
            TranslationService("provider", max_units_per_window=1)  # type: ignore[arg-type]
        with self.assertRaisesRegex(ValueError, "at least 1"):
            TranslationService(provider, max_units_per_window=0)
        with self.assertRaisesRegex(ValueError, "must not be negative"):
            TranslationService(provider, max_units_per_window=1, overlap_units=-1)
        with self.assertRaisesRegex(TypeError, "on_request_translated"):
            TranslationService(provider, max_units_per_window=1).translate(
                _source_artifact(),
                "vi",
                on_request_translated="callback",  # type: ignore[arg-type]
            )


class _FakeLlmProvider(LlmProvider):
    def __init__(self, *, responses: tuple[TranslationArtifact, ...]) -> None:
        self._responses = iter(responses)
        self.calls: list[tuple[TranslationRequest, str]] = []

    @property
    def capabilities(self) -> LlmProviderCapabilities:
        return LlmProviderCapabilities(
            model_ids=("offline-fake",),
            context_window_tokens=None,
            supports_structured_output=False,
            supports_streaming=False,
        )

    def translate(
        self,
        request: TranslationRequest,
        instructions: str,
    ) -> TranslationArtifact:
        self.calls.append((request, instructions))
        return next(self._responses)


def _source_artifact() -> StructuredTextArtifact:
    return StructuredTextArtifact(
        source_language="en",
        units=(
            StructuredTextUnit(unit_id="unit.1", text="First"),
            StructuredTextUnit(unit_id="unit.2", text="Second"),
            StructuredTextUnit(unit_id="unit.3", text="Third"),
        ),
    )


def _artifact(
    target_language: str,
    *units: tuple[str, str],
) -> TranslationArtifact:
    return TranslationArtifact(
        target_language=target_language,
        units=tuple(
            TranslatedTextUnit(unit_id=unit_id, translated_text=translated_text)
            for unit_id, translated_text in units
        ),
    )
