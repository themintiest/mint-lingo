"""EPUB-owned source-unit input guards before provider translation."""

from __future__ import annotations

from collections.abc import Iterable

from mint_lingo_engine.translation.models import StructuredTextUnit


_MAX_SOURCE_UNIT_UTF8_BYTES = 8 * 1024


class EpubTranslationUnitTooLargeError(ValueError):
    """A pending EPUB unit exceeds the fixed safe provider-input byte bound."""


def reject_oversized_epub_translation_units(
    units: Iterable[StructuredTextUnit],
) -> None:
    """Reject unsafe source payloads without treating bytes as a token estimate.

    This is a fixed UTF-8 byte bound on one source unit. It is deliberately not
    derived from provider context metadata and does not claim a token count.
    The caller retains the source text and any size detail; this exception is
    intentionally safe to map to a user-facing EPUB diagnostic.
    """

    for unit in units:
        if not isinstance(unit, StructuredTextUnit):
            raise TypeError("units must contain only StructuredTextUnit values")
        if len(unit.text.encode("utf-8")) > _MAX_SOURCE_UNIT_UTF8_BYTES:
            raise EpubTranslationUnitTooLargeError()
