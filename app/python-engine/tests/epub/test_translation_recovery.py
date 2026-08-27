import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from mint_lingo_engine.epub.translation_recovery import (
    EpubRecoveryIndex,
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

    def test_discovers_only_valid_records_and_matches_selected_or_moved_sources(self) -> None:
        store = self._store("9901e187-dc89-4cc3-a2f8-7e1e6f60c12e")
        record = self._create(store)
        resumable = store.mark_failed(
            LlmProviderFailure(
                category=LlmProviderFailureCategory.TIMEOUT,
                retryable=True,
                retry_scope=LlmProviderFailureRetryScope.USER_DIRECTED_RESUME,
            )
        )
        index = EpubRecoveryIndex(self.root / "application-data")
        index.sync(store.path, resumable)
        moved_source = self.root / "moved" / "renamed.epub"
        moved_source.parent.mkdir()
        moved_source.write_bytes(self.source.read_bytes())
        unrelated_source = self.root / "other.epub"
        unrelated_source.write_bytes(b"different EPUB")

        expected = {
            "recoveryId": record.recovery_id,
            "sourceLanguage": "en",
            "targetLanguage": "vi",
            "providerId": "ollama",
            "modelId": "offline-model",
            "failureCategory": "timeout",
        }
        self.assertEqual([candidate.to_json() for candidate in index.list_resumable()], [expected])
        self.assertEqual(
            [candidate.to_json() for candidate in index.find_for_source(self.source)],
            [expected],
        )
        self.assertEqual(
            [candidate.to_json() for candidate in index.find_for_source(moved_source)],
            [expected],
        )
        self.assertEqual(index.find_for_source(unrelated_source), ())
        self.assertEqual(
            index.resumable_record_for_source(record.recovery_id, moved_source),
            resumable,
        )
        self.assertIsNone(
            index.resumable_record_for_source(record.recovery_id, unrelated_source)
        )
        self.assertEqual(store.mark_running().lifecycle, EpubRecoveryLifecycle.RUNNING)
        self.assertIsNone(
            index.resumable_record_for_source(record.recovery_id, moved_source)
        )
        serialized = json.dumps(expected)
        for private_value in (str(self.source), str(store.path), "private source EPUB text"):
            self.assertNotIn(private_value, serialized)

    def test_drops_missing_corrupt_or_terminal_index_entries(self) -> None:
        index = EpubRecoveryIndex(self.root / "application-data")
        stores = (
            self._store("c362c5e7-4659-4f56-a8a1-0d03167e541b"),
            self._store("7d3e3537-ef9a-4710-81b9-a870bc1c484b"),
            self._store("4f2e50fd-42aa-4241-bba8-9d1dc57e2149"),
        )
        for store in stores:
            self._create(store)
            index.sync(
                store.path,
                store.mark_failed(
                    LlmProviderFailure(
                        category=LlmProviderFailureCategory.SERVICE_UNAVAILABLE,
                        retryable=True,
                        retry_scope=LlmProviderFailureRetryScope.USER_DIRECTED_RESUME,
                    )
                ),
            )
        stores[0].path.unlink()
        stores[1].path.write_text("private corrupt provider response", encoding="utf-8")
        index.sync(stores[2].path, stores[2].mark_completed())

        self.assertEqual(index.list_resumable(), ())
        self.assertEqual(
            json.loads(index.path.read_text(encoding="utf-8")),
            {"recoveries": []},
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
