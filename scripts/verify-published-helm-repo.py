#!/usr/bin/env python3
import argparse
import hashlib
import json
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path


def yaml_data(contents):
    parsed = subprocess.run(["yq", "-o=json", "."], input=contents, capture_output=True, check=True)
    return json.loads(parsed.stdout)


def fetch(url):
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read()


def verify(expected, repository_url, expected_metadata=None):
    base = repository_url.rstrip("/") + "/"
    if expected_metadata is not None:
        if not expected_metadata.get("repositoryID"):
            raise ValueError("expected repository metadata has no repositoryID")
        metadata = yaml_data(fetch(base + "artifacthub-repo.yml"))
        if metadata != expected_metadata:
            raise ValueError("public repository ownership metadata does not match")
    public = yaml_data(fetch(base + "index.yaml"))
    checked = 0
    with tempfile.TemporaryDirectory(prefix="nullify-public-helm-") as temporary:
        for name, versions in expected["entries"].items():
            actual_versions = {entry["version"]: entry for entry in public.get("entries", {}).get(name, [])}
            for entry in versions:
                version = entry["version"]
                actual = actual_versions.get(version)
                if actual is None or actual.get("digest") != entry["digest"]:
                    raise ValueError(f"public index does not match {name} {version}")
                package_url = urllib.parse.urljoin(base, actual["urls"][0])
                expected_urls = {urllib.parse.urljoin(base, url) for url in entry["urls"]}
                if package_url not in expected_urls or urllib.parse.urlsplit(package_url).scheme not in {"https", "http"}:
                    raise ValueError(f"package URL does not match the expected location for {name} {version}")
                contents = fetch(package_url)
                if hashlib.sha256(contents).hexdigest() != entry["digest"]:
                    raise ValueError(f"public package digest mismatch for {name} {version}")
                path = Path(temporary) / f"{name}-{version}.tgz"
                path.write_bytes(contents)
                metadata = subprocess.run(["helm", "show", "chart", str(path)], check=True, capture_output=True).stdout
                chart = yaml_data(metadata)
                if chart.get("name") != name or str(chart.get("version")) != str(version):
                    raise ValueError(f"downloaded chart identity mismatch for {name} {version}")
                print(f"verified {name} {version}", flush=True)
                checked += 1
    if checked == 0:
        raise ValueError("expected index contains no charts")
    return checked


def main():
    parser = argparse.ArgumentParser(description="Verify public chart index, immutable digests and downloaded package metadata.")
    parser.add_argument("--expected-index", type=Path, required=True)
    parser.add_argument("--expected-repository-metadata", type=Path)
    parser.add_argument("--url", default="https://nullify-platform.github.io/nullify-cloud-connector/")
    parser.add_argument("--attempts", type=int, default=1)
    parser.add_argument("--retry-seconds", type=float, default=15)
    args = parser.parse_args()
    if args.attempts < 1 or args.retry_seconds < 0:
        parser.error("attempts must be positive and retry-seconds must be non-negative")
    expected = yaml_data(args.expected_index.read_bytes())
    expected_metadata = yaml_data(args.expected_repository_metadata.read_bytes()) if args.expected_repository_metadata else None
    for attempt in range(args.attempts):
        try:
            count = verify(expected, args.url, expected_metadata)
            print(f"Public Helm verification passed for {count} chart versions")
            return
        except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
            if attempt + 1 == args.attempts:
                raise SystemExit(str(error)) from error
            print(f"Public Helm verification attempt {attempt + 1} failed: {error}; retrying", flush=True)
            time.sleep(args.retry_seconds)


if __name__ == "__main__":
    main()
