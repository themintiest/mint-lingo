from dataclasses import FrozenInstanceError
import unittest

from mint_lingo_engine.providers.translation.base import LlmProvider, LlmProviderCapabilities
from mint_lingo_engine.translation.models import (
    StructuredTextArtifact,
    StructuredTextUnit,
    TranslatedTextUnit,
    TranslationArtifact,
    TranslationContext,
    TranslationRequest,
)


class FakeLlmProvider(LlmProvider):
    """Offline substitute proving callers depend only on the shared contract."""

    def __init__(self) -> None:
        self.requests: list[TranslationRequest] = []

    @property
    def capabilities(self) -> LlmProviderCapabilities:
        return LlmProviderCapabilities(
            model_ids=("fake-translation",),
            context_window_tokens=None,
            supports_structured_output=False,
            supports_streaming=False,
        )

    def translate(
        self,
        request: TranslationRequest,
        instructions: str,
    ) -> TranslationArtifact:
        if not instructions:
            raise ValueError("instructions must not be blank")
        self.requests.append(request)
        return TranslationArtifact(
            target_language=request.target_language,
            units=[
                TranslatedTextUnit(
                    unit_id=unit.unit_id,
                    translated_text=f"translated: {unit.text}",
                )
                for unit in request.artifact.units
            ],
        )


class StructuredTextArtifactTest(unittest.TestCase):
    def test_preserves_ordered_stable_source_units(self) -> None:
        artifact = StructuredTextArtifact(
            source_language="zh-Hans-CN",
            units=[
                StructuredTextUnit(unit_id="body.2", text="Second source unit"),
                StructuredTextUnit(unit_id="body.1", text="First source unit"),
            ],
        )

        self.assertEqual(artifact.source_language, "zh-Hans-CN")
        self.assertEqual(
            [(unit.unit_id, unit.text) for unit in artifact.units],
            [("body.2", "Second source unit"), ("body.1", "First source unit")],
        )
        with self.assertRaises(FrozenInstanceError):
            artifact.units = ()  # type: ignore[misc]

    def test_rejects_empty_duplicate_or_malformed_source_units(self) -> None:
        with self.assertRaisesRegex(ValueError, "must not be empty"):
            StructuredTextArtifact(source_language="en", units=[])
        with self.assertRaisesRegex(ValueError, "unique unit_id"):
            StructuredTextArtifact(
                source_language="en",
                units=[
                    StructuredTextUnit(unit_id="same", text="One"),
                    StructuredTextUnit(unit_id="same", text="Two"),
                ],
            )
        with self.assertRaisesRegex(ValueError, "blank or padded"):
            StructuredTextUnit(unit_id=" ", text="Source")
        with self.assertRaisesRegex(ValueError, "text must not be blank"):
            StructuredTextUnit(unit_id="source", text="  ")


class TranslationRequestTest(unittest.TestCase):
    def test_carries_target_language_and_optional_reference_context(self) -> None:
        artifact = StructuredTextArtifact(
            source_language="ja",
            units=[StructuredTextUnit(unit_id="paragraph.1", text="Source")],
        )
        context = TranslationContext(
            units=[StructuredTextUnit(unit_id="paragraph.0", text="Before")]
        )

        request = TranslationRequest(
            artifact=artifact,
            target_language="pt-BR",
            context=context,
        )

        self.assertIs(request.artifact, artifact)
        self.assertEqual(request.target_language, "pt-BR")
        self.assertIs(request.context, context)

    def test_rejects_invalid_request_values(self) -> None:
        artifact = StructuredTextArtifact(
            source_language="en",
            units=[StructuredTextUnit(unit_id="source", text="Source")],
        )

        with self.assertRaisesRegex(TypeError, "StructuredTextArtifact"):
            TranslationRequest(artifact="source", target_language="vi")  # type: ignore[arg-type]
        with self.assertRaisesRegex(ValueError, "target_language"):
            TranslationRequest(artifact=artifact, target_language=" ")
        with self.assertRaisesRegex(TypeError, "TranslationContext"):
            TranslationRequest(
                artifact=artifact,
                target_language="vi",
                context="source",  # type: ignore[arg-type]
            )


