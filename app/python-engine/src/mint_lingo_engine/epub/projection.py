"""EPUB XHTML-to-structured-text projection with EPUB-owned merge targets."""
from __future__ import annotations
from dataclasses import dataclass
import xml.etree.ElementTree as ElementTree
from mint_lingo_engine.epub.document import EpubDocumentArtifact, EpubTextMergeTarget
from mint_lingo_engine.epub.sentence_boundaries import fragment_epub_prose_text
from mint_lingo_engine.translation.models import StructuredTextArtifact, StructuredTextUnit

@dataclass(frozen=True)
class EpubStructuredTextProjection:
    structured_text: StructuredTextArtifact
    merge_targets: tuple[EpubTextMergeTarget, ...]

class EpubStructuredTextProjector:
    def project(self, document: EpubDocumentArtifact, source_language: str) -> EpubStructuredTextProjection:
        units=[]; targets=[]
        for document_index, xhtml in enumerate(document.xhtml_documents):
            root=ElementTree.fromstring(xhtml.serialized_xhtml)
            text_index=0
            for node in root.iter():
                if node.text and node.text.strip():
                    text_index += 1
                    node_target_id=f"{xhtml.manifest_item_id}.text.{text_index}"
                    node_path=f"/document[{document_index + 1}]/{node.tag}[{text_index}]"
                    fragments = fragment_epub_prose_text(node.tag, node.text)
                    for fragment_index, fragment in enumerate(fragments, start=1):
                        unit_id = (
                            node_target_id
                            if len(fragments) == 1
                            else f"{node_target_id}.fragment.{fragment_index}"
                        )
                        units.append(StructuredTextUnit(unit_id, fragment.text))
                        targets.append(EpubTextMergeTarget(
                            unit_id,
                            xhtml.manifest_item_id,
                            node_path,
                            fragment_index=fragment_index,
                            fragment_count=len(fragments),
                            separator_after=fragment.separator_after,
                        ))
        return EpubStructuredTextProjection(StructuredTextArtifact(source_language, units), tuple(targets))
