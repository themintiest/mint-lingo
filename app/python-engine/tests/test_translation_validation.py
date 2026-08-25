import unittest

from mint_lingo_engine.translation import (
    StructuredTextArtifact,
    StructuredTextUnit,
    TranslatedTextUnit,
    TranslationArtifact,
    TranslationRequest,
)
from mint_lingo_engine.translation_validation import (
    TranslationValidationError,
    TranslationValidationErrorCode,
    validate_translation_artifact,
)


class TranslationArtifactValidationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.request = TranslationRequest(
            artifact=StructuredTextArtifact(
                source_language="en",
                units=[
                    StructuredTextUnit(unit_id="unit.1", text="First"),
                    StructuredTextUnit(unit_id="unit.2", text="Second"),
                ],
            ),
            target_language="vi",
        )

    def test_returns_a_result_that_matches_request_identity_and_language(self) -> None:
        artifact = TranslationArtifact(
            target_language="vi",
            units=[
                TranslatedTextUnit(unit_id="unit.1", translated_text="Má»™t"),
                TranslatedTextUnit(unit_id="unit.2", translated_text="Hai"),
            ],
        )

        result = validate_translation_artifact(self.request, artifact)

        self.assertIs(result, artifact)

    def test_rejects_target_language_mismatch(self) -> None:
        result = validate_translation_artifact(
            self.request,
            TranslationArtifact(
                target_language="pt-BR",
                units=[
                    TranslatedTextUnit(unit_id="unit.1", translated_text="One"),
                    TranslatedTextUnit(unit_id="unit.2", translated_text="Two"),
                ],
            ),
        )

        self.assert_validation_error(
            result,
            TranslationValidationErrorCode.TARGET_LANGUAGE_MISMATCH,
        )
        self.assertEqual(result.unit_ids, ())  # type: ignore[union-attr]

    def test_rejects_missing_extra_duplicate_and_malformed_unit_results(self) -> None:
        cases = (
            (
                "missing",
                TranslationArtifact(
                    target_language="vi",
                    units=[TranslatedTextUnit(unit_id="unit.1", translated_text="One")],
                ),
                TranslationValidationErrorCode.MISSING_UNIT_ID,
                ("unit.2",),
            ),
            (
                "unexpected",
                TranslationArtifact(
                    target_language="vi",
                    units=[
                        TranslatedTextUnit(unit_id="unit.1", translated_text="One"),
                        TranslatedTextUnit(unit_id="unit.2", translated_text="Two"),
                        TranslatedTextUnit(unit_id="unit.3", translated_text="Three"),
                    ],
                ),
                TranslationValidationErrorCode.UNEXPECTED_UNIT_ID,
                ("unit.3",),
            ),
            (
                "duplicate",
                TranslationArtifact(
                    target_language="vi",
                    units=[
                        TranslatedTextUnit(unit_id="unit.1", translated_text="One"),
                        TranslatedTextUnit(unit_id="unit.1", translated_text="Again"),
                    ],
                ),
                TranslationValidationErrorCode.DUPLICATE_UNIT_ID,
                ("unit.1",),
            ),
            (
                "malformed identifier",
                TranslationArtifact(
                    target_language="vi",
                    units=[
                        TranslatedTextUnit(unit_id=" unit.1", translated_text="One"),
                        TranslatedTextUnit(unit_id="unit.2", translated_text="Two"),
                    ],
                ),
                TranslationValidationErrorCode.MALFORMED_UNIT_ID,
                (" unit.1",),
            ),
            (
                "empty translation",
                TranslationArtifact(
                    target_language="vi",
                    units=[
                        TranslatedTextUnit(unit_id="unit.1", translated_text=" "),
                        TranslatedTextUnit(unit_id="unit.2", translated_text="Two"),
                    ],
                ),
                TranslationValidationErrorCode.EMPTY_TRANSLATED_TEXT,
                ("unit.1",),
            ),
        )

        for name, artifact, expected_code, expected_unit_ids in cases:
            with self.subTest(name=name):
                result = validate_translation_artifact(self.request, artifact)
                self.assert_validation_error(
                    result,
                    expected_code,
                )
                self.assertEqual(result.unit_ids, expected_unit_ids)  # type: ignore[union-attr]

    def test_rejects_non_translation_models(self) -> None:
        with self.assertRaisesRegex(TypeError, "TranslationRequest"):
            validate_translation_artifact("request", TranslationArtifact("vi", []))  # type: ignore[arg-type]
        with self.assertRaisesRegex(TypeError, "TranslationArtifact"):
            validate_translation_artifact(self.request, "artifact")  # type: ignore[arg-type]

    def assert_validation_error(
        self,
        result: TranslationArtifact | TranslationValidationError,
        expected_code: TranslationValidationErrorCode,
    ) -> None:
        self.assertIsInstance(result, TranslationValidationError)
        self.assertEqual(result.code, expected_code)  # type: ignore[union-attr]
