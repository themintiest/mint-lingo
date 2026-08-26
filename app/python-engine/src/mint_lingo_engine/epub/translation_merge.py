"""EPUB-owned stable-ID translation merge map for later XHTML restoration."""

from __future__ import annotations

from dataclasses import dataclass

from mint_lingo_engine.epub.document import EpubTextMergeTarget
from mint_lingo_engine.epub.projection import EpubStructuredTextProjection
from mint_lingo_engine.translation.models import TranslationArtifact, TranslationRequest
from mint_lingo_engine.translation.validation import validate_translation_artifact


@dataclass(frozen=True)
class EpubMergedTranslationUnit:
    """One translated value paired with its original EPUB-owned merge target."""

    target: EpubTextMergeTarget
    translated_text: str

    def __post_init__(self) -> None:
        if not isinstance(self.target, EpubTextMergeTarget):
            raise TypeError("target must be an EpubTextMergeTarget")
        if not isinstance(self.translated_text, str):
            raise TypeError("translated_text must be a string")
        if not self.translated_text or not self.translated_text.strip():
            raise ValueError("translated_text must not be blank")


@dataclass(frozen=True)
class EpubMergedTranslationArtifact:
    """Ordered, EPUB-owned merge values without modifying XHTML prematurely."""

    target_language: str
    units: tuple[EpubMergedTranslationUnit, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.target_language, str):
            raise TypeError("target_language must be a string")
        if not self.target_language or self.target_language.strip() != self.target_language:
            raise ValueError("target_language must not be blank or padded")
        units = tuple(self.units)
        if any(not isinstance(unit, EpubMergedTranslationUnit) for unit in units):
            raise TypeError("units must contain only EpubMergedTranslationUnit values")
        target_ids = [unit.target.target_id for unit in units]
        if len(set(target_ids)) != len(target_ids):
            raise ValueError("units must have unique EPUB merge target IDs")
        object.__setattr__(self, "units", units)


def merge_translation_artifact(
    projection: EpubStructuredTextProjection,
    translation: TranslationArtifact,
) -> EpubMergedTranslationArtifact:
    """Pair validated translations with the exact targets from this projection."""

    if not isinstance(projection, EpubStructuredTextProjection):
        raise TypeError("projection must be an EpubStructuredTextProjection")
    if not isinstance(translation, TranslationArtifact):
        raise TypeError("translation must be a TranslationArtifact")
    validation = validate_translation_artifact(
        TranslationRequest(projection.structured_text, translation.target_language),
        translation,
    )
    if not isinstance(validation, TranslationArtifact):
        raise ValueError("translation must match the EPUB structured-text projection")

    target_by_id = {target.target_id: target for target in projection.merge_targets}
    expected_unit_ids = tuple(unit.unit_id for unit in projection.structured_text.units)
    if len(target_by_id) != len(projection.merge_targets) or set(target_by_id) != set(
        expected_unit_ids
    ):
        raise ValueError("EPUB merge targets must match the projected unit IDs exactly")
    translated_by_id = {unit.unit_id: unit for unit in validation.units}
    return EpubMergedTranslationArtifact(
        target_language=validation.target_language,
        units=tuple(
            EpubMergedTranslationUnit(
                target=target_by_id[unit_id],
                translated_text=translated_by_id[unit_id].translated_text,
            )
            for unit_id in expected_unit_ids
        ),
    )
