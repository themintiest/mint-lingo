from pathlib import Path
import unittest

from mint_lingo_engine.epub.source import EpubSourceAcquisition, EpubSourceReference


class EpubSourceAcquisitionTest(unittest.TestCase):
    def setUp(self) -> None:
        self.acquisition = EpubSourceAcquisition()

    def test_accepts_only_a_path_from_the_concrete_epub_payload(self) -> None:
        reference = self.acquisition.accept(
            {"sourcePath": "C:/documents/unverified.epub"}
        )

        self.assertEqual(
            reference,
            EpubSourceReference(path=Path("C:/documents/unverified.epub")),
        )

    def test_does_not_require_reader_success_or_open_source_bytes(self) -> None:
        reference = self.acquisition.accept(
            {"sourcePath": "C:/documents/missing-or-invalid.epub"}
        )

        self.assertEqual(reference.path, Path("C:/documents/missing-or-invalid.epub"))
        self.assertFalse(reference.path.exists())

    def test_rejects_non_path_or_ambiguous_payload_shapes(self) -> None:
        with self.assertRaisesRegex(ValueError, "only sourcePath"):
            self.acquisition.accept(
                {"sourcePath": "C:/documents/book.epub", "readerReady": True}
            )
        with self.assertRaisesRegex(TypeError, "sourcePath must be a string"):
            self.acquisition.accept({"sourcePath": b"EPUB bytes"})
        with self.assertRaisesRegex(ValueError, "non-empty trimmed"):
            self.acquisition.accept({"sourcePath": " C:/documents/book.epub "})
