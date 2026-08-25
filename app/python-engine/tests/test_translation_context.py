import unittest

from mint_lingo_engine.translation import StructuredTextArtifact, StructuredTextUnit
from mint_lingo_engine.translation_context import build_translation_context_windows


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
