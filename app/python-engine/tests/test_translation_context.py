import unittest

from mint_lingo_engine.translation.models import StructuredTextArtifact, StructuredTextUnit
from mint_lingo_engine.translation.context import build_translation_context_windows


class TranslationContextWindowTest(unittest.TestCase):
    def test_splits_a_corpus_into_bounded_ordered_requests(self) -> None:
        artifact = StructuredTextArtifact(
            source_language="ja",
            units=[
                StructuredTextUnit(unit_id="chapter.1", text="One"),
                StructuredTextUnit(unit_id="chapter.2", text="Two"),
                StructuredTextUnit(unit_id="chapter.3", text="Three"),
                StructuredTextUnit(unit_id="chapter.4", text="Four"),
                StructuredTextUnit(unit_id="chapter.5", text="Five"),
            ],
        )

        windows = build_translation_context_windows(
            artifact,
            "vi",
            max_units_per_window=2,
        )

        self.assertEqual(len(windows), 3)
        self.assertEqual(
            [[unit.unit_id for unit in window.artifact.units] for window in windows],
            [
                ["chapter.1", "chapter.2"],
                ["chapter.3", "chapter.4"],
                ["chapter.5"],
            ],
        )
        self.assertTrue(
            all(window.artifact.source_language == "ja" for window in windows)
        )
        self.assertTrue(all(window.target_language == "vi" for window in windows))
        self.assertTrue(all(window.context is None for window in windows))
        self.assertEqual(
            [unit.unit_id for unit in artifact.units],
            ["chapter.1", "chapter.2", "chapter.3", "chapter.4", "chapter.5"],
        )

    def test_repeats_only_neighboring_units_as_non_authoritative_context(self) -> None:
        artifact = StructuredTextArtifact(
            source_language="en",
            units=[
                StructuredTextUnit(unit_id="unit.1", text="One"),
                StructuredTextUnit(unit_id="unit.2", text="Two"),
                StructuredTextUnit(unit_id="unit.3", text="Three"),
                StructuredTextUnit(unit_id="unit.4", text="Four"),
                StructuredTextUnit(unit_id="unit.5", text="Five"),
            ],
        )

        windows = build_translation_context_windows(
            artifact,
            "vi",
            max_units_per_window=2,
            overlap_units=1,
        )

        self.assertEqual(
            [[unit.unit_id for unit in window.artifact.units] for window in windows],
            [["unit.1", "unit.2"], ["unit.3", "unit.4"], ["unit.5"]],
        )
        self.assertEqual(
            [
                [unit.unit_id for unit in window.context.units]
                if window.context is not None
                else []
                for window in windows
            ],
            [["unit.3"], ["unit.2", "unit.5"], ["unit.4"]],
        )
        requested_ids = [
            unit.unit_id for window in windows for unit in window.artifact.units
        ]
        self.assertEqual(requested_ids, ["unit.1", "unit.2", "unit.3", "unit.4", "unit.5"])
        self.assertEqual(len(requested_ids), len(set(requested_ids)))

    def test_rejects_invalid_window_inputs(self) -> None:
        artifact = StructuredTextArtifact(
            source_language="en",
            units=[StructuredTextUnit(unit_id="unit.1", text="Source")],
        )

        with self.assertRaisesRegex(TypeError, "StructuredTextArtifact"):
            build_translation_context_windows(
                "source",  # type: ignore[arg-type]
                "vi",
                max_units_per_window=1,
            )
        with self.assertRaisesRegex(TypeError, "must be an integer"):
            build_translation_context_windows(
                artifact,
                "vi",
                max_units_per_window=True,
            )
        with self.assertRaisesRegex(ValueError, "at least 1"):
            build_translation_context_windows(
                artifact,
                "vi",
                max_units_per_window=0,
            )
        with self.assertRaisesRegex(ValueError, "overlap_units must not be negative"):
            build_translation_context_windows(
                artifact,
                "vi",
                max_units_per_window=1,
                overlap_units=-1,
            )
