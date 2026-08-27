from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
import xml.etree.ElementTree as ElementTree
import zipfile

from mint_lingo_engine.epub.document import (
    EpubDocumentArtifact,
    EpubManifestItem,
    EpubNavigationReference,
    EpubPackageMetadata,
    EpubSpineItem,
    EpubXhtmlDocument,
)
from mint_lingo_engine.epub.projection import EpubStructuredTextProjector
from mint_lingo_engine.epub.restoration import EpubDocumentRestorer
from mint_lingo_engine.epub.source import EpubSourceReference
from mint_lingo_engine.epub.translation_merge import merge_translation_artifact
from mint_lingo_engine.translation.models import TranslatedTextUnit, TranslationArtifact


class EpubDocumentRestorerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(self.enterContext(TemporaryDirectory()))

    def test_restores_only_projected_text_and_preserves_epub_structures(self) -> None:
        document = self._document()
        projection = EpubStructuredTextProjector().project(document, "en")
        merged = merge_translation_artifact(
            projection,
            TranslationArtifact(
                "vi",
                (
                    TranslatedTextUnit("chapter.text.1", "Mot "),
                    TranslatedTextUnit("chapter.text.2", "rất"),
                    TranslatedTextUnit("chapter.text.3", "Hai"),
                ),
            ),
        )

        restored = EpubDocumentRestorer().restore(document, merged)

        self.assertEqual(restored.package_metadata.language, "vi")
        self.assertEqual(restored.target_language, "vi")
        chapter = ElementTree.fromstring(restored.xhtml_documents[0].serialized_xhtml)
        self.assertEqual(chapter.attrib["lang"], "vi")
        paragraph = next(node for node in chapter.iter() if node.tag.endswith("p"))
        self.assertEqual(paragraph.attrib["class"], "lead")
        self.assertEqual(paragraph.text, "Mot  ")
        emphasis = next(node for node in chapter.iter() if node.tag.endswith("em"))
        self.assertEqual(emphasis.attrib["class"], "accent")
        self.assertEqual(emphasis.text, "rất")
        link = next(node for node in chapter.iter() if node.tag.endswith("a"))
        self.assertEqual(link.attrib["href"], "notes.xhtml#first")
        self.assertEqual(link.text, "Hai")
        self.assertIn("<img src=\"../images/cover.jpg\"", restored.xhtml_documents[0].serialized_xhtml)

        assert restored.navigation_document is not None
        navigation = ElementTree.fromstring(restored.navigation_document.serialized_xhtml)
        self.assertEqual(navigation.attrib["lang"], "vi")
        self.assertEqual(
            navigation.attrib["{http://www.w3.org/XML/1998/namespace}lang"],
            "vi",
        )
        nav_link = next(node for node in navigation.iter() if node.tag.endswith("a"))
        self.assertEqual(nav_link.attrib["href"], "chapter.xhtml#start")
        self.assertEqual(nav_link.text, "Chapter one")

    def test_rejects_a_merge_that_does_not_match_the_original_text_targets(self) -> None:
        document = self._document()
        projection = EpubStructuredTextProjector().project(document, "en")
        merged = merge_translation_artifact(
            projection,
            TranslationArtifact(
                "vi",
                (
                    TranslatedTextUnit("chapter.text.1", "Mot"),
                    TranslatedTextUnit("chapter.text.2", "rất"),
                    TranslatedTextUnit("chapter.text.3", "Hai"),
                ),
            ),
        )
        incomplete = type(merged)(target_language=merged.target_language, units=merged.units[:-1])

        with self.assertRaisesRegex(ValueError, "match every EPUB text target"):
            EpubDocumentRestorer().restore(document, incomplete)

    def test_reassembles_translated_sentence_fragments_in_the_original_text_node(self) -> None:
        document = self._document(
            chapter_xhtml=f"<html><body><p>{_fragment_source()}</p></body></html>"
        )
        projection = EpubStructuredTextProjector().project(document, "en")
        merged = merge_translation_artifact(
            projection,
            TranslationArtifact(
                "vi",
                (
                    TranslatedTextUnit("chapter.text.1.fragment.1", "Mot."),
                    TranslatedTextUnit("chapter.text.1.fragment.2", "Hai."),
                    TranslatedTextUnit("chapter.text.1.fragment.3", "Ba."),
                ),
            ),
        )

        restored = EpubDocumentRestorer().restore(document, merged)

        chapter = ElementTree.fromstring(restored.xhtml_documents[0].serialized_xhtml)
        paragraph = next(node for node in chapter.iter() if node.tag.endswith("p"))
        self.assertEqual(paragraph.text, "  Mot.  Hai.\nBa.  ")

    def _document(
        self,
        *,
        chapter_xhtml: str | None = None,
    ) -> EpubDocumentArtifact:
        source_path = self.root / "book.epub"
        with zipfile.ZipFile(source_path, "w") as archive:
            archive.writestr(
                "OEBPS/nav.xhtml",
                '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en"><body><nav><ol><li><a href="chapter.xhtml#start">Chapter one</a></li></ol></nav></body></html>',
            )
        return EpubDocumentArtifact(
            source=EpubSourceReference(source_path),
            package_metadata=EpubPackageMetadata("OEBPS/content.opf", language="en"),
            manifest=(
                EpubManifestItem("nav", "nav.xhtml", "application/xhtml+xml"),
                EpubManifestItem("chapter", "chapter.xhtml", "application/xhtml+xml"),
            ),
            spine=(EpubSpineItem("chapter"),),
            navigation=EpubNavigationReference("OEBPS/nav.xhtml"),
            preserved_resources=(),
            xhtml_documents=(
                EpubXhtmlDocument(
                    "chapter",
                    "OEBPS/chapter.xhtml",
                    chapter_xhtml
                    or '<html xmlns="http://www.w3.org/1999/xhtml" lang="en"><body><p class="lead" id="start">First <em class="accent">very</em></p><p><a href="notes.xhtml#first">Second</a><img src="../images/cover.jpg" alt="Cover" /></p></body></html>',
                ),
            ),
            merge_targets=(),
        )


def _fragment_source() -> str:
    first = (
        "First sentence carries enough ordinary prose to exercise a deterministic EPUB "
        "translation boundary without inline markup or unusual punctuation."
    )
    second = (
        "Second sentence preserves original spacing after the previous sentence while "
        "remaining ordinary prose for this offline fixture."
    )
    third = (
        "Third sentence completes the long paragraph with more ordinary prose so the "
        "conservative policy can safely create a final fragment."
    )
    return f"  {first}  {second}\n{third}  "
