import unittest

import mint_lingo_engine


class PackageImportTest(unittest.TestCase):
    def test_package_is_importable(self) -> None:
        self.assertEqual(
            mint_lingo_engine.__name__,
            "mint_lingo_engine",
        )