class TranslationContextTest(unittest.TestCase):
    def test_preserves_unique_reference_unit_identity(self) -> None:
        context = TranslationContext(
            units=[StructuredTextUnit(unit_id="previous", text="Before")]
        )

        self.assertEqual(context.units[0].unit_id, "previous")
        with self.assertRaisesRegex(ValueError, "must not be empty"):
            TranslationContext(units=[])
        with self.assertRaisesRegex(ValueError, "unique unit_id"):
            TranslationContext(
                units=[
                    StructuredTextUnit(unit_id="same", text="One"),
                    StructuredTextUnit(unit_id="same", text="Two"),
                ]
            )


class TranslationArtifactTest(unittest.TestCase):
    def test_preserves_translated_unit_identity_and_order(self) -> None:
        artifact = TranslationArtifact(
            target_language="vi",
            units=[
                TranslatedTextUnit(unit_id="body.2", translated_text="Hai"),
                TranslatedTextUnit(unit_id="body.1", translated_text="Một"),
            ],
        )

        self.assertEqual(artifact.target_language, "vi")
        self.assertEqual(
            [(unit.unit_id, unit.translated_text) for unit in artifact.units],
            [("body.2", "Hai"), ("body.1", "Một")],
        )

    def test_does_not_own_later_request_result_validation(self) -> None:
        artifact = TranslationArtifact(
            target_language="vi",
            units=[
                TranslatedTextUnit(unit_id="unexpected", translated_text=""),
                TranslatedTextUnit(unit_id="unexpected", translated_text="Kết quả"),
            ],
        )

        self.assertEqual(artifact.units[0].unit_id, "unexpected")
        self.assertEqual(artifact.units[0].translated_text, "")
        self.assertEqual(artifact.units[1].unit_id, "unexpected")
        self.assertEqual(TranslationArtifact(target_language="vi", units=[]).units, ())


class LlmProviderTest(unittest.TestCase):
    def test_fake_provider_uses_only_the_shared_translation_contract(self) -> None:
        request = TranslationRequest(
            artifact=StructuredTextArtifact(
                source_language="en",
                units=[StructuredTextUnit(unit_id="paragraph.1", text="Source")],
            ),
            target_language="vi",
        )
        provider: LlmProvider = FakeLlmProvider()

        result = provider.translate(request, "Translate the requested source units.")

        self.assertEqual(provider.requests, [request])  # type: ignore[attr-defined]
        self.assertEqual(provider.capabilities.model_ids, ("fake-translation",))
        self.assertEqual(result.target_language, "vi")
        self.assertEqual(
            [(unit.unit_id, unit.translated_text) for unit in result.units],
            [("paragraph.1", "translated: Source")],
        )

    def test_provider_contract_requires_normalized_translation_operation(self) -> None:
        with self.assertRaises(TypeError):
            LlmProvider()


class LlmProviderCapabilitiesTest(unittest.TestCase):
    def test_preserves_models_context_limit_and_support_flags(self) -> None:
        capabilities = LlmProviderCapabilities(
            model_ids=["local-model", "remote-model"],
            context_window_tokens=32_768,
            supports_structured_output=True,
            supports_streaming=False,
        )

        self.assertEqual(capabilities.model_ids, ("local-model", "remote-model"))
        self.assertEqual(capabilities.context_window_tokens, 32_768)
        self.assertTrue(capabilities.supports_structured_output)
        self.assertFalse(capabilities.supports_streaming)

    def test_allows_unknown_context_limit_and_rejects_malformed_metadata(self) -> None:
        capabilities = LlmProviderCapabilities(
            model_ids=[],
            context_window_tokens=None,
            supports_structured_output=False,
            supports_streaming=True,
        )
        self.assertEqual(capabilities.model_ids, ())
        self.assertIsNone(capabilities.context_window_tokens)

        with self.assertRaisesRegex(ValueError, "model_ids must be unique"):
            LlmProviderCapabilities(
                model_ids=["same", "same"],
                context_window_tokens=None,
                supports_structured_output=False,
                supports_streaming=False,
            )
        with self.assertRaisesRegex(ValueError, "at least 1"):
            LlmProviderCapabilities(
                model_ids=[],
                context_window_tokens=0,
                supports_structured_output=False,
                supports_streaming=False,
            )
        with self.assertRaisesRegex(TypeError, "supports_streaming"):
            LlmProviderCapabilities(
                model_ids=[],
                context_window_tokens=None,
                supports_structured_output=False,
                supports_streaming="no",  # type: ignore[arg-type]
            )
