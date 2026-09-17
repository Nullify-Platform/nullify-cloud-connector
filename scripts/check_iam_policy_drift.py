#!/usr/bin/env python3
"""Compares the IAM statements granted by the CloudFormation template against
both Terraform trees (v5 and v6), so the three customer-facing templates for
the same IAM role cannot silently drift apart (ncc #58, whiskeylotus, W58-3).

Terraform's readonly grant is split across readonly_policy_part1 and
readonly_policy_part2 (an IAM managed policy document size limit); the
CloudFormation template splits the same grant across ReadOnlyAccessPolicy and
ReadOnlyAccessPolicy2. Both splits are combined before comparing.

Comparison is per statement, not per action name: Effect, Action/NotAction,
Resource/NotResource and Condition are all compared. A scoped statement (for
example a Deny on one action restricted to a handful of resource ARNs) is
distinguished from an identical action sitting in a resource="*" statement --
moving it between the two is a drift, even though the set of action names is
unchanged. Statement grouping and ordering can legitimately differ between the
CFN template and either Terraform tree, so each side is flattened to a set of
(effect, action, resources, condition) tuples -- one entry per action per
statement -- before comparing.

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

READONLY_SOURCES = ["readonly_policy_part1", "readonly_policy_part2"]
DENY_SOURCE = "deny_actions_policy"
READONLY_RESOURCES = ["ReadOnlyAccessPolicy", "ReadOnlyAccessPolicy2"]
DENY_RESOURCES = ["DenyActionsPolicy"]

# One flattened comparison entry: (effect, action, resources, condition).
# `resources` and `condition` are hashable, order-independent normal forms.
Entry = tuple

# Partition-scoped ARNs are written with CFN `${AWS::Partition}` and Terraform
# `${data.aws_partition.current.partition}`. Collapse both to `${partition}`
# so a scoped grant like ssm:GetDocument on SSM-SessionManagerRunShell
# compares equal instead of leaving an unhashable Fn::Sub dict in the set.
_PARTITION_TOKEN = "${partition}"
_CFN_PARTITION = re.compile(r"\$\{AWS::Partition\}")
_TF_PARTITION = re.compile(r"\$\{data\.aws_partition\.current\.partition\}")


def _norm_cfn_value(value) -> str:
    if isinstance(value, str):
        return _CFN_PARTITION.sub(_PARTITION_TOKEN, value)
    if isinstance(value, dict) and "Fn::Sub" in value:
        template = value["Fn::Sub"]
        if isinstance(template, list):
            template = template[0]
        if isinstance(template, str):
            return _CFN_PARTITION.sub(_PARTITION_TOKEN, template)
    raise SystemExit(f"unsupported CloudFormation IAM value: {value!r}")


def _norm_tf_value(value: str) -> str:
    return _TF_PARTITION.sub(_PARTITION_TOKEN, value)


def _norm_resources(resources, negated: bool) -> tuple:
    key = "not_resources" if negated else "resources"
    return (key, tuple(sorted(resources)) if resources else ())


def _norm_condition(conditions: list) -> tuple:
    """conditions: list of (test, variable, values) triples."""
    return tuple(sorted((test, variable, tuple(sorted(values))) for test, variable, values in conditions))


def _flatten(effect: str, actions: list, actions_negated: bool, resources: list, resources_negated: bool, conditions: list) -> set:
    action_key = "not_action" if actions_negated else "action"
    resource_norm = _norm_resources(resources, resources_negated)
    condition_norm = _norm_condition(conditions)
    return {(effect, action_key, action, resource_norm, condition_norm) for action in actions}


def cfn_entries(resource_names: list) -> set:
    template = json.loads(CFN_TEMPLATE.read_text())
    entries: set = set()
    for resource_name in resource_names:
        statements = template["Resources"][resource_name]["Properties"]["PolicyDocument"]["Statement"]
        for statement in statements:
            effect = statement.get("Effect", "Allow")

            if "NotAction" in statement:
                actions, actions_negated = statement["NotAction"], True
            else:
                actions = statement.get("Action", [])
                actions_negated = False
            if not isinstance(actions, list):
                actions = [actions]
            actions = [_norm_cfn_value(action) for action in actions]

            if "NotResource" in statement:
                resources, resources_negated = statement["NotResource"], True
            else:
                resources = statement.get("Resource", [])
                resources_negated = False
            if not isinstance(resources, list):
                resources = [resources]
            resources = [_norm_cfn_value(resource) for resource in resources]

            conditions = []
            for test, variable_values in (statement.get("Condition") or {}).items():
                for variable, values in variable_values.items():
                    values = values if isinstance(values, list) else [values]
                    conditions.append((test, variable, [str(v) for v in values]))

            entries |= _flatten(effect, actions, actions_negated, resources, resources_negated, conditions)
    return entries


def _find_statement_blocks(data_tf_text: str, data_source_name: str) -> list:
    """Returns the text of every top-level `statement { ... }` block inside
    `data "aws_iam_policy_document" "<data_source_name>" { ... }`, including
    blocks generated by a `dynamic "statement"` wrapper."""
    doc_match = re.search(
        r'data\s+"aws_iam_policy_document"\s+"%s"\s*\{' % re.escape(data_source_name),
        data_tf_text,
    )
    if not doc_match:
        raise SystemExit(f'could not find data.aws_iam_policy_document.{data_source_name}')
    doc_body, _ = _extract_braced_block(data_tf_text, doc_match.end() - 1)

    blocks = []
    for kind in ("statement", '"statement"'):
        for m in re.finditer(r'(?:dynamic\s+)?%s\s*\{' % re.escape(kind), doc_body):
            block, _ = _extract_braced_block(doc_body, m.end() - 1)
            # A `dynamic "statement"` wraps the real statement in a `content { ... }`
            # block; unwrap it so callers only ever see statement bodies.
            content_match = re.search(r"\bcontent\s*\{", block)
            if kind == '"statement"' and content_match:
                block, _ = _extract_braced_block(block, content_match.end() - 1)
            blocks.append(block)
    return blocks


def _extract_braced_block(text: str, open_brace_index: int) -> tuple:
    """text[open_brace_index] must be '{'. Returns (inner_text, index_after_close)."""
    depth = 0
    for i in range(open_brace_index, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_brace_index + 1 : i], i + 1
    raise SystemExit("unbalanced braces while parsing Terraform HCL")


def _string_list(block: str, key: str) -> list:
    """Values of `key = [...]` or `key = ["single"]`, never matching a
    differently-prefixed key sharing the same suffix (e.g. `actions` inside
    `not_actions`)."""
    match = re.search(r"(?<![A-Za-z0-9_])%s\s*=\s*\[(.*?)\]" % re.escape(key), block, re.DOTALL)
    if not match:
        return []
    return re.findall(r'"([^"]*)"', match.group(1))


def _conditions(block: str) -> list:
    conditions = []
    for m in re.finditer(r"(?<![A-Za-z0-9_])condition\s*\{", block):
        cond_block, _ = _extract_braced_block(block, m.end() - 1)
        test_match = re.search(r'test\s*=\s*"([^"]*)"', cond_block)
        variable_match = re.search(r'variable\s*=\s*"([^"]*)"', cond_block)
        values = _string_list(cond_block, "values")
        conditions.append((test_match.group(1) if test_match else "", variable_match.group(1) if variable_match else "", values))
    return conditions


def terraform_entries(data_tf: Path, data_source_names: list) -> set:
    text = data_tf.read_text()
    entries: set = set()
    for name in data_source_names:
        for block in _find_statement_blocks(text, name):
            effect_match = re.search(r'effect\s*=\s*"([^"]*)"', block)
            effect = effect_match.group(1) if effect_match else "Allow"

            not_actions = _string_list(block, "not_actions")
            if not_actions:
                actions, actions_negated = not_actions, True
            else:
                actions, actions_negated = _string_list(block, "actions"), False
            actions = [_norm_tf_value(action) for action in actions]

            not_resources = _string_list(block, "not_resources")
            if not_resources:
                resources, resources_negated = not_resources, True
            else:
                resources, resources_negated = _string_list(block, "resources"), False
            resources = [_norm_tf_value(resource) for resource in resources]

            entries |= _flatten(effect, actions, actions_negated, resources, resources_negated, _conditions(block))
    return entries


def compare(label: str, cfn: set, terraform: set) -> bool:
    if cfn == terraform:
        print(f"OK: {label} matches ({len(cfn)} entries)")
        return True
    only_cfn = cfn - terraform
    only_tf = terraform - cfn
    print(f"MISMATCH: {label}")
    if only_cfn:
        print(f"  only in CloudFormation ({len(only_cfn)}): {sorted(only_cfn)}")
    if only_tf:
        print(f"  only in Terraform ({len(only_tf)}): {sorted(only_tf)}")
    return False


HELM_CLUSTERROLE = REPO_ROOT / "helm-charts/nullify-k8s-collector/templates/clusterrole.yaml"
TF_CLUSTERROLES = [
    REPO_ROOT / "aws-integration-setup/terraform/modules/k8s-resources/main.tf",
    REPO_ROOT / "aws-integration-setup/terraform-v6/modules/k8s-resources/main.tf",
]


def _quoted(block: str) -> list:
    return re.findall(r'"([^"]+)"', block)


def helm_clusterrole_kinds(text: str) -> set:
    kinds = set()
    for m in re.finditer(r"resources:\s*\[(.*?)\]", text, re.DOTALL):
        kinds.update(_quoted(m.group(1)))
    for m in re.finditer(r"nonResourceURLs:\s*\[(.*?)\]", text, re.DOTALL):
        kinds.update("url:" + url for url in _quoted(m.group(1)))
    return kinds


def terraform_clusterrole_kinds(text: str) -> set:
    match = re.search(r'resource\s+"kubernetes_cluster_role"\s+"nullify_readonly_role"\s*\{', text)
    if not match:
        raise SystemExit("could not find kubernetes_cluster_role.nullify_readonly_role")
    body, _ = _extract_braced_block(text, match.end() - 1)
    kinds = set()
    for m in re.finditer(r"(?<![A-Za-z0-9_])resources\s*=\s*\[(.*?)\]", body, re.DOTALL):
        kinds.update(_quoted(m.group(1)))
    for m in re.finditer(r"(?<![A-Za-z0-9_])non_resource_urls\s*=\s*\[(.*?)\]", body, re.DOTALL):
        kinds.update("url:" + url for url in _quoted(m.group(1)))
    return kinds


def main() -> int:
    cfn_readonly = cfn_entries(READONLY_RESOURCES)
    cfn_deny = cfn_entries(DENY_RESOURCES)

    ok = True
    for tree in TERRAFORM_TREES:
        data_tf = REPO_ROOT / tree / DATA_TF_RELATIVE
        tf_readonly = terraform_entries(data_tf, READONLY_SOURCES)
        tf_deny = terraform_entries(data_tf, [DENY_SOURCE])

        ok = compare(f"Allow statements: CloudFormation vs {tree}", cfn_readonly, tf_readonly) and ok
        ok = compare(f"Deny statements: CloudFormation vs {tree}", cfn_deny, tf_deny) and ok

    helm_kinds = helm_clusterrole_kinds(HELM_CLUSTERROLE.read_text())
    for path in TF_CLUSTERROLES:
        tf_kinds = terraform_clusterrole_kinds(path.read_text())
        ok = compare(f"ClusterRole kinds: Helm vs {path.relative_to(REPO_ROOT)}", helm_kinds, tf_kinds) and ok

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
