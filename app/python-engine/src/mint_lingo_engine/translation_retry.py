"""Provider-neutral retry classification for structured translation failures."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from mint_lingo_engine.translation import TranslationRequest
from mint_lingo_engine.translation_validation import (
    TranslationValidationError,
    TranslationValidationErrorCode,
)


class TranslationRetryScope(str, Enum):
    """The smallest safe set of requested units to retry."""

    NONE = "none"
    FAILED_UNITS = "failed_units"
    ALL_REQUESTED_UNITS = "all_requested_units"


@dataclass(frozen=True)
class TranslationRetryPlan:
    """A retry classification without retry execution or persistence behavior."""

    scope: TranslationRetryScope
    unit_ids: tuple[str, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.scope, TranslationRetryScope):
            raise TypeError("scope must be a TranslationRetryScope")
        if isinstance(self.unit_ids, (str, bytes)):
            raise TypeError("unit_ids must be an iterable of strings")
        unit_ids = tuple(self.unit_ids)
        if any(not isinstance(unit_id, str) for unit_id in unit_ids):
            raise TypeError("unit_ids must contain only strings")
        if not unit_ids and self.scope is not TranslationRetryScope.NONE:
            raise ValueError("retryable scopes must include unit IDs")
        if unit_ids and self.scope is TranslationRetryScope.NONE:
            raise ValueError("non-retryable scope must not include unit IDs")
        if len(set(unit_ids)) != len(unit_ids):
            raise ValueError("unit_ids must be unique")
        object.__setattr__(self, "unit_ids", unit_ids)

    @property
    def retryable(self) -> bool:
        """Whether this failure has a safe retry unit selection."""

        return self.scope is not TranslationRetryScope.NONE


def classify_translation_retry(
    request: TranslationRequest,
    failure: TranslationValidationError,
) -> TranslationRetryPlan:
    """Classify a validation failure and preserve unaffected request units."""

    if not isinstance(request, TranslationRequest):
        raise TypeError("request must be a TranslationRequest")
    if not isinstance(failure, TranslationValidationError):
        raise TypeError("failure must be a TranslationValidationError")

    requested_unit_ids = tuple(unit.unit_id for unit in request.artifact.units)
    if failure.code is TranslationValidationErrorCode.TARGET_LANGUAGE_MISMATCH:
        return TranslationRetryPlan(TranslationRetryScope.NONE, ())
    if failure.code in {
        TranslationValidationErrorCode.MISSING_UNIT_ID,
        TranslationValidationErrorCode.DUPLICATE_UNIT_ID,
        TranslationValidationErrorCode.EMPTY_TRANSLATED_TEXT,
    }:
        failed_unit_ids = _requested_failure_unit_ids(requested_unit_ids, failure.unit_ids)
        if failed_unit_ids:
            return TranslationRetryPlan(TranslationRetryScope.FAILED_UNITS, failed_unit_ids)
    return TranslationRetryPlan(
        TranslationRetryScope.ALL_REQUESTED_UNITS,
        requested_unit_ids,
    )


def _requested_failure_unit_ids(
    requested_unit_ids: tuple[str, ...],
    failure_unit_ids: tuple[str, ...],
) -> tuple[str, ...]:
    failure_unit_id_set = set(failure_unit_ids)
    return tuple(
        unit_id for unit_id in requested_unit_ids if unit_id in failure_unit_id_set
    )
