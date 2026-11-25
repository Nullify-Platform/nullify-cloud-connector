#!/usr/bin/env python3
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCAN_APIS = {
    "cloudkms.googleapis.com", "sqladmin.googleapis.com", "spanner.googleapis.com",
    "dataflow.googleapis.com", "bigquery.googleapis.com", "orgpolicy.googleapis.com",
    "accesscontextmanager.googleapis.com", "appengine.googleapis.com",
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
    if api == os.environ.get("FAILED_LIST_API"):
        sys.exit(1)
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
        self.assertIn("Scan API readiness: 7/8 enabled", result.stdout)
        self.assertIn(blocked, result.stderr)
        self.assertIn("installed successfully", result.stdout)
        self.assertTrue(any(call[:3] == ["iam", "service-accounts", "describe"] for call in calls))

    def test_transient_failure_retried_before_readiness(self):
        transient = "dataflow.googleapis.com"
        result, calls = self.run_installer(TRANSIENT_API=transient)
        self.assertEqual(0, result.returncode, result.stderr)
        enables = [call for call in calls if call[:3] == ["services", "enable", transient]]
        self.assertEqual(2, len(enables))
        self.assertIn("Scan API readiness: 8/8 enabled", result.stdout)
        self.assertNotIn("WARNING", result.stderr)

    def test_disabled_after_enable_is_not_reported_ready(self):
        result, calls = self.run_installer(UNREADY_API="bigquery.googleapis.com")
        self.assertEqual(0, result.returncode, result.stderr)
        lists = [call for call in calls if call[:2] == ["services", "list"] and "--filter=config.name=bigquery.googleapis.com" in call]
        self.assertEqual(3, len(lists))
        self.assertIn("Scan API readiness: 7/8 enabled", result.stdout)
        self.assertIn("bigquery.googleapis.com", result.stderr)

    def test_failed_list_output_is_not_reported_ready(self):
        result, calls = self.run_installer(FAILED_LIST_API="bigquery.googleapis.com")
        self.assertEqual(0, result.returncode, result.stderr)
        lists = [call for call in calls if call[:2] == ["services", "list"] and "--filter=config.name=bigquery.googleapis.com" in call]
        self.assertEqual(3, len(lists))
        self.assertIn("Scan API readiness: 7/8 enabled", result.stdout)

    def test_required_failure_stops_identity_setup(self):
        result, calls = self.run_installer(FAIL_REQUIRED="1")
        self.assertEqual(1, result.returncode)
        self.assertEqual(1, len(calls))
        self.assertNotIn("installed successfully", result.stdout)


# Checked against Google's Cloud Logging permissions reference for log-entry
# listing, downloads, private entries and access through log views.
REVIEWED_ORG_VIEWER_ROLES = {
    "roles/appengine.appViewer",
    "roles/browser",
    "roles/cloudasset.viewer",
    "roles/cloudfunctions.viewer",
    "roles/cloudkms.viewer",
    "roles/cloudsql.viewer",
    "roles/compute.viewer",
    "roles/container.clusterViewer",
    "roles/dataflow.viewer",
    "roles/dataproc.viewer",
    "roles/pubsub.viewer",
    "roles/run.viewer",
    "roles/spanner.viewer",
}


class GCPInstallerPermissions(unittest.TestCase):
    def test_gcloud_commands_match_organization_terraform_permissions(self):
        terraform = (ROOT / 'gcp-integration-setup/terraform/modules/nullify-gcp-integration/main.tf').read_text()
        def values(name):
            block = re.search(r'\b' + name + r'\s*=\s*\[(.*?)\]', terraform, re.S).group(1)
            return set(re.findall(r'"([A-Za-z][A-Za-z0-9./]+)"', block))
        permissions = values('custom_role_permissions_common') | values('custom_role_permissions_org_only')
        roles = values('predefined_viewer_roles') | values('discovery_roles')
        self.assertEqual(REVIEWED_ORG_VIEWER_ROLES, roles)
        for exists in (False, True):
            with self.subTest(existing_custom_role=exists), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                log = root / 'commands.jsonl'
                gcloud = root / 'gcloud'
                gcloud.write_text('''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['GCLOUD_LOG'], 'a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\\n')
if sys.argv[1:4] == ['iam', 'roles', 'describe']:
    sys.exit(0 if os.environ['ROLE_EXISTS'] == '1' else 1)
if sys.argv[1:4] == ['iam', 'workload-identity-pools', 'describe']:
    print('projects/123/locations/global/workloadIdentityPools/nullify-cloud-connector')
if sys.argv[1:3] == ['projects', 'describe']:
    print('123')
if sys.argv[1:3] == ['services', 'list']:
    print(next(arg.split('=', 2)[2] for arg in sys.argv if arg.startswith('--filter=config.name=')))
''')
                gcloud.chmod(0o700)
                environment = dict(os.environ, PATH=f'{root}:{os.environ["PATH"]}', GCLOUD_LOG=str(log), ROLE_EXISTS=str(int(exists)), NULLIFY_HOST_PROJECT='host-project', NULLIFY_ORG_ID='123', NULLIFY_OIDC_ISSUER_URI='https://example.com', NULLIFY_TENANT_ID='tenant')
                result = subprocess.run(['bash', str(ROOT / 'gcp-integration-setup/scripts/install.sh')], env=environment, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                commands = [json.loads(line) for line in log.read_text().splitlines()]
                custom = next(command for command in commands if command[:3] == ['iam', 'roles', 'update' if exists else 'create'])
                granted_permissions = next(arg.split('=', 1)[1] for arg in custom if arg.startswith('--permissions=')).split(',')
                self.assertEqual(set(granted_permissions), permissions)
                granted_roles = {arg.split('=', 1)[1] for command in commands if command[:2] == ['organizations', 'add-iam-policy-binding'] for arg in command if arg.startswith('--role=')}
                self.assertEqual(granted_roles, roles | {'organizations/123/roles/nullifyCloudConnector'})
                self.assertEqual(
                    {"logging.sinks.list", "logging.logMetrics.list", "logging.buckets.list"},
                    {permission for permission in granted_permissions if permission.startswith("logging.")},
                )
                self.assertIn('Set the organization scope to 123.', result.stdout)
                self.assertIn('Save the connection, then select Validate', result.stdout)
                log.write_text('')
                removed = subprocess.run(['bash', str(ROOT / 'gcp-integration-setup/scripts/uninstall.sh')], env=environment, capture_output=True, text=True, timeout=10)
                self.assertEqual(removed.returncode, 0, removed.stderr)
                commands = [json.loads(line) for line in log.read_text().splitlines()]
                removed_roles = {arg.split('=', 1)[1] for command in commands if command[:2] == ['organizations', 'remove-iam-policy-binding'] for arg in command if arg.startswith('--role=')}
                self.assertEqual(removed_roles, granted_roles | {'roles/logging.viewer', 'roles/iam.securityReviewer'})



if __name__ == "__main__":
    unittest.main()
