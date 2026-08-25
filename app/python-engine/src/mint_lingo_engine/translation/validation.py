"""Provider-neutral validation of structured translation results."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from mint_lingo_engine.translation.models import TranslationArtifact, TranslationRequest


class TranslationValidationErrorCode(str, Enum):
    """Normalized shared-translation result failures."""

    TARGET_LANGUAGE_MISMATCH = "translation.target_language_mismatch"
    MISSING_UNIT_ID = "translation.missing_unit_id"
    UNEXPECTED_UNIT_ID = "translation.unexpected_unit_id"
    DUPLICATE_UNIT_ID = "translation.duplicate_unit_id"
    MALFORMED_UNIT_ID = "translation.malformed_unit_id"
    EMPTY_TRANSLATED_TEXT = "translation.empty_translated_text"


@dataclass(frozen=True)
class TranslationValidationError:
    """A structured validation failure independent of any provider response."""

    code: TranslationValidationErrorCode
    message: str
    unit_ids: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.code, TranslationValidationErrorCode):
            raise TypeError("code must be a TranslationValidationErrorCode")
        if not isinstance(self.message, str):
            raise TypeError("message must be a string")
        if not self.message or self.message.strip() != self.message:
            raise ValueError("message must not be blank or padded")
        if isinstance(self.unit_ids, (str, bytes)):
            raise TypeError("unit_ids must be an iterable of strings")
        unit_ids = tuple(self.unit_ids)
        if any(not isinstance(unit_id, str) for unit_id in unit_ids):
            raise TypeError("unit_ids must contain only strings")
        if len(set(unit_ids)) != len(unit_ids):
            raise ValueError("unit_ids must be unique")
        object.__setattr__(self, "unit_ids", unit_ids)


def validate_translation_artifact(
    request: TranslationRequest,
    artifact: TranslationArtifact,
) -> TranslationArtifact | TranslationValidationError:
    """Return a valid artifact or the first precise shared validation error."""

    if not isinstance(request, TranslationRequest):
        raise TypeError("request must be a TranslationRequest")
    if not isinstance(artifact, TranslationArtifact):
        raise TypeError("artifact must be a TranslationArtifact")
    if artifact.target_language != request.target_language:
        return _error(
            TranslationValidationErrorCode.TARGET_LANGUAGE_MISMATCH,
            "Translated result target language does not match the request.",
        )

    returned_unit_ids: list[str] = []
    for unit in artifact.units:
        if not unit.unit_id or unit.unit_id.strip() != unit.unit_id:
            return _error(
                TranslationValidationErrorCode.MALFORMED_UNIT_ID,
                "Translated result contains a blank or padded unit ID.",
                unit_ids=(unit.unit_id,),
            )
        if not unit.translated_text or not unit.translated_text.strip():
            return _error(
                TranslationValidationErrorCode.EMPTY_TRANSLATED_TEXT,
                f"Translated result for unit ID {unit.unit_id!r} is empty.",
                unit_ids=(unit.unit_id,),
            )
        returned_unit_ids.append(unit.unit_id)

    duplicate_unit_ids = _duplicate_unit_ids(returned_unit_ids)
    if duplicate_unit_ids:
        return _error(
            TranslationValidationErrorCode.DUPLICATE_UNIT_ID,
            "Translated result contains duplicate unit IDs.",
            unit_ids=duplicate_unit_ids,
        )

    requested_unit_ids = {unit.unit_id for unit in request.artifact.units}
    returned_unit_id_set = set(returned_unit_ids)
    unexpected_unit_ids = tuple(
        unit_id for unit_id in returned_unit_ids if unit_id not in requested_unit_ids
    )
    if unexpected_unit_ids:
        return _error(
            TranslationValidationErrorCode.UNEXPECTED_UNIT_ID,
            "Translated result contains unit IDs that were not requested.",
            unit_ids=unexpected_unit_ids,
        )
    missing_unit_ids = tuple(
        unit.unit_id
        for unit in request.artifact.units
        if unit.unit_id not in returned_unit_id_set
    )
    if missing_unit_ids:
        return _error(
            TranslationValidationErrorCode.MISSING_UNIT_ID,
            "Translated result is missing requested unit IDs.",
            unit_ids=missing_unit_ids,
        )
    return artifact


def _error(
    code: TranslationValidationErrorCode,
    message: str,
    unit_ids: tuple[str, ...] = (),
) -> TranslationValidationError:
    return TranslationValidationError(code=code, message=message, unit_ids=unit_ids)


def _duplicate_unit_ids(unit_ids: list[str]) -> tuple[str, ...]:
    seen: set[str] = set()
    duplicate_unit_ids: list[str] = []
    for unit_id in unit_ids:
        if unit_id in seen and unit_id not in duplicate_unit_ids:
            duplicate_unit_ids.append(unit_id)
        seen.add(unit_id)
    return tuple(duplicate_unit_ids)
