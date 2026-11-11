#!/usr/bin/env python3
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class GCPInstaller(unittest.TestCase):
    def test_gcloud_commands_match_organization_terraform_permissions(self):
        terraform = (ROOT / 'gcp-integration-setup/terraform/modules/nullify-gcp-integration/main.tf').read_text()
        def values(name):
            block = re.search(r'\b' + name + r'\s*=\s*\[(.*?)\]', terraform, re.S).group(1)
            return set(re.findall(r'"([A-Za-z][A-Za-z0-9./]+)"', block))
        permissions = values('custom_role_permissions_common') | values('custom_role_permissions_org_only')
        roles = values('predefined_viewer_roles') | values('discovery_roles')
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
                self.assertNotIn('roles/logging.viewer', granted_roles)
                self.assertIn('Save the connection, then select Validate', result.stdout)
                log.write_text('')
                removed = subprocess.run(['bash', str(ROOT / 'gcp-integration-setup/scripts/uninstall.sh')], env=environment, capture_output=True, text=True, timeout=10)
                self.assertEqual(removed.returncode, 0, removed.stderr)
                commands = [json.loads(line) for line in log.read_text().splitlines()]
                removed_roles = {arg.split('=', 1)[1] for command in commands if command[:2] == ['organizations', 'remove-iam-policy-binding'] for arg in command if arg.startswith('--role=')}
                self.assertEqual(removed_roles, granted_roles | {'roles/logging.viewer'})


if __name__ == '__main__':
    unittest.main()
