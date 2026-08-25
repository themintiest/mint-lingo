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
