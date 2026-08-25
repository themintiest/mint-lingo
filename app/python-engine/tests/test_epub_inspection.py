from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
import zipfile

from mint_lingo_engine.epub_document import EpubDocumentArtifact, EpubPackageValidationError, EpubPackageValidationErrorCode
from mint_lingo_engine.epub_inspection import EpubPackageInspector
from mint_lingo_engine.epub_source import EpubSourceReference


class EpubPackageInspectorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(self.enterContext(TemporaryDirectory()))
        self.inspector = EpubPackageInspector()

    def test_inspects_required_container_package_manifest_spine_and_navigation(self) -> None:
        path = self.root / "book.epub"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
            archive.writestr("META-INF/container.xml", '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>')
            archive.writestr("OEBPS/content.opf", '<package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata><dc:title>Book</dc:title></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/></spine></package>')
            archive.writestr("OEBPS/one.xhtml", "<html><body><p>Chapter one</p></body></html>")
            archive.writestr("OEBPS/nav.xhtml", "<html><body><nav/></body></html>")
        result = self.inspector.inspect(EpubSourceReference(path))
        self.assertIsInstance(result, EpubDocumentArtifact)
        assert isinstance(result, EpubDocumentArtifact)
        self.assertEqual(result.package_metadata.title, "Book")
        self.assertEqual(result.navigation.href, "OEBPS/nav.xhtml")
        self.assertEqual(result.xhtml_documents[0].manifest_item_id, "one")
        self.assertEqual(result.xhtml_documents[0].serialized_xhtml, "<html><body><p>Chapter one</p></body></html>")
        self.assertEqual(result.preserved_resources[0].manifest_item_id, "nav")

    def test_reports_missing_or_invalid_container_structures(self) -> None:
        missing = self.inspector.inspect(EpubSourceReference(self.root / "missing.epub"))
        self.assertEqual(missing.code, EpubPackageValidationErrorCode.SOURCE_NOT_FOUND)
        path = self.root / "invalid.epub"
        path.write_text("not a zip")
        invalid = self.inspector.inspect(EpubSourceReference(path))
        self.assertIsInstance(invalid, EpubPackageValidationError)
        assert isinstance(invalid, EpubPackageValidationError)
        self.assertEqual(invalid.code, EpubPackageValidationErrorCode.INVALID_CONTAINER)
