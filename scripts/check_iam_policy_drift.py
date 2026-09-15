#!/usr/bin/env python3
"""Compares the Allow/Deny action sets granted by the CloudFormation template
against both Terraform trees (v5 and v6), so the three customer-facing
templates for the same IAM role cannot silently drift apart (ncc #58,
whiskeylotus, W58-3).

Terraform's readonly grant is split across readonly_policy_part1 and
readonly_policy_part2 (an IAM managed policy document size limit); the
CloudFormation template splits the same grant across ReadOnlyAccessPolicy and
ReadOnlyAccessPolicy2. Both splits are combined before comparing.

Exits non-zero and prints the symmetric difference on any mismatch.
"""

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CFN_TEMPLATE = REPO_ROOT / "aws-integration-setup/cloudformation/nullify-cloudformation-template.json"
TERRAFORM_TREES = ["aws-integration-setup/terraform", "aws-integration-setup/terraform-v6"]
DATA_TF_RELATIVE = "modules/nullify-aws-integration/data.tf"

# data source name -> Effect it must carry
READONLY_SOURCES = ["readonly_policy_part1", "readonly_policy_part2"]
DENY_SOURCE = "deny_actions_policy"


def cfn_actions(effect_resources: list) -> set:
    actions: set = set()
    for resource_name in effect_resources:
        template = json.loads(CFN_TEMPLATE.read_text())
        statements = template["Resources"][resource_name]["Properties"]["PolicyDocument"]["Statement"]
        for statement in statements:
            action = statement.get("Action", [])
            actions.update(action if isinstance(action, list) else [action])
    return actions


def terraform_actions(data_tf: Path, data_source_names: list) -> set:
    text = data_tf.read_text()
    actions: set = set()
    for name in data_source_names:
        block_match = re.search(
            r'data\s+"aws_iam_policy_document"\s+"%s"\s*\{(.*?)\n\}(?:\n|\Z)' % re.escape(name),
            text,
            re.DOTALL,
        )
        if not block_match:
            raise SystemExit(f"could not find data.aws_iam_policy_document.{name} in {data_tf}")
        block = block_match.group(1)
        for actions_match in re.finditer(r"actions\s*=\s*\[(.*?)\]", block, re.DOTALL):
            actions.update(re.findall(r'"([^"]+)"', actions_match.group(1)))
    return actions


def compare(label: str, cfn: set, terraform: set) -> bool:
    if cfn == terraform:
        print(f"OK: {label} matches ({len(cfn)} actions)")
        return True
    only_cfn = cfn - terraform
    only_tf = terraform - cfn
    print(f"MISMATCH: {label}")
    if only_cfn:
        print(f"  only in CloudFormation ({len(only_cfn)}): {sorted(only_cfn)}")
    if only_tf:
        print(f"  only in Terraform ({len(only_tf)}): {sorted(only_tf)}")
    return False


def main() -> int:
    cfn_readonly = cfn_actions(["ReadOnlyAccessPolicy", "ReadOnlyAccessPolicy2"])
    cfn_deny = cfn_actions(["DenyActionsPolicy"])

    ok = True
    for tree in TERRAFORM_TREES:
        data_tf = REPO_ROOT / tree / DATA_TF_RELATIVE
        tf_readonly = terraform_actions(data_tf, READONLY_SOURCES)
        tf_deny = terraform_actions(data_tf, [DENY_SOURCE])

        ok = compare(f"Allow actions: CloudFormation vs {tree}", cfn_readonly, tf_readonly) and ok
        ok = compare(f"Deny actions: CloudFormation vs {tree}", cfn_deny, tf_deny) and ok

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
