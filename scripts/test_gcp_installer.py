#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCAN_APIS = {
    "cloudkms.googleapis.com", "sqladmin.googleapis.com", "spanner.googleapis.com",
    "dataflow.googleapis.com", "bigquery.googleapis.com", "orgpolicy.googleapis.com",
    "accesscontextmanager.googleapis.com",
}
GCLOUD = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
log = pathlib.Path(os.environ["INSTALLER_CALLS"])
previous = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
with log.open("a") as stream:
    stream.write(json.dumps(args) + "\n")
if args[:2] == ["services", "enable"]:
    apis = [item for item in args[2:] if not item.startswith("--")]
    if len(apis) > 1 and os.environ.get("FAIL_REQUIRED"):
        sys.exit(1)
    if len(apis) == 1:
        api = apis[0]
        if api == os.environ.get("BLOCKED_API"):
            sys.exit(1)
        attempts = sum(call[:3] == args[:3] for call in previous)
        if api == os.environ.get("TRANSIENT_API") and attempts == 0:
            sys.exit(1)
elif args[:2] == ["services", "list"]:
    assert "--enabled" in args
    assert "--format=value(config.name)" in args
    filters = [item for item in args if item.startswith("--filter=config.name=")]
    assert len(filters) == 1
    api = filters[0].split("=", 2)[2]
    if api != os.environ.get("UNREADY_API"):
        print(api)
elif args[:1] == ["services"]:
    sys.exit("unsupported services subcommand: " + repr(args))
elif args[:2] == ["projects", "describe"]:
    print("123456789012")
elif args[:3] == ["iam", "workload-identity-pools", "describe"]:
    print("projects/123456789012/locations/global/workloadIdentityPools/nullify-cloud-connector")
'''


class GCPInstaller(unittest.TestCase):
    def run_installer(self, **settings):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        path = Path(temporary.name)
        binary = path / "gcloud"
        binary.write_text(GCLOUD)
        binary.chmod(0o755)
        sleeper = path / "sleep"
        sleeper.write_text("#!/bin/sh\nexit 0\n")
        sleeper.chmod(0o755)
        calls = path / "calls.jsonl"
        environment = {
            **os.environ,
            "PATH": str(path) + os.pathsep + os.environ["PATH"],
            "NULLIFY_HOST_PROJECT": "acme-security",
            "NULLIFY_ORG_ID": "123456789012",
            "NULLIFY_OIDC_ISSUER_URI": "https://gcp.nullify.ai",
            "NULLIFY_TENANT_ID": "GitHub-12345",
            "INSTALLER_CALLS": str(calls),
            **settings,
        }
        result = subprocess.run(
            ["bash", str(ROOT / "gcp-integration-setup/scripts/install.sh")],
            env=environment, text=True, capture_output=True, check=False,
        )
        return result, [json.loads(line) for line in calls.read_text().splitlines()]

    def test_optional_failure_isolated_and_bounded(self):
        blocked = "orgpolicy.googleapis.com"
        result, calls = self.run_installer(BLOCKED_API=blocked)
        self.assertEqual(0, result.returncode, result.stderr)
        enables = [call[2] for call in calls if call[:2] == ["services", "enable"] and len(call) == 4]
        self.assertEqual(SCAN_APIS, set(enables))
        self.assertEqual(3, enables.count(blocked))
        self.assertTrue(all(enables.count(api) == 1 for api in SCAN_APIS - {blocked}))
        self.assertIn("Scan API readiness: 6/7 enabled", result.stdout)
        self.assertIn(blocked, result.stderr)
        self.assertIn("installed successfully", result.stdout)
        self.assertTrue(any(call[:3] == ["iam", "service-accounts", "describe"] for call in calls))

    def test_transient_failure_retried_before_readiness(self):
        transient = "dataflow.googleapis.com"
        result, calls = self.run_installer(TRANSIENT_API=transient)
        self.assertEqual(0, result.returncode, result.stderr)
        enables = [call for call in calls if call[:3] == ["services", "enable", transient]]
        self.assertEqual(2, len(enables))
        self.assertIn("Scan API readiness: 7/7 enabled", result.stdout)
        self.assertNotIn("WARNING", result.stderr)

    def test_disabled_after_enable_is_not_reported_ready(self):
        result, calls = self.run_installer(UNREADY_API="bigquery.googleapis.com")
        self.assertEqual(0, result.returncode, result.stderr)
        lists = [call for call in calls if call[:2] == ["services", "list"] and "--filter=config.name=bigquery.googleapis.com" in call]
        self.assertEqual(3, len(lists))
        self.assertIn("Scan API readiness: 6/7 enabled", result.stdout)
        self.assertIn("bigquery.googleapis.com", result.stderr)

    def test_required_failure_stops_identity_setup(self):
        result, calls = self.run_installer(FAIL_REQUIRED="1")
        self.assertEqual(1, result.returncode)
        self.assertEqual(1, len(calls))
        self.assertNotIn("installed successfully", result.stdout)


if __name__ == "__main__":
    unittest.main()
