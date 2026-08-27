import unittest

from mint_lingo_engine.translation.models import (
    StructuredTextArtifact,
    StructuredTextUnit,
    TranslationContext,
    TranslationRequest,
)
from mint_lingo_engine.translation.prompt import (
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
        self.assertIn("Target language: Portuguese (Brazil) (pt-BR)", instructions)
        self.assertIn('Required unit IDs, in order: ["body.2", "body.1"]', instructions)
        self.assertIn("Preserve each required unit ID exactly", instructions)
        self.assertIn("No reference context is supplied.", instructions)
        self.assertNotIn("EPUB", instructions)
        self.assertNotIn("subtitle", instructions.lower())

    def test_requires_natural_language_output_in_the_resolved_target_language(self) -> None:
        instructions = build_structured_translation_instructions(
            _request(target_language="vi")
        )

        self.assertIn("Target language: Vietnamese (vi)", instructions)
        self.assertIn(
            "Write all translated natural-language text in Vietnamese.",
            instructions,
        )
        self.assertIn(
            "Do not use a different language for translated natural-language text.",
            instructions,
        )
        self.assertIn("proper name, quotation, code", instructions)

    def test_makes_complete_translation_and_source_copy_prohibition_unambiguous(
        self,
    ) -> None:
        instructions = build_structured_translation_instructions(
            _request(target_language="vi")
        )

        self.assertIn(
            "Render every ordinary natural-language sentence in every requested "
            "unit completely in Vietnamese, from beginning to end.",
            instructions,
        )
        self.assertIn(
            "Do not copy, retain, or leave a source-language sentence, clause, "
            "or material span of ordinary source prose in a translated value.",
            instructions,
        )
        self.assertIn(
            "A target-language prefix followed by copied ordinary source prose "
            "is invalid.",
            instructions,
        )
        self.assertIn(
            "Preserve source text only when it is genuinely non-translatable.",
            instructions,
        )

    def test_includes_a_provider_neutral_complete_translation_example_for_known_and_fallback_languages(
        self,
    ) -> None:
        for tag, name in (("vi", "Vietnamese"), ("x-user-language", "x-user-language")):
            with self.subTest(tag=tag):
                instructions = build_structured_translation_instructions(
                    _request(target_language=tag)
                )

                self.assertIn(
                    "Abstract structured example (illustrative only):", instructions
                )
                self.assertIn(
                    (
                        "(preserved unit ID: example.unit; complete translated value: "
                        f"<complete {name} text>)"
                    ),
                    instructions,
                )
                self.assertNotIn("Ollama", instructions)
                self.assertNotIn("EPUB", instructions)

    def test_resolves_supported_tags_and_safely_falls_back_to_an_unknown_tag(self) -> None:
        language_names = {
            "en": "English",
            "vi": "Vietnamese",
            "ja": "Japanese",
            "ko": "Korean",
            "zh-Hans": "Chinese (Simplified)",
            "zh-Hant": "Chinese (Traditional)",
            "pt-BR": "Portuguese (Brazil)",
            "pt-PT": "Portuguese (Portugal)",
            "fr": "French",
            "de": "German",
            "es": "Spanish",
            "it": "Italian",
            "ru": "Russian",
            "hi": "Hindi",
            "ar": "Arabic",
            "th": "Thai",
            "id": "Indonesian",
            "x-user-language": "x-user-language",
        }
        for tag, name in language_names.items():
            with self.subTest(tag=tag):
                instructions = build_structured_translation_instructions(
                    _request(target_language=tag)
                )
                self.assertIn(f"Target language: {name} ({tag})", instructions)

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


def _request(*, target_language: str) -> TranslationRequest:
    return TranslationRequest(
        artifact=StructuredTextArtifact(
            source_language="en",
            units=[StructuredTextUnit(unit_id="unit.1", text="Source")],
        ),
        target_language=target_language,
    )
