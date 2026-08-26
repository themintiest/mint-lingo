"""EPUB-owned XHTML and navigation restoration before package rebuilding."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import PurePosixPath
from zipfile import BadZipFile, ZipFile
import xml.etree.ElementTree as ElementTree

from mint_lingo_engine.epub.document import (
    EpubDocumentArtifact,
    EpubPackageMetadata,
    EpubTextMergeTarget,
    EpubXhtmlDocument,
)
from mint_lingo_engine.epub.translation_merge import EpubMergedTranslationArtifact

_XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"


@dataclass(frozen=True)
class EpubRestoredDocumentArtifact:
    """Restored EPUB content ready for a later package-rebuild stage.

    This artifact deliberately contains serialized XHTML, not a rebuilt EPUB
    archive. Packaging, validation, and destination ownership remain separate
    EPUB-BUILD-02 and EPUB-BUILD-03 responsibilities.
    """

    document: EpubDocumentArtifact
    package_metadata: EpubPackageMetadata
    target_language: str
    xhtml_documents: tuple[EpubXhtmlDocument, ...]
    navigation_document: EpubXhtmlDocument | None

    def __post_init__(self) -> None:
        if not isinstance(self.document, EpubDocumentArtifact):
            raise TypeError("document must be an EpubDocumentArtifact")
        if not isinstance(self.package_metadata, EpubPackageMetadata):
            raise TypeError("package_metadata must be an EpubPackageMetadata")
        if not isinstance(self.target_language, str):
            raise TypeError("target_language must be a string")
        if not self.target_language or self.target_language.strip() != self.target_language:
            raise ValueError("target_language must not be blank or padded")
        documents = tuple(self.xhtml_documents)
        if any(not isinstance(item, EpubXhtmlDocument) for item in documents):
            raise TypeError("xhtml_documents must contain only EpubXhtmlDocument values")
        if self.navigation_document is not None and not isinstance(
            self.navigation_document, EpubXhtmlDocument
        ):
            raise TypeError("navigation_document must be an EpubXhtmlDocument or None")
        object.__setattr__(self, "xhtml_documents", documents)


class EpubDocumentRestorer:
    """Restore one validated EPUB merge artifact into EPUB-owned documents."""

    def restore(
        self,
        document: EpubDocumentArtifact,
        merged_translation: EpubMergedTranslationArtifact,
    ) -> EpubRestoredDocumentArtifact:
        if not isinstance(document, EpubDocumentArtifact):
            raise TypeError("document must be an EpubDocumentArtifact")
        if not isinstance(merged_translation, EpubMergedTranslationArtifact):
            raise TypeError("merged_translation must be an EpubMergedTranslationArtifact")

        translations = self._validate_targets(document, merged_translation)
        restored_xhtml = tuple(
            self._restore_xhtml(
                xhtml,
                translations,
                merged_translation.target_language,
            )
            for xhtml in document.xhtml_documents
        )
        navigation = self._restore_navigation(document, merged_translation.target_language)
        metadata = EpubPackageMetadata(
            package_path=document.package_metadata.package_path,
            identifier=document.package_metadata.identifier,
            title=document.package_metadata.title,
            language=merged_translation.target_language,
        )
        return EpubRestoredDocumentArtifact(
            document=document,
            package_metadata=metadata,
            target_language=merged_translation.target_language,
            xhtml_documents=restored_xhtml,
            navigation_document=navigation,
        )

    def _validate_targets(
        self,
        document: EpubDocumentArtifact,
        merged_translation: EpubMergedTranslationArtifact,
    ) -> dict[str, str]:
        expected_targets = tuple(_iter_text_targets(document))
        expected_by_id = {target.target_id: target for target in expected_targets}
        actual_by_id = {
            unit.target.target_id: unit for unit in merged_translation.units
        }
        if len(actual_by_id) != len(merged_translation.units) or set(actual_by_id) != set(
            expected_by_id
        ):
            raise ValueError("merged translations must match every EPUB text target exactly")
        for target_id, expected in expected_by_id.items():
            actual = actual_by_id[target_id].target
            if actual != expected:
                raise ValueError("merged translation target does not match the EPUB document")
        return {
            target_id: unit.translated_text
            for target_id, unit in actual_by_id.items()
        }

    def _restore_xhtml(
        self,
        xhtml: EpubXhtmlDocument,
        translations: dict[str, str],
        target_language: str,
    ) -> EpubXhtmlDocument:
        root = _parse_xhtml(xhtml.serialized_xhtml, xhtml.archive_path)
        text_index = 0
        for node in root.iter():
            if node.text and node.text.strip():
                text_index += 1
                target_id = f"{xhtml.manifest_item_id}.text.{text_index}"
                try:
                    node.text = _retain_outer_whitespace(node.text, translations[target_id])
                except KeyError as error:
                    raise ValueError("merged translation is missing an EPUB text target") from error
        _set_content_language(root, target_language)
        return EpubXhtmlDocument(
            manifest_item_id=xhtml.manifest_item_id,
            archive_path=xhtml.archive_path,
            serialized_xhtml=_serialize_xhtml(root),
        )

    def _restore_navigation(
        self,
        document: EpubDocumentArtifact,
        target_language: str,
    ) -> EpubXhtmlDocument | None:
        if document.navigation is None:
            return None
        navigation_path = document.navigation.href
        manifest_item = next(
            (
                item
                for item in document.manifest
                if str(PurePosixPath(document.package_metadata.package_path).parent / item.href)
                == navigation_path
            ),
            None,
        )
        if manifest_item is None:
            raise ValueError("EPUB navigation reference is not present in the manifest")
        try:
            with ZipFile(document.source.path) as archive:
                serialized_xhtml = archive.read(navigation_path).decode("utf-8")
        except (BadZipFile, KeyError, OSError, UnicodeDecodeError) as error:
            raise ValueError("EPUB navigation document cannot be restored") from error
        root = _parse_xhtml(serialized_xhtml, navigation_path)
        _set_content_language(root, target_language)
        return EpubXhtmlDocument(
            manifest_item_id=manifest_item.item_id,
            archive_path=navigation_path,
            serialized_xhtml=_serialize_xhtml(root),
        )


def _iter_text_targets(document: EpubDocumentArtifact):
    for document_index, xhtml in enumerate(document.xhtml_documents):
        root = _parse_xhtml(xhtml.serialized_xhtml, xhtml.archive_path)
        text_index = 0
        for node in root.iter():
            if node.text and node.text.strip():
                text_index += 1
                yield EpubTextMergeTarget(
                    target_id=f"{xhtml.manifest_item_id}.text.{text_index}",
                    manifest_item_id=xhtml.manifest_item_id,
                    node_path=f"/document[{document_index + 1}]/{node.tag}[{text_index}]",
                )


def _parse_xhtml(serialized_xhtml: str, archive_path: str) -> ElementTree.Element:
    try:
        return ElementTree.fromstring(serialized_xhtml)
    except ElementTree.ParseError as error:
        raise ValueError(f"EPUB XHTML document is invalid: {archive_path}") from error


def _set_content_language(root: ElementTree.Element, target_language: str) -> None:
    if _local_name(root.tag) != "html":
        raise ValueError("EPUB XHTML root must be an html element")
    root.set("lang", target_language)
    if _XML_LANG in root.attrib:
        root.set(_XML_LANG, target_language)


def _retain_outer_whitespace(original: str, translated: str) -> str:
    leading = original[: len(original) - len(original.lstrip())]
    trailing = original[len(original.rstrip()) :]
    return f"{leading}{translated}{trailing}"


def _serialize_xhtml(root: ElementTree.Element) -> str:
    if root.tag.startswith("{"):
        namespace = root.tag[1:].partition("}")[0]
        ElementTree.register_namespace("", namespace)
    return ElementTree.tostring(root, encoding="unicode", method="xml")


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]
