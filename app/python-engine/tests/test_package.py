import unittest

import video_translator_engine


class PackageImportTest(unittest.TestCase):
    def test_package_is_importable(self) -> None:
        self.assertEqual(
            video_translator_engine.__name__,
            "video_translator_engine",
        )
