import unittest

from mint_lingo_engine.epub.chapter_context import EpubChapterContextWindowBuilder
from mint_lingo_engine.epub.document import EpubTextMergeTarget
from mint_lingo_engine.epub.projection import EpubStructuredTextProjection
from mint_lingo_engine.epub.translation_batching import EpubTranslationBatchingPolicy
from mint_lingo_engine.translation.models import StructuredTextArtifact, StructuredTextUnit


class EpubChapterContextWindowBuilderTest(unittest.TestCase):
    def test_selects_nearby_context_in_spine_order_without_crossing_chapters(self) -> None:
        projection = _projection()
        requests = EpubChapterContextWindowBuilder(
            EpubTranslationBatchingPolicy(max_units_per_window=2, overlap_units=1)
        ).build(
            projection,
            "vi",
            requested_unit_ids=frozenset(
                unit.unit_id for unit in projection.structured_text.units
            ),
        )

        self.assertEqual(
            [[unit.unit_id for unit in request.artifact.units] for request in requests],
            [
                ["chapter-one.text.1.fragment.1", "chapter-one.text.1.fragment.2"],
                ["chapter-one.text.1.fragment.3"],
                ["chapter-two.text.1", "chapter-two.text.2"],
            ],
        )
        self.assertEqual(
            [
                [] if request.context is None else [unit.unit_id for unit in request.context.units]
                for request in requests
            ],
            [
                ["chapter-one.text.1.fragment.3"],
                ["chapter-one.text.1.fragment.2"],
                [],
            ],
        )
        self.assertEqual(
            [unit.unit_id for request in requests for unit in request.artifact.units],
            [unit.unit_id for unit in projection.structured_text.units],
        )

    def test_safe_no_overlap_policy_sends_no_reference_context(self) -> None:
        projection = _projection()
        requests = EpubChapterContextWindowBuilder(
            EpubTranslationBatchingPolicy(max_units_per_window=1, overlap_units=0)
        ).build(
            projection,
            "vi",
            requested_unit_ids=frozenset(unit.unit_id for unit in projection.structured_text.units),
        )

        self.assertTrue(all(request.context is None for request in requests))

    def test_pending_fragment_keeps_nearby_chapter_references(self) -> None:
        requests = EpubChapterContextWindowBuilder(
            EpubTranslationBatchingPolicy(max_units_per_window=2, overlap_units=1)
        ).build(
            _projection(),
            "vi",
            requested_unit_ids=frozenset({"chapter-one.text.1.fragment.2"}),
        )

        self.assertEqual(
            [unit.unit_id for unit in requests[0].artifact.units],
            ["chapter-one.text.1.fragment.2"],
        )
        assert requests[0].context is not None
        self.assertEqual(
            [unit.unit_id for unit in requests[0].context.units],
            ["chapter-one.text.1.fragment.1", "chapter-one.text.1.fragment.3"],
        )

    def test_completed_middle_fragment_becomes_reference_only_during_resume(self) -> None:
        requests = EpubChapterContextWindowBuilder(
            EpubTranslationBatchingPolicy(max_units_per_window=2, overlap_units=1)
        ).build(
            _projection(),
            "vi",
            requested_unit_ids=frozenset(
                {
                    "chapter-one.text.1.fragment.1",
                    "chapter-one.text.1.fragment.3",
                }
            ),
        )

        self.assertEqual(
            [unit.unit_id for unit in requests[0].artifact.units],
            ["chapter-one.text.1.fragment.1", "chapter-one.text.1.fragment.3"],
        )
        assert requests[0].context is not None
        self.assertEqual(
            [unit.unit_id for unit in requests[0].context.units],
            ["chapter-one.text.1.fragment.2"],
        )


def _projection() -> EpubStructuredTextProjection:
    units = (
        StructuredTextUnit("chapter-one.text.1.fragment.1", "One."),
        StructuredTextUnit("chapter-one.text.1.fragment.2", "Two."),
        StructuredTextUnit("chapter-one.text.1.fragment.3", "Three."),
        StructuredTextUnit("chapter-two.text.1", "Four."),
        StructuredTextUnit("chapter-two.text.2", "Five."),
    )
    return EpubStructuredTextProjection(
        structured_text=StructuredTextArtifact(source_language="en", units=units),
        merge_targets=tuple(
            EpubTextMergeTarget(
                unit.unit_id,
                "chapter-one" if unit.unit_id.startswith("chapter-one") else "chapter-two",
                "/document[1]/p[1]",
                fragment_index=index if index <= 3 else 1,
                fragment_count=3 if index <= 3 else 1,
            )
            for index, unit in enumerate(units, start=1)
        ),
    )
