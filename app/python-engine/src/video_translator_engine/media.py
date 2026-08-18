"""Provider-neutral media inspection domain values.

This module describes normalized successful probe output and source-validation
failures. It deliberately does not resolve or execute any media tooling.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import timedelta
from enum import Enum


@dataclass(frozen=True)
class MediaDimensions:
    """The pixel dimensions of one video stream."""

    width: int
    height: int

    def __post_init__(self) -> None:
        _require_positive_integer(self.width, "width")
        _require_positive_integer(self.height, "height")


class MediaStreamKind(str, Enum):
    """A normalized category for a media stream."""

    VIDEO = "video"
    AUDIO = "audio"
    SUBTITLE = "subtitle"
    DATA = "data"
    ATTACHMENT = "attachment"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class MediaStream:
    """Provider-neutral metadata for one stream in a media container."""

    index: int
    kind: MediaStreamKind
    codec: str
    dimensions: MediaDimensions | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.index, int) or isinstance(self.index, bool):
            raise TypeError("index must be an integer")
        if self.index < 0:
            raise ValueError("index must not be negative")
        if not isinstance(self.kind, MediaStreamKind):
            raise TypeError("kind must be a MediaStreamKind")

        codec = _normalize_identifier(self.codec, "codec")
        object.__setattr__(self, "codec", codec)

        if self.kind is MediaStreamKind.VIDEO and self.dimensions is None:
            raise ValueError("video streams require dimensions")
        if self.kind is not MediaStreamKind.VIDEO and self.dimensions is not None:
            raise ValueError("only video streams can have dimensions")


@dataclass(frozen=True)
class MediaMetadata:
    """Normalized metadata returned after a successful media inspection."""

    duration: timedelta
    streams: tuple[MediaStream, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.duration, timedelta):
            raise TypeError("duration must be a timedelta")
        if self.duration < timedelta(0):
            raise ValueError("duration must not be negative")

        streams = tuple(self.streams)
        if not streams:
            raise ValueError("streams must not be empty")
        if any(not isinstance(stream, MediaStream) for stream in streams):
            raise TypeError("streams must contain only MediaStream values")
        if len({stream.index for stream in streams}) != len(streams):
            raise ValueError("stream indexes must be unique")
        object.__setattr__(self, "streams", streams)

    @property
    def audio_streams(self) -> tuple[MediaStream, ...]:
        """The audio streams, in the source container's stream order."""

        return tuple(
            stream for stream in self.streams if stream.kind is MediaStreamKind.AUDIO
        )

    @property
    def has_audio(self) -> bool:
        """Whether the inspected media contains at least one audio stream."""

        return bool(self.audio_streams)

    @property
    def video_streams(self) -> tuple[MediaStream, ...]:
        """The video streams, in the source container's stream order."""

        return tuple(
            stream for stream in self.streams if stream.kind is MediaStreamKind.VIDEO
        )


class MediaValidationErrorCode(str, Enum):
    """Stable, provider-neutral reasons source-media validation can fail."""

    SOURCE_NOT_FOUND = "media.source_not_found"
    SOURCE_NOT_READABLE = "media.source_not_readable"
    UNSUPPORTED_MEDIA = "media.unsupported_media"
    METADATA_UNAVAILABLE = "media.metadata_unavailable"
    AUDIO_STREAM_MISSING = "media.audio_stream_missing"


@dataclass(frozen=True)
class MediaValidationError:
    """A structured media-validation failure safe for application handling."""

    code: MediaValidationErrorCode
    message: str
    retryable: bool = False

    def __post_init__(self) -> None:
        if not isinstance(self.code, MediaValidationErrorCode):
            raise TypeError("code must be a MediaValidationErrorCode")
        if not isinstance(self.message, str):
            raise TypeError("message must be a string")
        if not self.message or self.message.strip() != self.message:
            raise ValueError("message must not be blank or padded")
        if not isinstance(self.retryable, bool):
            raise TypeError("retryable must be a bool")


def _require_positive_integer(value: object, name: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool):
        raise TypeError(f"{name} must be an integer")
    if value <= 0:
        raise ValueError(f"{name} must be positive")


def _normalize_identifier(value: object, name: str) -> str:
    if not isinstance(value, str):
        raise TypeError(f"{name} must be a string")
    if not value or value.strip() != value:
        raise ValueError(f"{name} must not be blank or padded")
    return value.lower()
