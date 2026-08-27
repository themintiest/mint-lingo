"""Conservative EPUB-owned prose sentence fragmentation."""

from __future__ import annotations

from dataclasses import dataclass
import re


_FRAGMENTABLE_PROSE_ELEMENTS = frozenset({"blockquote", "li", "p"})
_MIN_FRAGMENTABLE_PROSE_CHARACTERS = 240
_CLOSING_PUNCTUATION = frozenset({'"', "'", ")", "]", "}", "”", "’"})
_OPENING_PUNCTUATION = frozenset({'"', "'", "(", "[", "{", "“", "‘"})
_NON_TERMINAL_ABBREVIATIONS = frozenset(
    {
        "dr",
        "etc",
        "e.g",
        "fig",
        "i.e",
        "inc",
        "jr",
        "ltd",
        "mr",
        "mrs",
        "ms",
        "no",
        "prof",
        "sr",
        "st",
        "vs",
    }
)


@dataclass(frozen=True)
class EpubSentenceFragment:
    """One source fragment and whitespace to retain after its translation."""

    text: str
    separator_after: str

    def __post_init__(self) -> None:
        if not isinstance(self.text, str) or not self.text.strip():
            raise ValueError("text must not be blank")
        if self.text != self.text.strip():
            raise ValueError("text must not have outer whitespace")
        if not isinstance(self.separator_after, str) or self.separator_after.strip():
            raise ValueError("separator_after must contain only whitespace")


def fragment_epub_prose_text(
    element_tag: str,
    text: str,
) -> tuple[EpubSentenceFragment, ...]:
    """Return safe sentence fragments, or the original text as one fragment.

    The policy deliberately requires long prose in a small set of block-level
    XHTML elements and an unambiguous punctuation-plus-capital boundary. This
    avoids splitting headings, inline content, decimals, initials, and common
    abbreviations while preserving source whitespace for exact reassembly.
    """

    source = text.strip()
    if (
        _local_name(element_tag) not in _FRAGMENTABLE_PROSE_ELEMENTS
        or len(source) < _MIN_FRAGMENTABLE_PROSE_CHARACTERS
        or any(
            character == "." and _is_non_terminal_period(source, position)
            for position, character in enumerate(source)
        )
    ):
        return (EpubSentenceFragment(source, ""),)

    fragments: list[EpubSentenceFragment] = []
    fragment_start = 0
    position = 0
    while position < len(source):
        if source[position] not in ".!?":
            position += 1
            continue
        sentence_end = position + 1
        while (
            sentence_end < len(source)
            and source[sentence_end] in _CLOSING_PUNCTUATION
        ):
            sentence_end += 1
        next_start = sentence_end
        while next_start < len(source) and source[next_start].isspace():
            next_start += 1
        if (
            next_start == sentence_end
            or not _starts_sentence(source, next_start)
        ):
            position += 1
            continue

        fragments.append(
            EpubSentenceFragment(
                text=source[fragment_start:sentence_end],
                separator_after=source[sentence_end:next_start],
            )
        )
        fragment_start = next_start
        position = next_start

    if not fragments:
        return (EpubSentenceFragment(source, ""),)
    fragments.append(EpubSentenceFragment(source[fragment_start:], ""))
    return tuple(fragments)


def _is_non_terminal_period(text: str, position: int) -> bool:
    preceding = text[:position]
    token_match = re.search(r"([A-Za-z](?:[A-Za-z.]*[A-Za-z])?)$", preceding)
    if token_match is None:
        return False
    token = token_match.group(1).casefold()
    return token in _NON_TERMINAL_ABBREVIATIONS or len(token) == 1


def _starts_sentence(text: str, position: int) -> bool:
    while position < len(text) and text[position] in _OPENING_PUNCTUATION:
        position += 1
    return position < len(text) and text[position].isupper()


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].casefold()
