"""Provider-neutral structured-text translation composition.

This service batches source-neutral text, invokes an ``LlmProvider`` with
provider-neutral instructions, validates each result, and retries only the
smallest safe subset of units. Concrete workflows retain lifecycle, checkpoint,
and merge-back responsibilities.
"""

from __future__ import annotations

from collections.abc import Iterable

from mint_lingo_engine.llm_provider import LlmProvider
from mint_lingo_engine.translation import (
    StructuredTextArtifact,
    StructuredTextUnit,
    TranslatedTextUnit,
    TranslationArtifact,
    TranslationRequest,
)
from mint_lingo_engine.translation_context import build_translation_context_windows
from mint_lingo_engine.translation_prompt import build_structured_translation_instructions
from mint_lingo_engine.translation_retry import (
    TranslationRetryScope,
    classify_translation_retry,
)
from mint_lingo_engine.translation_validation import (
    TranslationValidationError,
    validate_translation_artifact,
)


class TranslationServiceValidationError(RuntimeError):
    """A provider result remained invalid after the service's bounded retries."""

    def __init__(self, failure: TranslationValidationError) -> None:
        self.failure = failure
        super().__init__(failure.message)


class TranslationService:
    """Translate source-neutral units without owning a concrete workflow.

    Each batch has one immediate, granular validation retry at most. The
    service deliberately introduces no configurable retry policy, backoff,
    transport retry, persistence, or workflow policy.
    """

    def __init__(
        self,
        provider: LlmProvider,
        *,
        max_units_per_window: int,
        overlap_units: int = 0,
    ) -> None:
        if not isinstance(provider, LlmProvider):
            raise TypeError("provider must be an LlmProvider")
        _require_positive_integer(max_units_per_window, "max_units_per_window")
        _require_non_negative_integer(overlap_units, "overlap_units")
        self._provider = provider
        self._max_units_per_window = max_units_per_window
        self._overlap_units = overlap_units

    def translate(
        self,
        artifact: StructuredTextArtifact,
        target_language: str,
    ) -> TranslationArtifact:
        """Translate every source unit and return results in source-unit order."""

        if not isinstance(artifact, StructuredTextArtifact):
            raise TypeError("artifact must be a StructuredTextArtifact")

        translated_by_id: dict[str, TranslatedTextUnit] = {}
        requests = build_translation_context_windows(
            artifact,
            target_language,
            max_units_per_window=self._max_units_per_window,
            overlap_units=self._overlap_units,
        )
        for request in requests:
            translated_by_id.update(self._translate_request(request))

        return TranslationArtifact(
            target_language=target_language,
            units=tuple(translated_by_id[unit.unit_id] for unit in artifact.units),
        )

    def _translate_request(
        self,
        request: TranslationRequest,
    ) -> dict[str, TranslatedTextUnit]:
        successful_units: dict[str, TranslatedTextUnit] = {}
        pending_request = request

        for attempt in range(2):
            instructions = build_structured_translation_instructions(pending_request)
            result = self._provider.translate(pending_request, instructions)
            validation_result = validate_translation_artifact(pending_request, result)
            if isinstance(validation_result, TranslationArtifact):
                successful_units.update(_units_by_id(validation_result.units))
                return successful_units

            retry_plan = classify_translation_retry(pending_request, validation_result)
            if (
                not retry_plan.retryable
                or attempt == 1
            ):
                raise TranslationServiceValidationError(validation_result)

            if retry_plan.scope is TranslationRetryScope.FAILED_UNITS:
                successful_units.update(
                    _preserved_valid_units(
                        pending_request,
                        result,
                        excluded_unit_ids=retry_plan.unit_ids,
                    )
                )
            pending_request = _retry_request(pending_request, retry_plan.unit_ids)

        raise AssertionError("translation attempts must either return or raise")


def _retry_request(
    request: TranslationRequest,
    unit_ids: tuple[str, ...],
) -> TranslationRequest:
    requested_unit_id_set = set(unit_ids)
    return TranslationRequest(
        artifact=StructuredTextArtifact(
            source_language=request.artifact.source_language,
            units=tuple(
                unit
                for unit in request.artifact.units
                if unit.unit_id in requested_unit_id_set
            ),
        ),
        target_language=request.target_language,
        context=request.context,
    )


def _preserved_valid_units(
    request: TranslationRequest,
    result: TranslationArtifact,
    *,
    excluded_unit_ids: tuple[str, ...],
) -> dict[str, TranslatedTextUnit]:
    requested_unit_ids = {unit.unit_id for unit in request.artifact.units}
    excluded_unit_id_set = set(excluded_unit_ids)
    result_units_by_id: dict[str, TranslatedTextUnit] = {}
    duplicate_unit_ids: set[str] = set()

    for unit in result.units:
        if unit.unit_id not in requested_unit_ids or unit.unit_id in excluded_unit_id_set:
            continue
        if not unit.translated_text or not unit.translated_text.strip():
            continue
        if unit.unit_id in result_units_by_id:
            duplicate_unit_ids.add(unit.unit_id)
            continue
        result_units_by_id[unit.unit_id] = unit

    return {
        unit.unit_id: result_units_by_id[unit.unit_id]
        for unit in request.artifact.units
        if unit.unit_id not in duplicate_unit_ids and unit.unit_id in result_units_by_id
    }


def _units_by_id(
    units: Iterable[TranslatedTextUnit],
) -> dict[str, TranslatedTextUnit]:
    return {unit.unit_id: unit for unit in units}


def _require_positive_integer(value: object, name: str) -> None:
    _require_non_negative_integer(value, name)
    if value < 1:
        raise ValueError(f"{name} must be at least 1")


def _require_non_negative_integer(value: object, name: str) -> None:
    if isinstance(value, bool) or not isinstance(value, int):
        raise TypeError(f"{name} must be an integer")
    if value < 0:
        raise ValueError(f"{name} must not be negative")
