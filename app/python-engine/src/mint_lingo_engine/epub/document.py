"""EPUB-owned package error and document-artifact domain values.

Inspection, parsing, projection, rebuilding, and export are deliberately not
implemented here. The values give those later EPUB-only tasks one place to
retain package structure and merge identity without leaking them into shared
translation or job models.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from mint_lingo_engine.epub.source import EpubSourceReference


class EpubPackageValidationErrorCode(str, Enum):
    """Normalized failures that later EPUB package inspection can report."""

    SOURCE_NOT_FOUND = "epub.source_not_found"
    SOURCE_NOT_READABLE = "epub.source_not_readable"
    INVALID_CONTAINER = "epub.invalid_container"
    MIMETYPE_INVALID = "epub.mimetype_invalid"
    PACKAGE_DOCUMENT_MISSING = "epub.package_document_missing"
    PACKAGE_DOCUMENT_INVALID = "epub.package_document_invalid"
    MANIFEST_INVALID = "epub.manifest_invalid"
    SPINE_INVALID = "epub.spine_invalid"
    NAVIGATION_MISSING = "epub.navigation_missing"


@dataclass(frozen=True)
class EpubPackageValidationError:
    """A structured EPUB-package failure safe for workflow handling."""

    code: EpubPackageValidationErrorCode
    message: str
    retryable: bool = False

    def __post_init__(self) -> None:
        if not isinstance(self.code, EpubPackageValidationErrorCode):
            raise TypeError("code must be an EpubPackageValidationErrorCode")
        if not isinstance(self.message, str):
            raise TypeError("message must be a string")
        if not self.message or self.message.strip() != self.message:
            raise ValueError("message must not be blank or padded")
        if not isinstance(self.retryable, bool):
            raise TypeError("retryable must be a bool")


@dataclass(frozen=True)
class EpubPackageMetadata:
    """Package-document metadata retained for EPUB-specific rebuilding."""

    package_path: str
    identifier: str | None = None
    title: str | None = None
    language: str | None = None

    def __post_init__(self) -> None:
        _require_value(self.package_path, "package_path")
        for name in ("identifier", "title", "language"):
            value = getattr(self, name)
            if value is not None:
                _require_value(value, name)


@dataclass(frozen=True)
class EpubManifestItem:
    """One manifest reference, including its EPUB package identity."""

    item_id: str
    href: str
    media_type: str

    def __post_init__(self) -> None:
        _require_value(self.item_id, "item_id")
        _require_value(self.href, "href")
        _require_value(self.media_type, "media_type")


@dataclass(frozen=True)
class EpubSpineItem:
    """One spine-ordered manifest reference."""

    manifest_item_id: str

    def __post_init__(self) -> None:
        _require_value(self.manifest_item_id, "manifest_item_id")


@dataclass(frozen=True)
class EpubNavigationReference:
    """The retained package-relative navigation-document reference."""

    href: str

    def __post_init__(self) -> None:
        _require_value(self.href, "href")


@dataclass(frozen=True)
class EpubPreservedResource:
    """A non-translatable package resource retained for later rebuilding."""

    manifest_item_id: str
    archive_path: str

    def __post_init__(self) -> None:
        _require_value(self.manifest_item_id, "manifest_item_id")
        _require_value(self.archive_path, "archive_path")


@dataclass(frozen=True)
class EpubXhtmlDocument:
    """One XHTML document and its preserved serialized structure."""

    manifest_item_id: str
    archive_path: str
    serialized_xhtml: str

    def __post_init__(self) -> None:
        _require_value(self.manifest_item_id, "manifest_item_id")
        _require_value(self.archive_path, "archive_path")
        if not isinstance(self.serialized_xhtml, str):
            raise TypeError("serialized_xhtml must be a string")


@dataclass(frozen=True)
class EpubTextMergeTarget:
    """An EPUB-owned target identity for a later translated-text merge."""

    target_id: str
    manifest_item_id: str
    node_path: str

    def __post_init__(self) -> None:
        _require_value(self.target_id, "target_id")
        _require_value(self.manifest_item_id, "manifest_item_id")
        _require_value(self.node_path, "node_path")


@dataclass(frozen=True)
class EpubDocumentArtifact:
    """The workflow-owned EPUB package state for later concrete EPUB work."""

    source: EpubSourceReference
    package_metadata: EpubPackageMetadata
    manifest: tuple[EpubManifestItem, ...]
    spine: tuple[EpubSpineItem, ...]
    navigation: EpubNavigationReference | None
    preserved_resources: tuple[EpubPreservedResource, ...]
    xhtml_documents: tuple[EpubXhtmlDocument, ...]
    merge_targets: tuple[EpubTextMergeTarget, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.source, EpubSourceReference):
            raise TypeError("source must be an EpubSourceReference")
        if not isinstance(self.package_metadata, EpubPackageMetadata):
            raise TypeError("package_metadata must be an EpubPackageMetadata")
        if self.navigation is not None and not isinstance(
            self.navigation, EpubNavigationReference
        ):
            raise TypeError("navigation must be an EpubNavigationReference or None")

        self._freeze_values("manifest", EpubManifestItem)
        self._freeze_values("spine", EpubSpineItem)
        self._freeze_values("preserved_resources", EpubPreservedResource)
        self._freeze_values("xhtml_documents", EpubXhtmlDocument)
        self._freeze_values("merge_targets", EpubTextMergeTarget)

    def _freeze_values(self, name: str, item_type: type[object]) -> None:
        values = tuple(getattr(self, name))
        if any(not isinstance(value, item_type) for value in values):
            raise TypeError(f"{name} must contain only {item_type.__name__} values")
        object.__setattr__(self, name, values)


def _require_value(value: object, name: str) -> None:
    if not isinstance(value, str):
        raise TypeError(f"{name} must be a string")
    if not value or value.strip() != value:
        raise ValueError(f"{name} must not be blank or padded")
