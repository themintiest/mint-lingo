"""EPUB-owned validation and atomic export of rebuilt package bytes."""

from __future__ import annotations

from collections.abc import Callable
import os
from pathlib import Path, PurePosixPath
from uuid import uuid4
import zipfile

from mint_lingo_engine.epub.builder import EpubRebuiltPackageArtifact
from mint_lingo_engine.epub.document import EpubDocumentArtifact, EpubPackageValidationError
from mint_lingo_engine.epub.inspection import EpubPackageInspector
from mint_lingo_engine.epub.source import EpubSourceReference
from mint_lingo_engine.processing.runner import CancellationToken

_CONTAINER_PATH = "META-INF/container.xml"
_EPUB_MIMETYPE = b"application/epub+zip"


class EpubPackageExportValidationError(ValueError):
    """Raised when rebuilt bytes are not a valid exportable EPUB package."""


class EpubPackageExporter:
    """Validate and atomically promote one rebuilt EPUB without rebuilding it.

    The temporary file always lives beside the requested destination, so
    ``os.replace`` promotes only a fully written and validated package on the
    same filesystem. A previous destination remains intact if writing,
    validation, cancellation, or promotion fails.
    """

    def __init__(
        self,
        *,
        package_inspector: EpubPackageInspector | None = None,
        write_temporary_file: Callable[[Path, bytes], None] | None = None,
        promote_temporary_file: Callable[[Path, Path], None] | None = None,
    ) -> None:
        if package_inspector is not None and not isinstance(
            package_inspector, EpubPackageInspector
        ):
            raise TypeError("package_inspector must be an EpubPackageInspector")
        self._package_inspector = package_inspector or EpubPackageInspector()
        self._write_temporary_file = write_temporary_file or self._write_temporary_file_to_disk
        self._promote_temporary_file = promote_temporary_file or os.replace

    def export(
        self,
        rebuilt_package: EpubRebuiltPackageArtifact,
        destination: Path | str,
        *,
        cancellation: CancellationToken | None = None,
    ) -> Path:
        """Write a validated package atomically and return its destination path.

        The source EPUB is explicitly protected, including when an existing
        destination is a hard link to it. Cancellation observed before
        promotion raises ``JobCancelled`` and never creates or replaces the
        destination.
        """

        if not isinstance(rebuilt_package, EpubRebuiltPackageArtifact):
            raise TypeError("rebuilt_package must be an EpubRebuiltPackageArtifact")
        if not isinstance(destination, (Path, str)):
            raise TypeError("destination must be a path")
        if cancellation is not None and not isinstance(cancellation, CancellationToken):
            raise TypeError("cancellation must be a CancellationToken or None")

        destination_path = Path(destination)
        self._reject_source_destination_collision(rebuilt_package, destination_path)
        if cancellation is not None:
            cancellation.raise_if_cancelled()

        temporary_path = self._temporary_path_for(destination_path)
        try:
            self._write_temporary_file(temporary_path, rebuilt_package.package_bytes)
            if cancellation is not None:
                cancellation.raise_if_cancelled()
            self._validate_temporary_package(rebuilt_package, temporary_path)
            if cancellation is not None:
                cancellation.raise_if_cancelled()
            self._promote_temporary_file(temporary_path, destination_path)
        finally:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                pass
        return destination_path

    def _reject_source_destination_collision(
        self,
        rebuilt_package: EpubRebuiltPackageArtifact,
        destination: Path,
    ) -> None:
        source = rebuilt_package.restored_document.document.source.path
        if source.resolve() == destination.resolve():
            raise ValueError("EPUB export destination must not overwrite the source EPUB")
        if destination.exists() and source.exists() and destination.samefile(source):
            raise ValueError("EPUB export destination must not overwrite the source EPUB")

    def _temporary_path_for(self, destination: Path) -> Path:
        if not destination.parent.is_dir():
            raise FileNotFoundError("EPUB export destination directory does not exist")
        if not destination.name:
            raise ValueError("EPUB export destination must name a file")
        return destination.parent / f".{destination.name}.{uuid4().hex}.tmp"

    def _validate_temporary_package(
        self,
        rebuilt_package: EpubRebuiltPackageArtifact,
        temporary_path: Path,
    ) -> None:
        try:
            with zipfile.ZipFile(temporary_path) as archive:
                infos = archive.infolist()
                names = [info.filename for info in infos]
                if (
                    not names
                    or names[0] != "mimetype"
                    or len(set(names)) != len(names)
                    or archive.getinfo("mimetype").compress_type != zipfile.ZIP_STORED
                    or archive.read("mimetype") != _EPUB_MIMETYPE
                    or archive.testzip() is not None
                ):
                    raise EpubPackageExportValidationError("rebuilt EPUB archive is invalid")
                if any(not _is_safe_archive_path(name) for name in names):
                    raise EpubPackageExportValidationError("rebuilt EPUB archive has unsafe paths")
                expected = rebuilt_package.restored_document
                expected_paths = {
                    _CONTAINER_PATH,
                    expected.package_metadata.package_path,
                    *(document.archive_path for document in expected.xhtml_documents),
                }
                if expected.navigation_document is not None:
                    expected_paths.add(expected.navigation_document.archive_path)
                if not expected_paths.issubset(names):
                    raise EpubPackageExportValidationError("rebuilt EPUB archive is missing restored members")
        except (OSError, zipfile.BadZipFile, KeyError) as error:
            raise EpubPackageExportValidationError("rebuilt EPUB archive cannot be opened") from error

        inspected = self._package_inspector.inspect(EpubSourceReference(temporary_path))
        if isinstance(inspected, EpubPackageValidationError):
            raise EpubPackageExportValidationError(inspected.message)
        self._validate_restored_identity(rebuilt_package, inspected)

    @staticmethod
    def _validate_restored_identity(
        rebuilt_package: EpubRebuiltPackageArtifact,
        inspected: EpubDocumentArtifact,
    ) -> None:
        expected = rebuilt_package.restored_document
        if (
            inspected.package_metadata.package_path != expected.package_metadata.package_path
            or inspected.package_metadata.language != expected.target_language
            or tuple((item.manifest_item_id, item.archive_path) for item in inspected.xhtml_documents)
            != tuple((item.manifest_item_id, item.archive_path) for item in expected.xhtml_documents)
            or (None if inspected.navigation is None else inspected.navigation.href)
            != (
                None
                if expected.navigation_document is None
                else expected.navigation_document.archive_path
            )
        ):
            raise EpubPackageExportValidationError(
                "rebuilt EPUB package does not match its restored document"
            )

    @staticmethod
    def _write_temporary_file_to_disk(path: Path, package_bytes: bytes) -> None:
        with path.open("xb") as file:
            file.write(package_bytes)
            file.flush()
            os.fsync(file.fileno())


def _is_safe_archive_path(archive_path: str) -> bool:
    path = PurePosixPath(archive_path)
    return (
        bool(archive_path)
        and "\\" not in archive_path
        and not path.is_absolute()
        and ".." not in path.parts
    )
