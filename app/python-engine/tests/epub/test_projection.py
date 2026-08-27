from pathlib import Path
import unittest

from mint_lingo_engine.epub.document import EpubDocumentArtifact, EpubPackageMetadata, EpubXhtmlDocument
from mint_lingo_engine.epub.projection import EpubStructuredTextProjector
from mint_lingo_engine.epub.source import EpubSourceReference


class EpubStructuredTextProjectorTest(unittest.TestCase):
    def test_projects_spine_ordered_xhtml_with_deterministic_merge_targets(self) -> None:
        document = EpubDocumentArtifact(
            source=EpubSourceReference(Path("C:/books/source.epub")),
            package_metadata=EpubPackageMetadata("OEBPS/content.opf"),
            manifest=(), spine=(), navigation=None, preserved_resources=(),
            xhtml_documents=(
                EpubXhtmlDocument("two", "OEBPS/two.xhtml", "<html><body><p>Second</p></body></html>"),
                EpubXhtmlDocument("one", "OEBPS/one.xhtml", "<html><body><p>First</p></body></html>"),
            ), merge_targets=(),
        )

        projection = EpubStructuredTextProjector().project(document, "en")

        self.assertEqual(
            [(unit.unit_id, unit.text) for unit in projection.structured_text.units],
            [("two.text.1", "Second"), ("one.text.1", "First")],
        )
        self.assertEqual(
            [(target.target_id, target.manifest_item_id) for target in projection.merge_targets],
            [("two.text.1", "two"), ("one.text.1", "one")],
        )

    def test_fragments_long_prose_with_stable_ids_and_source_whitespace(self) -> None:
        source = _long_prose()
        projection = EpubStructuredTextProjector().project(
            _document(f"<html><body><p>{source}</p></body></html>"),
            "en",
        )

        self.assertEqual(
            [(unit.unit_id, unit.text) for unit in projection.structured_text.units],
            [
                ("chapter.text.1.fragment.1", _FIRST_SENTENCE),
                ("chapter.text.1.fragment.2", _SECOND_SENTENCE),
                ("chapter.text.1.fragment.3", _THIRD_SENTENCE),
            ],
        )
        self.assertEqual(
            [
                (target.target_id, target.fragment_index, target.fragment_count, target.separator_after)
                for target in projection.merge_targets
            ],
            [
                ("chapter.text.1.fragment.1", 1, 3, "  "),
                ("chapter.text.1.fragment.2", 2, 3, "\n"),
                ("chapter.text.1.fragment.3", 3, 3, ""),
            ],
        )

    def test_keeps_headings_abbreviation_prose_and_inline_text_as_whole_units(self) -> None:
        long_prose = _long_prose().replace("First", "Dr. Rowan's first", 1)
        document = _document(
            "<html><body>"
            f"<h2>{_long_prose()}</h2>"
            f"<p>{long_prose}</p>"
            f"<p>Before <em>{_long_prose()}</em></p>"
            "</body></html>"
        )

        projection = EpubStructuredTextProjector().project(document, "en")

        self.assertEqual(
            [unit.unit_id for unit in projection.structured_text.units],
            ["chapter.text.1", "chapter.text.2", "chapter.text.3", "chapter.text.4"],
        )


_FIRST_SENTENCE = (
    "First sentence carries enough ordinary prose to exercise a deterministic EPUB "
    "translation boundary without inline markup or unusual punctuation."
)
_SECOND_SENTENCE = (
    "Second sentence preserves original spacing after the previous sentence while "
    "remaining ordinary prose for this offline fixture."
)
_THIRD_SENTENCE = (
    "Third sentence completes the long paragraph with more ordinary prose so the "
    "conservative policy can safely create a final fragment."
)


def _long_prose() -> str:
    return f"  {_FIRST_SENTENCE}  {_SECOND_SENTENCE}\n{_THIRD_SENTENCE}  "


def _document(serialized_xhtml: str) -> EpubDocumentArtifact:
    return EpubDocumentArtifact(
        source=EpubSourceReference(Path("C:/books/source.epub")),
        package_metadata=EpubPackageMetadata("OEBPS/content.opf"),
        manifest=(), spine=(), navigation=None, preserved_resources=(),
        xhtml_documents=(
            EpubXhtmlDocument("chapter", "OEBPS/chapter.xhtml", serialized_xhtml),
        ),
        merge_targets=(),
    )
