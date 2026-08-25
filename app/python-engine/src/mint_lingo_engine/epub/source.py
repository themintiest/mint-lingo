"""Path-only handoff into the concrete EPUB processing-acquisition boundary.

This module intentionally does not open, inspect, parse, or validate an EPUB
package. Those responsibilities belong to the following EPUB document tasks;
reader presentation success is never an input to this boundary.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class EpubSourceReference:
    """One local EPUB path accepted by the EPUB-specific acquisition branch."""

    path: Path

    def __post_init__(self) -> None:
        if not isinstance(self.path, Path):
            raise TypeError("path must be a Path")


class EpubSourceAcquisition:
    """Accept the concrete EPUB payload without reading source bytes."""

    def accept(self, payload: object) -> EpubSourceReference:
        """Return the selected local path without package validation.

        The payload is intentionally exact and path-only. Existence, file type,
        ZIP/container structure, package metadata, and XHTML content remain
        outside this source handoff.
        """

        if not isinstance(payload, dict) or set(payload) != {"sourcePath"}:
            raise ValueError("payload must contain only sourcePath")
        source_path = payload["sourcePath"]
        if not isinstance(source_path, str):
            raise TypeError("sourcePath must be a string")
        if not source_path or source_path.strip() != source_path:
            raise ValueError("sourcePath must be a non-empty trimmed string")
        return EpubSourceReference(path=Path(source_path))
