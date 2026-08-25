from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from mint_lingo_engine.processing.job import JobId
from mint_lingo_engine.processing.workspace import JobWorkspace, JobWorkspaceManager


class JobWorkspaceManagerTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary_directory = self.enterContext(TemporaryDirectory())
        self.project_root = Path(temporary_directory) / "project"
        self.project_root.mkdir()
        self.manifest = self.project_root / "project.json"
        self.manifest.write_text('{"manifestVersion": 1}')
        self.manager = JobWorkspaceManager(self.project_root / "temporary")

    def test_allocates_distinct_job_id_directories_under_the_temporary_area(self) -> None:
        first_job = JobId.new()
        second_job = JobId.new()

        first_workspace = self.manager.allocate(first_job)
        second_workspace = self.manager.allocate(second_job)

        self.assertEqual(
            first_workspace.path,
            self.project_root / "temporary" / f"job-{first_job.value}",
        )
        self.assertEqual(
            second_workspace.path,
            self.project_root / "temporary" / f"job-{second_job.value}",
        )
        self.assertNotEqual(first_workspace.path, second_workspace.path)
        self.assertTrue(first_workspace.path.is_dir())
        self.assertTrue(second_workspace.path.is_dir())
        self.assertEqual(self.manifest.read_text(), '{"manifestVersion": 1}')

    def test_cleanup_removes_arbitrary_nested_work_files_without_touching_manifest(self) -> None:
        workspace = self.manager.allocate(JobId.new())
        nested_directory = workspace.path / "work" / "segment"
        nested_directory.mkdir(parents=True)
        (nested_directory / "opaque-data").write_text("temporary")

        self.manager.cleanup(workspace)
        self.manager.cleanup(workspace)

        self.assertFalse(workspace.path.exists())
        self.assertTrue(self.manifest.exists())
        self.assertEqual(self.manifest.read_text(), '{"manifestVersion": 1}')

    def test_refuses_to_reuse_or_delete_a_workspace_outside_its_temporary_root(self) -> None:
        job_id = JobId.new()
        workspace = self.manager.allocate(job_id)

        with self.assertRaisesRegex(FileExistsError, job_id.value):
            self.manager.allocate(job_id)

        external_directory = self.project_root / "artifacts"
        external_directory.mkdir()
        external_file = external_directory / "retained-reference"
        external_file.write_text("persistent")
        outside_workspace = JobWorkspace(job_id=job_id, path=external_directory)

        with self.assertRaisesRegex(ValueError, "not owned"):
            self.manager.cleanup(outside_workspace)

        self.assertTrue(workspace.path.exists())
        self.assertEqual(external_file.read_text(), "persistent")
