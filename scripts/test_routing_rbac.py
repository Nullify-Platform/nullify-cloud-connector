#!/usr/bin/env python3
"""Check the routing collector's permissions in every maintained RBAC template."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = {
    "gateway.networking.k8s.io": {
        "gatewayclasses", "gateways", "httproutes", "referencegrants"
    },
    "networking.istio.io": {
        "virtualservices", "serviceentries", "destinationrules"
    },
}
DISCOVERY = {
    "/api", "/apis",
    "/apis/gateway.networking.k8s.io/v1",
    "/apis/gateway.networking.k8s.io/v1beta1",
    "/apis/gateway.networking.k8s.io/v1alpha2",
    "/apis/gateway.networking.k8s.io/v1alpha3",
    "/apis/networking.istio.io/v1",
    "/apis/networking.istio.io/v1beta1",
    "/apis/networking.istio.io/v1alpha3",
}
RULE = re.compile(
    r"api_?[gG]roups\s*[:=]\s*\[([^\]]*)\]\s*"
    r"resources\s*[:=]\s*\[([^\]]*)\]"
)


def values(raw):
    return set(re.findall(r'"([^\"]*)"', raw))


class RoutingRBAC(unittest.TestCase):
    def test_routing_permissions(self):
        paths = [
            ROOT / "helm-charts/nullify-k8s-collector/templates/clusterrole.yaml"
        ]
        for version in ("terraform", "terraform-v6"):
            base = ROOT / "aws-integration-setup" / version / "modules/k8s-resources"
            paths.extend((base / "main.tf", base / "managed_scan.tf"))
        for path in paths:
            with self.subTest(path=path.relative_to(ROOT)):
                raw = path.read_text()
                found = {}
                for match in RULE.finditer(raw):
                    for group in values(match[1]):
                        if group in RESOURCES:
                            self.assertNotIn(group, found)
                            found[group] = values(match[2])
                            if path.name != "managed_scan.tf":
                                verb = re.match(
                                    r"\s*verbs\s*[:=]\s*\[([^\]]*)\]",
                                    raw[match.end():],
                                )
                                self.assertIsNotNone(verb)
                                self.assertEqual(values(verb[1]), {"list"})
                self.assertEqual(found, RESOURCES)
                if path.name == "managed_scan.tf":
                    self.assertRegex(raw, r'verbs\s*=\s*\["list"\]')
                discovery = re.search(
                    r"non_?[rR]esource_?[uU][rR][lL][sS]\s*[:=]\s*\[([^\]]*)\]",
                    raw,
                )
                self.assertIsNotNone(discovery)
                endpoints = values(discovery[1])
                self.assertTrue(DISCOVERY <= endpoints)
                self.assertFalse(any("*" in endpoint for endpoint in endpoints))
                verb = re.match(
                    r"\s*verbs\s*[:=]\s*\[([^\]]*)\]",
                    raw[discovery.end():],
                )
                self.assertIsNotNone(verb)
                self.assertEqual(values(verb[1]), {"get"})


if __name__ == "__main__":
    unittest.main()
