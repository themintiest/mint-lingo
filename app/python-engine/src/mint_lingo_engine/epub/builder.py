"""EPUB-owned package rebuilding from restored XHTML and metadata."""

from __future__ import annotations

from dataclasses import dataclass
from io import BytesIO
from pathlib import PurePosixPath
import xml.etree.ElementTree as ElementTree
from zipfile import BadZipFile, ZIP_DEFLATED, ZIP_STORED, ZipFile, ZipInfo

from mint_lingo_engine.epub.document import EpubXhtmlDocument
from mint_lingo_engine.epub.restoration import EpubRestoredDocumentArtifact

_CONTAINER_PATH = "META-INF/container.xml"
_EPUB_MIMETYPE = b"application/epub+zip"
_OPF_NAMESPACE = "{http://www.idpf.org/2007/opf}"
_DC_NAMESPACE = "{http://purl.org/dc/elements/1.1/}"


@dataclass(frozen=True)
class EpubRebuiltPackageArtifact:
    """A rebuilt EPUB package held in memory before validation and export."""

    restored_document: EpubRestoredDocumentArtifact
    package_bytes: bytes

    def __post_init__(self) -> None:
        if not isinstance(self.restored_document, EpubRestoredDocumentArtifact):
            raise TypeError("restored_document must be an EpubRestoredDocumentArtifact")
        if not isinstance(self.package_bytes, bytes):
            raise TypeError("package_bytes must be bytes")
        if not self.package_bytes:
            raise ValueError("package_bytes must not be empty")


class EpubPackageBuilder:
    """Rebuild a standards-conformant package without choosing an output path."""

    def build(
        self,
        restored_document: EpubRestoredDocumentArtifact,
    ) -> EpubRebuiltPackageArtifact:
        if not isinstance(restored_document, EpubRestoredDocumentArtifact):
            raise TypeError("restored_document must be an EpubRestoredDocumentArtifact")

        replacements = _replacement_members(restored_document)
        source_path = restored_document.document.source.path
        try:
            with ZipFile(source_path) as source_archive:
                source_infos = source_archive.infolist()
                _validate_source_members(source_infos, restored_document, replacements)
                package_document = _updated_package_document(
                    source_archive.read(restored_document.package_metadata.package_path),
                    restored_document.target_language,
                )
                package_bytes = _rebuild_archive(
                    source_archive,
                    source_infos,
                    restored_document.package_metadata.package_path,
                    package_document,
                    replacements,
                )
        except (BadZipFile, KeyError, OSError, UnicodeDecodeError) as error:
            raise ValueError("EPUB source package cannot be rebuilt") from error

        return EpubRebuiltPackageArtifact(restored_document, package_bytes)


def _replacement_members(
    restored_document: EpubRestoredDocumentArtifact,
) -> dict[str, bytes]:
    original_documents = restored_document.document.xhtml_documents
    restored_documents = restored_document.xhtml_documents
    original_by_path = {document.archive_path: document for document in original_documents}
    restored_by_path = {document.archive_path: document for document in restored_documents}
    if len(original_by_path) != len(original_documents) or len(restored_by_path) != len(
        restored_documents
    ):
        raise ValueError("EPUB XHTML document paths must be unique")
    if set(original_by_path) != set(restored_by_path):
        raise ValueError("restored XHTML documents must match the original EPUB documents")
    for archive_path, original in original_by_path.items():
        restored = restored_by_path[archive_path]
        if restored.manifest_item_id != original.manifest_item_id:
            raise ValueError("restored XHTML document does not match its manifest item")

    replacements = {
        archive_path: document.serialized_xhtml.encode("utf-8")
        for archive_path, document in restored_by_path.items()
    }
    navigation = restored_document.document.navigation
    restored_navigation = restored_document.navigation_document
    if navigation is None:
        if restored_navigation is not None:
            raise ValueError("restored navigation requires an original navigation reference")
    else:
        if restored_navigation is None:
            raise ValueError("restored EPUB navigation document is missing")
        if restored_navigation.archive_path != navigation.href:
            raise ValueError("restored navigation document does not match the EPUB reference")
        replacements[navigation.href] = restored_navigation.serialized_xhtml.encode("utf-8")
    return replacements


def _validate_source_members(
    source_infos: list[ZipInfo],
    restored_document: EpubRestoredDocumentArtifact,
    replacements: dict[str, bytes],
) -> None:
    names = [info.filename for info in source_infos]
    if len(set(names)) != len(names):
        raise ValueError("EPUB source package has duplicate archive members")
    if not names or names[0] != "mimetype":
        raise ValueError("EPUB source package has no leading mimetype member")
    expected_paths = {
        _CONTAINER_PATH,
        restored_document.package_metadata.package_path,
        *replacements,
    }
    if not expected_paths.issubset(names):
        raise ValueError("EPUB source package is missing a required rebuild member")
    for name in names:
        if not _is_safe_archive_path(name):
            raise ValueError("EPUB source package contains an unsafe archive path")


def _rebuild_archive(
    source_archive: ZipFile,
    source_infos: list[ZipInfo],
    package_path: str,
    package_document: bytes,
    replacements: dict[str, bytes],
) -> bytes:
    buffer = BytesIO()
    with ZipFile(buffer, mode="w", compression=ZIP_DEFLATED) as rebuilt_archive:
        mimetype = ZipInfo("mimetype")
        mimetype.compress_type = ZIP_STORED
        rebuilt_archive.writestr(mimetype, _EPUB_MIMETYPE)
        for source_info in source_infos:
            archive_path = source_info.filename
            if archive_path == "mimetype":
                continue
            if archive_path == package_path:
                rebuilt_archive.writestr(source_info, package_document)
            elif archive_path in replacements:
                rebuilt_archive.writestr(source_info, replacements[archive_path])
            else:
                rebuilt_archive.writestr(source_info, source_archive.read(source_info))
    return buffer.getvalue()


def _updated_package_document(serialized_package: bytes, target_language: str) -> bytes:
    try:
        package = ElementTree.fromstring(serialized_package)
    except ElementTree.ParseError as error:
        raise ValueError("EPUB package document is invalid during rebuilding") from error
    metadata = package.find(f"{_OPF_NAMESPACE}metadata")
    if metadata is None:
        metadata = ElementTree.Element(f"{_OPF_NAMESPACE}metadata")
        package.insert(0, metadata)
    languages = metadata.findall(f"{_DC_NAMESPACE}language")
    if languages:
        for language in languages:
            language.text = target_language
    else:
        language = ElementTree.Element(f"{_DC_NAMESPACE}language")
        language.text = target_language
        metadata.append(language)
    ElementTree.register_namespace("", _OPF_NAMESPACE[1:-1])
    ElementTree.register_namespace("dc", _DC_NAMESPACE[1:-1])
    return ElementTree.tostring(package, encoding="utf-8", xml_declaration=True)


def _is_safe_archive_path(archive_path: str) -> bool:
    path = PurePosixPath(archive_path)
    return (
        bool(archive_path)
        and "\\" not in archive_path
        and not path.is_absolute()
        and ".." not in path.parts
    )
