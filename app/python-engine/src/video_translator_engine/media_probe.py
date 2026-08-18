"""FFprobe resolution and process boundary for media inspection.

This module deliberately returns raw FFprobe output. Parsing that output into
normalized media metadata is deferred to MEDIA-04.
"""

from __future__ import annotations

import os
import platform
import shutil
import subprocess
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Protocol


class MediaToolResolutionMode(str, Enum):
    """The explicit policy used to find the bundled or development tool."""

    DEVELOPMENT = "development"
    PACKAGED = "packaged"


class FfprobeResolutionErrorCode(str, Enum):
    """Stable failures defined by the MEDIA-02 tooling policy."""

    UNSUPPORTED_PLATFORM = "media.ffprobe_unsupported_platform"
    UNAVAILABLE = "media.ffprobe_unavailable"


@dataclass(frozen=True)
class FfprobeExecutable:
    """A verified FFprobe path ready for use by a process runner."""

    path: Path


@dataclass(frozen=True)
class FfprobeResolutionFailure:
    """A safe structured outcome when FFprobe cannot be resolved."""

    code: FfprobeResolutionErrorCode
    mode: MediaToolResolutionMode
    platform_tag: str | None


FfprobeResolution = FfprobeExecutable | FfprobeResolutionFailure


class FfprobeExecutableResolver:
    """Resolves FFprobe according to the single MEDIA-02 policy."""

    def __init__(
        self,
        *,
        mode: MediaToolResolutionMode,
        runtime_root: Path | None = None,
        environment: Mapping[str, str] | None = None,
        path_lookup: Callable[[str], str | None] = shutil.which,
        is_executable: Callable[[Path], bool] | None = None,
        system_name: Callable[[], str] = platform.system,
        machine_name: Callable[[], str] = platform.machine,
    ) -> None:
        self._mode = mode
        self._runtime_root = runtime_root
        self._environment = environment if environment is not None else os.environ
        self._path_lookup = path_lookup
        self._is_executable = is_executable or _is_regular_executable_file
        self._system_name = system_name
        self._machine_name = machine_name

    def resolve(self) -> FfprobeResolution:
        """Return a verified executable or a safe resolution failure."""

        if self._mode is MediaToolResolutionMode.DEVELOPMENT:
            return self._resolve_development()
        return self._resolve_packaged()

    def _resolve_development(self) -> FfprobeResolution:
        executable_name = _ffprobe_filename(self._system_name())
        override = self._environment.get("VIDEO_TRANSLATOR_FFPROBE_PATH")
        if override is not None:
            candidate = Path(override)
            if not candidate.is_absolute():
                return self._unavailable(platform_tag=None)
            return self._from_candidate(candidate, platform_tag=None)

        candidate_text = self._path_lookup(executable_name)
        if candidate_text is None:
            return self._unavailable(platform_tag=None)
        return self._from_candidate(Path(candidate_text), platform_tag=None)

    def _resolve_packaged(self) -> FfprobeResolution:
        platform_tag = _platform_tag(self._system_name(), self._machine_name())
        if platform_tag is None:
            return FfprobeResolutionFailure(
                code=FfprobeResolutionErrorCode.UNSUPPORTED_PLATFORM,
                mode=self._mode,
                platform_tag=None,
            )
        if self._runtime_root is None:
            return self._unavailable(platform_tag=platform_tag)

        candidate = (
            self._runtime_root
            / "media-tools"
            / platform_tag
            / _ffprobe_filename(self._system_name())
        )
        return self._from_candidate(candidate, platform_tag=platform_tag)

    def _from_candidate(self, candidate: Path, *, platform_tag: str | None) -> FfprobeResolution:
        if not self._is_executable(candidate):
            return self._unavailable(platform_tag=platform_tag)
        return FfprobeExecutable(path=candidate)

    def _unavailable(self, *, platform_tag: str | None) -> FfprobeResolutionFailure:
        return FfprobeResolutionFailure(
            code=FfprobeResolutionErrorCode.UNAVAILABLE,
            mode=self._mode,
            platform_tag=platform_tag,
        )


@dataclass(frozen=True)
class FfprobeProcessResult:
    """Raw output from one FFprobe process invocation."""

    return_code: int
    stdout: str
    stderr: str

    def __post_init__(self) -> None:
        if not isinstance(self.return_code, int) or isinstance(self.return_code, bool):
            raise TypeError("return_code must be an integer")
        if not isinstance(self.stdout, str) or not isinstance(self.stderr, str):
            raise TypeError("stdout and stderr must be strings")


class FfprobeProcessRunner(Protocol):
    """The substitutable boundary for external FFprobe process execution."""

    def run(
        self,
        executable: Path,
        arguments: Sequence[str],
    ) -> FfprobeProcessResult: ...


class SubprocessFfprobeProcessRunner:
    """Runs FFprobe without a shell and captures its raw output."""

    def run(
        self,
        executable: Path,
        arguments: Sequence[str],
    ) -> FfprobeProcessResult:
        completed = subprocess.run(
            [str(executable), *arguments],
            check=False,
            capture_output=True,
            text=True,
        )
        return FfprobeProcessResult(
            return_code=completed.returncode,
            stdout=completed.stdout,
            stderr=completed.stderr,
        )


class MediaProbe:
    """Builds the stable FFprobe inspection command through a runner boundary."""

    def __init__(
        self,
        executable: FfprobeExecutable,
        process_runner: FfprobeProcessRunner,
    ) -> None:
        self._executable = executable
        self._process_runner = process_runner

    def inspect(self, source: Path) -> FfprobeProcessResult:
        """Return raw FFprobe output without source validation or metadata parsing."""

        if not isinstance(source, Path):
            raise TypeError("source must be a Path")
        return self._process_runner.run(
            self._executable.path,
            (
                "-v",
                "error",
                "-show_format",
                "-show_streams",
                "-of",
                "json",
                str(source),
            ),
        )


def _platform_tag(system_name: str, machine_name: str) -> str | None:
    system = system_name.casefold()
    machine = machine_name.casefold()
    if machine not in {"amd64", "x86_64"} and not (
        system == "darwin" and machine == "arm64"
    ):
        return None
    if system == "windows":
        return "windows-x64" if machine in {"amd64", "x86_64"} else None
    if system == "linux":
        return "linux-x64" if machine in {"amd64", "x86_64"} else None
    if system == "darwin":
        return "macos-arm64" if machine == "arm64" else "macos-x64"
    return None


def _ffprobe_filename(system_name: str) -> str:
    return "ffprobe.exe" if system_name.casefold() == "windows" else "ffprobe"


def _is_regular_executable_file(candidate: Path) -> bool:
    return candidate.is_file() and (os.name == "nt" or os.access(candidate, os.X_OK))
