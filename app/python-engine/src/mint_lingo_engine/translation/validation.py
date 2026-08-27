"""Provider-neutral validation of structured translation results."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import re
import unicodedata

from mint_lingo_engine.translation.models import TranslationArtifact, TranslationRequest


class TranslationValidationErrorCode(str, Enum):
    """Normalized shared-translation result failures."""

    TARGET_LANGUAGE_MISMATCH = "translation.target_language_mismatch"
    MISSING_UNIT_ID = "translation.missing_unit_id"
    UNEXPECTED_UNIT_ID = "translation.unexpected_unit_id"
    DUPLICATE_UNIT_ID = "translation.duplicate_unit_id"
    MALFORMED_UNIT_ID = "translation.malformed_unit_id"
    EMPTY_TRANSLATED_TEXT = "translation.empty_translated_text"
    MATERIAL_SOURCE_COPY = "translation.material_source_copy"


# This narrow guard deliberately prefers false negatives. It detects only a
# long, ordinary-prose run that is material in both the source and result; it
# is not a language detector or a general translation-quality score.
_MIN_COPIED_RUN_TOKENS = 8
_MIN_COPIED_RUN_CHARACTERS = 48
_MIN_COPIED_SOURCE_PROPORTION = 0.40
_MIN_COPIED_RESULT_PROPORTION = 0.40
_MAX_WINDOW_CANDIDATES = 4
_MAX_PROTECTED_QUOTATION_TOKENS = 12
_WORD_PATTERN = re.compile(r"[^\W_]+(?:['’][^\W_]+)?", re.UNICODE)
_URL_OR_EMAIL_PATTERN = re.compile(
    r"(?:https?://|www\.)[^\s<>\"']+|\b[^\s@]+@[^\s@]+\.[^\s@]+\b",
    re.IGNORECASE,
)
_CODE_IDENTIFIER_PATTERN = re.compile(
    r"\b[A-Za-z_][A-Za-z0-9_]*(?:[.:/_-][A-Za-z0-9_./:-]+)+\b"
)
_SHORT_QUOTATION_PATTERN = re.compile(r'"([^\"]{0,160})"|“([^”]{0,160})”')


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
    translated_by_id = {unit.unit_id: unit.translated_text for unit in artifact.units}
    copied_unit_ids = tuple(
        unit.unit_id
        for unit in request.artifact.units
        if _contains_material_source_copy(unit.text, translated_by_id[unit.unit_id])
    )
    if copied_unit_ids:
        return _error(
            TranslationValidationErrorCode.MATERIAL_SOURCE_COPY,
            "Translated result contains materially copied source prose.",
            unit_ids=copied_unit_ids,
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


def _contains_material_source_copy(source_text: str, translated_text: str) -> bool:
    """Detect only substantial copied ordinary prose without retaining either text.

    Normalized text and tokens exist only while this function compares a single
    result. Protected spans and tokens keep ordinary translation overlaps such
    as names, dates, URLs, identifiers, and short quotations out of the
    comparison.
    """

    source_tokens = _ordinary_tokens(source_text)
    translated_tokens = _ordinary_tokens(translated_text)
    if (
        len(source_tokens) < _MIN_COPIED_RUN_TOKENS
        or len(translated_tokens) < _MIN_COPIED_RUN_TOKENS
    ):
        return False

    source_windows: dict[tuple[str, ...], list[int]] = {}
    for start in range(len(source_tokens) - _MIN_COPIED_RUN_TOKENS + 1):
        window = tuple(
            token for token, _ in source_tokens[start : start + _MIN_COPIED_RUN_TOKENS]
        )
        starts = source_windows.setdefault(window, [])
        if len(starts) < _MAX_WINDOW_CANDIDATES:
            starts.append(start)

    for translated_start in range(
        len(translated_tokens) - _MIN_COPIED_RUN_TOKENS + 1
    ):
        window = tuple(
            token
            for token, _ in translated_tokens[
                translated_start : translated_start + _MIN_COPIED_RUN_TOKENS
            ]
        )
        for source_start in source_windows.get(window, ()):
            copied_length = _copied_run_length(
                source_tokens,
                translated_tokens,
                source_start,
                translated_start,
            )
            copied_characters = sum(
                length for _, length in source_tokens[source_start : source_start + copied_length]
            ) + copied_length - 1
            if (
                copied_length >= _MIN_COPIED_RUN_TOKENS
                and copied_characters >= _MIN_COPIED_RUN_CHARACTERS
                and copied_length / len(source_tokens) >= _MIN_COPIED_SOURCE_PROPORTION
                and copied_length / len(translated_tokens) >= _MIN_COPIED_RESULT_PROPORTION
            ):
                return True
    return False


def _ordinary_tokens(text: str) -> list[tuple[str, int]]:
    normalized = unicodedata.normalize("NFKC", text)
    protected_spans = _protected_spans(normalized)
    tokens: list[tuple[str, int]] = []
    for match in _WORD_PATTERN.finditer(normalized):
        raw_token = match.group()
        if _is_protected_token(raw_token, match.span(), protected_spans):
            continue
        tokens.append((raw_token.casefold(), len(raw_token)))
    return tokens


def _protected_spans(text: str) -> tuple[tuple[int, int], ...]:
    spans = [match.span() for match in _URL_OR_EMAIL_PATTERN.finditer(text)]
    spans.extend(match.span() for match in _CODE_IDENTIFIER_PATTERN.finditer(text))
    for match in _SHORT_QUOTATION_PATTERN.finditer(text):
        quotation = match.group(1) or match.group(2) or ""
        if len(_WORD_PATTERN.findall(quotation)) <= _MAX_PROTECTED_QUOTATION_TOKENS:
            spans.append(match.span())
    return tuple(spans)


def _is_protected_token(
    token: str,
    token_span: tuple[int, int],
    protected_spans: tuple[tuple[int, int], ...],
) -> bool:
    if any(token_span[0] < end and start < token_span[1] for start, end in protected_spans):
        return True
    if any(character.isdigit() for character in token):
        return True
    return token[:1].isupper()


def _copied_run_length(
    source_tokens: list[tuple[str, int]],
    translated_tokens: list[tuple[str, int]],
    source_start: int,
    translated_start: int,
) -> int:
    length = 0
    while (
        source_start + length < len(source_tokens)
        and translated_start + length < len(translated_tokens)
        and source_tokens[source_start + length][0]
        == translated_tokens[translated_start + length][0]
    ):
        length += 1
    return length
