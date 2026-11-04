"""Preparation packs must include the reviewed forward fix from committed HEAD."""

import hashlib
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "package_app_store_prep.py"
SPEC = importlib.util.spec_from_file_location("package_app_store_prep", SCRIPT)
package = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package)
FORWARD_MIGRATION = "supabase/migrations/202611040001_business_conflict_http.sql"
FORWARD_POSTFLIGHT = "tools/deployment/tests/business_conflict_postflight.sql"


class PreparationPackageTest(unittest.TestCase):
    def snapshot_git(self, missing=()):
        paths = set(package.EXACT_PATHS) | {
            "docs/app-store/OWNER_NEXT_STEPS.md", "ios/Runner/Info.plist",
            "legal/privacy.html", "supabase/functions/delete-account/index.ts",
            "output/unrelated.txt", "build/private-evidence.json",
            "supabase/migrations/unreviewed.sql",
        }
        paths.difference_update(missing)
        contents = {path: ("Committed fixture: " + path + "\n").encode()
                    for path in paths}
        blobs = {hashlib.sha256(data).hexdigest(): data for data in contents.values()}
        tree = b"".join(
            (f"100644 blob {hashlib.sha256(contents[path]).hexdigest()}\t{path}\0").encode()
            for path in sorted(paths))

        def git(*args):
            if args == ("ls-tree", "-rz", "--full-tree", "reviewed-commit"):
                return tree
            if len(args) == 3 and args[:2] == ("cat-file", "blob"):
                return blobs[args[2]]
            raise AssertionError(f"Unexpected Git operation: {args}")

        return git, contents

    def test_committed_forward_fix_and_proof_are_required_payloads(self):
        self.assertTrue({FORWARD_MIGRATION, FORWARD_POSTFLIGHT} <= package.EXACT_PATHS)
        git, contents = self.snapshot_git()
        with patch.object(package, "git", git):
            snapshot = package.read_snapshot("reviewed-commit")
        for path in (FORWARD_MIGRATION, FORWARD_POSTFLIGHT):
            self.assertEqual(snapshot[path], (contents[path], 0o100644))
        self.assertNotIn("output/unrelated.txt", snapshot)
        self.assertNotIn("build/private-evidence.json", snapshot)
        self.assertNotIn("supabase/migrations/unreviewed.sql", snapshot)

    def test_old_head_cannot_silently_package_without_forward_fix(self):
        for missing in (FORWARD_MIGRATION, FORWARD_POSTFLIGHT):
            with self.subTest(missing=missing):
                git, _ = self.snapshot_git(missing=(missing,))
                with patch.object(package, "git", git):
                    with self.assertRaisesRegex(ValueError, "commit preparation first") as error:
                        package.read_snapshot("reviewed-commit")
                self.assertIn(missing, str(error.exception))

    def test_forward_fix_path_still_rejects_secret_material(self):
        key = b"-----BEGIN PRIVATE KEY-----\nQUJDREVGR0hJSktMTU5P\nUFFSU1RVVldYWVo=\n-----END PRIVATE KEY-----\n"
        with self.assertRaisesRegex(ValueError, "Credential-like material"):
            package.validate_payload(FORWARD_MIGRATION, key)


if __name__ == "__main__":
    unittest.main()
