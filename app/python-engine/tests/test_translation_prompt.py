import unittest

from mint_lingo_engine.translation import (
    StructuredTextArtifact,
    StructuredTextUnit,
    TranslationContext,
    TranslationRequest,
)
from mint_lingo_engine.translation_prompt import (
    build_structured_translation_instructions,
)


class StructuredTranslationInstructionsTest(unittest.TestCase):
    def test_makes_target_language_and_required_unit_ids_explicit(self) -> None:
        request = TranslationRequest(
            artifact=StructuredTextArtifact(
                source_language="ja",
                units=[
                    StructuredTextUnit(unit_id="body.2", text="Second"),
                    StructuredTextUnit(unit_id="body.1", text="First"),
                ],
            ),
            target_language="pt-BR",
        )

        instructions = build_structured_translation_instructions(request)

        self.assertIn("Source language: ja", instructions)
        self.assertIn("Target language: pt-BR", instructions)
        self.assertIn('Required unit IDs, in order: ["body.2", "body.1"]', instructions)
        self.assertIn("Preserve each required unit ID exactly", instructions)
        self.assertIn("No reference context is supplied.", instructions)
        self.assertNotIn("EPUB", instructions)
        self.assertNotIn("subtitle", instructions.lower())

    def test_marks_reference_context_as_non_output_material(self) -> None:
        request = TranslationRequest(
            artifact=StructuredTextArtifact(
                source_language="en",
                units=[StructuredTextUnit(unit_id="requested", text="Translate")],
            ),
            target_language="vi",
            context=TranslationContext(
                units=[StructuredTextUnit(unit_id="reference", text="Context")]
            ),
        )

        instructions = build_structured_translation_instructions(request)

        self.assertIn("Reference context is supplied only for comprehension", instructions)
        self.assertIn('["requested"]', instructions)
        self.assertNotIn("reference\"]", instructions)

    def test_rejects_non_request_input(self) -> None:
        with self.assertRaisesRegex(TypeError, "TranslationRequest"):
            build_structured_translation_instructions("request")  # type: ignore[arg-type]
