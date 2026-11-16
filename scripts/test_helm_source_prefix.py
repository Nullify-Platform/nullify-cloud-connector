#!/usr/bin/env python3
import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHART = ROOT / "helm-charts/nullify-k8s-collector"


@unittest.skipUnless(shutil.which("helm"), "source-prefix boundary requires Helm")
class HelmSourcePrefix(unittest.TestCase):
    def render(self, prefix, fixture="eks.yaml"):
        return subprocess.run([
            "helm", "template", "fixture", str(CHART),
            "-f", str(CHART / "ci" / fixture),
            "--set-string", "collector.s3.keyPrefix=" + prefix,
        ], capture_output=True, text=True)

    def test_issued_source_prefix_selects_the_new_writer_for_both_platforms(self):
        for fixture in ("eks.yaml", "gke.yaml"):
            for prefix in ("k8s-collector-scoped/GitHub-1/", "k8s-collector-scoped/enc-4269746275636b65742d7b317d/"):
                with self.subTest(fixture=fixture, prefix=prefix):
                    result = self.render(prefix, fixture)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    for variable in ("NULLIFY_S3_KEY_PREFIX", "NULLIFY_S3_SOURCE_PREFIX"):
                        self.assertRegex(result.stdout, r"name: " + variable + r'\s+value: "' + re.escape(prefix) + '"')
                    self.assertIn("k8s-collector-3.49.0", result.stdout)

    def test_old_or_unbounded_roots_fail_before_any_install(self):
        for prefix in ("", "k8s-collector", "k8s-collector/GitHub-1/", "k8s-collector/k8s-collector/", "k8s-collector-scoped/*/", "k8s-collector-scoped/../", "k8s-collector-scoped/GitHub-1/other/"):
            with self.subTest(prefix=prefix):
                result = self.render(prefix)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("collector.s3.keyPrefix", result.stderr)


if __name__ == "__main__":
    unittest.main()
