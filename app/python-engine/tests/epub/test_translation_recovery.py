import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from mint_lingo_engine.epub.translation_recovery import (
    EpubRecoveryLifecycle,
    EpubRecoveryRecordError,
    EpubRecoveryRecordStore,
)
from mint_lingo_engine.providers.translation.base import (
    LlmProviderFailure,
    LlmProviderFailureCategory,
    LlmProviderFailureRetryScope,
)


class EpubRecoveryRecordStoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(self.enterContext(TemporaryDirectory()))
        self.source = self.root / "book.epub"
        self.source.write_bytes(b"private source EPUB text")

    def test_atomically_retains_only_safe_retryable_invocation_metadata(self) -> None:
        store = self._store("78a49139-7b75-4e31-b9d7-0d6d11a6f27d")

        created = self._create(store)
        resumable = store.mark_failed(
            LlmProviderFailure(
                category=LlmProviderFailureCategory.SERVICE_UNAVAILABLE,
                retryable=True,
                retry_scope=LlmProviderFailureRetryScope.USER_DIRECTED_RESUME,
            )
        )

        self.assertEqual(created.lifecycle, EpubRecoveryLifecycle.RUNNING)
        self.assertEqual(resumable.lifecycle, EpubRecoveryLifecycle.RESUMABLE)
        self.assertTrue(resumable.is_resumable)
        self.assertEqual(resumable.failure_category, "service_unavailable")
        self.assertEqual(store.load(), resumable)
        self.assertEqual(list(store.path.parent.glob("*.tmp")), [])

        serialized = store.path.read_text(encoding="utf-8")
        payload = json.loads(serialized)
        self.assertEqual(
            set(payload),
            {
                "artifactRoot",
                "checkpointNamespace",
                "failureCategory",
                "lifecycle",
                "modelId",
                "providerId",
                "recoveryId",
                "sourceLanguage",
                "sourceSha256",
                "targetLanguage",
            },
        )
        for private_value in (
            "private source EPUB text",
            "translated text",
            "prompt content",
            "raw provider response",
            "Authorization: secret",
            str(self.source),
        ):
            self.assertNotIn(private_value, serialized)

    def test_terminal_lifecycles_cannot_resume(self) -> None:
        cases = (
            ("e4aec0e2-6367-4979-849a-726a0a1c84ad", "completed"),
            ("5b8f7e48-8c8f-4c1e-92e9-901e8415b8bf", "cancelled"),
            ("a31c9123-9eb0-49d0-9f31-8897b924e3a9", "failed"),
        )
        for recovery_id, operation in cases:
            with self.subTest(operation=operation):
                store = self._store(recovery_id)
                self._create(store)
                if operation == "completed":
                    record = store.mark_completed()
                elif operation == "cancelled":
                    record = store.mark_cancelled()
                else:
                    record = store.mark_failed(
                        LlmProviderFailure(
                            category=LlmProviderFailureCategory.REQUEST_REJECTED,
                            retryable=False,
                            retry_scope=LlmProviderFailureRetryScope.NONE,
                        )
                    )
                self.assertEqual(record.lifecycle.value, operation)
                self.assertFalse(record.is_resumable)

    def test_rejects_corrupt_records_without_exposing_their_contents(self) -> None:
        store = self._store("50f58d69-0535-4652-b6cf-0cdbd0ed1127")
        self._create(store)
        private_value = "private source text and provider response"
        store.path.write_text(private_value, encoding="utf-8")

        with self.assertRaises(EpubRecoveryRecordError) as raised:
            store.load()

        self.assertNotIn(private_value, str(raised.exception))
        self.assertEqual(
            json.loads(store.path.read_text(encoding="utf-8"))["lifecycle"],
            EpubRecoveryLifecycle.FAILED.value,
        )

    def _store(self, recovery_id: str) -> EpubRecoveryRecordStore:
        return EpubRecoveryRecordStore(self.root / "artifacts", recovery_id)

    def _create(self, store: EpubRecoveryRecordStore):
        return store.create(
            source_path=self.source,
            source_language="en",
            target_language="vi",
            provider_id="ollama",
            model_id="offline-model",
            checkpoint_namespace="book-translation",
        )
