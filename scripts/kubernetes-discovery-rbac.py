#!/usr/bin/env python3
"""Print explicit Helm list rules from Kubernetes discovery without changing RBAC."""

import argparse
import json
import re
import subprocess
import sys


class DiscoveryError(Exception):
    pass


def api_group(value):
    return isinstance(value, str) and len(value) <= 253 and all(
        re.fullmatch(r"[a-z0-9](?:[-a-z0-9]*[a-z0-9])?", label)
        and len(label) <= 63 for label in value.split(".")
    )


def version_name(value):
    return isinstance(value, str) and len(value) <= 63 and bool(
        re.fullmatch(r"[a-z](?:[-a-z0-9]*[a-z0-9])?", value)
    )


def discover(read, include_secrets=False, include_configmaps=True):
    core = read("/api")
    groups = read("/apis")
    if not isinstance(core.get("versions"), list) or not core["versions"]:
        raise DiscoveryError("/api has no served versions")
    if not isinstance(groups.get("groups"), list):
        raise DiscoveryError("/apis has no API group list")

    endpoints = {}
    for version in core["versions"]:
        if not version_name(version):
            raise DiscoveryError("/api has an invalid version")
        endpoints["/api/" + version] = ("", version)
    for group in groups["groups"]:
        if not isinstance(group, dict) or not api_group(group.get("name")):
            raise DiscoveryError("/apis has an invalid API group")
        name = group["name"]
        if not isinstance(group.get("versions"), list) or not group["versions"]:
            raise DiscoveryError("API group " + name + " has no served versions")
        for version in group["versions"]:
            if not isinstance(version, dict) or not version_name(version.get("version")):
                raise DiscoveryError("API group " + name + " has an invalid version")
            group_version = name + "/" + version["version"]
            if version.get("groupVersion") != group_version:
                raise DiscoveryError("API group " + name + " has inconsistent version identity")
            endpoints["/apis/" + group_version] = (name, group_version)

    resources = {}
    for endpoint, (group, group_version) in sorted(endpoints.items()):
        document = read(endpoint)
        if document.get("groupVersion") != group_version or not isinstance(document.get("resources"), list):
            raise DiscoveryError(endpoint + " has inconsistent resource discovery")
        for resource in document["resources"]:
            if not isinstance(resource, dict):
                raise DiscoveryError(endpoint + " has an invalid API resource")
            name, verbs = resource.get("name"), resource.get("verbs")
            if not isinstance(name, str) or not isinstance(verbs, list):
                raise DiscoveryError(endpoint + " has an invalid resource name or verbs")
            if "/" in name or "list" not in verbs:
                continue
            if not re.fullmatch(r"[a-z][a-z0-9-]*", name):
                raise DiscoveryError(endpoint + " has an invalid top-level resource name")
            if group == "" and ((name == "secrets" and not include_secrets) or
                                (name == "configmaps" and not include_configmaps)):
                continue
            resources.setdefault(group, set()).add(name)

    return {
        "grantSecretsRead": include_secrets,
        "grantConfigMapsRead": include_configmaps,
        "extraRules": [
            {"apiGroups": [group], "resources": sorted(names), "verbs": ["list"]}
            for group, names in sorted(resources.items())
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", help="kubectl context; defaults to the current context")
    parser.add_argument("--include-secrets", action="store_true", help="explicitly grant core Secret list access, which can return Secret values")
    parser.add_argument("--exclude-configmaps", action="store_true", help="withhold ConfigMap list access; match the cluster's collectConfigMaps policy")
    args = parser.parse_args()
    command = ["kubectl", "--request-timeout=15s"]
    if args.context:
        command.extend(["--context", args.context])

    def read(endpoint):
        try:
            result = subprocess.run(command + ["get", "--raw", endpoint], capture_output=True, text=True, check=True, timeout=30)
            document = json.loads(result.stdout)
        except (OSError, subprocess.SubprocessError, ValueError) as err:
            raise DiscoveryError("cannot read discovery endpoint " + endpoint) from err
        if not isinstance(document, dict):
            raise DiscoveryError(endpoint + " did not return a discovery object")
        return document

    try:
        values = discover(read, args.include_secrets, not args.exclude_configmaps)
    except DiscoveryError as err:
        print("discovery failed: " + str(err), file=sys.stderr)
        return 1
    json.dump(values, sys.stdout, indent=2, sort_keys=True)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
