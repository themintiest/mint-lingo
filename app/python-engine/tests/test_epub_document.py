from dataclasses import FrozenInstanceError
from pathlib import Path
import unittest

from mint_lingo_engine.epub.document import (
    EpubDocumentArtifact,
    EpubManifestItem,
    EpubNavigationReference,
    EpubPackageMetadata,
    EpubPackageValidationError,
    EpubPackageValidationErrorCode,
    EpubPreservedResource,
    EpubSpineItem,
    EpubTextMergeTarget,
    EpubXhtmlDocument,
)
from mint_lingo_engine.epub.source import EpubSourceReference


class EpubDocumentArtifactTest(unittest.TestCase):
    def test_keeps_epub_package_structure_and_merge_identity_together(self) -> None:
        artifact = EpubDocumentArtifact(
            source=EpubSourceReference(path=Path("C:/books/source.epub")),
            package_metadata=EpubPackageMetadata(
                package_path="OEBPS/content.opf",
                identifier="book-id",
                title="Source book",
                language="en",
            ),
            manifest=[
                EpubManifestItem("chapter-1", "text/chapter-1.xhtml", "application/xhtml+xml")
            ],
            spine=[EpubSpineItem("chapter-1")],
            navigation=EpubNavigationReference("nav.xhtml"),
            preserved_resources=[EpubPreservedResource("cover", "images/cover.jpg")],
            xhtml_documents=[
                EpubXhtmlDocument(
                    "chapter-1", "OEBPS/text/chapter-1.xhtml", "<html><body/></html>"
                )
            ],
            merge_targets=[EpubTextMergeTarget("chapter-1.p.1", "chapter-1", "/body/p[1]")],
        )

        self.assertEqual(artifact.spine[0].manifest_item_id, "chapter-1")
        self.assertEqual(artifact.xhtml_documents[0].serialized_xhtml, "<html><body/></html>")
        self.assertEqual(artifact.merge_targets[0].target_id, "chapter-1.p.1")
        with self.assertRaises(FrozenInstanceError):
            artifact.navigation = None  # type: ignore[misc]

    def test_rejects_untyped_artifact_values_without_package_inspection(self) -> None:
        with self.assertRaisesRegex(TypeError, "source must be an EpubSourceReference"):
            EpubDocumentArtifact(  # type: ignore[arg-type]
                source="C:/books/source.epub",
                package_metadata=EpubPackageMetadata("content.opf"),
                manifest=[], spine=[], navigation=None, preserved_resources=[],
                xhtml_documents=[], merge_targets=[],
            )
        with self.assertRaisesRegex(ValueError, "must not be blank"):
            EpubManifestItem("chapter", " ", "application/xhtml+xml")


class EpubPackageValidationErrorTest(unittest.TestCase):
    def test_exposes_normalized_epub_package_failure_values(self) -> None:
        error = EpubPackageValidationError(
            code=EpubPackageValidationErrorCode.INVALID_CONTAINER,
            message="The selected file is not a supported EPUB container.",
        )

        self.assertEqual(error.code.value, "epub.invalid_container")
        self.assertFalse(error.retryable)
        with self.assertRaisesRegex(TypeError, "EpubPackageValidationErrorCode"):
            EpubPackageValidationError(code="epub.invalid_container", message="Invalid")  # type: ignore[arg-type]
