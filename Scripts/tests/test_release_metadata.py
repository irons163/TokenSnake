import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("release_metadata", Path(__file__).parents[1] / "release_metadata.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

PROJECT = """
    MARKETING_VERSION = 1.3.0;
    CURRENT_PROJECT_VERSION = 10;
    MARKETING_VERSION = 1.3.0;
    CURRENT_PROJECT_VERSION = 10;
"""


class ReleaseMetadataTests(unittest.TestCase):
    def test_manual_and_stable_release(self):
        self.assertEqual(module.resolve(PROJECT)["version"], "1.3.0")
        self.assertEqual(module.resolve(PROJECT, "v1.3.0")["build_number"], "10")

    def test_prerelease_requires_matching_base_and_flag(self):
        self.assertEqual(module.resolve(PROJECT, "v1.3.0-rc.1", True)["version"], "1.3.0-rc.1")
        for tag, flag in [("v1.3.0-rc.1", False), ("v1.4.0-rc.1", True)]:
            with self.assertRaises(ValueError):
                module.resolve(PROJECT, tag, flag)

    def test_invalid_tags_cannot_reach_shell_or_artifact_paths(self):
        for tag in ["v1.3.0/../../file", "v1.3.0\ninjected=true", "$(touch marker)", "v1.3.0;exit", "v01.3.0", "v9.9.9"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                module.resolve(PROJECT, tag)

    def test_inconsistent_or_missing_project_settings_fail(self):
        for text in ["", PROJECT.replace("MARKETING_VERSION = 1.3.0;", "MARKETING_VERSION = wrong;", 1),
                     PROJECT.replace("CURRENT_PROJECT_VERSION = 10;", "CURRENT_PROJECT_VERSION = 11;", 1)]:
            with self.assertRaises(ValueError):
                module.resolve(text)


if __name__ == "__main__":
    unittest.main()
