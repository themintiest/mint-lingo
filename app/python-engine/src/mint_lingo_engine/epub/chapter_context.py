"""EPUB-owned bounded chapter-local translation reference context."""

from __future__ import annotations

from dataclasses import dataclass

from mint_lingo_engine.epub.projection import EpubStructuredTextProjection
from mint_lingo_engine.epub.translation_batching import EpubTranslationBatchingPolicy
from mint_lingo_engine.translation.models import (
    StructuredTextArtifact,
    StructuredTextUnit,
    TranslationContext,
    TranslationRequest,
)


@dataclass(frozen=True)
class EpubChapterContextWindowBuilder:
    """Build bounded requests with reference context from the same XHTML file."""

    batching_policy: EpubTranslationBatchingPolicy

    def __post_init__(self) -> None:
        if not isinstance(self.batching_policy, EpubTranslationBatchingPolicy):
            raise TypeError("batching_policy must be an EpubTranslationBatchingPolicy")

    def build(
        self,
        projection: EpubStructuredTextProjection,
        target_language: str,
        *,
        requested_unit_ids: frozenset[str],
    ) -> tuple[TranslationRequest, ...]:
        """Build deterministic chapter-local request windows for pending units.

        Completed units may remain source-only references during a resumed job;
        reference context never changes requested-unit ownership or checkpoints.
        """

        if not isinstance(projection, EpubStructuredTextProjection):
            raise TypeError("projection must be an EpubStructuredTextProjection")
        if not isinstance(target_language, str) or not target_language.strip():
            raise ValueError("target_language must not be blank")
        if not isinstance(requested_unit_ids, frozenset) or any(
            not isinstance(unit_id, str) for unit_id in requested_unit_ids
        ):
            raise TypeError("requested_unit_ids must be a frozenset of strings")

        units_by_document = _units_by_document(projection)
        available_ids = {
            unit.unit_id
            for units in units_by_document.values()
            for unit in units
        }
        if not requested_unit_ids or not requested_unit_ids <= available_ids:
            raise ValueError("requested_unit_ids must identify projected EPUB units")

        requests: list[TranslationRequest] = []
        for chapter_units in units_by_document.values():
            pending_units = tuple(
                unit for unit in chapter_units if unit.unit_id in requested_unit_ids
            )
            for start in range(
                0,
                len(pending_units),
                self.batching_policy.max_units_per_window,
            ):
                requested = pending_units[
                    start : start + self.batching_policy.max_units_per_window
                ]
                requests.append(
                    TranslationRequest(
                        artifact=StructuredTextArtifact(
                            source_language=projection.structured_text.source_language,
                            units=requested,
                        ),
                        target_language=target_language,
                        context=_reference_context(
                            chapter_units,
                            requested_unit_ids={unit.unit_id for unit in requested},
                            limit=self.batching_policy.reference_context_unit_limit,
                        ),
                    )
                )
        return tuple(requests)


def _units_by_document(
    projection: EpubStructuredTextProjection,
) -> dict[str, tuple[StructuredTextUnit, ...]]:
    merge_targets = tuple(projection.merge_targets)
    target_by_id = {target.target_id: target for target in merge_targets}
    if len(target_by_id) != len(merge_targets) or set(target_by_id) != {
        unit.unit_id for unit in projection.structured_text.units
    }:
        raise ValueError("EPUB projection targets must match structured units exactly")
    units_by_document: dict[str, list[StructuredTextUnit]] = {}
    for unit in projection.structured_text.units:
        units_by_document.setdefault(
            target_by_id[unit.unit_id].manifest_item_id,
            [],
        ).append(unit)
    return {
        manifest_item_id: tuple(units)
        for manifest_item_id, units in units_by_document.items()
    }


def _reference_context(
    chapter_units: tuple[StructuredTextUnit, ...],
    *,
    requested_unit_ids: set[str],
    limit: int,
) -> TranslationContext | None:
    if limit == 0:
        return None
    requested_positions = [
        index
        for index, unit in enumerate(chapter_units)
        if unit.unit_id in requested_unit_ids
    ]
    first_requested = min(requested_positions)
    last_requested = max(requested_positions)
    middle = [
        (index, unit)
        for index, unit in enumerate(chapter_units)
        if first_requested < index < last_requested
        and unit.unit_id not in requested_unit_ids
    ]
    preceding = next(
        (
            (index, unit)
            for index, unit in reversed(tuple(enumerate(chapter_units[:first_requested])))
            if unit.unit_id not in requested_unit_ids
        ),
        None,
    )
    following = next(
        (
            (index, unit)
            for index, unit in enumerate(chapter_units[last_requested + 1 :], start=last_requested + 1)
            if unit.unit_id not in requested_unit_ids
        ),
        None,
    )
    selected = middle[:limit]
    if preceding is not None and len(selected) < limit:
        selected.append(preceding)
    if following is not None and len(selected) < limit:
        selected.append(following)
    selected.sort(key=lambda candidate: candidate[0])
    if not selected:
        return None
    return TranslationContext(units=tuple(candidate[1] for candidate in selected))
