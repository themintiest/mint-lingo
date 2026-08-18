"""Source-media validation built on the FFprobe boundary and metadata parser."""

from __future__ import annotations

import os
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from video_translator_engine.media import (
    MediaMetadata,
    MediaValidationError,
    MediaValidationErrorCode,
)
from video_translator_engine.media_probe import (
    FfprobeMetadataParseError,
    MediaProbe,
    parse_ffprobe_metadata,
)


@dataclass(frozen=True)
class MediaValidationSuccess:
    """A source that passed filesystem, probe, metadata, and audio checks."""

    metadata: MediaMetadata


@dataclass(frozen=True)
class MediaValidationFailure:
    """A source that failed validation with a safe structured error."""

    error: MediaValidationError


MediaValidationResult = MediaValidationSuccess | MediaValidationFailure


class SourceMediaValidator:
    """Validates one source path without exposing filesystem details to callers."""

    def __init__(
        self,
        media_probe: MediaProbe,
        *,
        is_regular_file: Callable[[Path], bool] | None = None,
        is_readable: Callable[[Path], bool] | None = None,
    ) -> None:
        self._media_probe = media_probe
        self._is_regular_file = is_regular_file or Path.is_file
        self._is_readable = is_readable or _is_readable_file

    def validate(self, source: Path) -> MediaValidationResult:
        """Validate a source path and return metadata or a structured failure."""

        if not isinstance(source, Path):
            raise TypeError("source must be a Path")
        try:
            if not source.exists():
                return _failure(
                    MediaValidationErrorCode.SOURCE_NOT_FOUND,
                    "The source media file does not exist.",
                )
            if not self._is_regular_file(source) or not self._is_readable(source):
                return _failure(
                    MediaValidationErrorCode.SOURCE_NOT_READABLE,
                    "The source media file cannot be read.",
                )
        except OSError:
            return _failure(
                MediaValidationErrorCode.SOURCE_NOT_READABLE,
                "The source media file cannot be read.",
            )

        process_result = self._media_probe.inspect(source)
        if process_result.return_code != 0:
            return _failure(
                MediaValidationErrorCode.UNSUPPORTED_MEDIA,
                "The source media format is unsupported.",
            )

        try:
            metadata = parse_ffprobe_metadata(process_result.stdout)
        except FfprobeMetadataParseError:
            return _failure(
                MediaValidationErrorCode.METADATA_UNAVAILABLE,
                "The source media metadata could not be read.",
            )
        if not metadata.has_audio:
            return _failure(
                MediaValidationErrorCode.AUDIO_STREAM_MISSING,
                "The source media does not contain an audio stream.",
            )
        return MediaValidationSuccess(metadata)


def _failure(code: MediaValidationErrorCode, message: str) -> MediaValidationFailure:
    return MediaValidationFailure(MediaValidationError(code=code, message=message))


def _is_readable_file(path: Path) -> bool:
    return os.access(path, os.R_OK)
