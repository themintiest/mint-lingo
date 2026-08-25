import unittest

from mint_lingo_engine.translation import (
    StructuredTextArtifact,
    StructuredTextUnit,
    TranslatedTextUnit,
    TranslationArtifact,
    TranslationRequest,
)
from mint_lingo_engine.translation_retry import (
    TranslationRetryPlan,
    TranslationRetryScope,
    classify_translation_retry,
)
from mint_lingo_engine.translation_validation import (
    TranslationValidationError,
    TranslationValidationErrorCode,
    validate_translation_artifact,
)


class TranslationRetryClassificationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.request = TranslationRequest(
            artifact=StructuredTextArtifact(
                source_language="en",
                units=[
                    StructuredTextUnit(unit_id="unit.1", text="First"),
                    StructuredTextUnit(unit_id="unit.2", text="Second"),
                    StructuredTextUnit(unit_id="unit.3", text="Third"),
                ],
            ),
            target_language="vi",
        )

    def test_retries_only_failed_requested_units_when_safe(self) -> None:
        for code in (
            TranslationValidationErrorCode.MISSING_UNIT_ID,
            TranslationValidationErrorCode.DUPLICATE_UNIT_ID,
            TranslationValidationErrorCode.EMPTY_TRANSLATED_TEXT,
        ):
            with self.subTest(code=code):
                plan = classify_translation_retry(
                    self.request,
                    TranslationValidationError(
                        code=code,
                        message="Retry selected units.",
                        unit_ids=("unit.3", "unit.1"),
                    ),
                )

                self.assertTrue(plan.retryable)
                self.assertEqual(plan.scope, TranslationRetryScope.FAILED_UNITS)
                self.assertEqual(plan.unit_ids, ("unit.1", "unit.3"))

    def test_uses_validator_missing_id_metadata_to_preserve_successful_units(self) -> None:
        failure = validate_translation_artifact(
            self.request,
            TranslationArtifact(
                target_language="vi",
                units=[
                    TranslatedTextUnit(unit_id="unit.1", translated_text="One"),
                    TranslatedTextUnit(unit_id="unit.3", translated_text="Three"),
                ],
            ),
        )
        self.assertIsInstance(failure, TranslationValidationError)

        plan = classify_translation_retry(self.request, failure)

        self.assertEqual(plan.scope, TranslationRetryScope.FAILED_UNITS)
        self.assertEqual(plan.unit_ids, ("unit.2",))

    def test_retries_full_request_only_for_structurally_unsafe_results(self) -> None:
        for code in (
            TranslationValidationErrorCode.UNEXPECTED_UNIT_ID,
            TranslationValidationErrorCode.MALFORMED_UNIT_ID,
        ):
            with self.subTest(code=code):
                plan = classify_translation_retry(
                    self.request,
                    TranslationValidationError(
                        code=code,
                        message="Response structure is unsafe.",
                        unit_ids=("unexpected",),
                    ),
                )

                self.assertTrue(plan.retryable)
                self.assertEqual(plan.scope, TranslationRetryScope.ALL_REQUESTED_UNITS)
                self.assertEqual(plan.unit_ids, ("unit.1", "unit.2", "unit.3"))

    def test_rejects_target_language_mismatch_from_retry(self) -> None:
        plan = classify_translation_retry(
            self.request,
            TranslationValidationError(
                code=TranslationValidationErrorCode.TARGET_LANGUAGE_MISMATCH,
                message="Target languages differ.",
            ),
        )

        self.assertFalse(plan.retryable)
        self.assertEqual(plan.scope, TranslationRetryScope.NONE)
        self.assertEqual(plan.unit_ids, ())

    def test_retry_plan_rejects_invalid_scope_unit_combinations(self) -> None:
        with self.assertRaisesRegex(ValueError, "retryable scopes"):
            TranslationRetryPlan(TranslationRetryScope.FAILED_UNITS, ())
        with self.assertRaisesRegex(ValueError, "non-retryable"):
            TranslationRetryPlan(TranslationRetryScope.NONE, ("unit.1",))
