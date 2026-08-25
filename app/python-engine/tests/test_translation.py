from dataclasses import FrozenInstanceError
import unittest

from mint_lingo_engine.translation import (
    StructuredTextArtifact,
    StructuredTextUnit,
    TranslatedTextUnit,
    TranslationArtifact,
    TranslationRequest,
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
    def test_carries_target_language_and_optional_context_without_batch_behavior(self) -> None:
        artifact = StructuredTextArtifact(
            source_language="ja",
            units=[StructuredTextUnit(unit_id="paragraph.1", text="Source")],
        )

        request = TranslationRequest(
            artifact=artifact,
            target_language="pt-BR",
            context="Previous paragraph summary.",
        )

        self.assertIs(request.artifact, artifact)
        self.assertEqual(request.target_language, "pt-BR")
        self.assertEqual(request.context, "Previous paragraph summary.")

    def test_rejects_invalid_request_values(self) -> None:
        artifact = StructuredTextArtifact(
            source_language="en",
            units=[StructuredTextUnit(unit_id="source", text="Source")],
        )

        with self.assertRaisesRegex(TypeError, "StructuredTextArtifact"):
            TranslationRequest(artifact="source", target_language="vi")  # type: ignore[arg-type]
        with self.assertRaisesRegex(ValueError, "target_language"):
            TranslationRequest(artifact=artifact, target_language=" ")
        with self.assertRaisesRegex(TypeError, "context"):
            TranslationRequest(artifact=artifact, target_language="vi", context=42)  # type: ignore[arg-type]


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
