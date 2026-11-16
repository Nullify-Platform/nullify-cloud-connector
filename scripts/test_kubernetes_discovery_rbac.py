#!/usr/bin/env python3
"""Exercise discovery-only kubectl calls and explicit Helm scope output."""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/kubernetes-discovery/endpoints.json"
GENERATOR = ROOT / "scripts/kubernetes-discovery-rbac.py"
FAKE_KUBECTL = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
if len(args) != 6 or args[:5] != ["--request-timeout=15s", "--context", "fixture", "get", "--raw"]:
    sys.exit(97)
endpoint = args[5]
with open(os.environ["DISCOVERY_REQUESTS"], "a") as log:
    log.write(endpoint + "\\n")
endpoints = json.loads(Path(os.environ["DISCOVERY_FIXTURE"]).read_text())
if endpoint not in endpoints or endpoints[endpoint] is None:
    sys.exit(1)
print(json.dumps(endpoints[endpoint]))
'''


class DiscoveryRBAC(unittest.TestCase):
    def generate(self, *arguments, change=None):
        endpoints = json.loads(FIXTURE.read_text())
        if change:
            change(endpoints)
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            fixture = directory / "endpoints.json"
            fixture.write_text(json.dumps(endpoints))
            requests = directory / "requests.txt"
            kubectl = directory / "kubectl"
            kubectl.write_text(FAKE_KUBECTL)
            kubectl.chmod(0o755)
            environment = dict(os.environ, PATH=str(directory) + os.pathsep + os.environ["PATH"],
                               DISCOVERY_FIXTURE=str(fixture), DISCOVERY_REQUESTS=str(requests))
            result = subprocess.run([sys.executable, str(GENERATOR), "--context", "fixture", *arguments],
                                    env=environment, capture_output=True, text=True)
            seen = requests.read_text().splitlines() if requests.exists() else []
        return result, seen

    def test_exact_list_scope_and_metadata_only_requests(self):
        result, requests = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        values = json.loads(result.stdout)
        self.assertFalse(values["grantSecretsRead"])
        self.assertTrue(values["grantConfigMapsRead"])
        self.assertEqual(values["extraRules"], [
            {"apiGroups": [""], "resources": ["configmaps", "pods"], "verbs": ["list"]},
            {"apiGroups": ["acme.example"], "resources": ["gadgets", "secrets", "widgets"], "verbs": ["list"]},
            {"apiGroups": ["apiextensions.k8s.io"], "resources": ["customresourcedefinitions"], "verbs": ["list"]},
            {"apiGroups": ["apps"], "resources": ["deployments"], "verbs": ["list"]},
        ])
        self.assertEqual(set(requests), set(json.loads(FIXTURE.read_text())))
        self.assertEqual(len(requests), len(set(requests)))

    def test_explicit_sensitive_kind_policy(self):
        result, _ = self.generate("--include-secrets", "--exclude-configmaps")
        self.assertEqual(result.returncode, 0, result.stderr)
        values = json.loads(result.stdout)
        self.assertTrue(values["grantSecretsRead"])
        self.assertFalse(values["grantConfigMapsRead"])
        self.assertEqual(values["extraRules"][0]["resources"], ["pods", "secrets"])

    def test_failed_discovery_emits_no_partial_values(self):
        result, _ = self.generate(change=lambda data: data.update({"/apis/apps/v1": None}))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("cannot read discovery endpoint", result.stderr)

    def test_foreign_group_version_is_rejected(self):
        result, _ = self.generate(change=lambda data: data["/apis/acme.example/v1"].update(groupVersion="other.example/v1"))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_path_injection_is_rejected_before_request(self):
        result, requests = self.generate(change=lambda data: data["/apis"]["groups"][0].update(name="../secrets"))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(requests, ["/api", "/apis"])

    def test_wildcard_discovery_resource_is_rejected(self):
        result, _ = self.generate(change=lambda data: data["/api/v1"]["resources"].append({"name": "*", "verbs": ["list"]}))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_output_is_stable_across_discovery_order(self):
        def reverse(data):
            data["/apis"]["groups"].reverse()
            for document in data.values():
                if "resources" in document:
                    document["resources"].reverse()
        first, _ = self.generate()
        second, _ = self.generate(change=reverse)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(first.stdout, second.stdout)

    def test_charts_keep_the_same_extra_rule_policy(self):
        helpers = [ROOT / "helm-charts" / chart / "templates/_extra-rules.tpl" for chart in
                   ("nullify-k8s-collector", "nullify-k8s-readonly-access")]
        self.assertEqual(helpers[0].read_text().splitlines()[1:], helpers[1].read_text().splitlines()[1:])


@unittest.skipUnless(shutil.which("helm"), "rendered RBAC boundary requires Helm")
class HelmRBAC(unittest.TestCase):
    def render(self, chart, *arguments):
        command = ["helm", "template", "fixture", str(ROOT / "helm-charts" / chart)]
        if chart == "nullify-k8s-collector":
            command.extend(["-f", str(ROOT / "helm-charts" / chart / "ci/eks.yaml")])
        result = subprocess.run(command + list(arguments), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def role_resources(self, rendered):
        resources = set()
        for document in rendered.split("---"):
            if not re.search(r"^kind: ClusterRole$", document, re.MULTILINE):
                continue
            lines = document.splitlines()
            for index, line in enumerate(lines):
                field = re.match(r"^(\s*)resources: *(.*)$", line)
                if not field:
                    continue
                if field[2]:
                    resources.update(json.loads(field[2]))
                    continue
                for item in lines[index + 1:]:
                    match = re.match(r"^(\s*)- ([a-z0-9/-]+)$", item)
                    if not match or len(match[1]) < len(field[1]):
                        break
                    resources.add(match[2])
        return resources

    def test_default_and_explicit_sensitive_kind_policy(self):
        for chart in ("nullify-k8s-collector", "nullify-k8s-readonly-access"):
            with self.subTest(chart=chart):
                default = self.render(chart)
                self.assertNotIn("secrets", self.role_resources(default))
                self.assertIn("configmaps", self.role_resources(default))
                explicit = self.render(chart, "--set", "grantSecretsRead=true", "--set", "grantConfigMapsRead=false")
                self.assertIn("secrets", self.role_resources(explicit))
                self.assertNotIn("configmaps", self.role_resources(explicit))
                if chart == "nullify-k8s-collector":
                    for output, secret, configmap in ((default, "false", "true"), (explicit, "true", "false")):
                        for name, value in (("NULLIFY_COLLECT_SECRETS", secret), ("NULLIFY_COLLECT_CONFIGMAPS", configmap)):
                            self.assertRegex(output, r"name: " + name + r'\s+value: "' + value + '"')

    def test_existing_duplicate_list_verbs_remain_valid(self):
        values = {"extraRules": [{"apiGroups": ["acme.example"], "resources": ["widgets"], "verbs": ["list", "list"]}]}
        for chart in ("nullify-k8s-collector", "nullify-k8s-readonly-access"):
            with self.subTest(chart=chart):
                output = self.render(chart, "--set-json", "extraRules=" + json.dumps(values["extraRules"]))
                self.assertRegex(output, r"verbs:\s*\n\s*- list\s*\n\s*- list")

    def test_discovered_names_are_rendered_without_wildcard_resource_grants(self):
        for chart in ("nullify-k8s-collector", "nullify-k8s-readonly-access"):
            with self.subTest(chart=chart):
                values = ROOT / "helm-charts" / chart / "ci/discovered-resources.yaml"
                output = self.render(chart, "-f", str(values))
                resources = self.role_resources(output)
                self.assertTrue({"widgets", "gadgets", "customresourcedefinitions"} <= resources)
                self.assertNotIn("secrets", resources)
                self.assertNotIn("configmaps", resources)
                self.assertFalse(any("*" in resource for resource in resources))


if __name__ == "__main__":
    unittest.main()
