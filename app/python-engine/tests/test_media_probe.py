from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

from video_translator_engine.media_probe import (
    FfprobeExecutable,
    FfprobeExecutableResolver,
    FfprobeProcessResult,
    FfprobeResolutionErrorCode,
    FfprobeResolutionFailure,
    MediaProbe,
    MediaToolResolutionMode,
    SubprocessFfprobeProcessRunner,
)


class FfprobeExecutableResolverTest(unittest.TestCase):
    def test_development_override_wins_over_path(self) -> None:
        lookup_calls: list[str] = []
        resolver = FfprobeExecutableResolver(
            mode=MediaToolResolutionMode.DEVELOPMENT,
            environment={"VIDEO_TRANSLATOR_FFPROBE_PATH": r"C:\tools\ffprobe.exe"},
            path_lookup=lambda name: lookup_calls.append(name) or r"C:\path\ffprobe.exe",
            is_executable=lambda path: path == Path(r"C:\tools\ffprobe.exe"),
            system_name=lambda: "Windows",
        )

        resolution = resolver.resolve()

        self.assertEqual(resolution, FfprobeExecutable(Path(r"C:\tools\ffprobe.exe")))
        self.assertEqual(lookup_calls, [])

    def test_invalid_development_override_does_not_fall_back_to_path(self) -> None:
        lookup_calls: list[str] = []
        resolver = FfprobeExecutableResolver(
            mode=MediaToolResolutionMode.DEVELOPMENT,
            environment={"VIDEO_TRANSLATOR_FFPROBE_PATH": "relative/ffprobe"},
            path_lookup=lambda name: lookup_calls.append(name) or "/usr/bin/ffprobe",
            is_executable=lambda path: True,
        )

        resolution = resolver.resolve()

        self.assertEqual(
            resolution,
            FfprobeResolutionFailure(
                code=FfprobeResolutionErrorCode.UNAVAILABLE,
                mode=MediaToolResolutionMode.DEVELOPMENT,
                platform_tag=None,
            ),
        )
        self.assertEqual(lookup_calls, [])

    def test_packaged_resolution_uses_the_platform_specific_bundle(self) -> None:
        runtime_root = Path(r"C:\Video Translator")
        resolver = FfprobeExecutableResolver(
            mode=MediaToolResolutionMode.PACKAGED,
            runtime_root=runtime_root,
            is_executable=lambda path: path
            == runtime_root / "media-tools" / "windows-x64" / "ffprobe.exe",
            system_name=lambda: "Windows",
            machine_name=lambda: "AMD64",
        )

        resolution = resolver.resolve()

        self.assertEqual(
            resolution,
            FfprobeExecutable(
                runtime_root / "media-tools" / "windows-x64" / "ffprobe.exe",
            ),
        )

    def test_packaged_unsupported_platform_is_structured(self) -> None:
        resolver = FfprobeExecutableResolver(
            mode=MediaToolResolutionMode.PACKAGED,
            runtime_root=Path("/runtime"),
            system_name=lambda: "Linux",
            machine_name=lambda: "aarch64",
        )

        self.assertEqual(
            resolver.resolve(),
            FfprobeResolutionFailure(
                code=FfprobeResolutionErrorCode.UNSUPPORTED_PLATFORM,
                mode=MediaToolResolutionMode.PACKAGED,
                platform_tag=None,
            ),
        )


class MediaProbeTest(unittest.TestCase):
    def test_inspect_uses_a_substitutable_process_runner(self) -> None:
        runner = _FakeProcessRunner(
            FfprobeProcessResult(return_code=0, stdout="{\"streams\": []}", stderr=""),
        )
        probe = MediaProbe(
            FfprobeExecutable(Path(r"C:\tools\ffprobe.exe")),
            runner,
        )

        result = probe.inspect(Path(r"C:\videos\source.mp4"))

        self.assertEqual(result.return_code, 0)
        self.assertEqual(
            runner.calls,
            [
                (
                    Path(r"C:\tools\ffprobe.exe"),
                    (
                        "-v",
                        "error",
                        "-show_format",
                        "-show_streams",
                        "-of",
                        "json",
                        r"C:\videos\source.mp4",
                    ),
                ),
            ],
        )

    def test_subprocess_runner_uses_direct_arguments_and_captures_output(self) -> None:
        completed = subprocess.CompletedProcess(
            args=[],
            returncode=7,
            stdout="probe output",
            stderr="probe error",
        )
        with patch(
            "video_translator_engine.media_probe.subprocess.run",
            return_value=completed,
        ) as run:
            result = SubprocessFfprobeProcessRunner().run(
                Path(r"C:\tools\ffprobe.exe"),
                ("-of", "json", r"C:\videos\source.mp4"),
            )

        self.assertEqual(
            result,
            FfprobeProcessResult(7, "probe output", "probe error"),
        )
        run.assert_called_once_with(
            [
                r"C:\tools\ffprobe.exe",
                "-of",
                "json",
                r"C:\videos\source.mp4",
            ],
            check=False,
            capture_output=True,
            text=True,
        )


class _FakeProcessRunner:
    def __init__(self, result: FfprobeProcessResult) -> None:
        self._result = result
        self.calls: list[tuple[Path, tuple[str, ...]]] = []

    def run(self, executable: Path, arguments: tuple[str, ...]) -> FfprobeProcessResult:
        self.calls.append((executable, arguments))
        return self._result
