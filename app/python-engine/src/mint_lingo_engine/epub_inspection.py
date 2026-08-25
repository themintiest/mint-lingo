"""Authoritative inspection of the EPUB container and package document."""

from __future__ import annotations

from pathlib import Path, PurePosixPath
import xml.etree.ElementTree as ElementTree
import zipfile

from mint_lingo_engine.epub_document import (
    EpubDocumentArtifact,
    EpubManifestItem,
    EpubNavigationReference,
    EpubPackageMetadata,
    EpubPackageValidationError,
    EpubPackageValidationErrorCode,
    EpubPreservedResource,
    EpubSpineItem,
    EpubXhtmlDocument,
)
from mint_lingo_engine.epub_source import EpubSourceReference


_CONTAINER_PATH = "META-INF/container.xml"
_EPUB_MIMETYPE = b"application/epub+zip"
_OPF_NAMESPACE = "{http://www.idpf.org/2007/opf}"
_DC_NAMESPACE = "{http://purl.org/dc/elements/1.1/}"


class EpubPackageInspector:
    """Validate only the container/package structures required before parsing."""

    def inspect(
        self, source: EpubSourceReference
    ) -> EpubDocumentArtifact | EpubPackageValidationError:
        if not isinstance(source, EpubSourceReference):
            raise TypeError("source must be an EpubSourceReference")
        path = source.path
        if not path.exists():
            return _error(EpubPackageValidationErrorCode.SOURCE_NOT_FOUND, "EPUB source was not found.")
        try:
            with zipfile.ZipFile(path) as archive:
                names = archive.namelist()
                if (
                    not names
                    or names[0] != "mimetype"
                    or archive.getinfo("mimetype").compress_type != zipfile.ZIP_STORED
                    or archive.read("mimetype") != _EPUB_MIMETYPE
                ):
                    return _error(EpubPackageValidationErrorCode.MIMETYPE_INVALID, "EPUB mimetype is missing or invalid.")
                try:
                    container = ElementTree.fromstring(archive.read(_CONTAINER_PATH))
                    rootfile = next(element for element in container.iter() if element.tag.endswith("rootfile"))
                    package_path = rootfile.attrib["full-path"]
                except (KeyError, StopIteration, ElementTree.ParseError):
                    return _error(EpubPackageValidationErrorCode.PACKAGE_DOCUMENT_MISSING, "EPUB container has no usable package document.")
                if package_path not in names:
                    return _error(EpubPackageValidationErrorCode.PACKAGE_DOCUMENT_MISSING, "EPUB package document is missing.")
                try:
                    package = ElementTree.fromstring(archive.read(package_path))
                    manifest = tuple(
                        EpubManifestItem(item.attrib["id"], item.attrib["href"], item.attrib["media-type"])
                        for item in package.findall(f"{_OPF_NAMESPACE}manifest/{_OPF_NAMESPACE}item")
                    )
                    spine = tuple(
                        EpubSpineItem(item.attrib["idref"])
                        for item in package.findall(f"{_OPF_NAMESPACE}spine/{_OPF_NAMESPACE}itemref")
                    )
                except (KeyError, ElementTree.ParseError, ValueError, TypeError):
                    return _error(EpubPackageValidationErrorCode.PACKAGE_DOCUMENT_INVALID, "EPUB package document is invalid.")
                if not manifest:
                    return _error(EpubPackageValidationErrorCode.MANIFEST_INVALID, "EPUB manifest is missing.")
                manifest_ids = {item.item_id for item in manifest}
                if not spine or any(item.manifest_item_id not in manifest_ids for item in spine):
                    return _error(EpubPackageValidationErrorCode.SPINE_INVALID, "EPUB spine is missing or invalid.")
                nav = next((item for item in manifest if item.media_type == "application/xhtml+xml" and "nav" in package.find(f"{_OPF_NAMESPACE}manifest/{_OPF_NAMESPACE}item[@id='{item.item_id}']").attrib.get("properties", "").split()), None)
                if nav is None:
                    return _error(EpubPackageValidationErrorCode.NAVIGATION_MISSING, "EPUB navigation document is missing.")
                metadata = package.find(f"{_OPF_NAMESPACE}metadata")
                manifest_by_id = {item.item_id: item for item in manifest}
                spine_ids = {item.manifest_item_id for item in spine}
                package_root = PurePosixPath(package_path).parent
                try:
                    xhtml_documents = tuple(
                        EpubXhtmlDocument(
                            manifest_item_id=spine_item.manifest_item_id,
                            archive_path=str(package_root / manifest_by_id[spine_item.manifest_item_id].href),
                            serialized_xhtml=archive.read(
                                str(package_root / manifest_by_id[spine_item.manifest_item_id].href)
                            ).decode("utf-8"),
                        )
                        for spine_item in spine
                        if manifest_by_id[spine_item.manifest_item_id].media_type == "application/xhtml+xml"
                    )
                except (KeyError, UnicodeDecodeError, OSError):
                    return _error(EpubPackageValidationErrorCode.PACKAGE_DOCUMENT_INVALID, "EPUB spine content is invalid.")
                preserved_resources = tuple(
                    EpubPreservedResource(item.item_id, str(package_root / item.href))
                    for item in manifest
                    if item.item_id not in spine_ids
                )
                return EpubDocumentArtifact(
                    source=source,
                    package_metadata=EpubPackageMetadata(
                        package_path=package_path,
                        identifier=_metadata_value(metadata, "identifier"),
                        title=_metadata_value(metadata, "title"),
                        language=_metadata_value(metadata, "language"),
                    ), manifest=manifest, spine=spine,
                    navigation=EpubNavigationReference(str(PurePosixPath(package_path).parent / nav.href)),
                    preserved_resources=preserved_resources, xhtml_documents=xhtml_documents, merge_targets=(),
                )
        except (OSError, zipfile.BadZipFile):
            return _error(EpubPackageValidationErrorCode.INVALID_CONTAINER, "EPUB container cannot be opened.")


def _metadata_value(metadata: ElementTree.Element | None, name: str) -> str | None:
    if metadata is None:
        return None
    element = metadata.find(f"{_DC_NAMESPACE}{name}")
    return element.text.strip() if element is not None and element.text and element.text.strip() else None


def _error(code: EpubPackageValidationErrorCode, message: str) -> EpubPackageValidationError:
    return EpubPackageValidationError(code=code, message=message)
