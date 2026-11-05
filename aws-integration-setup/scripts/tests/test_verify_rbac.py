#!/usr/bin/env python3
"""Exercise RBAC verification with real kubectl and no optional CRDs."""

import json
import os
import subprocess
import shutil
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "setup-eks-managed-scan.sh"
OPTIONAL = {
    "gateway.networking.k8s.io": (
        "gatewayclasses", "gateways", "httproutes", "referencegrants"
    ),
    "networking.istio.io": (
        "virtualservices", "serviceentries", "destinationrules"
    ),
}


class VerifyRBAC(unittest.TestCase):
    def test_absent_crds(self):
        requests = []
        denied = set()

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def respond(self, payload, status=200):
                data = json.dumps(payload).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self):
                path = self.path.split("?")[0]
                if path == "/api":
                    self.respond({"kind": "APIVersions", "versions": ["v1"]})
                elif path == "/apis":
                    self.respond({"kind": "APIGroupList", "groups": [
                        {"name": group, "versions": [{"groupVersion": f"{group}/v1", "version": "v1"}],
                         "preferredVersion": {"groupVersion": f"{group}/v1", "version": "v1"}}
                        for group in ("authorization.k8s.io", "rbac.authorization.k8s.io")
                    ]})
                elif path in ("/api/v1", "/apis/authorization.k8s.io/v1", "/apis/rbac.authorization.k8s.io/v1"):
                    names = {
                        "/api/v1": ("pods", "secrets", "nodes", "users", "serviceaccounts", "groups"),
                        "/apis/authorization.k8s.io/v1": ("selfsubjectaccessreviews",),
                        "/apis/rbac.authorization.k8s.io/v1": ("clusterroles",),
                    }[path]
                    self.respond({"kind": "APIResourceList", "groupVersion": path.removeprefix("/apis/").removeprefix("/api/"),
                                  "resources": [{"name": name, "kind": "SelfSubjectAccessReview" if name == "selfsubjectaccessreviews" else name.title(),
                                                 "namespaced": name in ("pods", "secrets", "serviceaccounts"),
                                                 "verbs": ["create", "get", "list"]} for name in names]})
                else:
                    self.respond({"kind": "Status", "status": "Failure", "reason": "NotFound", "code": 404}, 404)

            def do_POST(self):
                raw = self.rfile.read(int(self.headers["Content-Length"]))
                if raw.startswith(b"k8s\x00"):
                    self.respond({"apiVersion": "authorization.k8s.io/v1", "kind": "SelfSubjectAccessReview",
                                  "status": {"allowed": False}})
                    return
                request = json.loads(raw)
                requests.append((request, self.headers.get("Impersonate-User"), self.headers.get("Impersonate-Group")))
                attrs = request["spec"].get("resourceAttributes", {})
                key = (attrs.get("group", ""), attrs.get("resource", ""))
                allowed = (
                    attrs.get("verb") == "list" and attrs.get("resource") != "secrets"
                    and not attrs.get("subresource") and "/" not in attrs.get("resource", "")
                    and key not in denied
                ) or "nonResourceAttributes" in request["spec"]
                self.respond({"apiVersion": "authorization.k8s.io/v1", "kind": "SelfSubjectAccessReview",
                              "spec": request["spec"], "status": {"allowed": allowed}})

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as cache:
                kubectl = shutil.which(os.environ.get("KUBECTL", "kubectl"))
                self.assertIsNotNone(kubectl, "kubectl is required")
                Path(cache, "kubectl").symlink_to(kubectl)
                env = dict(os.environ, PATH=cache + os.pathsep + os.environ["PATH"])
                command = ["bash", "-c", '''
eval "$(sed '$d; s|^SCRIPT_DIR=.*|SCRIPT_DIR="$(dirname "$1")"|' "$1")"
KUBECTL=("$2" --server "$3" --kubeconfig /dev/null --cache-dir "$4")
setup_kubectl() { :; }
verify_rbac
''', "verify-rbac", str(SCRIPT), os.environ.get("KUBECTL", "kubectl"),
                    f"http://127.0.0.1:{server.server_port}", cache]
                for blocked in (None, ("gateway.networking.k8s.io", "gateways"), ("networking.istio.io", "virtualservices"), ("batch", "cronjobs")):
                    with self.subTest(blocked=blocked):
                        requests.clear()
                        denied.clear()
                        if blocked:
                            denied.add(blocked)
                        result = subprocess.run(command, capture_output=True, text=True, timeout=60, env=env)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        for group, resources in OPTIONAL.items():
                            for resource in resources:
                                outcome = "cannot" if (group, resource) == blocked else "can"
                                self.assertIn(f"group nullify-readonly {outcome} list {resource}.{group}", result.stderr)
                        for group, resource in [(group, resource) for group, resources in OPTIONAL.items() for resource in resources] + [("batch", "cronjobs"), ("apps", "deployments"), ("", "pods")]:
                            self.assertTrue(any(
                                request["spec"].get("resourceAttributes") == {"verb": "list", "group": group, "resource": resource}
                                and user == "nullify-verify" and impersonated_group == "nullify-readonly"
                                for request, user, impersonated_group in requests
                            ), (group, resource, result.stderr))
                        if blocked:
                            self.assertIn(f"cannot list {blocked[1]}.{blocked[0]}", result.stderr)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    unittest.main()
