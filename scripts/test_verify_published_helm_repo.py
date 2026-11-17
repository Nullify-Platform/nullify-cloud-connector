import functools
import hashlib
import http.server
import importlib.util
import json
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("verify_public_helm", Path(__file__).with_name("verify-published-helm-repo.py"))
verify_public = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify_public)


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        chart = self.root / "example"
        chart.mkdir()
        (chart / "Chart.yaml").write_text("apiVersion: v2\nname: example\nversion: 1.0.0\n")
        subprocess.run(["helm", "package", str(chart), "--destination", str(self.root)], check=True, capture_output=True)
        self.package = self.root / "example-1.0.0.tgz"
        digest = hashlib.sha256(self.package.read_bytes()).hexdigest()
        self.expected = {"entries": {"example": [{"version": "1.0.0", "digest": digest, "urls": [self.package.name]}]}}
        self.write_index(self.expected)
        handler = functools.partial(QuietHandler, directory=str(self.root))
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f"http://127.0.0.1:{self.server.server_port}/"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temporary.cleanup()

    def write_index(self, data):
        (self.root / "index.yaml").write_text(json.dumps(data))

    def test_public_consumer_can_download_and_read_verified_chart(self):
        self.assertEqual(verify_public.verify(self.expected, self.url), 1)

    def test_missing_version_fails(self):
        self.write_index({"entries": {}})
        with self.assertRaisesRegex(ValueError, "public index does not match"):
            verify_public.verify(self.expected, self.url)

    def test_package_tampering_fails(self):
        self.package.write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "digest mismatch"):
            verify_public.verify(self.expected, self.url)

    def test_outside_repository_download_is_refused(self):
        changed = json.loads(json.dumps(self.expected))
        changed["entries"]["example"][0]["urls"] = ["https://example.com/other.tgz"]
        self.write_index(changed)
        with self.assertRaisesRegex(ValueError, "does not match the expected location"):
            verify_public.verify(self.expected, self.url)

    def test_empty_expected_index_cannot_pass(self):
        with self.assertRaisesRegex(ValueError, "no charts"):
            verify_public.verify({"entries": {}}, self.url)

    def test_public_repository_ownership_metadata_is_verified(self):
        metadata = {"repositoryID": "158135dc-d5cd-4016-9d22-5494d9510594"}
        (self.root / "artifacthub-repo.yml").write_text(json.dumps(metadata))
        self.assertEqual(verify_public.verify(self.expected, self.url, metadata), 1)

    def test_changed_repository_ownership_metadata_fails(self):
        (self.root / "artifacthub-repo.yml").write_text('{"repositoryID":"another-repository"}')
        with self.assertRaisesRegex(ValueError, "ownership metadata does not match"):
            verify_public.verify(self.expected, self.url, {"repositoryID": "expected-repository"})

    def test_missing_repository_ownership_metadata_fails(self):
        with self.assertRaises(OSError):
            verify_public.verify(self.expected, self.url, {"repositoryID": "expected-repository"})


if __name__ == "__main__":
    unittest.main()
