import unittest

from mint_lingo_engine.epub.translation_batching import EpubTranslationBatchingPolicy
from mint_lingo_engine.providers.translation.base import LlmProviderCapabilities
from mint_lingo_engine.translation.context import build_translation_context_windows
from mint_lingo_engine.translation.models import StructuredTextArtifact, StructuredTextUnit


class EpubTranslationBatchingPolicyTest(unittest.TestCase):
    def test_safely_defaults_when_the_context_limit_is_unknown_or_small(self) -> None:
        for context_limit in (None, 4_096):
            with self.subTest(context_limit=context_limit):
                self.assertEqual(
                    EpubTranslationBatchingPolicy.from_capabilities(
                        _capabilities(context_limit)
                    ),
                    EpubTranslationBatchingPolicy(
                        max_units_per_window=1,
                        overlap_units=0,
                    ),
                )

    def test_caps_larger_contexts_to_conservative_bounded_windows(self) -> None:
        self.assertEqual(
            EpubTranslationBatchingPolicy.from_capabilities(_capabilities(8_192)),
            EpubTranslationBatchingPolicy(max_units_per_window=2, overlap_units=1),
        )
        self.assertEqual(
            EpubTranslationBatchingPolicy.from_capabilities(_capabilities(32_768)),
            EpubTranslationBatchingPolicy(max_units_per_window=4, overlap_units=1),
        )
        self.assertEqual(
            EpubTranslationBatchingPolicy.from_capabilities(
                _capabilities(8_192)
            ).reference_context_unit_limit,
            2,
        )
        self.assertEqual(
            EpubTranslationBatchingPolicy.from_capabilities(
                _capabilities(32_768)
            ).reference_context_unit_limit,
            2,
        )
        self.assertEqual(
            EpubTranslationBatchingPolicy.from_capabilities(
                _capabilities(None)
            ).reference_context_unit_limit,
            0,
        )

    def test_uses_neighboring_context_without_duplicate_result_ownership(self) -> None:
        artifact = StructuredTextArtifact(
            source_language="en",
            units=tuple(
                StructuredTextUnit(f"chapter.text.{index}", f"Text {index}")
                for index in range(1, 6)
            ),
        )
        policy = EpubTranslationBatchingPolicy.from_capabilities(_capabilities(8_192))

        requests = build_translation_context_windows(
            artifact,
            "vi",
            max_units_per_window=policy.max_units_per_window,
            overlap_units=policy.overlap_units,
        )

        self.assertEqual(
            [[unit.unit_id for unit in request.artifact.units] for request in requests],
            [
                ["chapter.text.1", "chapter.text.2"],
                ["chapter.text.3", "chapter.text.4"],
                ["chapter.text.5"],
            ],
        )
        self.assertEqual(
            [
                [] if request.context is None else [unit.unit_id for unit in request.context.units]
                for request in requests
            ],
            [["chapter.text.3"], ["chapter.text.2", "chapter.text.5"], ["chapter.text.4"]],
        )
        requested_ids = [
            unit.unit_id for request in requests for unit in request.artifact.units
        ]
        self.assertEqual(requested_ids, [unit.unit_id for unit in artifact.units])


def _capabilities(context_window_tokens: int | None) -> LlmProviderCapabilities:
    return LlmProviderCapabilities(
        model_ids=("offline-test-model",),
        context_window_tokens=context_window_tokens,
        supports_structured_output=True,
        supports_streaming=False,
    )
