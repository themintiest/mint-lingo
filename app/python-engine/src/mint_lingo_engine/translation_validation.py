"""Provider-neutral validation of structured translation results."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from mint_lingo_engine.translation import TranslationArtifact, TranslationRequest


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

    def __post_init__(self) -> None:
        if not isinstance(self.code, TranslationValidationErrorCode):
            raise TypeError("code must be a TranslationValidationErrorCode")
        if not isinstance(self.message, str):
            raise TypeError("message must be a string")
        if not self.message or self.message.strip() != self.message:
            raise ValueError("message must not be blank or padded")


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
            )
        if not unit.translated_text or not unit.translated_text.strip():
            return _error(
                TranslationValidationErrorCode.EMPTY_TRANSLATED_TEXT,
                f"Translated result for unit ID {unit.unit_id!r} is empty.",
            )
        returned_unit_ids.append(unit.unit_id)

    if len(set(returned_unit_ids)) != len(returned_unit_ids):
        return _error(
            TranslationValidationErrorCode.DUPLICATE_UNIT_ID,
            "Translated result contains duplicate unit IDs.",
        )

    requested_unit_ids = {unit.unit_id for unit in request.artifact.units}
    returned_unit_id_set = set(returned_unit_ids)
    unexpected_unit_ids = returned_unit_id_set - requested_unit_ids
    if unexpected_unit_ids:
        return _error(
            TranslationValidationErrorCode.UNEXPECTED_UNIT_ID,
            "Translated result contains unit IDs that were not requested.",
        )
    missing_unit_ids = requested_unit_ids - returned_unit_id_set
    if missing_unit_ids:
        return _error(
            TranslationValidationErrorCode.MISSING_UNIT_ID,
            "Translated result is missing requested unit IDs.",
        )
    return artifact


def _error(
    code: TranslationValidationErrorCode,
    message: str,
) -> TranslationValidationError:
    return TranslationValidationError(code=code, message=message)
