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
from mint_lingo_engine.epub.sentence_boundaries import fragment_epub_prose_text
from mint_lingo_engine.epub.translation_merge import (
    EpubMergedTranslationArtifact,
    EpubMergedTranslationUnit,
)

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
        expected_fragments_by_node = _expected_fragment_targets(document)
        expected_by_id = {
            node_target_id: fragments[0]
            for node_target_id, fragments in expected_fragments_by_node.items()
        }
        actual_by_id = {
            unit.target.target_id: unit for unit in merged_translation.units
        }
        if len(actual_by_id) != len(merged_translation.units):
            raise ValueError("merged translations must have unique EPUB target IDs")
        fragments_by_node: dict[str, list[EpubMergedTranslationUnit]] = {}
        for unit in merged_translation.units:
            target = unit.target
            node_target_id = _node_target_id(target.target_id)
            expected = expected_by_id.get(node_target_id)
            if expected is None or (
                target.manifest_item_id != expected.manifest_item_id
                or target.node_path != expected.node_path
            ):
                raise ValueError("merged translation target does not match the EPUB document")
            fragments_by_node.setdefault(node_target_id, []).append(unit)
        if set(fragments_by_node) != set(expected_by_id):
            raise ValueError("merged translations must match every EPUB text target exactly")
        translations: dict[str, str] = {}
        for node_target_id, fragments in fragments_by_node.items():
            ordered_fragments = sorted(
                fragments,
                key=lambda unit: unit.target.fragment_index,
            )
            expected_fragments = expected_fragments_by_node[node_target_id]
            if tuple(unit.target for unit in ordered_fragments) != expected_fragments:
                raise ValueError("merged translation fragments do not match the EPUB node")
            translations[node_target_id] = "".join(
                unit.translated_text + unit.target.separator_after
                for unit in ordered_fragments
            )
        return translations

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


def _expected_fragment_targets(
    document: EpubDocumentArtifact,
) -> dict[str, tuple[EpubTextMergeTarget, ...]]:
    targets: dict[str, tuple[EpubTextMergeTarget, ...]] = {}
    for document_index, xhtml in enumerate(document.xhtml_documents):
        root = _parse_xhtml(xhtml.serialized_xhtml, xhtml.archive_path)
        text_index = 0
        for node in root.iter():
            if node.text and node.text.strip():
                text_index += 1
                node_target_id = f"{xhtml.manifest_item_id}.text.{text_index}"
                node_path = f"/document[{document_index + 1}]/{node.tag}[{text_index}]"
                fragments = fragment_epub_prose_text(node.tag, node.text)
                targets[node_target_id] = tuple(
                    EpubTextMergeTarget(
                        target_id=(
                            node_target_id
                            if len(fragments) == 1
                            else f"{node_target_id}.fragment.{fragment_index}"
                        ),
                        manifest_item_id=xhtml.manifest_item_id,
                        node_path=node_path,
                        fragment_index=fragment_index,
                        fragment_count=len(fragments),
                        separator_after=fragment.separator_after,
                    )
                    for fragment_index, fragment in enumerate(fragments, start=1)
                )
    return targets


def _node_target_id(target_id: str) -> str:
    fragment_marker = ".fragment."
    if fragment_marker not in target_id:
        return target_id
    node_target_id, _, fragment_index = target_id.rpartition(fragment_marker)
    if not node_target_id or not fragment_index.isdecimal():
        return ""
    return node_target_id


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
