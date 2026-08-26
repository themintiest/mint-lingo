from io import BytesIO
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
import xml.etree.ElementTree as ElementTree
import zipfile

from mint_lingo_engine.epub.builder import EpubPackageBuilder, EpubRebuiltPackageArtifact
from mint_lingo_engine.epub.document import EpubDocumentArtifact
from mint_lingo_engine.epub.export import (
    EpubPackageExporter,
    EpubPackageExportValidationError,
)
from mint_lingo_engine.epub.inspection import EpubPackageInspector
from mint_lingo_engine.epub.projection import EpubStructuredTextProjector
from mint_lingo_engine.epub.restoration import EpubDocumentRestorer, EpubRestoredDocumentArtifact
from mint_lingo_engine.epub.source import EpubSourceReference
from mint_lingo_engine.epub.translation_merge import merge_translation_artifact
from mint_lingo_engine.processing.runner import CancellationToken, JobCancelled
from mint_lingo_engine.translation.models import TranslatedTextUnit, TranslationArtifact


class EpubPackageBuilderTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(self.enterContext(TemporaryDirectory()))

    def test_rebuilds_a_complete_epub_while_preserving_unmodified_resources(self) -> None:
        restored = self._restored_document()

        rebuilt = EpubPackageBuilder().build(restored)

        self.assertIsInstance(rebuilt, EpubRebuiltPackageArtifact)
        with zipfile.ZipFile(BytesIO(rebuilt.package_bytes)) as archive:
            self.assertEqual(archive.infolist()[0].filename, "mimetype")
            self.assertEqual(archive.infolist()[0].compress_type, zipfile.ZIP_STORED)
            self.assertEqual(archive.read("mimetype"), b"application/epub+zip")
            self.assertEqual(
                archive.read("META-INF/container.xml"),
                b'<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
            )
            self.assertEqual(
                archive.namelist(),
                [
                    "mimetype",
                    "META-INF/container.xml",
                    "OEBPS/content.opf",
                    "OEBPS/nav.xhtml",
                    "OEBPS/chapter.xhtml",
                    "OEBPS/book.css",
                    "OEBPS/images/cover.jpg",
                    "OEBPS/fonts/book.otf",
                ],
            )
            package = ElementTree.fromstring(archive.read("OEBPS/content.opf"))
            language = package.find("{http://www.idpf.org/2007/opf}metadata/{http://purl.org/dc/elements/1.1/}language")
            assert language is not None
            self.assertEqual(language.text, "vi")
            self.assertEqual(
                [item.attrib["id"] for item in package.findall("{http://www.idpf.org/2007/opf}manifest/{http://www.idpf.org/2007/opf}item")],
                ["nav", "chapter", "css", "cover", "font"],
            )
            self.assertEqual(
                [item.attrib["idref"] for item in package.findall("{http://www.idpf.org/2007/opf}spine/{http://www.idpf.org/2007/opf}itemref")],
                ["chapter"],
            )
            chapter = ElementTree.fromstring(archive.read("OEBPS/chapter.xhtml"))
            self.assertEqual(chapter.attrib["lang"], "vi")
            self.assertEqual(next(node for node in chapter.iter() if node.tag.endswith("p")).text, "Mot")
            navigation = ElementTree.fromstring(archive.read("OEBPS/nav.xhtml"))
            self.assertEqual(navigation.attrib["lang"], "vi")
            self.assertEqual(archive.read("OEBPS/book.css"), b"p { color: #123456; }")
            self.assertEqual(archive.read("OEBPS/images/cover.jpg"), b"image-bytes")
            self.assertEqual(archive.read("OEBPS/fonts/book.otf"), b"font-bytes")

    def test_rejects_restored_documents_that_omit_an_original_xhtml_member(self) -> None:
        restored = self._restored_document()
        incomplete = EpubRestoredDocumentArtifact(
            document=restored.document,
            package_metadata=restored.package_metadata,
            target_language=restored.target_language,
            xhtml_documents=(),
            navigation_document=restored.navigation_document,
        )

        with self.assertRaisesRegex(ValueError, "must match the original EPUB documents"):
            EpubPackageBuilder().build(incomplete)

    def _restored_document(self) -> EpubRestoredDocumentArtifact:
        source_path = self.root / "source.epub"
        _write_source_epub(source_path)
        inspected = EpubPackageInspector().inspect(EpubSourceReference(source_path))
        self.assertIsInstance(inspected, EpubDocumentArtifact)
        assert isinstance(inspected, EpubDocumentArtifact)
        projection = EpubStructuredTextProjector().project(inspected, "en")
        merged = merge_translation_artifact(
            projection,
            TranslationArtifact("vi", (TranslatedTextUnit("chapter.text.1", "Mot"),)),
        )
        return EpubDocumentRestorer().restore(inspected, merged)


class EpubPackageExporterTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(self.enterContext(TemporaryDirectory()))

    def test_validates_and_atomically_exports_a_rebuilt_package_without_changing_source(self) -> None:
        rebuilt = self._rebuilt_package()
        source = rebuilt.restored_document.document.source.path
        source_bytes = source.read_bytes()
        destination = self.root / "translated.epub"

        exported = EpubPackageExporter().export(rebuilt, destination)

        self.assertEqual(exported, destination)
        self.assertEqual(destination.read_bytes(), rebuilt.package_bytes)
        self.assertEqual(source.read_bytes(), source_bytes)
        inspected = EpubPackageInspector().inspect(EpubSourceReference(destination))
        self.assertIsInstance(inspected, EpubDocumentArtifact)
        self.assertEqual(list(self.root.glob(".translated.epub.*.tmp")), [])

    def test_rejects_invalid_output_without_creating_a_destination(self) -> None:
        rebuilt = self._rebuilt_package()
        invalid = EpubRebuiltPackageArtifact(rebuilt.restored_document, b"not an EPUB")
        destination = self.root / "translated.epub"

        with self.assertRaises(EpubPackageExportValidationError):
            EpubPackageExporter().export(invalid, destination)

        self.assertFalse(destination.exists())
        self.assertEqual(list(self.root.glob(".translated.epub.*.tmp")), [])

    def test_refuses_to_overwrite_the_source_epub(self) -> None:
        rebuilt = self._rebuilt_package()
        source = rebuilt.restored_document.document.source.path
        source_bytes = source.read_bytes()

        with self.assertRaisesRegex(ValueError, "must not overwrite the source"):
            EpubPackageExporter().export(rebuilt, source)

        self.assertEqual(source.read_bytes(), source_bytes)

    def test_failure_or_cancellation_keeps_an_existing_destination_and_cleans_temporary_file(self) -> None:
        rebuilt = self._rebuilt_package()
        destination = self.root / "translated.epub"
        destination.write_bytes(b"previous complete EPUB")

        cancellation = CancellationToken()

        def cancel_after_write(path: Path, contents: bytes) -> None:
            path.write_bytes(contents)
            cancellation._cancel()

        with self.assertRaises(JobCancelled):
            EpubPackageExporter(write_temporary_file=cancel_after_write).export(
                rebuilt,
                destination,
                cancellation=cancellation,
            )

        self.assertEqual(destination.read_bytes(), b"previous complete EPUB")
        self.assertEqual(list(self.root.glob(".translated.epub.*.tmp")), [])

        def interrupted_promotion(_temporary: Path, _destination: Path) -> None:
            raise OSError("simulated promotion failure")

        with self.assertRaisesRegex(OSError, "simulated promotion failure"):
            EpubPackageExporter(
                promote_temporary_file=interrupted_promotion
            ).export(rebuilt, destination)

        self.assertEqual(destination.read_bytes(), b"previous complete EPUB")
        self.assertEqual(list(self.root.glob(".translated.epub.*.tmp")), [])

    def _rebuilt_package(self) -> EpubRebuiltPackageArtifact:
        source_path = self.root / "source.epub"
        _write_source_epub(source_path)
        inspected = EpubPackageInspector().inspect(EpubSourceReference(source_path))
        self.assertIsInstance(inspected, EpubDocumentArtifact)
        assert isinstance(inspected, EpubDocumentArtifact)
        projection = EpubStructuredTextProjector().project(inspected, "en")
        merged = merge_translation_artifact(
            projection,
            TranslationArtifact("vi", (TranslatedTextUnit("chapter.text.1", "Mot"),)),
        )
        return EpubPackageBuilder().build(EpubDocumentRestorer().restore(inspected, merged))


def _write_source_epub(path: Path) -> None:
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        archive.writestr(
            "META-INF/container.xml",
            '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
        )
        archive.writestr(
            "OEBPS/content.opf",
            '<package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata><dc:title>Source book</dc:title><dc:language>en</dc:language></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/><item id="css" href="book.css" media-type="text/css"/><item id="cover" href="images/cover.jpg" media-type="image/jpeg"/><item id="font" href="fonts/book.otf" media-type="application/vnd.ms-opentype"/></manifest><spine><itemref idref="chapter"/></spine></package>',
        )
        archive.writestr(
            "OEBPS/nav.xhtml",
            '<html xmlns="http://www.w3.org/1999/xhtml" lang="en"><body><nav><ol><li><a href="chapter.xhtml#start">Chapter</a></li></ol></nav></body></html>',
        )
        archive.writestr(
            "OEBPS/chapter.xhtml",
            '<html xmlns="http://www.w3.org/1999/xhtml" lang="en"><body><p id="start">First</p></body></html>',
        )
        archive.writestr("OEBPS/book.css", b"p { color: #123456; }")
        archive.writestr("OEBPS/images/cover.jpg", b"image-bytes")
        archive.writestr("OEBPS/fonts/book.otf", b"font-bytes")
